-- Functional transaction tests only. No persistent rows or permissions remain.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select plan(10);

insert into base_foods(id, name, measure_style, display_unit)
values ('97000000-0000-0000-0000-000000000001', 'QA leftover ingredient', 'weight', (select id from measure_conversions where short_name = 'g')),
       ('97000000-0000-0000-0000-000000000002', 'QA leftover dish', 'discrete', (select id from measure_conversions where short_name = 'ct'));
insert into products(id, food, name, package_qty_base, package_unit, serving_qty_base, nutrition_basis_qty, kcal)
values ('97000000-0000-0000-0000-000000000003', '97000000-0000-0000-0000-000000000001', 'QA ingredient', 400, (select id from measure_conversions where short_name = 'g'), 100, 100, 300);
insert into inventory_lots(id, product, initial_qty, remaining_qty, total_cost)
values ('97000000-0000-0000-0000-000000000004','97000000-0000-0000-0000-000000000003',400,400,12);
insert into recipes(id, name, servings, output_food, yield_qty, instructions)
values ('97000000-0000-0000-0000-000000000005','QA dinner',4,'97000000-0000-0000-0000-000000000002',4,'[]');
insert into recipe_ingredients(recipe, ingredient, qty, unit)
values ('97000000-0000-0000-0000-000000000005','97000000-0000-0000-0000-000000000001',100,(select id from measure_conversions where short_name = 'g'));
insert into meal_plans(id, recipe, plan_date, daypart, scale_factor, group_id, intent)
values ('97000000-0000-0000-0000-000000000006','97000000-0000-0000-0000-000000000005',current_date,'dinner',1,'old-display-group','prepare');
insert into meal_plans(id, recipe, plan_date, daypart, scale_factor, group_id, intent, source_meal_plan)
values ('97000000-0000-0000-0000-000000000007','97000000-0000-0000-0000-000000000005',current_date+1,'lunch',1,'future-display-group','leftover','97000000-0000-0000-0000-000000000006');
select throws_ok($$delete from meal_plans where id = '97000000-0000-0000-0000-000000000006'$$,'23503',null,'Cannot silently detach future leftovers by deleting their source');
create temporary table leftover_test_batch as
select prepare_recipe('97000000-0000-0000-0000-000000000005', 1, 3, 'fridge', '97000000-0000-0000-0000-000000000006') result;
update meal_plans set group_id = 'renamed-display-group' where id = '97000000-0000-0000-0000-000000000006';
select lives_ok($$select consume_planned_meals(array['97000000-0000-0000-0000-000000000007'::uuid], array[0.5::numeric])$$,'Future leftover resolves by FK after display group rename');
select is((select remaining_qty from inventory_lots where id=(select (result->>'lotId')::uuid from leftover_test_batch)),2.5::numeric,'Fractional portion subtracts exactly from the selected batch');
select is((select kcal from food_logs where id=(select food_log from planned_consumptions where meal_plan='97000000-0000-0000-0000-000000000007')),50::numeric,'Nutrition uses actual yield of three rather than recipe yield of four');
select lives_ok($$select void_food_log((select food_log from planned_consumptions where meal_plan='97000000-0000-0000-0000-000000000007'))$$,'Individual undo restores the batch');
select is((select remaining_qty from inventory_lots where id=(select (result->>'lotId')::uuid from leftover_test_batch)),3::numeric,'Undo restores the exact half portion');
delete from meal_plans where id='97000000-0000-0000-0000-000000000007';
insert into meal_plans(id, inventory_lot, plan_date, daypart, scale_factor, intent)
select '97000000-0000-0000-0000-000000000008',(result->>'lotId')::uuid,current_date+2,'lunch',1,'consume' from leftover_test_batch;
delete from meal_plans where id='97000000-0000-0000-0000-000000000006';
select lives_ok($select gpt_preview_daily_nutrition(current_date+2,'{"sourceType":"recipe","sourceId":"97000000-0000-0000-0000-000000000005","servings":1}')$,'AI preview accepts prepared-lot plans');
select lives_ok($select consume_planned_meals(array['97000000-0000-0000-0000-000000000008'::uuid], array[1::numeric])$$,'Exact prepared lot remains edible after original plan is deleted');
select is((select remaining_qty from inventory_lots where id=(select (result->>'lotId')::uuid from leftover_test_batch)),2::numeric,'Exact-lot plan consumes one actual serving');
select throws_ok($$select consume_planned_meals(array['97000000-0000-0000-0000-000000000008'::uuid], array[1::numeric])$$,'P0001',null,'Duplicate fulfilled-plan consumption cannot deduct again');
select * from finish();
rollback;
