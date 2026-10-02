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

  perform public.gpt_update_recipe(recipe_id,jsonb_build_object('ingredients',jsonb_build_array(jsonb_build_object(
    'id',ingredient_id,'foodId',food_id,'quantity',600,'unit',unit_id,
    'pieceBasis',jsonb_build_object('count',3,'grams',600,'label','thighs','sourceQuantity',600,'sourceUnit','g','provenance','saved estimate')))));
  if (select piece_basis->>'count' from public.recipe_ingredients where id=ingredient_id)<>'3' then raise exception 'Estimate failed save/reload'; end if;
  perform public.gpt_save_recipe(jsonb_build_object('id',recipe_id,'name','QA piece cooking','servings',4,'ingredients',jsonb_build_array(jsonb_build_object(
    'id',ingredient_id,'foodId',food_id,'quantity',600,'unit',unit_id))));
  if (select piece_basis->>'provenance' from public.recipe_ingredients where id=ingredient_id)<>'saved estimate' then raise exception 'POST dropped saved estimate'; end if;
  result := public.gpt_save_recipe(jsonb_build_object('name','QA imported count','servings',2,'ingredients',jsonb_build_array(jsonb_build_object(
    'foodId',food_id,'quantity',450,'unit',unit_id,'pieceBasis',jsonb_build_object('count',3,'grams',450,'label','thighs','sourceQuantity',1,'sourceUnit','lb','provenance','example estimate')))));
  if (select piece_basis->>'sourceUnit' from public.recipe_ingredients where recipe=(result->>'id')::uuid)<>'lb' then raise exception 'New import lost original source'; end if;
  piece_input := jsonb_build_array(jsonb_build_object('ingredientId',ingredient_id,'lotId',lot_id,'pieces',3,'expectedRemaining',900));
  result := public.prepare_recipe(recipe_id,piece_input,gen_random_uuid(),1,null,'fridge',null,0,now());
  if (select remaining_qty from public.inventory_lots where id=lot_id)<>300 then raise exception 'Saved estimate deduction'; end if;
  if (select piece_count from public.inventory_lots where id=lot_id) is not null then raise exception 'Invented lot count'; end if;
  perform public.undo_prep((result->>'prepId')::uuid);
  update public.inventory_lots set piece_count=6,piece_basis_qty=900 where id=lot_id;
  result := public.prepare_recipe(recipe_id,piece_input,gen_random_uuid(),1,null,'fridge',null,0,now());
  if (select remaining_qty from public.inventory_lots where id=lot_id)<>450 then raise exception 'Lot average must override saved estimate'; end if;
  perform public.undo_prep((result->>'prepId')::uuid);
  update public.recipe_ingredients set qty=450,piece_basis=jsonb_build_object('count',1,'grams',450,'label','tenderloin','sourceQuantity',450,'sourceUnit','g','provenance','saved estimate','anchor',true) where id=ingredient_id;
  insert into public.recipe_ingredients(recipe,ingredient,qty,unit,sort_order) values(recipe_id,food_id,100,unit_id,1);
  piece_input := jsonb_build_array(jsonb_build_object('ingredientId',ingredient_id,'lotId',lot_id,'pieces',1,'weightGrams',675,'scaleRecipe',true,'expectedRemaining',900));
  result := public.prepare_recipe(recipe_id,piece_input,gen_random_uuid(),1,null,'fridge',null,0,now());
  if (result->>'servingsMade')::numeric<>6 then raise exception 'Anchor yield must be 1.5 times'; end if;
  if (select scale_factor from public.preps where id=(result->>'prepId')::uuid)<>1.5 then raise exception 'Anchor scale must be 1.5'; end if;
  if (select remaining_qty from public.inventory_lots where id=lot_id)<>75 then raise exception 'Known weight plus scaled supporting ingredient deduction'; end if;
  perform public.undo_prep((result->>'prepId')::uuid);
end $$;
set constraints all immediate;
rollback;
