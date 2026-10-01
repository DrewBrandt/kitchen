-- Preserve unknown ingredient nutrients per nutrient and carry estimate provenance into new preparations.
-- Existing function ACLs are retained; no historical rows are rewritten.

create or replace function public.lot_nutrition_json(
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
  prep_row public.preps%rowtype;
  prep_yield numeric;
  result jsonb;
  derived jsonb;
begin
  if p_lot = any(p_path) then
    raise exception 'Prepared-lot nutrition graph contains a cycle at lot %', p_lot;
  end if;

  select product, prep into lot_product, lot_prep
  from public.inventory_lots where id = p_lot;
  if not found then raise exception 'Inventory lot % does not exist', p_lot; end if;

  if lot_product is not null then
    select jsonb_build_object(
      'kcal', case when product.kcal is null then food.kcal / nullif(food.nutrition_basis_qty, 0) else product.kcal * public.product_nutrition_multiplier(product.id, 1) end,
      'protein_g', case when product.protein_g is null then food.protein_g / nullif(food.nutrition_basis_qty, 0) else product.protein_g * public.product_nutrition_multiplier(product.id, 1) end,
      'carbs_g', case when product.carbs_g is null then food.carbs_g / nullif(food.nutrition_basis_qty, 0) else product.carbs_g * public.product_nutrition_multiplier(product.id, 1) end,
      'fat_g', case when product.fat_g is null then food.fat_g / nullif(food.nutrition_basis_qty, 0) else product.fat_g * public.product_nutrition_multiplier(product.id, 1) end,
      'fiber_g', case when product.fiber_g is null then food.fiber_g / nullif(food.nutrition_basis_qty, 0) else product.fiber_g * public.product_nutrition_multiplier(product.id, 1) end,
      'sugar_g', case when product.sugar_g is null then food.sugar_g / nullif(food.nutrition_basis_qty, 0) else product.sugar_g * public.product_nutrition_multiplier(product.id, 1) end,
      'sodium_mg', case when product.sodium_mg is null then food.sodium_mg / nullif(food.nutrition_basis_qty, 0) else product.sodium_mg * public.product_nutrition_multiplier(product.id, 1) end
    ) into result
    from public.products product
    join public.base_foods food on food.id = product.food
    where product.id = lot_product;
    return result;
  end if;

  select * into prep_row from public.preps prep where prep.id = lot_prep and prep.voided_at is null;
  prep_yield := prep_row.actual_yield_qty;
  if prep_yield is null or prep_yield <= 0 then
    raise exception 'Prep % needs an actual yield before nutrition can resolve', lot_prep;
  end if;

  if prep_row.recipe is null then
    return jsonb_build_object(
      'kcal', prep_row.kcal,
      'protein_g', prep_row.protein_g,
      'carbs_g', prep_row.carbs_g,
      'fat_g', prep_row.fat_g,
      'fiber_g', prep_row.fiber_g,
      'sugar_g', prep_row.sugar_g,
      'sodium_mg', prep_row.sodium_mg
    );
  end if;

  select jsonb_build_object(
    'kcal', case when count(*) > 0 and bool_and((nutrients.value ->> 'kcal') is not null) then sum(-event.quantity_delta * (nutrients.value ->> 'kcal')::numeric) else null end,
    'protein_g', case when count(*) > 0 and bool_and((nutrients.value ->> 'protein_g') is not null) then sum(-event.quantity_delta * (nutrients.value ->> 'protein_g')::numeric) else null end,
    'carbs_g', case when count(*) > 0 and bool_and((nutrients.value ->> 'carbs_g') is not null) then sum(-event.quantity_delta * (nutrients.value ->> 'carbs_g')::numeric) else null end,
    'fat_g', case when count(*) > 0 and bool_and((nutrients.value ->> 'fat_g') is not null) then sum(-event.quantity_delta * (nutrients.value ->> 'fat_g')::numeric) else null end,
    'fiber_g', case when count(*) > 0 and bool_and((nutrients.value ->> 'fiber_g') is not null) then sum(-event.quantity_delta * (nutrients.value ->> 'fiber_g')::numeric) else null end,
    'sugar_g', case when count(*) > 0 and bool_and((nutrients.value ->> 'sugar_g') is not null) then sum(-event.quantity_delta * (nutrients.value ->> 'sugar_g')::numeric) else null end,
    'sodium_mg', case when count(*) > 0 and bool_and((nutrients.value ->> 'sodium_mg') is not null) then sum(-event.quantity_delta * (nutrients.value ->> 'sodium_mg')::numeric) else null end
  ) into derived
  from public.inventory_events event
  cross join lateral (
    select public.lot_nutrition_json(event.lot, p_path || p_lot) as value
  ) nutrients
  where event.prep = lot_prep and event.reason = 'prep' and event.voided_at is null;

  select jsonb_build_object(
    'kcal', coalesce(recipe.override_kcal / recipe.override_basis_qty, (derived ->> 'kcal')::numeric / prep_yield),
    'protein_g', coalesce(recipe.override_protein_g / recipe.override_basis_qty, (derived ->> 'protein_g')::numeric / prep_yield),
    'carbs_g', coalesce(recipe.override_carbs_g / recipe.override_basis_qty, (derived ->> 'carbs_g')::numeric / prep_yield),
    'fat_g', coalesce(recipe.override_fat_g / recipe.override_basis_qty, (derived ->> 'fat_g')::numeric / prep_yield),
    'fiber_g', coalesce(recipe.override_fiber_g / recipe.override_basis_qty, (derived ->> 'fiber_g')::numeric / prep_yield),
    'sugar_g', coalesce(recipe.override_sugar_g / recipe.override_basis_qty, (derived ->> 'sugar_g')::numeric / prep_yield),
    'sodium_mg', coalesce(recipe.override_sodium_mg / recipe.override_basis_qty, (derived ->> 'sodium_mg')::numeric / prep_yield)
  ) into result
  from public.recipes recipe where recipe.id = prep_row.recipe;
  return result;
end;
$$;

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

  -- Snapshot provenance for this new preparation; historical preparations remain unchanged.
  update public.preps
  set nutrition_is_estimated = inputs.estimated,
      nutrition_source = inputs.source
  from (
    select coalesce(bool_or(coalesce(product.nutrition_is_estimated, false)
      or coalesce(food.nutrition_is_estimated, false)
      or coalesce(source_prep.nutrition_is_estimated, false)), false) as estimated,
      string_agg(distinct coalesce(product.nutrition_source, food.nutrition_source, source_prep.nutrition_source), '; ') as source
    from public.inventory_events event
    join public.inventory_lots input_lot on input_lot.id = event.lot
    left join public.products product on product.id = input_lot.product
    left join public.base_foods food on food.id = product.food
    left join public.preps source_prep on source_prep.id = input_lot.prep
    where event.prep = new_prep and event.reason = 'prep' and event.voided_at is null
  ) inputs
  where id = new_prep;

  insert into public.inventory_lots(prep, initial_qty, remaining_qty, location)
  values (new_prep, actual_yield, actual_yield, p_location);

  return new_prep;
end;
$$;


-- Unknown cost is valid when explicitly estimated and supported by acquisition provenance.
-- Missing source, payer, acquisition type, or dates for known prices still fails.
create or replace function public.enforce_inventory_lot_provenance()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_lot public.inventory_lots%rowtype;
begin
  select * into current_lot
  from public.inventory_lots
  where id = new.id;

  if not found then
    return null;
  end if;

  if current_lot.acquisition_type is null
    or (current_lot.out_of_pocket_cost is null and not current_lot.cost_is_estimated)
    or nullif(trim(current_lot.paid_by), '') is null
    or nullif(trim(current_lot.cost_source), '') is null
    or (
      current_lot.acquisition_type in ('grocery', 'restaurant', 'takeout')
      and current_lot.total_cost is null
      and not current_lot.cost_is_estimated
    )
    or (current_lot.total_cost is not null and current_lot.price_as_of is null)
  then
    raise exception 'Inventory lot % is missing required acquisition or cost provenance', current_lot.id
      using errcode = '23514',
        constraint = 'inventory_lots_provenance_required';
  end if;

  return null;
end;
$$;



-- Keep the prepared-lot provenance derivation lint-clean.

create or replace function public.refresh_prepared_lot_provenance(p_prep uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  derived_out_of_pocket numeric;
  derived_paid_by text;
  derived_is_estimated boolean;
  derived_source text;
  derived_price_as_of date;
begin
  select
    case when count(*) = 0 then 0
      when bool_and(source_lot.out_of_pocket_cost is not null)
        then round(sum(-event.quantity_delta * source_lot.out_of_pocket_cost / source_lot.initial_qty), 2)
      else null end,
    coalesce(string_agg(distinct nullif(trim(source_lot.paid_by), ''), '; '), 'household'),
    coalesce(bool_or(source_lot.cost_is_estimated), false),
    case when count(*) = 0 then 'Prepared entirely from always-available household ingredients'
      else 'Carried forward from ingredient lots: ' || coalesce(
        string_agg(distinct nullif(trim(source_lot.cost_source), ''), '; '),
        'ingredient purchase records') end,
    max(source_lot.price_as_of)
  into derived_out_of_pocket, derived_paid_by,
       derived_is_estimated, derived_source, derived_price_as_of
  from public.inventory_events event
  join public.inventory_lots source_lot on source_lot.id = event.lot
  where event.prep = p_prep
    and event.reason = 'prep'
    and event.voided_at is null;

  update public.inventory_lots output_lot
  set acquisition_type = 'home',
      is_external = false,
      out_of_pocket_cost = derived_out_of_pocket,
      paid_by = derived_paid_by,
      cost_is_estimated = derived_is_estimated or coalesce(prep.nutrition_estimate ->> 'method' = 'proportional_piece_weight', false),
      cost_source = derived_source,
      price_as_of = case when output_lot.total_cost is null then null else coalesce(derived_price_as_of, case when output_lot.total_cost = 0 then prep.prepped_at::date end) end,
      acquired_time_precision = prep.time_precision
  from public.preps prep
  where output_lot.prep = p_prep and prep.id = p_prep;
end;
$$;

revoke all on function public.refresh_prepared_lot_provenance(uuid)
  from public, anon, authenticated, service_role;

-- Recipe cooking creates ingredient events before its output lot. Initialize provenance only
-- after that lot exists, including direct app cooking and proportional-piece cooking.
create function public.initialize_recipe_lot_provenance()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if exists(select 1 from public.preps where id = new.prep and recipe is not null) then
    perform public.refresh_prepared_lot_provenance(new.prep);
  end if;
  return null;
end;
$$;
revoke all on function public.initialize_recipe_lot_provenance() from public, anon, authenticated, service_role;
create trigger inventory_lots_initialize_recipe_provenance
after insert on public.inventory_lots for each row when (new.prep is not null)
execute function public.initialize_recipe_lot_provenance();
