-- A meal-plan status, a preparation, its prepared servings, and the eventual
-- food-log entry are one lifecycle. Keep the links in the database so every UI
-- surface observes the same state and no action can deduct ingredients twice.

alter table public.preps
  add column meal_plan uuid references public.meal_plans(id) on delete set null;

create unique index preps_active_meal_plan_idx
  on public.preps(meal_plan)
  where meal_plan is not null and voided_at is null;

comment on column public.preps.meal_plan is
  'The planned recipe component fulfilled by this preparation, when cooking started from the plan.';

-- Repair the status-only actions and lot-less preparations that exposed this
-- bug. Pair recent preparations with matching plans that were marked made soon
-- afterward, then materialize every successful prep as servings-based stock.
with ranked_preps as (
  select
    prep.id,
    prep.recipe,
    prep.prepped_at,
    row_number() over (partition by prep.recipe order by prep.prepped_at desc, prep.id) as match_rank
  from public.preps prep
  where prep.voided_at is null
    and prep.meal_plan is null
), ranked_plans as (
  select
    plan.id,
    plan.recipe,
    plan.made_at,
    row_number() over (partition by plan.recipe order by plan.made_at desc, plan.id) as match_rank
  from public.meal_plans plan
  where plan.status = 'made'
    and plan.recipe is not null
    and plan.made_at is not null
)
update public.preps prep
set meal_plan = plan.id
from ranked_preps candidate
join ranked_plans plan
  on plan.recipe = candidate.recipe
 and plan.match_rank = candidate.match_rank
where prep.id = candidate.id
  and abs(extract(epoch from (plan.made_at - candidate.prepped_at))) <= 12 * 60 * 60;

update public.preps prep
set actual_yield_qty = recipe.servings * prep.scale_factor
from public.recipes recipe
where recipe.id = prep.recipe
  and prep.voided_at is null
  and prep.actual_yield_qty is null;

insert into public.inventory_lots(prep, initial_qty, remaining_qty, location, note)
select
  prep.id,
  prep.actual_yield_qty,
  prep.actual_yield_qty,
  'fridge',
  'Prepared servings restored by meal lifecycle migration'
from public.preps prep
where prep.voided_at is null
  and prep.actual_yield_qty > 0
  and not exists (
    select 1 from public.inventory_lots lot where lot.prep = prep.id
  );

-- A fulfilled consumption must have a log. Planned/cancelled rows may retain a
-- voided log reference so one-click restore can reattach the same event.
alter table public.planned_consumptions
  drop constraint planned_consumptions_fulfillment,
  add constraint planned_consumptions_fulfillment check (
    status <> 'fulfilled' or food_log is not null
  );

