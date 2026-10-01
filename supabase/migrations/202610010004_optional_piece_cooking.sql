-- Optional counted pieces are a proportional estimate alongside canonical mass.
-- No historical counts are inferred. Existing events continue to govern remaining
-- mass, so void/undo restores the same estimated remaining pieces automatically.
alter table public.inventory_lots add column piece_count numeric;
alter table public.inventory_lots add column piece_basis_qty numeric;
alter table public.inventory_lots add constraint inventory_lot_piece_basis_valid check (
  (piece_count is null and piece_basis_qty is null) or
  (piece_count is not null and piece_basis_qty is not null and piece_count > 0 and piece_basis_qty > 0
    and piece_count::text not in ('NaN','Infinity','-Infinity')
    and piece_basis_qty::text not in ('NaN','Infinity','-Infinity'))
);

create function public.prepare_recipe(
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
  if recipe_row.override_kcal is not null or recipe_row.override_protein_g is not null
    or recipe_row.override_carbs_g is not null or recipe_row.override_fat_g is not null
    or recipe_row.override_fiber_g is not null or recipe_row.override_sugar_g is not null
    or recipe_row.override_sodium_mg is not null then
    raise exception 'This recipe has fixed nutrition overrides; use weighed quantities until its nutrition can follow actual ingredients';
  end if;
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
      if counted_pieces is null then
        counted_pieces := (piece_input->>'lotPieces')::numeric;
        basis := lot_row.remaining_qty;
        if counted_pieces is null or counted_pieces::text in ('NaN', 'Infinity', '-Infinity') or counted_pieces <= 0 or mod(counted_pieces * 4, 1) <> 0 or basis <= 0 then
          raise exception 'Enter the pieces currently in this lot; no historical count is assumed';
        end if;
        update public.inventory_lots set piece_count = counted_pieces, piece_basis_qty = basis where id = lot_row.id;
      end if;
      needed := selected_pieces * basis / counted_pieces;
      if needed > lot_row.remaining_qty + 0.0000001 then raise exception 'This lot does not contain that many pieces'; end if;
      needed := least(needed, lot_row.remaining_qty);
      insert into public.inventory_events(lot, quantity_delta, reason, prep, note)
        values (lot_row.id, -needed, 'prep', prep_id, 'Estimated weight from counted pieces');
      piece_snapshot := piece_snapshot || jsonb_build_array(jsonb_build_object(
        'ingredientId', ingredient_row.id, 'lotId', lot_row.id, 'pieces', selected_pieces,
        'basisPieces', counted_pieces, 'basisQuantity', basis, 'quantity', needed,
        'method', 'proportional package weight; individual pieces may differ'));
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
  update public.preps set nutrition_is_estimated = true,
    nutrition_source = 'Counted pieces allocated proportionally from lot weight',
    nutrition_estimate = jsonb_build_object('method', 'proportional_piece_weight', 'confidence', 'approximate', 'inputs', piece_snapshot),
    components = piece_snapshot where id = prep_id;
  insert into public.inventory_lots(prep, initial_qty, remaining_qty, location, cost_is_estimated, cost_source)
    values (prep_id, servings_made, servings_made, p_location, true, 'Ingredient portions estimated from counted pieces');
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

-- Execution permission is deliberately withheld pending explicit approval.
revoke all on function public.prepare_recipe(uuid, jsonb, uuid, numeric, numeric, text, uuid, numeric, timestamptz)
  from public, anon, authenticated, service_role;
