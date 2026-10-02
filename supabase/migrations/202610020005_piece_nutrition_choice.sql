-- Preserve recipe overrides for uniform piece batches and snapshot their scaled
-- totals across actual yield. Explicit per-batch ingredient nutrition never edits
-- the recipe. Existing batches and function ACLs remain unchanged.
create or replace function public.prepare_recipe(
  p_recipe uuid,
  p_piece_inputs jsonb,
  p_request_id uuid,
  p_scale numeric default 1,
  p_servings numeric default null,
  p_location text default 'fridge',
  p_meal_plan uuid default null,
  p_eaten_servings numeric default 0,
  p_occurred_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  action_result jsonb;
  recipe_row public.recipes%rowtype;
  plan_row public.meal_plans%rowtype;
  effective_scale numeric;
  servings_made numeric;
  prep_id uuid;
  lot_id uuid;
  log_id uuid;
  ingredient_row public.recipe_ingredients%rowtype;
  lot_row public.inventory_lots%rowtype;
  piece_input jsonb;
  piece_snapshot jsonb := '[]'::jsonb;
  needed numeric;
  taken numeric;
  counted_pieces numeric;
  selected_pieces numeric;
  basis numeric;
  expected numeric;
  selected_weight numeric;
  has_override boolean;
  use_ingredient_nutrition boolean;
  override_snapshot jsonb;

begin
  if not public.is_app_owner() then
    raise exception 'Only the app owner may prepare recipes' using errcode = '42501';
  end if;
  action_result := public.claim_mutation_payload(p_request_id, 'prepareRecipePieces', jsonb_build_object(
    'recipe', p_recipe, 'pieceInputs', p_piece_inputs, 'scale', p_scale, 'servings', p_servings,
    'location', p_location, 'mealPlan', p_meal_plan, 'eatenServings', p_eaten_servings, 'occurredAt', p_occurred_at));
  if action_result is not null then return action_result; end if;
  select * into recipe_row from public.recipes where id = p_recipe;
  if not found then raise exception 'Recipe does not exist'; end if;

  if jsonb_typeof(p_piece_inputs) is distinct from 'array' or jsonb_array_length(p_piece_inputs) = 0 then
    raise exception 'Choose at least one ingredient to cook by pieces';
  end if;
  if exists (select 1 from jsonb_array_elements(p_piece_inputs) item
    where not exists (select 1 from public.recipe_ingredients i where i.id = (item->>'ingredientId')::uuid and i.recipe = p_recipe))
    or (select count(*) from jsonb_array_elements(p_piece_inputs)) <>
       (select count(distinct item->>'ingredientId') from jsonb_array_elements(p_piece_inputs) item) then
    raise exception 'Each piece input must match one distinct recipe ingredient';
  end if;
  has_override := recipe_row.override_kcal is not null or recipe_row.override_protein_g is not null
    or recipe_row.override_carbs_g is not null or recipe_row.override_fat_g is not null
    or recipe_row.override_fiber_g is not null or recipe_row.override_sugar_g is not null
    or recipe_row.override_sodium_mg is not null;
  use_ingredient_nutrition := exists(select 1 from jsonb_array_elements(p_piece_inputs) item
    where item->'useIngredientNutrition'='true'::jsonb);
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

  for ingredient_row in select * from public.recipe_ingredients where recipe=p_recipe and piece_basis->>'anchor'='true' loop
    select item into piece_input from jsonb_array_elements(p_piece_inputs) item where item->>'ingredientId'=ingredient_row.id::text and item->>'scaleRecipe'='true';
    if piece_input is not null then
      select * into lot_row from public.inventory_lots where id=(piece_input->>'lotId')::uuid for update;
      selected_weight := coalesce((piece_input->>'weightGrams')::numeric,
        (piece_input->>'pieces')::numeric * coalesce(lot_row.piece_basis_qty/nullif(lot_row.piece_count,0),
        (ingredient_row.piece_basis->>'grams')::numeric/(ingredient_row.piece_basis->>'count')::numeric));
      effective_scale := selected_weight/(ingredient_row.piece_basis->>'grams')::numeric;
    end if;
  end loop;

  if effective_scale is null or effective_scale::text in ('NaN','Infinity','-Infinity') or effective_scale <= 0 then raise exception 'Recipe scale must be positive'; end if;
  servings_made := coalesce(p_servings, recipe_row.servings * effective_scale);
  if servings_made is null or servings_made::text in ('NaN','Infinity','-Infinity') or servings_made <= 0 then raise exception 'Servings made must be positive'; end if;
  if p_eaten_servings is null or p_eaten_servings::text in ('NaN','Infinity','-Infinity') or p_eaten_servings < 0 or p_eaten_servings > servings_made then
    raise exception 'Servings eaten must be between zero and the servings made';
  end if;

  insert into public.preps(recipe, scale_factor, actual_yield_qty)
    values (p_recipe, effective_scale, servings_made) returning id into prep_id;
  for ingredient_row in select * from public.recipe_ingredients where recipe = p_recipe order by sort_order, id loop
    select item into piece_input from jsonb_array_elements(p_piece_inputs) item where item->>'ingredientId' = ingredient_row.id::text;
    if piece_input is not null then
      select lot.* into lot_row from public.inventory_lots lot
        join public.products product on product.id = lot.product
        join public.base_foods food on food.id = product.food
        where lot.id = (piece_input->>'lotId')::uuid and product.food = ingredient_row.ingredient
          and food.measure_style = 'weight' and not food.always_available
          and (ingredient_row.pinned_product is null or product.id = ingredient_row.pinned_product)
        for update of lot;
      if not found then raise exception 'Choose a matching weighed inventory lot for pieces'; end if;
      expected := (piece_input->>'expectedRemaining')::numeric;
      selected_pieces := (piece_input->>'pieces')::numeric;
      if expected is null or expected::text in ('NaN', 'Infinity', '-Infinity') or abs(expected - lot_row.remaining_qty) > 0.0000001 then
        raise exception 'This lot changed. Refresh and confirm the remaining pieces before cooking';
      end if;
      if selected_pieces is null or selected_pieces::text in ('NaN', 'Infinity', '-Infinity') or selected_pieces <= 0 or mod(selected_pieces * 4, 1) <> 0 then
        raise exception 'Use positive whole, half, or quarter pieces';
      end if;
      counted_pieces := lot_row.piece_count;
      basis := lot_row.piece_basis_qty;
      selected_weight := (piece_input->>'weightGrams')::numeric;
      if selected_weight is not null and (ingredient_row.piece_basis is null or selected_weight::text in ('NaN','Infinity','-Infinity') or selected_weight<=0) then
        raise exception 'Known piece weight must be positive and use a saved recipe estimate';
      end if;
      if counted_pieces is null and ingredient_row.piece_basis is not null then
        counted_pieces := (ingredient_row.piece_basis->>'count')::numeric;
        basis := (ingredient_row.piece_basis->>'grams')::numeric;
      elsif counted_pieces is null then
        counted_pieces := (piece_input->>'lotPieces')::numeric;
        basis := lot_row.remaining_qty;
        if counted_pieces is null or counted_pieces::text in ('NaN','Infinity','-Infinity') or counted_pieces<=0 or mod(counted_pieces*4,1)<>0 or basis<=0 then
          raise exception 'Enter the pieces currently in this lot; no historical count is assumed';
        end if;
        update public.inventory_lots set piece_count=counted_pieces,piece_basis_qty=basis where id=lot_row.id;
      end if;
      needed := coalesce(selected_weight,selected_pieces*basis/counted_pieces);
      if needed > lot_row.remaining_qty + 0.0000001 then raise exception 'This lot does not contain that many pieces'; end if;
      if has_override and not use_ingredient_nutrition and abs(needed-public.to_base_quantity(ingredient_row.ingredient,ingredient_row.qty*effective_scale,ingredient_row.unit))>0.0001 then
        raise exception 'Selected pieces change ingredient proportions. Choose ingredient nutrition for this batch';
      end if;
      needed := least(needed, lot_row.remaining_qty);
      insert into public.inventory_events(lot, quantity_delta, reason, prep, note)
        values (lot_row.id, -needed, 'prep', prep_id, 'Piece weight: entered, lot average or recipe estimate');
      piece_snapshot := piece_snapshot || jsonb_build_array(jsonb_build_object(
        'ingredientId', ingredient_row.id, 'lotId', lot_row.id, 'pieces', selected_pieces,
        'basisPieces', counted_pieces, 'basisQuantity', basis, 'quantity', needed,
        'method', case when selected_weight is not null then 'user supplied weight' when lot_row.piece_count is not null then 'lot average; individual pieces may differ' else 'saved recipe estimate' end, 'recipeBasis', ingredient_row.piece_basis));
    else
      if exists (select 1 from public.base_foods where id = ingredient_row.ingredient and always_available) then continue; end if;
      needed := public.to_base_quantity(ingredient_row.ingredient, ingredient_row.qty * effective_scale, ingredient_row.unit);
      for lot_row in select lot.* from public.inventory_lots lot
        left join public.products product on product.id = lot.product
        left join public.preps prep on prep.id = lot.prep and prep.voided_at is null
        left join public.recipes recipe on recipe.id = prep.recipe
        where lot.remaining_qty > 0 and coalesce(product.food, recipe.output_food) = ingredient_row.ingredient
          and (ingredient_row.pinned_product is null or product.id = ingredient_row.pinned_product)
        order by lot.use_by asc nulls last, lot.acquired_at, lot.id for update of lot loop
        exit when needed <= 0.0000001;
        taken := least(needed, lot_row.remaining_qty);
        insert into public.inventory_events(lot, quantity_delta, reason, prep) values (lot_row.id, -taken, 'prep', prep_id);
        needed := needed - taken;
      end loop;
      if needed > 0.0000001 then raise exception 'Not enough inventory for ingredient %', ingredient_row.ingredient; end if;
    end if;
  end loop;
  override_snapshot := jsonb_build_object(
    'kcal', case when use_ingredient_nutrition then null else recipe_row.override_kcal / recipe_row.override_basis_qty * recipe_row.servings * effective_scale / servings_made end,
    'protein_g', case when use_ingredient_nutrition then null else recipe_row.override_protein_g / recipe_row.override_basis_qty * recipe_row.servings * effective_scale / servings_made end,
    'carbs_g', case when use_ingredient_nutrition then null else recipe_row.override_carbs_g / recipe_row.override_basis_qty * recipe_row.servings * effective_scale / servings_made end,
    'fat_g', case when use_ingredient_nutrition then null else recipe_row.override_fat_g / recipe_row.override_basis_qty * recipe_row.servings * effective_scale / servings_made end,
    'fiber_g', case when use_ingredient_nutrition then null else recipe_row.override_fiber_g / recipe_row.override_basis_qty * recipe_row.servings * effective_scale / servings_made end,
    'sugar_g', case when use_ingredient_nutrition then null else recipe_row.override_sugar_g / recipe_row.override_basis_qty * recipe_row.servings * effective_scale / servings_made end,
    'sodium_mg', case when use_ingredient_nutrition then null else recipe_row.override_sodium_mg / recipe_row.override_basis_qty * recipe_row.servings * effective_scale / servings_made end
  );
  update public.preps set nutrition_is_estimated = true,
    nutrition_source = 'Piece weights from entered weight, lot averages or saved recipe estimates',
    nutrition_estimate = jsonb_build_object('method', 'proportional_piece_weight', 'confidence', 'approximate', 'inputs', piece_snapshot, 'recipeOverridePerServing', override_snapshot,
      'nutritionMode', case when use_ingredient_nutrition then 'ingredients' else 'uniform_recipe' end),
    components = piece_snapshot where id = prep_id;
  insert into public.inventory_lots(prep, initial_qty, remaining_qty, location, cost_is_estimated, cost_source)
    values (prep_id, servings_made, servings_made, p_location, true, 'Ingredient portions from selected piece weights');
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

  action_result := jsonb_build_object(
    'prepId', prep_id,
    'lotId', lot_id,
    'mealPlanId', p_meal_plan,
    'servingsMade', servings_made,
    'servingsRemaining', servings_made - p_eaten_servings,
    'location', p_location,
    'foodLogId', log_id
  );
  perform public.gpt_complete_request(p_request_id, action_result);
  return action_result;
end;
$$;


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
    'kcal', coalesce(case when prep_row.nutrition_estimate ? 'recipeOverridePerServing' then (prep_row.nutrition_estimate #>> '{recipeOverridePerServing,kcal}')::numeric else recipe.override_kcal / recipe.override_basis_qty end, (derived ->> 'kcal')::numeric / prep_yield),
    'protein_g', coalesce(case when prep_row.nutrition_estimate ? 'recipeOverridePerServing' then (prep_row.nutrition_estimate #>> '{recipeOverridePerServing,protein_g}')::numeric else recipe.override_protein_g / recipe.override_basis_qty end, (derived ->> 'protein_g')::numeric / prep_yield),
    'carbs_g', coalesce(case when prep_row.nutrition_estimate ? 'recipeOverridePerServing' then (prep_row.nutrition_estimate #>> '{recipeOverridePerServing,carbs_g}')::numeric else recipe.override_carbs_g / recipe.override_basis_qty end, (derived ->> 'carbs_g')::numeric / prep_yield),
    'fat_g', coalesce(case when prep_row.nutrition_estimate ? 'recipeOverridePerServing' then (prep_row.nutrition_estimate #>> '{recipeOverridePerServing,fat_g}')::numeric else recipe.override_fat_g / recipe.override_basis_qty end, (derived ->> 'fat_g')::numeric / prep_yield),
    'fiber_g', coalesce(case when prep_row.nutrition_estimate ? 'recipeOverridePerServing' then (prep_row.nutrition_estimate #>> '{recipeOverridePerServing,fiber_g}')::numeric else recipe.override_fiber_g / recipe.override_basis_qty end, (derived ->> 'fiber_g')::numeric / prep_yield),
    'sugar_g', coalesce(case when prep_row.nutrition_estimate ? 'recipeOverridePerServing' then (prep_row.nutrition_estimate #>> '{recipeOverridePerServing,sugar_g}')::numeric else recipe.override_sugar_g / recipe.override_basis_qty end, (derived ->> 'sugar_g')::numeric / prep_yield),
    'sodium_mg', coalesce(case when prep_row.nutrition_estimate ? 'recipeOverridePerServing' then (prep_row.nutrition_estimate #>> '{recipeOverridePerServing,sodium_mg}')::numeric else recipe.override_sodium_mg / recipe.override_basis_qty end, (derived ->> 'sodium_mg')::numeric / prep_yield)
  ) into result
  from public.recipes recipe where recipe.id = prep_row.recipe;
  return result;
end;
$$;