-- Cooking always produces a prepared batch. Recipes without output_food are
-- ordinary meals measured in servings; output_food remains useful only when a
-- prepared recipe is itself an ingredient in another recipe.
create or replace function public.cook_recipe(
  p_recipe uuid,
  p_scale numeric default 1,
  p_actual_yield numeric default null,
  p_location text default 'fridge'
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  recipe_row public.recipes%rowtype;
  ingredient_row public.recipe_ingredients%rowtype;
  lot_row public.inventory_lots%rowtype;
  new_prep uuid;
  needed numeric;
  taken numeric;
  actual_yield numeric;
begin
  if not public.is_app_owner() then
    raise exception 'Only the app owner may cook recipes' using errcode = '42501';
  end if;
  if p_scale <= 0 then raise exception 'Recipe scale must be positive'; end if;

  select * into recipe_row from public.recipes where id = p_recipe;
  if not found then raise exception 'Recipe does not exist'; end if;

  actual_yield := coalesce(p_actual_yield, recipe_row.yield_qty * p_scale, recipe_row.servings * p_scale);
  if actual_yield is null or actual_yield <= 0 then
    raise exception 'Prepared output needs a positive serving yield';
  end if;

  insert into public.preps(recipe, scale_factor, actual_yield_qty)
  values (p_recipe, p_scale, actual_yield)
  returning id into new_prep;

  for ingredient_row in
    select ingredient.*
    from public.recipe_ingredients ingredient
    where ingredient.recipe = p_recipe
    order by ingredient.sort_order
  loop
    if exists (
      select 1 from public.base_foods food
      where food.id = ingredient_row.ingredient and food.always_available
    ) then
      continue;
    end if;

    needed := public.to_base_quantity(
      ingredient_row.ingredient,
      ingredient_row.qty * p_scale,
      ingredient_row.unit
    );

    for lot_row in
      select lot.*
      from public.inventory_lots lot
      left join public.products product on product.id = lot.product
      left join public.preps source_prep on source_prep.id = lot.prep and source_prep.voided_at is null
      left join public.recipes source_recipe on source_recipe.id = source_prep.recipe
      where lot.remaining_qty > 0
        and coalesce(product.food, source_recipe.output_food) = ingredient_row.ingredient
        and (ingredient_row.pinned_product is null or product.id = ingredient_row.pinned_product)
      order by lot.use_by asc nulls last, lot.acquired_at, lot.id
      for update of lot
    loop
      exit when needed <= 0.0000001;
      taken := least(needed, lot_row.remaining_qty);
      insert into public.inventory_events(lot, quantity_delta, reason, prep)
      values (lot_row.id, -taken, 'prep', new_prep);
      needed := needed - taken;
    end loop;

    if needed > 0.0000001 then
      raise exception 'Not enough inventory for ingredient %', ingredient_row.ingredient;
    end if;
  end loop;

  insert into public.inventory_lots(prep, initial_qty, remaining_qty, location)
  values (new_prep, actual_yield, actual_yield, p_location);

  return new_prep;
end;
$$;

create function public.consume_prepared_batch(
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
    set servings = p_quantity, status = 'fulfilled', food_log = new_log
    where meal_plan = linked_plan and status = 'planned';
  end if;

  return new_log;
end;
$$;

create or replace function public.consume_prepared_lot(
  p_lot uuid,
  p_quantity numeric default 1,
  p_occurred_at timestamptz default now()
)
returns uuid
language sql
set search_path = ''
as $$
  select public.consume_prepared_batch(p_lot, p_quantity, null, p_occurred_at);
$$;

create function public.prepare_recipe(
  p_recipe uuid,
  p_scale numeric default 1,
  p_servings numeric default null,
  p_location text default 'fridge',
  p_meal_plan uuid default null,
  p_eaten_servings numeric default 0,
  p_occurred_at timestamptz default now()
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  recipe_row public.recipes%rowtype;
  plan_row public.meal_plans%rowtype;
  effective_scale numeric;
  servings_made numeric;
  prep_id uuid;
  lot_id uuid;
  log_id uuid;
begin
  if not public.is_app_owner() then
    raise exception 'Only the app owner may prepare recipes' using errcode = '42501';
  end if;
  select * into recipe_row from public.recipes where id = p_recipe;
  if not found then raise exception 'Recipe does not exist'; end if;

  effective_scale := p_scale;
  if p_meal_plan is not null then
    select * into plan_row from public.meal_plans where id = p_meal_plan for update;
    if not found then raise exception 'Planned meal does not exist'; end if;
    if plan_row.recipe is distinct from p_recipe then raise exception 'Planned meal recipe does not match'; end if;
    if plan_row.intent <> 'prepare' then raise exception 'A leftovers plan does not prepare a new batch'; end if;
    if plan_row.status = 'made' or exists (
      select 1 from public.preps prep
      where prep.meal_plan = p_meal_plan and prep.voided_at is null
    ) then
      raise exception 'This planned recipe has already been prepared';
    end if;
    effective_scale := plan_row.scale_factor;
  end if;

  if effective_scale <= 0 then raise exception 'Recipe scale must be positive'; end if;
  servings_made := coalesce(p_servings, recipe_row.servings * effective_scale);
  if servings_made <= 0 then raise exception 'Servings made must be positive'; end if;
  if p_eaten_servings < 0 or p_eaten_servings > servings_made then
    raise exception 'Servings eaten must be between zero and the servings made';
  end if;

  prep_id := public.cook_recipe(p_recipe, effective_scale, servings_made, p_location);
  update public.preps set meal_plan = p_meal_plan where id = prep_id;
  select id into lot_id from public.inventory_lots where prep = prep_id;

  if p_meal_plan is not null then
    update public.meal_plans
    set status = 'made', made_at = p_occurred_at
    where id = p_meal_plan;
  end if;

  if p_eaten_servings > 0 then
    log_id := public.consume_prepared_batch(lot_id, p_eaten_servings, p_meal_plan, p_occurred_at);
  end if;

  return jsonb_build_object(
    'prepId', prep_id,
    'lotId', lot_id,
    'mealPlanId', p_meal_plan,
    'servingsMade', servings_made,
    'servingsRemaining', servings_made - p_eaten_servings,
    'location', p_location,
    'foodLogId', log_id
  );
end;
$$;

create function public.consume_planned_meals(
  p_meal_plans uuid[],
  p_occurred_at timestamptz default now()
)
returns uuid[]
language plpgsql
set search_path = ''
as $$
declare
  plan_id uuid;
  plan_row public.meal_plans%rowtype;
  consumption_row public.planned_consumptions%rowtype;
  selected_lot public.inventory_lots%rowtype;
  log_id uuid;
  log_ids uuid[] := array[]::uuid[];
begin
  if not public.is_app_owner() then
    raise exception 'Only the app owner may consume planned meals' using errcode = '42501';
  end if;
  if coalesce(array_length(p_meal_plans, 1), 0) = 0 then
    raise exception 'Choose at least one planned meal component';
  end if;

  foreach plan_id in array p_meal_plans loop
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
        and lot.remaining_qty >= consumption_row.servings
      order by prep.prepped_at desc, lot.id
      limit 1
      for update of lot;
    else
      select lot.* into selected_lot
      from public.inventory_lots lot
      join public.preps prep on prep.id = lot.prep and prep.voided_at is null
      where prep.meal_plan = plan_id
        and lot.remaining_qty >= consumption_row.servings
      order by prep.prepped_at desc, lot.id
      limit 1
      for update of lot;
    end if;

    if selected_lot.id is null then
      raise exception 'No prepared batch has enough servings for the planned portion';
    end if;

    log_id := public.consume_prepared_batch(
      selected_lot.id,
      consumption_row.servings,
      plan_id,
      p_occurred_at
    );
    log_ids := array_append(log_ids, log_id);
  end loop;

  return log_ids;
end;
$$;

create or replace function public.undo_prep(p_prep uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  prep_row public.preps%rowtype;
  produced public.inventory_lots%rowtype;
begin
  if not public.is_app_owner() then
    raise exception 'Only the app owner may undo a cook' using errcode = '42501';
  end if;

  select * into prep_row from public.preps where id = p_prep for update;
  if not found then raise exception 'Preparation does not exist'; end if;
  if prep_row.voided_at is not null then return; end if;

  select * into produced from public.inventory_lots where prep = p_prep for update;
  if produced.id is not null and exists (
    select 1 from public.inventory_events
    where lot = produced.id and voided_at is null
  ) then
    raise exception 'This batch has already been eaten from and can no longer be undone';
  end if;

  if produced.id is not null and produced.remaining_qty > 0 then
    insert into public.inventory_events(lot, quantity_delta, reason, note)
    values (produced.id, -produced.remaining_qty, 'adjust', 'Cook undone');
  end if;

  update public.inventory_events
  set voided_at = now()
  where prep = p_prep and reason = 'prep' and voided_at is null;

  update public.preps set voided_at = now() where id = p_prep;
  if prep_row.meal_plan is not null then
    update public.meal_plans
    set status = 'planned', made_at = null
    where id = prep_row.meal_plan;
  end if;
end;
$$;

create or replace function public.void_food_log(p_food_log uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  log_row public.food_logs%rowtype;
begin
  if not public.is_app_owner() then
    raise exception 'Only the app owner may void food logs' using errcode = '42501';
  end if;
  select * into log_row from public.food_logs where id = p_food_log for update;
  if not found then raise exception 'Food log entry does not exist'; end if;
  if log_row.voided_at is not null then return; end if;

  update public.food_logs set voided_at = now() where id = p_food_log;
  update public.inventory_events set voided_at = now()
  where food_log = p_food_log and voided_at is null;
  update public.planned_consumptions set status = 'planned'
  where food_log = p_food_log and status = 'fulfilled';
end;
$$;

create or replace function public.restore_food_log(p_food_log uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  log_row public.food_logs%rowtype;
begin
  if not public.is_app_owner() then
    raise exception 'Only the app owner may restore food logs' using errcode = '42501';
  end if;
  select * into log_row from public.food_logs where id = p_food_log for update;
  if not found then raise exception 'Food log entry does not exist'; end if;
  if log_row.voided_at is null then return; end if;

  update public.food_logs set voided_at = null where id = p_food_log;
  update public.inventory_events set voided_at = null
  where food_log = p_food_log and voided_at is not null;
  update public.planned_consumptions set status = 'fulfilled'
  where food_log = p_food_log and status = 'planned';
end;
$$;

revoke all on function public.consume_prepared_batch(uuid, numeric, uuid, timestamptz) from public, anon;
grant execute on function public.consume_prepared_batch(uuid, numeric, uuid, timestamptz) to authenticated;
revoke all on function public.prepare_recipe(uuid, numeric, numeric, text, uuid, numeric, timestamptz) from public, anon;
grant execute on function public.prepare_recipe(uuid, numeric, numeric, text, uuid, numeric, timestamptz) to authenticated;
revoke all on function public.consume_planned_meals(uuid[], timestamptz) from public, anon;
grant execute on function public.consume_planned_meals(uuid[], timestamptz) to authenticated;
