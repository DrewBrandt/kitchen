create table public.record_edits (
  id uuid primary key default gen_random_uuid(),
  resource text not null check (resource in ('food', 'product', 'recipe', 'inventory_lot', 'consumption')),
  record_id uuid not null,
  before_state jsonb not null,
  after_state jsonb not null,
  edited_at timestamptz not null default now()
);

create index record_edits_record_idx on public.record_edits(resource, record_id, edited_at desc);

alter table public.record_edits enable row level security;
create policy record_edits_owner_select on public.record_edits
  for select using (public.is_app_owner());
revoke all on public.record_edits from public, anon;
grant select on public.record_edits to authenticated;

create function public.gpt_update_food(p_food uuid, p_patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  food_row public.base_foods%rowtype;
  updated_row public.base_foods%rowtype;
  bad_key text;
  display_unit_id uuid;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  if jsonb_typeof(p_patch) <> 'object' or p_patch = '{}'::jsonb then raise exception 'patch must be a non-empty object'; end if;
  select key into bad_key from jsonb_object_keys(p_patch) key
  where key <> all(array['name','plural','emoji','measureStyle','displayUnit','groceryCategory','ingredientRole','storeAisle','gPerFlOz','gPerCount','aliases','nutrition']) limit 1;
  if bad_key is not null then raise exception 'Unsupported food edit field: %', bad_key; end if;
  if p_patch ? 'aliases' and jsonb_typeof(p_patch -> 'aliases') <> 'array' then raise exception 'aliases must be an array'; end if;
  if p_patch ? 'nutrition' and jsonb_typeof(p_patch -> 'nutrition') <> 'object' then raise exception 'nutrition must be an object'; end if;

  select * into food_row from public.base_foods where id = p_food for update;
  if not found then raise exception 'Food does not exist'; end if;
  if p_patch ? 'name' and trim(coalesce(p_patch ->> 'name', '')) = '' then raise exception 'name cannot be empty'; end if;
  display_unit_id := case when p_patch ? 'displayUnit' then public.resolve_measure_conversion(p_patch ->> 'displayUnit') else food_row.display_unit end;

  update public.base_foods set
    name = case when p_patch ? 'name' then trim(p_patch ->> 'name') else name end,
    plural = case when p_patch ? 'plural' then nullif(p_patch ->> 'plural', '') else plural end,
    emoji = case when p_patch ? 'emoji' then nullif(p_patch ->> 'emoji', '') else emoji end,
    measure_style = case when p_patch ? 'measureStyle' then (p_patch ->> 'measureStyle')::public.measure_style else measure_style end,
    display_unit = display_unit_id,
    grocery_category = case when p_patch ? 'groceryCategory' then nullif(p_patch ->> 'groceryCategory', '') else grocery_category end,
    ingredient_role = case when p_patch ? 'ingredientRole' then nullif(p_patch ->> 'ingredientRole', '') else ingredient_role end,
    store_aisle = case when p_patch ? 'storeAisle' then nullif(p_patch ->> 'storeAisle', '') else store_aisle end,
    g_per_fl_oz = case when p_patch ? 'gPerFlOz' then nullif(p_patch ->> 'gPerFlOz', '')::numeric else g_per_fl_oz end,
    g_per_count = case when p_patch ? 'gPerCount' then nullif(p_patch ->> 'gPerCount', '')::numeric else g_per_count end,
    aliases = case when p_patch ? 'aliases' then array(select jsonb_array_elements_text(p_patch -> 'aliases')) else aliases end,
    nutrition_basis_qty = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,basisQuantity}', '')::numeric else nutrition_basis_qty end,
    kcal = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,calories}', '')::numeric else kcal end,
    protein_g = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,proteinG}', '')::numeric else protein_g end,
    carbs_g = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,carbsG}', '')::numeric else carbs_g end,
    fat_g = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,fatG}', '')::numeric else fat_g end,
    fiber_g = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,fiberG}', '')::numeric else fiber_g end,
    sugar_g = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,sugarG}', '')::numeric else sugar_g end,
    sodium_mg = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,sodiumMg}', '')::numeric else sodium_mg end,
    nutrition_source = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,source}', '') else nutrition_source end,
    nutrition_is_estimated = case when p_patch ? 'nutrition' then coalesce((p_patch #>> '{nutrition,estimated}')::boolean, false) else nutrition_is_estimated end,
    updated_at = now()
  where id = p_food returning * into updated_row;

  insert into public.record_edits(resource, record_id, before_state, after_state)
  values ('food', p_food, to_jsonb(food_row), to_jsonb(updated_row));
  return jsonb_build_object('status', 'updated', 'id', p_food);
end;
$$;

create function public.gpt_update_product(p_product uuid, p_patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  product_row public.products%rowtype;
  updated_row public.products%rowtype;
  bad_key text;
  unit_id uuid;
  package_base numeric;
  serving_base numeric;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  if jsonb_typeof(p_patch) <> 'object' or p_patch = '{}'::jsonb then raise exception 'patch must be a non-empty object'; end if;
  select key into bad_key from jsonb_object_keys(p_patch) key
  where key <> all(array['name','brand','barcode','emoji','aliases','packageQuantity','packageUnit','servingQuantity','nutrition','estimatedCost','costSource','costAsOf']) limit 1;
  if bad_key is not null then raise exception 'Unsupported product edit field: %', bad_key; end if;
  if (p_patch ? 'packageQuantity') <> (p_patch ? 'packageUnit') then raise exception 'packageQuantity and packageUnit must be edited together'; end if;
  if p_patch ? 'aliases' and jsonb_typeof(p_patch -> 'aliases') <> 'array' then raise exception 'aliases must be an array'; end if;
  if p_patch ? 'nutrition' and p_patch -> 'nutrition' <> 'null'::jsonb and jsonb_typeof(p_patch -> 'nutrition') <> 'object' then raise exception 'nutrition must be an object or null'; end if;

  select * into product_row from public.products where id = p_product for update;
  if not found then raise exception 'Product does not exist'; end if;
  if p_patch ? 'name' and trim(coalesce(p_patch ->> 'name', '')) = '' then raise exception 'name cannot be empty'; end if;
  unit_id := case when p_patch ? 'packageUnit' then public.resolve_measure_conversion(p_patch ->> 'packageUnit') else product_row.package_unit end;
  package_base := case when p_patch ? 'packageQuantity' then public.to_base_quantity(product_row.food, (p_patch ->> 'packageQuantity')::numeric, unit_id) else product_row.package_qty_base end;
  serving_base := case when p_patch ? 'servingQuantity' then
    case when p_patch -> 'servingQuantity' = 'null'::jsonb then null else public.to_base_quantity(product_row.food, (p_patch ->> 'servingQuantity')::numeric, unit_id) end
    else product_row.serving_qty_base end;

  update public.products set
    name = case when p_patch ? 'name' then trim(p_patch ->> 'name') else name end,
    brand = case when p_patch ? 'brand' then nullif(p_patch ->> 'brand', '') else brand end,
    barcode = case when p_patch ? 'barcode' then nullif(p_patch ->> 'barcode', '') else barcode end,
    emoji = case when p_patch ? 'emoji' then nullif(p_patch ->> 'emoji', '') else emoji end,
    aliases = case when p_patch ? 'aliases' then array(select jsonb_array_elements_text(p_patch -> 'aliases')) else aliases end,
    package_qty_base = package_base,
    package_unit = unit_id,
    serving_qty_base = serving_base,
    nutrition_basis_qty = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,basisQuantity}', '')::numeric else nutrition_basis_qty end,
    kcal = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,calories}', '')::numeric else kcal end,
    protein_g = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,proteinG}', '')::numeric else protein_g end,
    carbs_g = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,carbsG}', '')::numeric else carbs_g end,
    fat_g = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,fatG}', '')::numeric else fat_g end,
    fiber_g = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,fiberG}', '')::numeric else fiber_g end,
    sugar_g = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,sugarG}', '')::numeric else sugar_g end,
    sodium_mg = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,sodiumMg}', '')::numeric else sodium_mg end,
    nutrition_source = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,source}', '') else nutrition_source end,
    nutrition_is_estimated = case when p_patch ? 'nutrition' then coalesce((p_patch #>> '{nutrition,estimated}')::boolean, false) else nutrition_is_estimated end,
    estimated_cost = case when p_patch ? 'estimatedCost' then nullif(p_patch ->> 'estimatedCost', '')::numeric else estimated_cost end,
    cost_source = case when p_patch ? 'costSource' then nullif(p_patch ->> 'costSource', '') else cost_source end,
    cost_as_of = case when p_patch ? 'costAsOf' then nullif(p_patch ->> 'costAsOf', '')::date else cost_as_of end,
    updated_at = now()
  where id = p_product returning * into updated_row;

  insert into public.record_edits(resource, record_id, before_state, after_state)
  values ('product', p_product, to_jsonb(product_row), to_jsonb(updated_row));
  return jsonb_build_object('status', 'updated', 'id', p_product);
end;
$$;

create function public.gpt_update_recipe(p_recipe uuid, p_patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  recipe_row public.recipes%rowtype;
  updated_row public.recipes%rowtype;
  bad_key text;
  ingredient jsonb;
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
    override_basis_qty = case when p_patch ? 'nutrition' then case when p_patch -> 'nutrition' = 'null'::jsonb then null else next_servings end when override_basis_qty is not null then next_servings else null end,
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
    delete from public.recipe_ingredients where recipe = p_recipe;
    for ingredient in select value from jsonb_array_elements(p_patch -> 'ingredients')
    loop
      food_id := nullif(ingredient ->> 'foodId', '')::uuid;
      if food_id is null then select id into food_id from public.base_foods where lower(name) = lower(ingredient ->> 'food'); end if;
      if food_id is null then raise exception 'Unknown ingredient: %', coalesce(ingredient ->> 'foodId', ingredient ->> 'food'); end if;
      unit_id := public.resolve_measure_conversion(ingredient ->> 'unit');
      insert into public.recipe_ingredients(recipe, ingredient, qty, unit, sort_order, note)
      values (p_recipe, food_id, (ingredient ->> 'quantity')::numeric, unit_id,
        coalesce((ingredient ->> 'sortOrder')::integer, 0), nullif(ingredient ->> 'note', ''));
    end loop;
  end if;

  after_state := jsonb_build_object('recipe', to_jsonb(updated_row), 'ingredients',
    coalesce((select jsonb_agg(to_jsonb(item) order by item.sort_order) from public.recipe_ingredients item where item.recipe = p_recipe), '[]'::jsonb));
  insert into public.record_edits(resource, record_id, before_state, after_state)
  values ('recipe', p_recipe, before_state, after_state);
  return jsonb_build_object('status', 'updated', 'id', p_recipe);
end;
$$;

create function public.gpt_update_inventory_lot(p_lot uuid, p_patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  lot_row public.inventory_lots%rowtype;
  updated_row public.inventory_lots%rowtype;
  bad_key text;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  if jsonb_typeof(p_patch) <> 'object' or p_patch = '{}'::jsonb then raise exception 'patch must be a non-empty object'; end if;
  select key into bad_key from jsonb_object_keys(p_patch) key
  where key <> all(array['remainingQuantity','location','bestBy','acquiredAt','totalCost','costIsEstimated','costSource','awayFromHome','note']) limit 1;
  if bad_key is not null then raise exception 'Unsupported inventory-lot edit field: %', bad_key; end if;

  select * into lot_row from public.inventory_lots where id = p_lot for update;
  if not found then raise exception 'Inventory lot does not exist'; end if;
  if p_patch ? 'remainingQuantity' then
    if (p_patch ->> 'remainingQuantity')::numeric < 0 then raise exception 'remainingQuantity cannot be negative'; end if;
    perform public.set_inventory_lot_quantity(p_lot, (p_patch ->> 'remainingQuantity')::numeric, false);
  end if;

  update public.inventory_lots set
    location = case when p_patch ? 'location' then nullif(p_patch ->> 'location', '') else location end,
    use_by = case when p_patch ? 'bestBy' then nullif(p_patch ->> 'bestBy', '')::date else use_by end,
    acquired_at = case when p_patch ? 'acquiredAt' then (p_patch ->> 'acquiredAt')::timestamptz else acquired_at end,
    total_cost = case when p_patch ? 'totalCost' then nullif(p_patch ->> 'totalCost', '')::numeric else total_cost end,
    cost_is_estimated = case when p_patch ? 'costIsEstimated' then (p_patch ->> 'costIsEstimated')::boolean else cost_is_estimated end,
    cost_source = case when p_patch ? 'costSource' then nullif(p_patch ->> 'costSource', '') else cost_source end,
    is_external = case when p_patch ? 'awayFromHome' then (p_patch ->> 'awayFromHome')::boolean else is_external end,
    note = case when p_patch ? 'note' then nullif(p_patch ->> 'note', '') else note end
  where id = p_lot returning * into updated_row;
  if updated_row.is_external and updated_row.remaining_qty > 0 and updated_row.location is null then
    raise exception 'A location is required when away-from-home food remains';
  end if;

  insert into public.record_edits(resource, record_id, before_state, after_state)
  values ('inventory_lot', p_lot, to_jsonb(lot_row), to_jsonb(updated_row));
  return jsonb_build_object('status', 'updated', 'id', p_lot, 'remainingQuantity', updated_row.remaining_qty);
end;
$$;

create function public.gpt_update_consumption(p_food_log uuid, p_patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  log_row public.food_logs%rowtype;
  updated_row public.food_logs%rowtype;
  lot_row public.inventory_lots%rowtype;
  updated_lot public.inventory_lots%rowtype;
  bad_key text;
  linked_lot_ids uuid[];
  before_state jsonb;
  after_state jsonb;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  if jsonb_typeof(p_patch) <> 'object' or p_patch = '{}'::jsonb then raise exception 'patch must be a non-empty object'; end if;
  select key into bad_key from jsonb_object_keys(p_patch) key
  where key <> all(array['label','timestamp','note','nutrition','purchaseTotalCost','costIsEstimated','costSource']) limit 1;
  if bad_key is not null then raise exception 'Unsupported consumption edit field: %', bad_key; end if;
  if p_patch ? 'nutrition' and p_patch -> 'nutrition' <> 'null'::jsonb and jsonb_typeof(p_patch -> 'nutrition') <> 'object' then raise exception 'nutrition must be an object or null'; end if;

  select * into log_row from public.food_logs where id = p_food_log for update;
  if not found then raise exception 'Consumption event does not exist'; end if;
  if log_row.voided_at is not null then raise exception 'Voided consumption events cannot be edited'; end if;
  if p_patch ? 'label' and trim(coalesce(p_patch ->> 'label', '')) = '' then raise exception 'label cannot be empty'; end if;

  select array_agg(distinct event.lot) into linked_lot_ids
  from public.inventory_events event
  join public.inventory_lots lot on lot.id = event.lot
  where event.food_log = p_food_log and lot.product is not null and lot.is_external;
  if p_patch ?| array['purchaseTotalCost','costIsEstimated','costSource'] then
    if coalesce(array_length(linked_lot_ids, 1), 0) <> 1 then
      raise exception 'Cost correction requires exactly one linked away-from-home purchase lot; edit a specific lot instead';
    end if;
    select * into lot_row from public.inventory_lots where id = linked_lot_ids[1] for update;
  end if;
  before_state := jsonb_build_object('consumption', to_jsonb(log_row), 'purchaseLot', case when lot_row.id is null then null else to_jsonb(lot_row) end);

  update public.food_logs set
    label = case when p_patch ? 'label' then trim(p_patch ->> 'label') else label end,
    occurred_at = case when p_patch ? 'timestamp' then (p_patch ->> 'timestamp')::timestamptz else occurred_at end,
    note = case when p_patch ? 'note' then nullif(p_patch ->> 'note', '') else note end,
    kcal = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,calories}', '')::numeric else kcal end,
    protein_g = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,proteinG}', '')::numeric else protein_g end,
    carbs_g = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,carbsG}', '')::numeric else carbs_g end,
    fat_g = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,fatG}', '')::numeric else fat_g end,
    fiber_g = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,fiberG}', '')::numeric else fiber_g end,
    sugar_g = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,sugarG}', '')::numeric else sugar_g end,
    sodium_mg = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,sodiumMg}', '')::numeric else sodium_mg end,
    nutrition_is_estimated = case when p_patch ? 'nutrition' then coalesce((p_patch #>> '{nutrition,estimated}')::boolean, false) else nutrition_is_estimated end
  where id = p_food_log returning * into updated_row;
  if p_patch ? 'timestamp' then
    update public.inventory_events set occurred_at = updated_row.occurred_at where food_log = p_food_log;
  end if;
  if lot_row.id is not null then
    update public.inventory_lots set
      total_cost = case when p_patch ? 'purchaseTotalCost' then nullif(p_patch ->> 'purchaseTotalCost', '')::numeric else total_cost end,
      cost_is_estimated = case when p_patch ? 'costIsEstimated' then (p_patch ->> 'costIsEstimated')::boolean else cost_is_estimated end,
      cost_source = case when p_patch ? 'costSource' then nullif(p_patch ->> 'costSource', '') else cost_source end
    where id = lot_row.id returning * into updated_lot;
  end if;

  after_state := jsonb_build_object('consumption', to_jsonb(updated_row), 'purchaseLot', case when updated_lot.id is null then null else to_jsonb(updated_lot) end);
  insert into public.record_edits(resource, record_id, before_state, after_state)
  values ('consumption', p_food_log, before_state, after_state);
  return jsonb_build_object('status', 'updated', 'id', p_food_log, 'lotId', case when updated_lot.id is null then null else updated_lot.id end);
end;
$$;

revoke all on function public.gpt_update_food(uuid, jsonb) from public, anon;
revoke all on function public.gpt_update_product(uuid, jsonb) from public, anon;
revoke all on function public.gpt_update_recipe(uuid, jsonb) from public, anon;
revoke all on function public.gpt_update_inventory_lot(uuid, jsonb) from public, anon;
revoke all on function public.gpt_update_consumption(uuid, jsonb) from public, anon;
grant execute on function public.gpt_update_food(uuid, jsonb) to authenticated, service_role;
grant execute on function public.gpt_update_product(uuid, jsonb) to authenticated, service_role;
grant execute on function public.gpt_update_recipe(uuid, jsonb) to authenticated, service_role;
grant execute on function public.gpt_update_inventory_lot(uuid, jsonb) to authenticated, service_role;
grant execute on function public.gpt_update_consumption(uuid, jsonb) to authenticated, service_role;
