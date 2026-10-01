-- Run only against a disposable/local DB or in this explicit rollback transaction.
-- Does not create sessions, users, or persistent records. Uses the database
-- test runner's privileged connection; permission gates are reviewed separately.
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
do $$
declare
  request_id uuid := gen_random_uuid();
  food_id uuid := gen_random_uuid();
  product_id uuid := gen_random_uuid();
  recipe_id uuid := gen_random_uuid();
  ingredient_id uuid := gen_random_uuid();
  lot_id uuid := gen_random_uuid();
  unit_id uuid;
  result jsonb;
  piece_input jsonb;
  prep_id uuid;
  log_id uuid;
  rejected boolean := false;
begin
  select id into strict unit_id from public.measure_conversions where short_name = 'g';
  insert into public.base_foods(id,name,measure_style,display_unit) values(food_id,'QA piece chicken','weight',unit_id);
  insert into public.products(id,food,name,package_qty_base,package_unit,serving_qty_base,nutrition_basis_qty,kcal)
    values(product_id,food_id,'QA six-piece pack',900,unit_id,150,100,200);
  insert into public.inventory_lots(id,product,initial_qty,remaining_qty,location,total_cost,out_of_pocket_cost,paid_by,cost_source,price_as_of,acquisition_type)
    values(lot_id,product_id,900,900,'fridge',9,9,'self','QA receipt',current_date,'grocery');
  insert into public.recipes(id,name,servings,instructions) values(recipe_id,'QA piece cooking',4,'[]');
  insert into public.recipe_ingredients(id,recipe,ingredient,qty,unit)
    values(ingredient_id,recipe_id,food_id,600,unit_id);
  piece_input := jsonb_build_array(jsonb_build_object('ingredientId',ingredient_id,'lotId',lot_id,
    'pieces',2.5,'lotPieces',6,'expectedRemaining',900));
  result := public.prepare_recipe(recipe_id,piece_input,request_id,1,3,'fridge',null,0,now());
  if public.prepare_recipe(recipe_id,piece_input,request_id,1,3,'fridge',null,0,now()) is distinct from result then raise exception 'Same request must return original result'; end if;
  prep_id := (result->>'prepId')::uuid;
  if (select remaining_qty from public.inventory_lots where id=lot_id) <> 525 then
    raise exception '2.5 of six pieces must deduct 375 of 900 grams';
  end if;
  if (select remaining_qty*piece_count/piece_basis_qty from public.inventory_lots where id=lot_id) <> 3.5 then
    raise exception 'Remaining estimated count must conserve proportional mass';
  end if;
  if not (select nutrition_is_estimated from public.preps where id=prep_id) then raise exception 'Piece prep must retain uncertainty'; end if;
  if (select components->0->>'quantity' from public.preps where id=prep_id)::numeric <> 375 then raise exception 'Prep must snapshot actual estimated input mass'; end if;
  begin
    perform public.prepare_recipe(recipe_id,piece_input,gen_random_uuid(),1,3,'fridge',null,0,now());
  exception when others then
    if sqlerrm not like 'This lot changed.%' then raise; end if;
    rejected := true;
  end;
  if not rejected then raise exception 'Stale piece snapshot must be rejected'; end if;
  log_id := public.consume_prepared_batch((result->>'lotId')::uuid,0.5,null,now());
  rejected := false;
  begin
    perform public.undo_prep(prep_id);
  exception when others then rejected := true;
  end;
  if not rejected then raise exception 'Cannot undo batch with active downstream eating'; end if;
  perform public.void_food_log(log_id);
  perform public.undo_prep(prep_id);
  if (select remaining_qty from public.inventory_lots where id=lot_id) <> 900 then raise exception 'Undo must restore exact original mass'; end if;
  if (select remaining_qty*piece_count/piece_basis_qty from public.inventory_lots where id=lot_id) <> 6 then raise exception 'Undo must restore count from restored mass'; end if;
  if (select qty from public.recipe_ingredients where id=ingredient_id) <> 600 then raise exception 'Piece cooking must not mutate recipe definition'; end if;
end;
$$;
set constraints all immediate;
rollback;
