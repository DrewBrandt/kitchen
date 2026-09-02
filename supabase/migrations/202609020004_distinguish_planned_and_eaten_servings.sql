-- A plan answers "how much did I intend to eat?" while the linked food log
-- answers "how much did I actually eat?". Preserve both values and let the
-- consumption transaction receive an explicit actual quantity per component.

create or replace function public.consume_prepared_batch(
  p_lot uuid,
  p_quantity numeric,
  p_meal_plan uuid default null,
  p_occurred_at timestamptz default now()
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  lot_row public.inventory_lots%rowtype;
  prep_row public.preps%rowtype;
  recipe_row public.recipes%rowtype;
  nutrients jsonb;
  linked_plan uuid;
  new_log uuid;
begin
  if not public.is_app_owner() then
    raise exception 'Only the app owner may consume inventory' using errcode = '42501';
  end if;
  if p_quantity <= 0 then raise exception 'Quantity must be positive'; end if;

  select * into lot_row from public.inventory_lots where id = p_lot for update;
  if not found or lot_row.prep is null then raise exception 'Prepared lot does not exist'; end if;
  if lot_row.remaining_qty < p_quantity then
    raise exception 'Prepared lot has only % servings remaining', lot_row.remaining_qty;
  end if;

  select * into prep_row from public.preps where id = lot_row.prep and voided_at is null;
  if not found then raise exception 'Preparation does not exist'; end if;
  select * into recipe_row from public.recipes where id = prep_row.recipe;
  nutrients := public.lot_nutrition_json(p_lot);

  insert into public.food_logs(
    label, kind, recipe, servings, occurred_at,
    kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg
  ) values (
    recipe_row.name, 'prepared', recipe_row.id, p_quantity, p_occurred_at,
    coalesce((nutrients ->> 'kcal')::numeric, 0) * p_quantity,
    coalesce((nutrients ->> 'protein_g')::numeric, 0) * p_quantity,
    coalesce((nutrients ->> 'carbs_g')::numeric, 0) * p_quantity,
    coalesce((nutrients ->> 'fat_g')::numeric, 0) * p_quantity,
    coalesce((nutrients ->> 'fiber_g')::numeric, 0) * p_quantity,
    coalesce((nutrients ->> 'sugar_g')::numeric, 0) * p_quantity,
    coalesce((nutrients ->> 'sodium_mg')::numeric, 0) * p_quantity
  ) returning id into new_log;

  insert into public.inventory_events(lot, quantity_delta, reason, food_log, occurred_at)
  values (p_lot, -p_quantity, 'eaten', new_log, p_occurred_at);

  linked_plan := coalesce(p_meal_plan, prep_row.meal_plan);
  if linked_plan is not null then
    update public.meal_plans
    set status = 'made', made_at = coalesce(made_at, prep_row.prepped_at)
    where id = linked_plan;

    update public.planned_consumptions
    set status = 'fulfilled', food_log = new_log
    where meal_plan = linked_plan and status = 'planned';
  end if;

  return new_log;
end;
$$;

drop function if exists public.consume_planned_meals(uuid[], timestamptz);

create function public.consume_planned_meals(
  p_meal_plans uuid[],
  p_servings numeric[],
  p_occurred_at timestamptz default now()
)
returns uuid[]
language plpgsql
set search_path = ''
as $$
declare
  plan_index integer;
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

revoke all on function public.consume_planned_meals(uuid[], numeric[], timestamptz) from public, anon;
grant execute on function public.consume_planned_meals(uuid[], numeric[], timestamptz) to authenticated;
