create function public.to_base_quantity(
  p_food uuid,
  p_amount numeric,
  p_unit uuid
)
returns numeric
language plpgsql
stable
set search_path = ''
as $$
declare
  food_style public.measure_style;
  unit_style public.measure_style;
  unit_ratio numeric;
  grams_per_fluid_ounce numeric;
  grams_per_count numeric;
  unit_style_base numeric;
begin
  if p_amount <= 0 then
    raise exception 'Quantity must be positive';
  end if;

  select
    food.measure_style,
    food.g_per_fl_oz,
    food.g_per_count
  into
    food_style,
    grams_per_fluid_ounce,
    grams_per_count
  from public.base_foods food
  where food.id = p_food;

  if not found then
    raise exception 'Food % does not exist', p_food;
  end if;

  select unit.measure_style, unit.base_to_this_ratio
  into unit_style, unit_ratio
  from public.measure_conversions unit
  where unit.id = p_unit;

  if not found then
    raise exception 'Unit % does not exist', p_unit;
  end if;

  unit_style_base := p_amount / unit_ratio;

  if food_style = unit_style then
    return unit_style_base;
  elsif food_style = 'weight' and unit_style = 'volume' then
    return unit_style_base * grams_per_fluid_ounce;
  elsif food_style = 'volume' and unit_style = 'weight' then
    return unit_style_base / grams_per_fluid_ounce;
  elsif food_style = 'weight' and unit_style = 'discrete' then
    return unit_style_base * grams_per_count;
  elsif food_style = 'discrete' and unit_style = 'weight' then
    return unit_style_base / grams_per_count;
  elsif food_style = 'volume' and unit_style = 'discrete' then
    return unit_style_base * grams_per_count / grams_per_fluid_ounce;
  elsif food_style = 'discrete' and unit_style = 'volume' then
    return unit_style_base * grams_per_fluid_ounce / grams_per_count;
  end if;

  raise exception 'Unit cannot be converted to the food stock measure';
end;
$$;

create function public.from_base_quantity(
  p_food uuid,
  p_base_amount numeric,
  p_unit uuid
)
returns numeric
language sql
stable
set search_path = ''
as $$
  select p_base_amount / public.to_base_quantity(p_food, 1, p_unit);
$$;

