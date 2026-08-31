create or replace function public.is_app_owner()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.role() = 'service_role' or exists (
    select 1
    from auth.users app_user
    join auth.sessions app_session on app_session.user_id = app_user.id
    where app_user.id = auth.uid()
      and app_user.email = 'xdrewbrandtx@gmail.com'
      and app_user.email_confirmed_at is not null
      and app_session.id = case
        when auth.jwt() ->> 'session_id' ~ '^[0-9a-f-]{36}$'
          then (auth.jwt() ->> 'session_id')::uuid
        else null
      end
  );
$$;

create or replace function public.resolve_measure_conversion(p_unit text)
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  resolved uuid;
begin
  if p_unit ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    select id into resolved from public.measure_conversions where id = p_unit::uuid;
  end if;
  if resolved is null then
    select id into resolved
    from public.measure_conversions
    where lower(full_name) = lower(trim(p_unit))
       or lower(short_name) = lower(trim(p_unit));
  end if;
  if resolved is null then raise exception 'Unknown unit: %', p_unit; end if;
  return resolved;
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
  prep_recipe uuid;
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
      'kcal', coalesce(product.kcal / product.nutrition_basis_qty, food.kcal / food.nutrition_basis_qty),
      'protein_g', coalesce(product.protein_g / product.nutrition_basis_qty, food.protein_g / food.nutrition_basis_qty),
      'carbs_g', coalesce(product.carbs_g / product.nutrition_basis_qty, food.carbs_g / food.nutrition_basis_qty),
      'fat_g', coalesce(product.fat_g / product.nutrition_basis_qty, food.fat_g / food.nutrition_basis_qty),
      'fiber_g', coalesce(product.fiber_g / product.nutrition_basis_qty, food.fiber_g / food.nutrition_basis_qty),
      'sugar_g', coalesce(product.sugar_g / product.nutrition_basis_qty, food.sugar_g / food.nutrition_basis_qty),
      'sodium_mg', coalesce(product.sodium_mg / product.nutrition_basis_qty, food.sodium_mg / food.nutrition_basis_qty)
    ) into result
    from public.products product
    join public.base_foods food on food.id = product.food
    where product.id = lot_product;
    return result;
  end if;

  select prep.recipe, prep.actual_yield_qty into prep_recipe, prep_yield
  from public.preps prep where prep.id = lot_prep and prep.voided_at is null;
  if prep_yield is null or prep_yield <= 0 then
    raise exception 'Prep % needs an actual yield before nutrition can resolve', lot_prep;
  end if;

  select jsonb_build_object(
    'kcal', sum(-event.quantity_delta * (nutrients.value ->> 'kcal')::numeric),
    'protein_g', sum(-event.quantity_delta * (nutrients.value ->> 'protein_g')::numeric),
    'carbs_g', sum(-event.quantity_delta * (nutrients.value ->> 'carbs_g')::numeric),
    'fat_g', sum(-event.quantity_delta * (nutrients.value ->> 'fat_g')::numeric),
    'fiber_g', sum(-event.quantity_delta * (nutrients.value ->> 'fiber_g')::numeric),
    'sugar_g', sum(-event.quantity_delta * (nutrients.value ->> 'sugar_g')::numeric),
    'sodium_mg', sum(-event.quantity_delta * (nutrients.value ->> 'sodium_mg')::numeric)
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
  from public.recipes recipe where recipe.id = prep_recipe;
  return result;
end;
$$;

create function public.gpt_add_grocery_lots(p_items jsonb, p_source text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  item jsonb;
  product_row public.products%rowtype;
  unit_id uuid;
  base_quantity numeric;
  lot_id uuid;
  created_ids uuid[] := array[]::uuid[];
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'items must be a non-empty array';
  end if;

  for item in select value from jsonb_array_elements(p_items)
  loop
    select * into product_row from public.products where id = (item ->> 'productId')::uuid;
    if not found or product_row.is_external then raise exception 'Unknown pantry product: %', item ->> 'productId'; end if;
    unit_id := public.resolve_measure_conversion(item ->> 'unit');
    base_quantity := public.to_base_quantity(product_row.food, (item ->> 'quantity')::numeric, unit_id);
    insert into public.inventory_lots(product, initial_qty, remaining_qty, total_cost, cost_is_estimated, cost_source, use_by, location, note)
    values (
      product_row.id,
      base_quantity,
      base_quantity,
      nullif(item ->> 'totalCost', '')::numeric,
      coalesce((item ->> 'costIsEstimated')::boolean, false),
      p_source,
      nullif(item ->> 'bestBy', '')::date,
      coalesce(nullif(item ->> 'location', ''), 'pantry'),
      nullif(item ->> 'note', '')
    ) returning id into lot_id;
    created_ids := created_ids || lot_id;
  end loop;
  return jsonb_build_object('status', 'created', 'lotIds', created_ids);
end;
$$;

create function public.gpt_reconcile_inventory(p_replacements jsonb, p_source text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  replacement jsonb;
  replacement_lot jsonb;
  lot_row public.inventory_lots%rowtype;
  created jsonb := '[]'::jsonb;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  if jsonb_typeof(p_replacements) <> 'array' then raise exception 'replacements must be an array'; end if;

  for replacement in select value from jsonb_array_elements(p_replacements)
  loop
    if not exists (select 1 from public.base_foods where id = (replacement ->> 'foodId')::uuid) then
      raise exception 'Unknown food: %', replacement ->> 'foodId';
    end if;
    for replacement_lot in select value from jsonb_array_elements(coalesce(replacement -> 'lots', '[]'::jsonb))
    loop
      if not exists (
        select 1 from public.products
        where id = (replacement_lot ->> 'productId')::uuid
          and food = (replacement ->> 'foodId')::uuid
          and not is_external
      ) then
        raise exception 'Replacement product % does not belong to food %', replacement_lot ->> 'productId', replacement ->> 'foodId';
      end if;
    end loop;
    for lot_row in
      select lot.* from public.inventory_lots lot
      join public.products product on product.id = lot.product
      where product.food = (replacement ->> 'foodId')::uuid and lot.remaining_qty > 0
      for update of lot
    loop
      insert into public.inventory_events(lot, quantity_delta, reason, note)
      values (lot_row.id, -lot_row.remaining_qty, 'adjust', coalesce(p_source, 'GPT inventory reconciliation'));
    end loop;
    if jsonb_array_length(coalesce(replacement -> 'lots', '[]'::jsonb)) > 0 then
      created := created || public.gpt_add_grocery_lots(replacement -> 'lots', p_source);
    end if;
  end loop;
  return jsonb_build_object('status', 'reconciled');
end;
$$;

create function public.gpt_save_recipe(p_recipe jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  recipe_id uuid := coalesce(nullif(p_recipe ->> 'id', '')::uuid, gen_random_uuid());
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
  on conflict (id) do update set
    name = excluded.name, emoji = excluded.emoji, servings = excluded.servings,
    instructions = excluded.instructions, portions = excluded.portions,
    preparation_rules = excluded.preparation_rules, source_url = excluded.source_url,
    source_note = excluded.source_note, prompt_for_feedback = excluded.prompt_for_feedback,
    override_basis_qty = excluded.override_basis_qty, override_kcal = excluded.override_kcal,
    override_protein_g = excluded.override_protein_g, override_carbs_g = excluded.override_carbs_g,
    override_fat_g = excluded.override_fat_g, override_fiber_g = excluded.override_fiber_g,
    override_sugar_g = excluded.override_sugar_g, override_sodium_mg = excluded.override_sodium_mg;

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

create function public.gpt_replace_weekly_plan(p_week_start date, p_entries jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  entry jsonb;
  inserted_count integer := 0;
  grocery_count integer;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  if jsonb_typeof(p_entries) <> 'array' then raise exception 'entries must be an array'; end if;
  delete from public.meal_plans where plan_date between p_week_start and p_week_start + 6;
  for entry in select value from jsonb_array_elements(p_entries)
  loop
    if (entry ->> 'date')::date not between p_week_start and p_week_start + 6 then
      raise exception 'Plan entry date is outside the requested week';
    end if;
    insert into public.meal_plans(
      plan_date, daypart, scheduled_time, meal, recipe, scale_factor, status, name, emoji,
      group_id, leftover_of_group_id, intent, preparation_tasks, note
    ) values (
      (entry ->> 'date')::date, (entry ->> 'slot')::public.daypart,
      nullif(entry ->> 'scheduledTime', '')::time,
      case when entry ->> 'source' = 'meal' then (entry ->> 'sourceId')::uuid else null end,
      case when entry ->> 'source' = 'recipe' then (entry ->> 'sourceId')::uuid else null end,
      coalesce((entry ->> 'scaleFactor')::numeric, 1), 'planned', nullif(entry ->> 'name', ''),
      nullif(entry ->> 'emoji', ''), nullif(entry ->> 'groupId', ''),
      nullif(entry ->> 'leftoverOfGroupId', ''), coalesce(nullif(entry ->> 'intent', ''), 'prepare'),
      coalesce(entry -> 'preparationTasks', '[]'::jsonb), nullif(entry ->> 'note', '')
    );
    inserted_count := inserted_count + 1;
  end loop;
  grocery_count := public.rebuild_shopping_from_plan(p_week_start, p_week_start + 6);
  return jsonb_build_object('status', 'replaced', 'entries', inserted_count, 'generatedGroceries', grocery_count);
end;
$$;

create function public.gpt_prepare_recipe(
  p_recipe uuid,
  p_servings numeric,
  p_location text default 'fridge',
  p_use_by date default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  recipe_row public.recipes%rowtype;
  prep_id uuid;
  lot_id uuid;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  select * into recipe_row from public.recipes where id = p_recipe;
  if not found then raise exception 'Recipe does not exist'; end if;
  if p_servings <= 0 then raise exception 'servings must be positive'; end if;
  prep_id := public.cook_recipe(p_recipe, p_servings / recipe_row.servings, p_servings, p_location);
  select id into lot_id from public.inventory_lots where prep = prep_id;
  if lot_id is null then
    insert into public.inventory_lots(prep, initial_qty, remaining_qty, location, use_by, note)
    values (prep_id, p_servings, p_servings, p_location, p_use_by, p_note)
    returning id into lot_id;
  else
    update public.inventory_lots set use_by = p_use_by, note = p_note where id = lot_id;
  end if;
  return jsonb_build_object('status', 'prepared', 'prepId', prep_id, 'lotId', lot_id);
end;
$$;

create function public.gpt_consume_prepared(
  p_lot uuid,
  p_quantity numeric,
  p_occurred_at timestamptz default now(),
  p_label text default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  lot_row public.inventory_lots%rowtype;
  recipe_row public.recipes%rowtype;
  nutrients jsonb;
  log_id uuid;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  select * into lot_row from public.inventory_lots where id = p_lot for update;
  if not found or lot_row.prep is null then raise exception 'Prepared lot does not exist'; end if;
  if p_quantity <= 0 or lot_row.remaining_qty < p_quantity then raise exception 'Invalid prepared quantity'; end if;
  select recipe.* into recipe_row from public.preps prep join public.recipes recipe on recipe.id = prep.recipe
  where prep.id = lot_row.prep and prep.voided_at is null;
  nutrients := public.lot_nutrition_json(p_lot);
  insert into public.food_logs(label, kind, recipe, servings, occurred_at, kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg, note)
  values (
    coalesce(nullif(p_label, ''), recipe_row.name), 'prepared', recipe_row.id, p_quantity, p_occurred_at,
    coalesce((nutrients ->> 'kcal')::numeric, 0) * p_quantity,
    coalesce((nutrients ->> 'protein_g')::numeric, 0) * p_quantity,
    coalesce((nutrients ->> 'carbs_g')::numeric, 0) * p_quantity,
    coalesce((nutrients ->> 'fat_g')::numeric, 0) * p_quantity,
    coalesce((nutrients ->> 'fiber_g')::numeric, 0) * p_quantity,
    coalesce((nutrients ->> 'sugar_g')::numeric, 0) * p_quantity,
    coalesce((nutrients ->> 'sodium_mg')::numeric, 0) * p_quantity,
    p_note
  ) returning id into log_id;
  insert into public.inventory_events(lot, quantity_delta, reason, food_log, occurred_at, note)
  values (p_lot, -p_quantity, 'eaten', log_id, p_occurred_at, p_note);
  return jsonb_build_object('status', 'consumed', 'id', log_id);
end;
$$;

create function public.gpt_consume_inventory(
  p_food uuid,
  p_quantity numeric,
  p_unit text,
  p_occurred_at timestamptz default now(),
  p_label text default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  needed numeric;
  taken numeric;
  lot_row public.inventory_lots%rowtype;
  nutrients jsonb;
  totals jsonb := jsonb_build_object('kcal',0,'protein_g',0,'carbs_g',0,'fat_g',0,'fiber_g',0,'sugar_g',0,'sodium_mg',0);
  deductions jsonb := '[]'::jsonb;
  food_name text;
  log_id uuid;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  select name into food_name from public.base_foods where id = p_food;
  if food_name is null then raise exception 'Food does not exist'; end if;
  needed := public.to_base_quantity(p_food, p_quantity, public.resolve_measure_conversion(p_unit));
  for lot_row in
    select lot.* from public.inventory_lots lot join public.products product on product.id = lot.product
    where product.food = p_food and lot.remaining_qty > 0
    order by lot.use_by asc nulls last, lot.acquired_at, lot.id for update of lot
  loop
    exit when needed <= 0.0000001;
    taken := least(needed, lot_row.remaining_qty);
    nutrients := public.lot_nutrition_json(lot_row.id);
    totals := jsonb_build_object(
      'kcal', (totals ->> 'kcal')::numeric + coalesce((nutrients ->> 'kcal')::numeric,0) * taken,
      'protein_g', (totals ->> 'protein_g')::numeric + coalesce((nutrients ->> 'protein_g')::numeric,0) * taken,
      'carbs_g', (totals ->> 'carbs_g')::numeric + coalesce((nutrients ->> 'carbs_g')::numeric,0) * taken,
      'fat_g', (totals ->> 'fat_g')::numeric + coalesce((nutrients ->> 'fat_g')::numeric,0) * taken,
      'fiber_g', (totals ->> 'fiber_g')::numeric + coalesce((nutrients ->> 'fiber_g')::numeric,0) * taken,
      'sugar_g', (totals ->> 'sugar_g')::numeric + coalesce((nutrients ->> 'sugar_g')::numeric,0) * taken,
      'sodium_mg', (totals ->> 'sodium_mg')::numeric + coalesce((nutrients ->> 'sodium_mg')::numeric,0) * taken
    );
    deductions := deductions || jsonb_build_array(jsonb_build_object('lot', lot_row.id, 'quantity', taken));
    needed := needed - taken;
  end loop;
  if needed > 0.0000001 then raise exception 'Not enough inventory for %', food_name; end if;
  insert into public.food_logs(label, kind, servings, occurred_at, kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg, note)
  values (coalesce(nullif(p_label,''), food_name), 'inventory', p_quantity, p_occurred_at,
    (totals->>'kcal')::numeric,(totals->>'protein_g')::numeric,(totals->>'carbs_g')::numeric,
    (totals->>'fat_g')::numeric,(totals->>'fiber_g')::numeric,(totals->>'sugar_g')::numeric,
    (totals->>'sodium_mg')::numeric,p_note) returning id into log_id;
  for nutrients in select value from jsonb_array_elements(deductions)
  loop
    insert into public.inventory_events(lot, quantity_delta, reason, food_log, occurred_at, note)
    values ((nutrients->>'lot')::uuid, -(nutrients->>'quantity')::numeric, 'eaten', log_id, p_occurred_at, p_note);
  end loop;
  return jsonb_build_object('status','consumed','id',log_id,'deductions',deductions);
end;
$$;

create function public.gpt_save_external_food(p_food jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  product_id uuid := coalesce(nullif(p_food ->> 'id','')::uuid, gen_random_uuid());
  food_id uuid;
  count_unit uuid;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  select id into count_unit from public.measure_conversions where measure_style = 'discrete' and base_to_this_ratio = 1 limit 1;
  select food into food_id from public.products where id = product_id;
  if food_id is null then food_id := gen_random_uuid(); end if;
  insert into public.base_foods(id,name,plural,measure_style,emoji,display_unit,nutrition_basis_qty,kcal,protein_g,carbs_g,fat_g,fiber_g,sugar_g,sodium_mg,nutrition_source,nutrition_is_estimated)
  values (food_id,p_food->>'name',p_food->>'name','discrete',nullif(p_food->>'emoji',''),count_unit,1,
    (p_food->>'calories')::numeric,(p_food->>'proteinG')::numeric,(p_food->>'carbsG')::numeric,
    (p_food->>'fatG')::numeric,(p_food->>'fiberG')::numeric,(p_food->>'sugarG')::numeric,
    (p_food->>'sodiumMg')::numeric,nullif(p_food->>'source',''),coalesce((p_food->>'estimated')::boolean,false))
  on conflict(id) do update set name=excluded.name,emoji=excluded.emoji,kcal=excluded.kcal,protein_g=excluded.protein_g,
    carbs_g=excluded.carbs_g,fat_g=excluded.fat_g,fiber_g=excluded.fiber_g,sugar_g=excluded.sugar_g,
    sodium_mg=excluded.sodium_mg,nutrition_source=excluded.nutrition_source,nutrition_is_estimated=excluded.nutrition_is_estimated;
  insert into public.products(id,food,barcode,name,brand,package_qty_base,package_unit,serving_qty_base,nutrition_basis_qty,
    kcal,protein_g,carbs_g,fat_g,fiber_g,sugar_g,sodium_mg,emoji,is_external,nutrition_source,nutrition_is_estimated)
  values (product_id,food_id,nullif(p_food->>'barcode',''),p_food->>'name',nullif(p_food->>'brand',''),1,count_unit,1,1,
    (p_food->>'calories')::numeric,(p_food->>'proteinG')::numeric,(p_food->>'carbsG')::numeric,
    (p_food->>'fatG')::numeric,(p_food->>'fiberG')::numeric,(p_food->>'sugarG')::numeric,
    (p_food->>'sodiumMg')::numeric,nullif(p_food->>'emoji',''),true,nullif(p_food->>'source',''),coalesce((p_food->>'estimated')::boolean,false))
  on conflict(id) do update set barcode=excluded.barcode,name=excluded.name,brand=excluded.brand,kcal=excluded.kcal,
    protein_g=excluded.protein_g,carbs_g=excluded.carbs_g,fat_g=excluded.fat_g,fiber_g=excluded.fiber_g,
    sugar_g=excluded.sugar_g,sodium_mg=excluded.sodium_mg,emoji=excluded.emoji,
    nutrition_source=excluded.nutrition_source,nutrition_is_estimated=excluded.nutrition_is_estimated;
  return jsonb_build_object('status','saved','id',product_id);
end;
$$;

revoke all on function public.resolve_measure_conversion(text) from public, anon, authenticated;
revoke all on function public.gpt_add_grocery_lots(jsonb,text) from public, anon, authenticated;
revoke all on function public.gpt_reconcile_inventory(jsonb,text) from public, anon, authenticated;
revoke all on function public.gpt_save_recipe(jsonb) from public, anon, authenticated;
revoke all on function public.gpt_replace_weekly_plan(date,jsonb) from public, anon, authenticated;
revoke all on function public.gpt_prepare_recipe(uuid,numeric,text,date,text) from public, anon, authenticated;
revoke all on function public.gpt_consume_prepared(uuid,numeric,timestamptz,text,text) from public, anon, authenticated;
revoke all on function public.gpt_consume_inventory(uuid,numeric,text,timestamptz,text,text) from public, anon, authenticated;
revoke all on function public.gpt_save_external_food(jsonb) from public, anon, authenticated;
grant execute on function public.resolve_measure_conversion(text) to service_role;
grant execute on function public.gpt_add_grocery_lots(jsonb,text) to service_role;
grant execute on function public.gpt_reconcile_inventory(jsonb,text) to service_role;
grant execute on function public.gpt_save_recipe(jsonb) to service_role;
grant execute on function public.gpt_replace_weekly_plan(date,jsonb) to service_role;
grant execute on function public.gpt_prepare_recipe(uuid,numeric,text,date,text) to service_role;
grant execute on function public.gpt_consume_prepared(uuid,numeric,timestamptz,text,text) to service_role;
grant execute on function public.gpt_consume_inventory(uuid,numeric,text,timestamptz,text,text) to service_role;
grant execute on function public.gpt_save_external_food(jsonb) to service_role;
