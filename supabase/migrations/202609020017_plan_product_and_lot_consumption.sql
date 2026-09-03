-- A day plan may describe either something to prepare or something already in
-- inventory to consume. Keep one plan and one planned-consumption lifecycle;
-- product/lot sources do not need a parallel planning table.
alter table public.meal_plans
  add column product uuid references public.products(id),
  add column inventory_lot uuid references public.inventory_lots(id);

alter table public.meal_plans
  drop constraint meal_plans_one_source,
  drop constraint meal_plans_intent_check;

alter table public.meal_plans
  add constraint meal_plans_one_source check (
    num_nonnulls(meal, recipe, product, inventory_lot) = 1
  ),
  add constraint meal_plans_intent_check check (
    intent in ('prepare', 'leftover', 'consume')
  ),
  add constraint meal_plans_source_matches_intent check (
    (
      intent = 'consume'
      and meal is null
      and recipe is null
      and num_nonnulls(product, inventory_lot) = 1
    )
    or
    (
      intent in ('prepare', 'leftover')
      and product is null
      and inventory_lot is null
      and num_nonnulls(meal, recipe) = 1
    )
  );

create index meal_plans_product_idx on public.meal_plans(product)
  where product is not null;
create index meal_plans_inventory_lot_idx on public.meal_plans(inventory_lot)
  where inventory_lot is not null;

-- Planned recipes still consume their prepared batch. Planned products are
-- already edible: a generic product resolves to the first FEFO lot that can
-- satisfy the portion, while an exact-lot plan remains pinned to that lot.
create or replace function public.consume_planned_meals(
  p_meal_plans uuid[],
  p_servings numeric[],
  p_occurred_at timestamptz default now()
)
returns uuid[]
language plpgsql
set search_path = ''
as $$
declare
  plan_id uuid;
  eaten_servings numeric;
  plan_row public.meal_plans%rowtype;
  consumption_row public.planned_consumptions%rowtype;
  selected_lot public.inventory_lots%rowtype;
  product_row public.products%rowtype;
  quantity_to_consume numeric;
  log_id uuid;
  log_ids uuid[] := array[]::uuid[];
begin
  if not public.is_app_owner() then
    raise exception 'Only the app owner may consume planned items' using errcode = '42501';
  end if;
  if coalesce(cardinality(p_meal_plans), 0) = 0 then
    raise exception 'Choose at least one planned item';
  end if;
  if cardinality(p_meal_plans) <> coalesce(cardinality(p_servings), 0) then
    raise exception 'Every planned item needs an eaten serving quantity';
  end if;

  for plan_index in 1..cardinality(p_meal_plans) loop
    plan_id := p_meal_plans[plan_index];
    eaten_servings := p_servings[plan_index];
    if eaten_servings is null or eaten_servings <= 0 then
      raise exception 'Eaten servings must be positive';
    end if;

    select * into plan_row from public.meal_plans where id = plan_id for update;
    if not found then raise exception 'Planned item does not exist'; end if;
    select * into consumption_row from public.planned_consumptions where meal_plan = plan_id for update;
    if not found then raise exception 'Planned consumption does not exist'; end if;
    if consumption_row.status = 'fulfilled' then
      raise exception 'The planned portion of % has already been eaten', coalesce(plan_row.name, plan_row.recipe::text, plan_row.product::text, plan_row.inventory_lot::text);
    end if;

    if plan_row.intent = 'consume' then
      if plan_row.inventory_lot is not null then
        select * into selected_lot
        from public.inventory_lots
        where id = plan_row.inventory_lot and prep is null
        for update;
        if not found or selected_lot.product is null then
          raise exception 'The selected inventory lot is no longer available';
        end if;
        select * into product_row
        from public.products
        where id = selected_lot.product and archived_at is null;
      else
        select * into product_row
        from public.products
        where id = plan_row.product and archived_at is null;
        if not found then raise exception 'The planned product is no longer available'; end if;

        quantity_to_consume := case
          when product_row.servings_per_package is not null
            and product_row.servings_per_package > 0
            and product_row.package_qty_base > 0
            and product_row.serving_qty_base is not null
            and product_row.nutrition_basis_qty is not null
            and abs(product_row.nutrition_basis_qty - product_row.serving_qty_base) < 0.000001
            then eaten_servings * product_row.package_qty_base / product_row.servings_per_package
          else eaten_servings * coalesce(nullif(product_row.serving_qty_base, 0), 1)
        end;

        select lot.* into selected_lot
        from public.inventory_lots lot
        where lot.product = product_row.id
          and lot.prep is null
          and lot.remaining_qty >= quantity_to_consume
        order by lot.use_by asc nulls last, lot.acquired_at, lot.id
        limit 1
        for update of lot;
      end if;

      if selected_lot.id is null or product_row.id is null then
        raise exception 'No available lot has enough for this planned portion';
      end if;

      if quantity_to_consume is null then
        quantity_to_consume := case
          when product_row.servings_per_package is not null
            and product_row.servings_per_package > 0
            and product_row.package_qty_base > 0
            and product_row.serving_qty_base is not null
            and product_row.nutrition_basis_qty is not null
            and abs(product_row.nutrition_basis_qty - product_row.serving_qty_base) < 0.000001
            then eaten_servings * product_row.package_qty_base / product_row.servings_per_package
          else eaten_servings * coalesce(nullif(product_row.serving_qty_base, 0), 1)
        end;
      end if;
      if selected_lot.remaining_qty < quantity_to_consume then
        raise exception 'The selected lot has only % servings remaining', public.product_servings_for_quantity(product_row.id, selected_lot.remaining_qty);
      end if;

      log_id := public.consume_inventory_lot(selected_lot.id, quantity_to_consume, p_occurred_at);
      update public.planned_consumptions
      set status = 'fulfilled', food_log = log_id, updated_at = now()
      where id = consumption_row.id;
      log_ids := array_append(log_ids, log_id);
      quantity_to_consume := null;
      selected_lot := null;
      product_row := null;
      continue;
    end if;

    if plan_row.status <> 'made' and plan_row.intent <> 'leftover' then
      raise exception 'Prepare the planned recipe before logging it as eaten';
    end if;

    selected_lot := null;
    if plan_row.intent = 'leftover' then
      select lot.* into selected_lot
      from public.inventory_lots lot
      join public.preps prep on prep.id = lot.prep and prep.voided_at is null
      join public.meal_plans source_plan on source_plan.id = prep.meal_plan
      where source_plan.group_id = plan_row.leftover_of_group_id
        and source_plan.recipe = plan_row.recipe
        and lot.remaining_qty >= eaten_servings
      order by prep.prepped_at desc, lot.id
      limit 1
      for update of lot;
    else
      select lot.* into selected_lot
      from public.inventory_lots lot
      join public.preps prep on prep.id = lot.prep and prep.voided_at is null
      where prep.meal_plan = plan_id
        and lot.remaining_qty >= eaten_servings
      order by prep.prepped_at desc, lot.id
      limit 1
      for update of lot;
    end if;

    if selected_lot.id is null then
      raise exception 'No prepared batch has enough servings for the amount eaten';
    end if;

    log_id := public.consume_prepared_batch(selected_lot.id, eaten_servings, plan_id, p_occurred_at);
    log_ids := array_append(log_ids, log_id);
  end loop;

  return log_ids;
end;
$$;
