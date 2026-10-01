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
        insert into public.recipe_ingredients(recipe,ingredient,qty,unit,sort_order,note)
        values(p_recipe,food_id,(ingredient_input->>'quantity')::numeric,unit_id,(ingredient_input->>'sortOrder')::integer,nullif(ingredient_input->>'note',''))
        returning id into ingredient_id;
        matched_ids:=array_append(matched_ids,ingredient_id);
      else
        select * into strict old_ingredient from public.recipe_ingredients where id=ingredient_id;
        update public.recipe_ingredients set ingredient=food_id,unit=unit_id,qty=(ingredient_input->>'quantity')::numeric,
          sort_order=(ingredient_input->>'sortOrder')::integer,
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

