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


  update public.recipe_ingredients set piece_basis=jsonb_build_object('count',3,'grams',600,'label','thighs','sourceQuantity',600,'sourceUnit','g','provenance','fixture') where id=ingredient_id;
  update public.recipes set override_basis_qty=4,override_kcal=800 where id=recipe_id;
  -- Uniform saved estimate: keep batch calories while allowing an edited yield.
  piece_input := jsonb_build_array(jsonb_build_object('ingredientId',ingredient_id,'lotId',lot_id,'pieces',3,'expectedRemaining',900));
  result := public.prepare_recipe(recipe_id,piece_input,gen_random_uuid(),1,2,'fridge',null,0,now());
  if (public.lot_nutrition_json((result->>'lotId')::uuid)->>'kcal')::numeric<>400 then raise exception 'Uniform batch must divide 800 calories across actual yield 2'; end if;
  if (select remaining_qty from public.inventory_lots where id=lot_id)<>300 then raise exception 'Uniform deduction'; end if;
  perform public.undo_prep((result->>'prepId')::uuid);
  -- Uniform anchor: scale recipe totals 1.5x, allocate over actual yield 3.
  update public.recipe_ingredients set qty=450,piece_basis=jsonb_build_object('count',1,'grams',450,'label','tenderloin','sourceQuantity',450,'sourceUnit','g','provenance','fixture','anchor',true) where id=ingredient_id;
  piece_input := jsonb_build_array(jsonb_build_object('ingredientId',ingredient_id,'lotId',lot_id,'pieces',1,'weightGrams',675,'scaleRecipe',true,'expectedRemaining',900));
  result := public.prepare_recipe(recipe_id,piece_input,gen_random_uuid(),1,3,'fridge',null,0,now());
  if (public.lot_nutrition_json((result->>'lotId')::uuid)->>'kcal')::numeric<>400 then raise exception 'Anchor must allocate 1200 batch calories over yield 3'; end if;
  if (select scale_factor from public.preps where id=(result->>'prepId')::uuid)<>1.5 then raise exception 'Anchor scale'; end if;
  perform public.undo_prep((result->>'prepId')::uuid);
  -- Nonuniform quantities must fail without consent and leave inventory untouched.
  piece_input := jsonb_build_array(jsonb_build_object('ingredientId',ingredient_id,'lotId',lot_id,'pieces',1,'weightGrams',600,'expectedRemaining',900));
  begin
    perform public.prepare_recipe(recipe_id,piece_input,gen_random_uuid(),1,2,'fridge',null,0,now());
  exception when raise_exception then
    if sqlerrm not like 'Selected pieces change ingredient proportions.%' then raise; end if;
    rejected:=true;
  end;
  if not rejected or (select remaining_qty from public.inventory_lots where id=lot_id)<>900 then raise exception 'Nonuniform must reject atomically'; end if;
  -- Explicit batch-only choice uses 600g x 2 kcal/g, without editing saved values.
  piece_input:=jsonb_set(piece_input,'{0,useIngredientNutrition}','true');
  result := public.prepare_recipe(recipe_id,piece_input,gen_random_uuid(),1,2,'fridge',null,0,now());
  if (public.lot_nutrition_json((result->>'lotId')::uuid)->>'kcal')::numeric<>600 then raise exception 'Consented batch must use ingredient calories'; end if;
  if (select override_kcal from public.recipes where id=recipe_id)<>800 then raise exception 'Saved override changed'; end if;
  perform public.undo_prep((result->>'prepId')::uuid);
end $$;
set constraints all immediate;
rollback;
