begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(30);
create temporary table transaction_test_results(result text);
grant insert, select on transaction_test_results to authenticated;

insert into auth.sessions(id, user_id, created_at, updated_at)
select
  '90000000-0000-0000-0000-000000000001',
  app_user.id,
  now(),
  now()
from auth.users app_user
where app_user.email = 'xdrewbrandtx@gmail.com';

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', (select id from auth.users where email = 'xdrewbrandtx@gmail.com'),
    'role', 'authenticated',
    'session_id', '90000000-0000-0000-0000-000000000001'
  )::text,
  true
);
set local role authenticated;

insert into transaction_test_results select ok(public.is_app_owner(), 'Test JWT resolves to the live owner and temporary session');

insert into base_foods(id, name, measure_style, display_unit)
values
  ('91000000-0000-0000-0000-000000000001', 'Transaction test ingredient', 'weight', (select id from measure_conversions where short_name = 'g')),
  ('91000000-0000-0000-0000-000000000002', 'Transaction test prepared food', 'discrete', (select id from measure_conversions where short_name = 'ct'));

insert into products(id, food, name, package_qty_base, package_unit, nutrition_basis_qty, kcal, protein_g, carbs_g, fat_g, fiber_g, sodium_mg)
values (
  '92000000-0000-0000-0000-000000000001',
  '91000000-0000-0000-0000-000000000001',
  'Transaction test ingredient product',
  200,
  (select id from measure_conversions where short_name = 'g'),
  100,
  300,
  10,
  50,
  5,
  2,
  100
);

insert into inventory_lots(id, product, initial_qty, remaining_qty, total_cost, location)
values ('93000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001', 200, 200, 4, 'pantry');

insert into recipes(id, name, servings, output_food, yield_qty, instructions)
values ('94000000-0000-0000-0000-000000000001', 'Transaction test recipe', 2, '91000000-0000-0000-0000-000000000002', 2, '[]');

insert into recipe_ingredients(recipe, ingredient, qty, unit)
values ('94000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001', 100, (select id from measure_conversions where short_name = 'g'));

insert into transaction_test_results select lives_ok(
  $$select cook_recipe('94000000-0000-0000-0000-000000000001')$$,
  'Cooking succeeds as one owner-authorized transaction'
);

insert into transaction_test_results select is(
  (select remaining_qty from inventory_lots where id = '93000000-0000-0000-0000-000000000001'),
  100::numeric,
  'Cooking deducts the required ingredient quantity'
);

insert into transaction_test_results select lives_ok(
  $$select save_prep_feedback((select id from preps where recipe = '94000000-0000-0000-0000-000000000001'), 4, 5, 27)$$,
  'Preparation feedback is saved against the preparation event'
);

insert into transaction_test_results select is(
  (select concat(ease_rating, '/', taste_rating, '/', actual_minutes) from preps where recipe = '94000000-0000-0000-0000-000000000001'),
  '4/5/27',
  'Ease, taste, and actual time remain attached to that preparation'
);

insert into transaction_test_results select lives_ok(
  $$select consume_inventory_lot('93000000-0000-0000-0000-000000000001'::uuid, 10::numeric)$$,
  'Consuming a raw inventory lot logs nutrition and deducts the lot'
);

insert into transaction_test_results select is(
  (select remaining_qty from inventory_lots where id = '93000000-0000-0000-0000-000000000001'),
  90::numeric,
  'Raw inventory consumption reduces remaining stock'
);

insert into transaction_test_results select is(
  (select count(*) from food_logs where kind = 'inventory' and product = '92000000-0000-0000-0000-000000000001'),
  1::bigint,
  'Raw inventory consumption creates one linked food log'
);

insert into transaction_test_results select lives_ok(
  $$select set_inventory_lot_quantity('93000000-0000-0000-0000-000000000001'::uuid, 80::numeric, false)$$,
  'A lot can be manually adjusted to a corrected remaining quantity'
);

insert into transaction_test_results select is(
  (select remaining_qty from inventory_lots where id = '93000000-0000-0000-0000-000000000001'),
  80::numeric,
  'The adjustment event sets the corrected stock quantity'
);

insert into transaction_test_results select lives_ok(
  $$select consume_prepared_lot((select id from inventory_lots where prep is not null and id <> '93000000-0000-0000-0000-000000000001'), 1)$$,
  'Consuming a prepared unit logs food and deducts the prepared lot atomically'
);

insert into transaction_test_results select is(
  (select remaining_qty from inventory_lots where prep is not null),
  1::numeric,
  'Prepared inventory decreases by the consumed quantity'
);

insert into meal_plans(plan_date, daypart, recipe, scale_factor, status)
values (current_date, 'dinner', '94000000-0000-0000-0000-000000000001', 2, 'planned');

