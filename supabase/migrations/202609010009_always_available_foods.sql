alter table public.base_foods
  add column always_available boolean not null default false;

comment on column public.base_foods.always_available is
  'Recipe ingredient is supplied on demand and is excluded from inventory deductions and generated grocery shortages.';

update public.base_foods
set always_available = true,
    updated_at = now()
where lower(name) = 'water';

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
  if p_scale <= 0 then
    raise exception 'Recipe scale must be positive';
  end if;

  select * into recipe_row from public.recipes where id = p_recipe;
  if not found then raise exception 'Recipe does not exist'; end if;

  actual_yield := coalesce(p_actual_yield, recipe_row.yield_qty * p_scale);
  if recipe_row.output_food is not null and (actual_yield is null or actual_yield <= 0) then
    raise exception 'Prepared output needs a positive actual yield';
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
      select 1
      from public.base_foods food
      where food.id = ingredient_row.ingredient
        and food.always_available
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

  if recipe_row.output_food is not null then
    insert into public.inventory_lots(prep, initial_qty, remaining_qty, location)
    values (new_prep, actual_yield, actual_yield, p_location);
  end if;

  return new_prep;
end;
$$;

create or replace function public.rebuild_shopping_from_plan(
  p_from date default current_date,
  p_through date default current_date + 6
)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  inserted_count integer;
begin
  if not public.is_app_owner() then
    raise exception 'Only the app owner may rebuild shopping items' using errcode = '42501';
  end if;
  if p_through < p_from then raise exception 'Plan end date precedes start date'; end if;

  delete from public.shopping_items
  where source = 'generated'
    and lot is null;

  with planned_ingredients as (
    select
      ingredient.ingredient as food,
      sum(public.to_base_quantity(
        ingredient.ingredient,
        ingredient.qty * plan.scale_factor,
        ingredient.unit
      )) as needed_base,
      min(plan.plan_date) as first_needed_date
    from public.meal_plans plan
    join public.recipe_ingredients ingredient on ingredient.recipe = plan.recipe
    join public.base_foods food on food.id = ingredient.ingredient
    where plan.plan_date between p_from and p_through
      and plan.status = 'planned'
      and plan.intent = 'prepare'
      and not food.always_available
    group by ingredient.ingredient
  ), available_inventory as (
    select
      coalesce(product.food, prepared_recipe.output_food) as food,
      sum(lot.remaining_qty) as available_base
    from public.inventory_lots lot
    left join public.products product on product.id = lot.product
    left join public.preps prep on prep.id = lot.prep and prep.voided_at is null
    left join public.recipes prepared_recipe on prepared_recipe.id = prep.recipe
    where lot.remaining_qty > 0
    group by coalesce(product.food, prepared_recipe.output_food)
  ), shortages as (
    select
      planned.food,
      greatest(planned.needed_base - coalesce(stock.available_base, 0), 0) as shortage_base,
      planned.first_needed_date
    from planned_ingredients planned
    left join available_inventory stock on stock.food = planned.food
  ), display_shortages as (
    select
      shortage.food,
      shortage.first_needed_date,
      coalesce(food.display_unit, base_unit.id) as unit,
      public.from_base_quantity(
        shortage.food,
        shortage.shortage_base,
        coalesce(food.display_unit, base_unit.id)
      ) as quantity
    from shortages shortage
    join public.base_foods food on food.id = shortage.food
    join lateral (
      select conversion.id
      from public.measure_conversions conversion
      where conversion.measure_style = food.measure_style
        and conversion.base_to_this_ratio = 1
      limit 1
    ) base_unit on true
    where shortage.shortage_base > 0.0000001
  )
  insert into public.shopping_items(
    food, qty_needed, unit, source, first_needed_date, quantity_label
  )
  select
    shortage.food,
    shortage.quantity,
    shortage.unit,
    'generated',
    shortage.first_needed_date,
    trim(to_char(shortage.quantity, 'FM999999990.##')) || ' ' || conversion.short_name
  from display_shortages shortage
  join public.measure_conversions conversion on conversion.id = shortage.unit;

  get diagnostics inserted_count = row_count;
  return inserted_count;
end;
$$;

create or replace function public.gpt_update_food(p_food uuid, p_patch jsonb)
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
  where key <> all(array['name','plural','emoji','measureStyle','displayUnit','groceryCategory','ingredientRole','storeAisle','gPerFlOz','gPerCount','aliases','nutrition','alwaysAvailable']) limit 1;
  if bad_key is not null then raise exception 'Unsupported food edit field: %', bad_key; end if;
  if p_patch ? 'aliases' and jsonb_typeof(p_patch -> 'aliases') <> 'array' then raise exception 'aliases must be an array'; end if;
  if p_patch ? 'nutrition' and jsonb_typeof(p_patch -> 'nutrition') <> 'object' then raise exception 'nutrition must be an object'; end if;
  if p_patch ? 'alwaysAvailable' and jsonb_typeof(p_patch -> 'alwaysAvailable') <> 'boolean' then raise exception 'alwaysAvailable must be a boolean'; end if;

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
    always_available = case when p_patch ? 'alwaysAvailable' then (p_patch ->> 'alwaysAvailable')::boolean else always_available end,
    updated_at = now()
  where id = p_food returning * into updated_row;

  insert into public.record_edits(resource, record_id, before_state, after_state)
  values ('food', p_food, to_jsonb(food_row), to_jsonb(updated_row));
  return jsonb_build_object('status', 'updated', 'id', p_food);
end;
$$;
