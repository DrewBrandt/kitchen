-- Recipe-local estimates; canonical qty/unit remain the planning mass basis.
alter table public.recipe_ingredients add column piece_basis jsonb;
create unique index recipe_one_piece_anchor on public.recipe_ingredients(recipe)
where piece_basis->>'anchor' = 'true';
create function public.validate_recipe_piece_basis() returns trigger
language plpgsql set search_path = '' as $$
declare b jsonb := new.piece_basis; grams numeric;
begin
  if b is null then return new; end if;
  grams := public.to_base_quantity(new.ingredient,new.qty,new.unit);
  if jsonb_typeof(b) <> 'object' or not (b ?& array['count','grams','label','sourceQuantity','sourceUnit','provenance'])
    or jsonb_typeof(b->'sourceQuantity') <> 'number' or jsonb_typeof(b->'label') <> 'string' or jsonb_typeof(b->'sourceUnit') <> 'string' or jsonb_typeof(b->'provenance') <> 'string'
    or jsonb_typeof(b->'count') <> 'number' or jsonb_typeof(b->'grams') <> 'number'
    or (b->>'count')::numeric <= 0 or mod((b->>'count')::numeric*4,1) <> 0
    or (b->>'grams')::numeric <= 0 or abs(grams-(b->>'grams')::numeric)>0.0001
    or coalesce(length(trim(b->>'label')),0)=0 or coalesce(length(trim(b->>'provenance')),0)=0
    or coalesce(length(trim(b->>'sourceUnit')),0)=0 or coalesce((b->>'sourceQuantity')::numeric,0)<=0
    or (b ? 'anchor' and jsonb_typeof(b->'anchor') <> 'boolean')
    or not exists(select 1 from public.base_foods where id=new.ingredient and measure_style='weight' and not always_available)
  then raise exception 'Piece estimate requires a positive quarter-piece count, matching canonical grams, label and source provenance'; end if;
  return new;
end $$;
revoke all on function public.validate_recipe_piece_basis() from public,anon,authenticated,service_role;
create trigger validate_recipe_piece_basis before insert or update on public.recipe_ingredients
for each row execute function public.validate_recipe_piece_basis();

