create function public.cook_recipe(
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
    select * from public.recipe_ingredients where recipe = p_recipe order by sort_order
  loop
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

create function public.consume_prepared_lot(
  p_lot uuid,
  p_quantity numeric default 1,
  p_occurred_at timestamptz default now()
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  lot_row public.inventory_lots%rowtype;
  prep_row public.preps%rowtype;
  recipe_row public.recipes%rowtype;
  nutrients record;
  new_log uuid;
begin
  if not public.is_app_owner() then
    raise exception 'Only the app owner may consume inventory' using errcode = '42501';
  end if;
  if p_quantity <= 0 then raise exception 'Quantity must be positive'; end if;

  select * into lot_row from public.inventory_lots where id = p_lot for update;
  if not found or lot_row.prep is null then raise exception 'Prepared lot does not exist'; end if;
  if lot_row.remaining_qty < p_quantity then raise exception 'Prepared lot has only % remaining', lot_row.remaining_qty; end if;

  select * into prep_row from public.preps where id = lot_row.prep and voided_at is null;
  select * into recipe_row from public.recipes where id = prep_row.recipe;
  select * into nutrients from public.lot_nutrition_per_base_unit(p_lot);

  insert into public.food_logs(
    label, kind, recipe, servings, occurred_at,
    kcal, protein_g, carbs_g, fat_g, fiber_g, sodium_mg
  ) values (
    recipe_row.name, 'prepared', recipe_row.id, p_quantity, p_occurred_at,
    nutrients.kcal * p_quantity,
    nutrients.protein_g * p_quantity,
    nutrients.carbs_g * p_quantity,
    nutrients.fat_g * p_quantity,
    nutrients.fiber_g * p_quantity,
    nutrients.sodium_mg * p_quantity
  ) returning id into new_log;

  insert into public.inventory_events(lot, quantity_delta, reason, food_log, occurred_at)
  values (p_lot, -p_quantity, 'eaten', new_log, p_occurred_at);

  return new_log;
end;
$$;

create function public.cook_recipes(p_recipes uuid[])
returns uuid[]
language plpgsql
set search_path = ''
as $$
declare
  recipe_id uuid;
  prep_ids uuid[] := array[]::uuid[];
begin
  if coalesce(array_length(p_recipes, 1), 0) = 0 then
    raise exception 'Select at least one recipe';
  end if;
  foreach recipe_id in array p_recipes loop
    prep_ids := prep_ids || public.cook_recipe(recipe_id, 1, null, 'fridge');
  end loop;
  return prep_ids;
end;
$$;

revoke all on function public.cook_recipe(uuid, numeric, numeric, text) from public, anon;
grant execute on function public.cook_recipe(uuid, numeric, numeric, text) to authenticated;
revoke all on function public.consume_prepared_lot(uuid, numeric, timestamptz) from public, anon;
grant execute on function public.consume_prepared_lot(uuid, numeric, timestamptz) to authenticated;
revoke all on function public.cook_recipes(uuid[]) from public, anon;
grant execute on function public.cook_recipes(uuid[]) to authenticated;