insert into shopping_items(food, qty_needed, unit, source, checked_at, quantity_label)
values (
  '91000000-0000-0000-0000-000000000001',
  999,
  (select id from measure_conversions where short_name = 'oz'),
  'generated',
  now(),
  'stale checked item'
);

insert into shopping_items(free_text, source)
values ('Manual transaction-test item', 'manual');

insert into transaction_test_results select is(
  rebuild_shopping_from_plan(current_date, current_date),
  1,
  'Rebuilding the plan creates one grocery shortage'
);

insert into transaction_test_results select is(
  (select round(qty_needed, 2) from shopping_items where food = '91000000-0000-0000-0000-000000000001' and source = 'generated'),
  4.23::numeric,
  'Generated grocery quantity subtracts available inventory and uses the food display unit'
);

insert into transaction_test_results select is(
  (select count(*) from shopping_items where source = 'generated' and checked_at is null),
  1::bigint,
  'Rebuilding replaces checked generated items with the current plan projection'
);

insert into transaction_test_results select is(
  (select count(*) from shopping_items where source = 'manual' and free_text = 'Manual transaction-test item'),
  1::bigint,
  'Rebuilding preserves manually added shopping items'
);

insert into transaction_test_results select lives_ok(
  $$select set_inventory_lot_quantity('93000000-0000-0000-0000-000000000001'::uuid, 0::numeric, true)$$,
  'Discarding a lot records its remaining quantity as waste'
);

insert into transaction_test_results select is(
  (select count(*) from inventory_events where lot = '93000000-0000-0000-0000-000000000001' and reason = 'waste'),
  1::bigint,
  'The discard event is explicitly classified as waste'
);

-- Undo, as compensating events. Each of these asserts that the lot cache lands
-- back where it started, since that cache is recomputed from non-voided events.

insert into transaction_test_results select is(
  (select remaining_qty from inventory_lots where id = '93000000-0000-0000-0000-000000000001'),
  0::numeric,
  'The discard left the lot empty before undo'
);

insert into transaction_test_results select lives_ok(
  $$select undo_inventory_adjustment((select id from inventory_events where lot = '93000000-0000-0000-0000-000000000001' and reason = 'waste' and voided_at is null))$$,
  'A discard can be undone'
);

insert into transaction_test_results select is(
  (select remaining_qty from inventory_lots where id = '93000000-0000-0000-0000-000000000001'),
  80::numeric,
  'Undoing the discard restores exactly what the lot held before it'
);

insert into transaction_test_results select throws_ok(
  $$select undo_inventory_adjustment((select id from inventory_events where reason = 'eaten' and voided_at is null limit 1))$$,
  'Undoing an adjustment cannot be aimed at an eaten event'
);

-- Undoing an eat: the log stops counting and the servings come back.
insert into transaction_test_results select lives_ok(
  $$select void_food_log((select id from food_logs where kind = 'prepared' order by occurred_at desc limit 1))$$,
  'An eaten serving can be voided'
);

insert into transaction_test_results select is(
  (select count(*) from inventory_events where food_log = (select id from food_logs where kind = 'prepared' order by occurred_at desc limit 1) and voided_at is null),
  0::bigint,
  'Voiding the log voids the inventory events it consumed'
);

insert into transaction_test_results select lives_ok(
  $$select restore_food_log((select id from food_logs where kind = 'prepared' order by occurred_at desc limit 1))$$,
  'A removed log entry can be restored'
);

insert into transaction_test_results select is(
  (select count(*) from inventory_events where food_log = (select id from food_logs where kind = 'prepared' order by occurred_at desc limit 1) and voided_at is null),
  1::bigint,
  'Restoring the log reapplies its deduction'
);

-- Undoing a cook: refused once the batch has been eaten from, allowed otherwise.
insert into transaction_test_results select throws_ok(
  $$select undo_prep((select prep from inventory_lots where prep is not null and remaining_qty < initial_qty limit 1))$$,
  'A batch that has been eaten from can no longer be uncooked'
);

insert into transaction_test_results select lives_ok(
  $$select cook_recipe('94000000-0000-0000-0000-000000000001'::uuid, 1, null, 'fridge')$$,
  'A second batch can be cooked for the undo case'
);

insert into transaction_test_results select lives_ok(
  $$select undo_prep((select id from preps where voided_at is null order by prepped_at desc limit 1))$$,
  'An untouched batch can be uncooked'
);

insert into transaction_test_results select is(
  (select count(*) from inventory_lots lot join preps prep on prep.id = lot.prep where prep.voided_at is null and lot.remaining_qty > 0),
  1::bigint,
  'Uncooking zeroes the batch it produced and leaves the earlier one alone'
);

insert into transaction_test_results select * from finish();
select json_agg(result) as transaction_tests from transaction_test_results;
rollback;