-- Preserve recipe metadata and nutrition facts during atomic edits. No ACL changes.
-- If nutrition is omitted, retain its stored basis and values even on yield edits:
-- per-serving override nutrition stays constant. Explicit nutrition replaces batch
-- totals with next_servings as its basis; explicit null clears the override.
create or replace function public.gpt_update_recipe(p_recipe uuid, p_patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  recipe_row public.recipes%rowtype;
  updated_row public.recipes%rowtype;
  bad_key text;
  ingredient_input jsonb;
  normalized jsonb := '[]'::jsonb;
  matched_ids uuid[] := array[]::uuid[];
  ingredient_id uuid;
  ordinal integer;
  pass integer;
  candidates uuid[];
  competing_inputs integer;
  old_ingredient public.recipe_ingredients%rowtype;
  food_id uuid;
  unit_id uuid;
  next_servings numeric;
  before_state jsonb;
  after_state jsonb;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  if jsonb_typeof(p_patch) <> 'object' or p_patch = '{}'::jsonb then raise exception 'patch must be a non-empty object'; end if;
  select key into bad_key from jsonb_object_keys(p_patch) key
  where key <> all(array['name','emoji','servings','instructions','portions','preparationRules','sourceUrl','sourceNote','promptForFeedback','nutrition','ingredients']) limit 1;
  if bad_key is not null then raise exception 'Unsupported recipe edit field: %', bad_key; end if;
  if p_patch ? 'ingredients' and (jsonb_typeof(p_patch -> 'ingredients') <> 'array' or jsonb_array_length(p_patch -> 'ingredients') = 0) then raise exception 'ingredients must be a non-empty array'; end if;
  if p_patch ? 'instructions' and jsonb_typeof(p_patch -> 'instructions') <> 'array' then raise exception 'instructions must be an array'; end if;
  if p_patch ? 'portions' and jsonb_typeof(p_patch -> 'portions') <> 'array' then raise exception 'portions must be an array'; end if;
  if p_patch ? 'preparationRules' and jsonb_typeof(p_patch -> 'preparationRules') <> 'array' then raise exception 'preparationRules must be an array'; end if;
  if p_patch ? 'nutrition' and p_patch -> 'nutrition' <> 'null'::jsonb and jsonb_typeof(p_patch -> 'nutrition') <> 'object' then raise exception 'nutrition must be an object or null'; end if;

  select * into recipe_row from public.recipes where id = p_recipe for update;
  if not found then raise exception 'Recipe does not exist'; end if;
  if p_patch ? 'name' and trim(coalesce(p_patch ->> 'name', '')) = '' then raise exception 'name cannot be empty'; end if;
  next_servings := case when p_patch ? 'servings' then (p_patch ->> 'servings')::numeric else recipe_row.servings end;
  if next_servings <= 0 then raise exception 'servings must be positive'; end if;
  before_state := jsonb_build_object('recipe', to_jsonb(recipe_row), 'ingredients',
    coalesce((select jsonb_agg(to_jsonb(item) order by item.sort_order) from public.recipe_ingredients item where item.recipe = p_recipe), '[]'::jsonb));

  update public.recipes set
    name = case when p_patch ? 'name' then trim(p_patch ->> 'name') else name end,
    emoji = case when p_patch ? 'emoji' then nullif(p_patch ->> 'emoji', '') else emoji end,
    servings = next_servings,
    instructions = case when p_patch ? 'instructions' then p_patch -> 'instructions' else instructions end,
    portions = case when p_patch ? 'portions' then coalesce(p_patch -> 'portions', '[]'::jsonb) else portions end,
    preparation_rules = case when p_patch ? 'preparationRules' then coalesce(p_patch -> 'preparationRules', '[]'::jsonb) else preparation_rules end,
    source_url = case when p_patch ? 'sourceUrl' then nullif(p_patch ->> 'sourceUrl', '') else source_url end,
    source_note = case when p_patch ? 'sourceNote' then nullif(p_patch ->> 'sourceNote', '') else source_note end,
    prompt_for_feedback = case when p_patch ? 'promptForFeedback' then (p_patch ->> 'promptForFeedback')::boolean else prompt_for_feedback end,
    override_basis_qty = case when p_patch ? 'nutrition' then case when p_patch -> 'nutrition' = 'null'::jsonb then null else next_servings end else override_basis_qty end,
    override_kcal = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,calories}', '')::numeric else override_kcal end,
    override_protein_g = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,proteinG}', '')::numeric else override_protein_g end,
    override_carbs_g = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,carbsG}', '')::numeric else override_carbs_g end,
    override_fat_g = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,fatG}', '')::numeric else override_fat_g end,
    override_fiber_g = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,fiberG}', '')::numeric else override_fiber_g end,
    override_sugar_g = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,sugarG}', '')::numeric else override_sugar_g end,
    override_sodium_mg = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,sodiumMg}', '')::numeric else override_sodium_mg end,
    updated_at = now()
  where id = p_recipe returning * into updated_row;

  if p_patch ? 'ingredients' then
    -- App edits carry row IDs. Legacy clients without IDs reserve unchanged
    -- positions across the entire input before attempting any moved/quantity match.
    perform 1 from public.recipe_ingredients where recipe=p_recipe order by id for update;
    for ingredient_input, ordinal in select value, ordinality::integer from jsonb_array_elements(p_patch -> 'ingredients') with ordinality
    loop
      food_id := nullif(ingredient_input ->> 'foodId', '')::uuid;
      if food_id is null then select id into food_id from public.base_foods where lower(name) = lower(ingredient_input ->> 'food'); end if;
      if food_id is null then raise exception 'Unknown ingredient: %', coalesce(ingredient_input ->> 'foodId', ingredient_input ->> 'food'); end if;
      unit_id := public.resolve_measure_conversion(ingredient_input ->> 'unit');
      ingredient_id := nullif(ingredient_input->>'id','')::uuid;
      if ingredient_id is not null then
        if ingredient_id=any(matched_ids) then raise exception 'Duplicate ingredient ID'; end if;
        if not exists(select 1 from public.recipe_ingredients where id=ingredient_id and recipe=p_recipe) then
          raise exception 'Ingredient ID does not belong to this recipe';
        end if;
        matched_ids:=array_append(matched_ids,ingredient_id);
      end if;
      normalized:=normalized||jsonb_build_array(ingredient_input||jsonb_build_object(
        'foodId',food_id,'unit',unit_id,'sortOrder',coalesce((ingredient_input->>'sortOrder')::integer,ordinal-1),'matchedId',ingredient_id));
    end loop;
    -- Pass 1: unchanged position. Pass 2: uniquely identifiable moved row.
    -- Pass 3: uniquely identifiable quantity edit. Never guess between duplicates.
    for pass in 1..3 loop
      for ingredient_input, ordinal in select value, ordinality::integer from jsonb_array_elements(normalized) with ordinality
      loop
        if ingredient_input ? 'id' or ingredient_input->>'matchedId' is not null then continue; end if;
        select array_agg(ri.id order by ri.sort_order,ri.id) into candidates
        from public.recipe_ingredients ri
        where ri.recipe=p_recipe and ri.ingredient=(ingredient_input->>'foodId')::uuid
          and ri.unit=(ingredient_input->>'unit')::uuid and not(ri.id=any(matched_ids))
          and (pass=3 or ri.qty=(ingredient_input->>'quantity')::numeric)
          and (pass<>1 or ri.sort_order=(ingredient_input->>'sortOrder')::integer);
        select count(*) into competing_inputs from jsonb_array_elements(normalized) other
        where not(other ? 'id') and other->>'matchedId' is null
          and other->>'foodId'=ingredient_input->>'foodId' and other->>'unit'=ingredient_input->>'unit'
          and (pass=3 or (other->>'quantity')::numeric=(ingredient_input->>'quantity')::numeric)
          and (pass<>1 or (other->>'sortOrder')::integer=(ingredient_input->>'sortOrder')::integer);
        if cardinality(candidates)=1 and competing_inputs=1 then
          ingredient_id:=candidates[1];
          matched_ids:=array_append(matched_ids,ingredient_id);
          normalized:=jsonb_set(normalized,array[(ordinal-1)::text,'matchedId'],to_jsonb(ingredient_id));
        elsif cardinality(candidates)>0 and pass>1 then
          raise exception 'Ambiguous duplicate ingredients; provide ingredient IDs or use the recipe editor';
        end if;
      end loop;
    end loop;
    for ingredient_input in select value from jsonb_array_elements(normalized)
    loop
      food_id:=(ingredient_input->>'foodId')::uuid;
      unit_id:=(ingredient_input->>'unit')::uuid;
      ingredient_id:=(ingredient_input->>'matchedId')::uuid;
      if ingredient_id is null then
        insert into public.recipe_ingredients(recipe,ingredient,qty,unit,sort_order,note,piece_basis)
        values(p_recipe,food_id,(ingredient_input->>'quantity')::numeric,unit_id,(ingredient_input->>'sortOrder')::integer,nullif(ingredient_input->>'note',''),nullif(ingredient_input->'pieceBasis','null'::jsonb))
        returning id into ingredient_id;
        matched_ids:=array_append(matched_ids,ingredient_id);
      else
        select * into strict old_ingredient from public.recipe_ingredients where id=ingredient_id;
        update public.recipe_ingredients set ingredient=food_id,unit=unit_id,qty=(ingredient_input->>'quantity')::numeric,
          sort_order=(ingredient_input->>'sortOrder')::integer,
          piece_basis=case when ingredient_input ? 'pieceBasis' then nullif(ingredient_input->'pieceBasis','null'::jsonb) else old_ingredient.piece_basis end,
          note=case when ingredient_input ? 'note' then nullif(ingredient_input->>'note','') else old_ingredient.note end
        where id=ingredient_id;
        -- pinned_product and row identity are deliberately left intact.
      end if;
    end loop;
    delete from public.recipe_ingredients where recipe=p_recipe and not(id=any(matched_ids));
  end if;

  after_state := jsonb_build_object('recipe', to_jsonb(updated_row), 'ingredients',
    coalesce((select jsonb_agg(to_jsonb(item) order by item.sort_order) from public.recipe_ingredients item where item.recipe = p_recipe), '[]'::jsonb));
  insert into public.record_edits(resource, record_id, before_state, after_state)
  values ('recipe', p_recipe, before_state, after_state);
  return jsonb_build_object('status', 'updated', 'id', p_recipe);
