begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select plan(37);

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select ok(public.is_app_owner(), 'Service-role Edge Function requests are recognized as the app operator');

insert into base_foods(id, name, measure_style, display_unit, nutrition_basis_qty, kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg)
values ('a1000000-0000-4000-8000-000000000001', 'GPT API test apple', 'discrete',
  (select id from measure_conversions where short_name = 'ct'), 1, 95, 0.5, 25, 0.3, 4.4, 19, 2);

insert into products(id, food, name, package_qty_base, package_unit, serving_qty_base)
values ('a2000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000001', 'GPT API test apple product', 1,
  (select id from measure_conversions where short_name = 'ct'), 1);

select lives_ok(
  $$select gpt_add_grocery_lots('[{"productId":"a2000000-0000-4000-8000-000000000001","quantity":2,"unit":"ct","location":"fridge"}]', 'pgTAP')$$,
  'GPT grocery RPC accepts a structured product lot'
);

select is(
  (select remaining_qty from inventory_lots where product = 'a2000000-0000-4000-8000-000000000001'),
  2::numeric,
  'GPT grocery RPC stores canonical base quantity'
);

select lives_ok(
  $$select gpt_consume_inventory('a1000000-0000-4000-8000-000000000001', 1, 'ct', now(), 'Test apple', null)$$,
  'GPT inventory consumption is atomic'
);

select is(
  (select remaining_qty from inventory_lots where product = 'a2000000-0000-4000-8000-000000000001'),
  1::numeric,
  'GPT inventory consumption deducts the FEFO lot'
);

select is(
  (select sugar_g from food_logs where label = 'Test apple'),
  19::numeric,
  'GPT consumption retains sugar nutrition'
);

select lives_ok(
  $$select consume_product_purchase('a2000000-0000-4000-8000-000000000001', 1, 0.5, 'fridge', now(), 1.25, false, 'pgTAP', 'Away apple', null)$$,
  'GPT purchased-product acquisition and partial consumption are atomic'
);

select is(
  (select count(*) from inventory_lots where product = 'a2000000-0000-4000-8000-000000000001' and is_external and remaining_qty = 0.5 and location = 'fridge'),
  1::bigint,
  'Partial consumption retains the remainder in the reported location'
);

select is(
  (select count(*) from inventory_events event join food_logs log on log.id = event.food_log where log.label = 'Away apple' and event.reason = 'eaten' and event.voided_at is null),
  1::bigint,
  'Immediate consumption uses the ordinary eaten-event ledger'
);

select is(
  (select cost from inventory_event_costs event_cost join inventory_events event on event.id = event_cost.inventory_event_id join food_logs log on log.id = event.food_log where log.label = 'Away apple'),
  0.6250::numeric,
  'Partial consumption allocates only the consumed share of purchase cost'
);

select is(
  (select kind from food_logs where label = 'Away apple'),
  'inventory',
  'Purchased products use the unified inventory food-log kind'
);

select lives_ok(
  $$select gpt_update_consumption((select id from food_logs where label = 'Away apple'), '{"purchaseTotalCost":4.05,"costIsEstimated":false,"costSource":"Receipt"}')$$,
  'An existing purchased-food consumption cost can be corrected in place'
);

select is(
  (select count(*) from food_logs where label = 'Away apple'),
  1::bigint,
  'Cost correction does not duplicate nutrition history'
);

select is(
  (select total_cost from inventory_lots where product = 'a2000000-0000-4000-8000-000000000001' and is_external),
  4.05::numeric,
  'Consumption cost correction updates the originating purchase lot'
);

select is(
  (select cost from inventory_event_costs event_cost join inventory_events event on event.id = event_cost.inventory_event_id join food_logs log on log.id = event.food_log where log.label = 'Away apple'),
  2.0250::numeric,
  'Corrected purchase cost is allocated to the consumed portion'
);

select is(
  (select count(*) from record_edits where resource = 'consumption' and record_id = (select id from food_logs where label = 'Away apple')),
  1::bigint,
  'Consumption correction stores an audit record'
);

select lives_ok(
  $$select log_manual_consumption('Spaghetti at Mom''s', '1 large plate', '2026-09-01T19:15:00-04:00', null, 0, false, 'Shared family meal', null)$$,
  'A manual meal can be logged with no product or nutrition'
);

select is(
  (select kind from food_logs where label = 'Spaghetti at Mom''s'),
  'manual',
  'Manual consumption has its own event kind'
);

