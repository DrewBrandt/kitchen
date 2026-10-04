-- Focused app RPC proof in the disposable harness only; no live writes.
begin;
do $$ declare owner_email text; begin
  if to_regclass('isolated_test.marker') is null then raise exception 'Isolated database required'; end if;
  select (regexp_match(pg_get_functiondef('public.is_app_owner()'::regprocedure), $re$email = '([^']+)'$re$))[1] into strict owner_email;
  insert into auth.users(id,email,email_confirmed_at) values('99770000-0000-4000-8000-000000000001',owner_email,now());
  insert into auth.sessions(id,user_id) values('99770000-0000-4000-8000-000000000002','99770000-0000-4000-8000-000000000001');
end $$;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"99770000-0000-4000-8000-000000000001","session_id":"99770000-0000-4000-8000-000000000002"}',true);
set local role authenticated;
do $$ declare
  food uuid; spice uuid; product uuid; spice_product uuid; lot uuid; recipe uuid; ingredient uuid; unit uuid;
  plan uuid; leftover uuid; request uuid:=gen_random_uuid(); inputs jsonb; result jsonb; logs uuid[]; before_preps bigint;
begin
  select id into strict unit from public.measure_conversions where short_name='g';
  insert into public.base_foods(name,measure_style,display_unit) values('Synthetic piece chicken','weight',unit) returning id into food;
  insert into public.base_foods(name,measure_style,display_unit) values('Synthetic oregano','weight',unit) returning id into spice;
  insert into public.products(food,name,package_qty_base,package_unit,serving_qty_base,nutrition_basis_qty,kcal)
    values(food,'Synthetic chicken',800,unit,100,100,200) returning id into product;
  insert into public.products(food,name,package_qty_base,package_unit,serving_qty_base,nutrition_basis_qty,kcal)
    values(spice,'Synthetic oregano',10,unit,1,1,1) returning id into spice_product;
  insert into public.inventory_lots(product,initial_qty,remaining_qty,location) values(product,800,800,'freezer') returning id into lot;
  insert into public.recipes(name,servings,instructions) values('Synthetic planned chicken',6,'[]') returning id into recipe;
  insert into public.recipe_ingredients(recipe,ingredient,qty,unit,piece_basis)
    values(recipe,food,900,unit,'{"count":4,"grams":900,"label":"pieces","provenance":"synthetic recipe estimate","sourceQuantity":900,"sourceUnit":"g","anchor":true}') returning id into ingredient;
  insert into public.recipe_ingredients(recipe,ingredient,qty,unit) values(recipe,spice,9,unit);
  insert into public.meal_plans(plan_date,daypart,recipe,scale_factor,intent) values(current_date,'dinner',recipe,1,'prepare') returning id into plan;
  insert into public.meal_plans(plan_date,daypart,recipe,scale_factor,intent,source_meal_plan) values(current_date+1,'dinner',recipe,1,'leftover',plan) returning id into leftover;
  inputs:=jsonb_build_array(jsonb_build_object('ingredientId',ingredient,'lotId',lot,'pieces',4,'expectedRemaining',800,'weightGrams',800,'scaleRecipe',true));
  select count(*) into before_preps from public.preps;
  begin
    perform public.prepare_recipe(recipe,inputs,request,1,null,'fridge',plan,0,now());
    raise exception 'Missing spice was accepted';
  exception when raise_exception then
    if sqlerrm not like 'Not enough inventory for ingredient %' then raise; end if;
  end;
  if (select count(*) from public.preps)<>before_preps or (select remaining_qty from public.inventory_lots where id=lot)<>800
    or (select status from public.meal_plans where id=plan)<>'planned' then raise exception 'Shortage left partial writes'; end if;
  insert into public.inventory_lots(product,initial_qty,remaining_qty,location) values(spice_product,10,10,'pantry');
  result:=public.prepare_recipe(recipe,inputs,request,1,null,'fridge',plan,0,now());
  if public.prepare_recipe(recipe,inputs,request,1,null,'fridge',plan,0,now()) is distinct from result then raise exception 'Retry did not replay'; end if;
  if abs((result->>'servingsMade')::numeric-6*800::numeric/900)>0.000001 or result->>'mealPlanId'<>plan::text or result->>'foodLogId' is not null
    or (select meal_plan from public.preps where id=(result->>'prepId')::uuid)<>plan
    or (select status from public.meal_plans where id=plan)<>'made' then raise exception 'Plan linkage or weight-scaled yield failed'; end if;
  if (select remaining_qty from public.inventory_lots where id=lot)<>0 or (select piece_count from public.inventory_lots where id=lot) is not null
    or (select count(*) from public.preps)<>before_preps+1 then raise exception 'Incorrect deduction, invented count or duplicate prep'; end if;
  begin
    perform public.prepare_recipe(recipe,jsonb_set(inputs,'{0,weightGrams}','700'),request,1,null,'fridge',plan,0,now());
    raise exception 'Changed retry accepted';
  exception when raise_exception then if sqlerrm='Changed retry accepted' then raise; end if; end;
  logs:=public.consume_planned_meals(gen_random_uuid(),array[plan],array[1::numeric],now());
  logs:=public.consume_planned_meals(gen_random_uuid(),array[leftover],array[1::numeric],now());
  if (select status from public.planned_consumptions where meal_plan=leftover)<>'fulfilled'
    or abs((select remaining_qty from public.inventory_lots where id=(result->>'lotId')::uuid)-(6*800::numeric/900-2))>0.000001 then raise exception 'Linked leftovers could not consume original batch'; end if;
  raise notice 'PASS: authenticated linked piece prep, missing-spice rollback, actual-weight scaling, retry, unknown count preserved and exact linked leftovers';
end $$;
rollback;