end;
$$;


-- Deliberate narrowing: existing-ID POST preserves rows and omitted metadata.
-- Removals/replacements or ambiguous identity must use PATCH explicitly.
-- Creation defaults, response, signature, owner guard and ACLs remain unchanged.
create or replace function public.gpt_save_recipe(p_recipe jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  recipe_id uuid := coalesce(nullif(p_recipe ->> 'id', '')::uuid, gen_random_uuid());
  inserted_id uuid;
  original_ids uuid[];
  patch jsonb;
  ingredient jsonb;
  food_id uuid;
  unit_id uuid;
  servings numeric := (p_recipe ->> 'servings')::numeric;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  if trim(coalesce(p_recipe ->> 'name', '')) = '' or servings <= 0 then raise exception 'name and positive servings are required'; end if;
  if jsonb_typeof(p_recipe -> 'ingredients') <> 'array' or jsonb_array_length(p_recipe -> 'ingredients') = 0 then
    raise exception 'ingredients must be a non-empty array';
  end if;

  insert into public.recipes(
    id, name, emoji, servings, instructions, portions, preparation_rules, source_url, source_note,
    prompt_for_feedback, override_basis_qty, override_kcal, override_protein_g, override_carbs_g,
    override_fat_g, override_fiber_g, override_sugar_g, override_sodium_mg
  ) values (
    recipe_id, p_recipe ->> 'name', nullif(p_recipe ->> 'emoji', ''), servings,
    coalesce(p_recipe -> 'instructions', '[]'::jsonb), coalesce(p_recipe -> 'portions', '[]'::jsonb),
    coalesce(p_recipe -> 'preparationRules', '[]'::jsonb), nullif(p_recipe ->> 'sourceUrl', ''),
    nullif(p_recipe ->> 'sourceNote', ''), coalesce((p_recipe ->> 'promptForFeedback')::boolean, true),
    case when p_recipe ? 'nutrition' then servings else null end,
    nullif(p_recipe #>> '{nutrition,calories}', '')::numeric,
    nullif(p_recipe #>> '{nutrition,proteinG}', '')::numeric,
    nullif(p_recipe #>> '{nutrition,carbsG}', '')::numeric,
    nullif(p_recipe #>> '{nutrition,fatG}', '')::numeric,
    nullif(p_recipe #>> '{nutrition,fiberG}', '')::numeric,
    nullif(p_recipe #>> '{nutrition,sugarG}', '')::numeric,
    nullif(p_recipe #>> '{nutrition,sodiumMg}', '')::numeric
  )
  on conflict (id) do nothing returning id into inserted_id;

  if inserted_id is null then
    -- The conflicting insert waits for a concurrent creator. Lock before taking
    -- the identity snapshot; PATCH takes the same recipe/ingredient locks.
    perform 1 from public.recipes where id=recipe_id for update;
    if not found then raise exception 'Recipe no longer exists; refresh before saving'; end if;
    perform 1 from public.recipe_ingredients where recipe=recipe_id order by id for update;
    select coalesce(array_agg(id),array[]::uuid[]) into original_ids
      from public.recipe_ingredients where recipe=recipe_id;
    -- POST historically ignores unknown keys. Do not forward them to PATCH's
    -- stricter top-level validator, or change POST's omitted sortOrder default.
    select jsonb_object_agg(key,value) into patch from jsonb_each(p_recipe)
      where key=any(array['name','emoji','servings','instructions','portions','preparationRules',
        'sourceUrl','sourceNote','promptForFeedback','nutrition','ingredients']);
    if patch ? 'ingredients' then
      select jsonb_agg(value || jsonb_build_object('sortOrder',coalesce((value->>'sortOrder')::integer,0)) order by ordinal)
        into ingredient from jsonb_array_elements(patch->'ingredients') with ordinality as rows(value,ordinal);
      patch:=jsonb_set(patch,'{ingredients}',ingredient);
    end if;
    begin
      perform public.gpt_update_recipe(recipe_id,patch);
    exception when raise_exception then
      if sqlerrm like 'Ambiguous duplicate ingredients%' or sqlerrm in ('Duplicate ingredient ID','Ingredient ID does not belong to this recipe') then
        raise exception 'Ingredient identity is unclear; use PATCH with ingredient IDs';
      end if;
      raise;
    end;
    -- POST's legacy list has no reliable deletion intent. Fail atomically rather
    -- than silently replacing/removing an old row and losing its metadata.
    if exists(select 1 from unnest(original_ids) old(id)
      where not exists(select 1 from public.recipe_ingredients ri where ri.id=old.id and ri.recipe=recipe_id)) then
      raise exception 'Removing or replacing ingredients requires PATCH with ingredient IDs';
    end if;
    return jsonb_build_object('status','saved','id',recipe_id);
  end if;

  delete from public.recipe_ingredients where recipe = recipe_id;
  for ingredient in select value from jsonb_array_elements(p_recipe -> 'ingredients') with ordinality
  loop
    food_id := nullif(ingredient ->> 'foodId', '')::uuid;
    if food_id is null then
      select id into food_id from public.base_foods where lower(name) = lower(ingredient ->> 'food');
    end if;
    if food_id is null then raise exception 'Unknown ingredient: %', coalesce(ingredient ->> 'foodId', ingredient ->> 'food'); end if;
    unit_id := public.resolve_measure_conversion(ingredient ->> 'unit');
    insert into public.recipe_ingredients(recipe, ingredient, qty, unit, sort_order, note, piece_basis)
    values (recipe_id, food_id, (ingredient ->> 'quantity')::numeric, unit_id,
      coalesce((ingredient ->> 'sortOrder')::integer, 0), nullif(ingredient ->> 'note', ''), nullif(ingredient->'pieceBasis','null'::jsonb));
  end loop;
  return jsonb_build_object('status', 'saved', 'id', recipe_id);
end;
$$;

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
  update public.preps set nutrition_is_estimated = true,
    nutrition_source = 'Piece weights from entered weight, lot averages or saved recipe estimates',
    nutrition_estimate = jsonb_build_object('method', 'proportional_piece_weight', 'confidence', 'approximate', 'inputs', piece_snapshot),
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