select is(
  (select count(*) from inventory_events event join food_logs log on log.id = event.food_log where log.label = 'Spaghetti at Mom''s'),
  0::bigint,
  'Manual consumption creates no inventory deduction'
);

select is(
  (select nutrition_status from food_logs where label = 'Spaghetti at Mom''s'),
  'unknown',
  'All-null nutrition is explicitly unknown'
);

select lives_ok(
  $$select log_manual_consumption('Estimated snack', '1 bowl', now(), '{"calories":320,"proteinG":8,"estimated":true,"source":"Visual estimate"}', 2.50, true, 'Memory', null)$$,
  'A manual meal accepts a partial estimated nutrition snapshot and direct cost'
);

select is(
  (select nutrition_status from food_logs where label = 'Estimated snack'),
  'partial',
  'Missing nutrient fields produce partial status instead of zeroes'
);

select ok(
  (select nutrition_is_estimated from food_logs where label = 'Estimated snack'),
  'Nutrition confidence is independent from completeness'
);

select is(
  (select cost from food_logs where label = 'Estimated snack'),
  2.50::numeric,
  'Manual consumption stores direct cost without a lot'
);

select lives_ok(
  $$select gpt_update_consumption((select id from food_logs where label = 'Spaghetti at Mom''s'), '{"portionLabel":"2 small plates","nutrition":{"calories":700,"proteinG":25,"carbsG":90,"fatG":24,"fiberG":6,"sugarG":12,"sodiumMg":900,"estimated":true,"source":"Family recipe estimate"}}')$$,
  'A manual consumption event can be corrected in place'
);

select is(
  (select concat(portion_label, '/', nutrition_status) from food_logs where label = 'Spaghetti at Mom''s'),
  '2 small plates/complete',
  'Correction updates the portion and computed nutrition completeness'
);

select ok(
  (select partial_entries >= 1 from daily_nutrition where local_date = (now() at time zone (select time_zone from app_settings where singleton))::date),
  'Daily nutrition exposes incomplete entry counts'
);

select lives_ok(
  $$select gpt_update_inventory_lot((select id from inventory_lots where product = 'a2000000-0000-4000-8000-000000000001' and is_external), '{"remainingQuantity":0.25,"location":"freezer"}')$$,
  'Lot metadata and remaining quantity can be corrected together'
);

select is(
  (select remaining_qty from inventory_lots where product = 'a2000000-0000-4000-8000-000000000001' and is_external),
  0.25::numeric,
  'Lot correction changes the current remaining quantity'
);

select is(
  (select count(*) from inventory_events event join inventory_lots lot on lot.id = event.lot where lot.is_external and event.reason = 'adjust' and event.quantity_delta = -0.25),
  1::bigint,
  'Lot quantity correction is represented by a ledger adjustment'
);

select lives_ok(
  $$select gpt_update_product('a2000000-0000-4000-8000-000000000001', '{"name":"Corrected apple product","estimatedCost":4.05,"costSource":"Receipt"}')$$,
  'A product definition can be partially edited'
);

select is(
  (select name from products where id = 'a2000000-0000-4000-8000-000000000001'),
  'Corrected apple product',
  'Product edits preserve identity while changing selected fields'
);

insert into recipes(id, name, servings)
values ('a3000000-0000-4000-8000-000000000001', 'GPT edit recipe', 2);
insert into recipe_ingredients(recipe, ingredient, qty, unit)
values ('a3000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000001', 1,
  (select id from measure_conversions where short_name = 'ct'));

select lives_ok(
  $$select gpt_update_recipe('a3000000-0000-4000-8000-000000000001', '{"name":"Corrected GPT edit recipe","servings":3}')$$,
  'A recipe can be partially edited without resupplying ingredients'
);

select is(
  (select name from recipes where id = 'a3000000-0000-4000-8000-000000000001'),
  'Corrected GPT edit recipe',
  'Recipe metadata edit preserves recipe identity'
);

select is(
  (select count(*) from recipe_ingredients where recipe = 'a3000000-0000-4000-8000-000000000001'),
  1::bigint,
  'Omitted recipe ingredients remain unchanged'
);

select lives_ok(
  $$select gpt_update_food('a1000000-0000-4000-8000-000000000001', '{"name":"Corrected GPT API test apple","aliases":["edit apple"]}')$$,
  'A canonical food can be partially edited'
);

select is(
  (select aliases from base_foods where id = 'a1000000-0000-4000-8000-000000000001'),
  array['edit apple']::text[],
  'Food edit applies only the supplied fields'
);

select * from finish();
rollback;