create function public.lot_nutrition_json(
  p_lot uuid,
  p_path uuid[] default '{}'::uuid[]
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  lot_product uuid;
  lot_prep uuid;
  prep_recipe uuid;
  prep_yield numeric;
  result jsonb;
  derived jsonb;
begin
  if p_lot = any(p_path) then
    raise exception 'Prepared-lot nutrition graph contains a cycle at lot %', p_lot;
  end if;

  select product, prep into lot_product, lot_prep
  from public.inventory_lots
  where id = p_lot;

  if not found then
    raise exception 'Inventory lot % does not exist', p_lot;
  end if;

  if lot_product is not null then
    select jsonb_build_object(
      'kcal', coalesce(
        product.kcal / product.nutrition_basis_qty,
        food.kcal / food.nutrition_basis_qty
      ),
      'protein_g', coalesce(
        product.protein_g / product.nutrition_basis_qty,
        food.protein_g / food.nutrition_basis_qty
      ),
      'carbs_g', coalesce(
        product.carbs_g / product.nutrition_basis_qty,
        food.carbs_g / food.nutrition_basis_qty
      ),
      'fat_g', coalesce(
        product.fat_g / product.nutrition_basis_qty,
        food.fat_g / food.nutrition_basis_qty
      ),
      'fiber_g', coalesce(
        product.fiber_g / product.nutrition_basis_qty,
        food.fiber_g / food.nutrition_basis_qty
      ),
      'sodium_mg', coalesce(
        product.sodium_mg / product.nutrition_basis_qty,
        food.sodium_mg / food.nutrition_basis_qty
      )
    ) into result
    from public.products product
    join public.base_foods food on food.id = product.food
    where product.id = lot_product;

    return result;
  end if;

  select prep.recipe, prep.actual_yield_qty
  into prep_recipe, prep_yield
  from public.preps prep
  where prep.id = lot_prep and prep.voided_at is null;

  if prep_yield is null or prep_yield <= 0 then
    raise exception 'Prep % needs an actual yield before nutrition can resolve', lot_prep;
  end if;

  select jsonb_build_object(
    'kcal', sum(
      -event.quantity_delta * (nutrients.value ->> 'kcal')::numeric
    ),
    'protein_g', sum(
      -event.quantity_delta * (nutrients.value ->> 'protein_g')::numeric
    ),
    'carbs_g', sum(
      -event.quantity_delta * (nutrients.value ->> 'carbs_g')::numeric
    ),
    'fat_g', sum(
      -event.quantity_delta * (nutrients.value ->> 'fat_g')::numeric
    ),
    'fiber_g', sum(
      -event.quantity_delta * (nutrients.value ->> 'fiber_g')::numeric
    ),
    'sodium_mg', sum(
      -event.quantity_delta * (nutrients.value ->> 'sodium_mg')::numeric
    )
  ) into derived
  from public.inventory_events event
  cross join lateral (
    select public.lot_nutrition_json(event.lot, p_path || p_lot) as value
  ) nutrients
  where event.prep = lot_prep
    and event.reason = 'prep'
    and event.voided_at is null;

  select jsonb_build_object(
    'kcal', coalesce(
      recipe.override_kcal / recipe.override_basis_qty,
      (derived ->> 'kcal')::numeric / prep_yield
    ),
    'protein_g', coalesce(
      recipe.override_protein_g / recipe.override_basis_qty,
      (derived ->> 'protein_g')::numeric / prep_yield
    ),
    'carbs_g', coalesce(
      recipe.override_carbs_g / recipe.override_basis_qty,
      (derived ->> 'carbs_g')::numeric / prep_yield
    ),
    'fat_g', coalesce(
      recipe.override_fat_g / recipe.override_basis_qty,
      (derived ->> 'fat_g')::numeric / prep_yield
    ),
    'fiber_g', coalesce(
      recipe.override_fiber_g / recipe.override_basis_qty,
      (derived ->> 'fiber_g')::numeric / prep_yield
    ),
    'sodium_mg', coalesce(
      recipe.override_sodium_mg / recipe.override_basis_qty,
      (derived ->> 'sodium_mg')::numeric / prep_yield
    )
  ) into result
  from public.recipes recipe
  where recipe.id = prep_recipe;

  return result;
end;
$$;

create function public.lot_nutrition_per_base_unit(p_lot uuid)
returns table (
  kcal numeric,
  protein_g numeric,
  carbs_g numeric,
  fat_g numeric,
  fiber_g numeric,
  sodium_mg numeric
)
language sql
stable
set search_path = ''
as $$
  select
    (nutrition ->> 'kcal')::numeric,
    (nutrition ->> 'protein_g')::numeric,
    (nutrition ->> 'carbs_g')::numeric,
    (nutrition ->> 'fat_g')::numeric,
    (nutrition ->> 'fiber_g')::numeric,
    (nutrition ->> 'sodium_mg')::numeric
  from (
    select public.lot_nutrition_json(p_lot) as nutrition
  ) resolved;
$$;

create function public.prep_total_cost(p_prep uuid)
returns numeric
language sql
stable
set search_path = ''
as $$
  select case
    when count(*) filter (where lot.total_cost is null) > 0 then null
    else coalesce(sum(
      -event.quantity_delta * lot.total_cost / lot.initial_qty
    ), 0)
  end
  from public.inventory_events event
  join public.inventory_lots lot on lot.id = event.lot
  where event.prep = p_prep
    and event.reason = 'prep'
    and event.voided_at is null;
$$;

create or replace function public.initialize_inventory_lot()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  prep_yield numeric;
begin
  new.remaining_qty = new.initial_qty;

  if new.prep is not null then
    select actual_yield_qty into prep_yield
    from public.preps
    where id = new.prep and voided_at is null;

    if prep_yield is null or prep_yield <= 0 then
      raise exception 'Prep needs an actual yield before its inventory lot is created';
    end if;

    new.total_cost = round(
      public.prep_total_cost(new.prep) * new.initial_qty / prep_yield,
      2
    );
  end if;

  return new;
end;
$$;

create view public.inventory_event_costs
with (security_invoker = true)
as
select
  event.id as inventory_event_id,
  event.lot,
  event.reason,
  event.occurred_at,
  event.voided_at,
  round(abs(event.quantity_delta) * lot.total_cost / lot.initial_qty, 4) as cost
from public.inventory_events event
join public.inventory_lots lot on lot.id = event.lot;

create view public.daily_nutrition
with (security_invoker = true)
as
select
  (event.occurred_at at time zone settings.time_zone)::date as local_date,
  sum(-event.quantity_delta * nutrition.kcal) as kcal,
  sum(-event.quantity_delta * nutrition.protein_g) as protein_g,
  sum(-event.quantity_delta * nutrition.carbs_g) as carbs_g,
  sum(-event.quantity_delta * nutrition.fat_g) as fat_g,
  sum(-event.quantity_delta * nutrition.fiber_g) as fiber_g,
  sum(-event.quantity_delta * nutrition.sodium_mg) as sodium_mg
from public.inventory_events event
cross join public.app_settings settings
cross join lateral public.lot_nutrition_per_base_unit(event.lot) nutrition
where event.reason = 'eaten'
  and event.voided_at is null
group by (event.occurred_at at time zone settings.time_zone)::date;

grant execute on function public.to_base_quantity(uuid, numeric, uuid) to authenticated;
grant execute on function public.from_base_quantity(uuid, numeric, uuid) to authenticated;
grant execute on function public.lot_nutrition_per_base_unit(uuid) to authenticated;
grant execute on function public.prep_total_cost(uuid) to authenticated;
revoke execute on function public.lot_nutrition_json(uuid, uuid[]) from public, anon;
grant execute on function public.lot_nutrition_json(uuid, uuid[]) to authenticated;
grant select on public.inventory_event_costs to authenticated;
grant select on public.daily_nutrition to authenticated;
