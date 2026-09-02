-- PL/pgSQL integer FOR loops declare their index automatically. Replacing the
-- function without an explicit declaration removes the shadow/unused warning.
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
  log_id uuid;
  log_ids uuid[] := array[]::uuid[];
begin
  if not public.is_app_owner() then
    raise exception 'Only the app owner may consume planned meals' using errcode = '42501';
  end if;
  if coalesce(cardinality(p_meal_plans), 0) = 0 then
    raise exception 'Choose at least one planned meal component';
  end if;
  if cardinality(p_meal_plans) <> coalesce(cardinality(p_servings), 0) then
    raise exception 'Every planned meal component needs an eaten serving quantity';
  end if;

  for plan_index in 1..cardinality(p_meal_plans) loop
    plan_id := p_meal_plans[plan_index];
    eaten_servings := p_servings[plan_index];
    if eaten_servings is null or eaten_servings <= 0 then
      raise exception 'Eaten servings must be positive';
    end if;

    select * into plan_row from public.meal_plans where id = plan_id for update;
    if not found then raise exception 'Planned meal does not exist'; end if;
    select * into consumption_row from public.planned_consumptions where meal_plan = plan_id for update;
    if not found then raise exception 'Planned consumption does not exist'; end if;
    if consumption_row.status = 'fulfilled' then
      raise exception 'The planned portion of % has already been eaten', coalesce(plan_row.name, plan_row.recipe::text);
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

    log_id := public.consume_prepared_batch(
      selected_lot.id,
      eaten_servings,
      plan_id,
      p_occurred_at
    );
    log_ids := array_append(log_ids, log_id);
  end loop;

  return log_ids;
end;
$$;
