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
    insert into public.recipe_ingredients(recipe, ingredient, qty, unit, sort_order, note)
    values (recipe_id, food_id, (ingredient ->> 'quantity')::numeric, unit_id,
      coalesce((ingredient ->> 'sortOrder')::integer, 0), nullif(ingredient ->> 'note', ''));
  end loop;
  return jsonb_build_object('status', 'saved', 'id', recipe_id);
end;
$$;
