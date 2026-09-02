begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select plan(77);

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select ok(public.is_app_owner(), 'Service-role Edge Function requests are recognized as the app operator');

insert into base_foods(id, name, measure_style, display_unit, nutrition_basis_qty, kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg)
values ('a1000000-0000-4000-8000-000000000001', 'GPT API test apple', 'discrete',
  (select id from measure_conversions where short_name = 'ct'), 1, 95, 0.5, 25, 0.3, 4.4, 19, 2);

insert into products(id, food, name, package_qty_base, package_unit, serving_qty_base)
values ('a2000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000001', 'GPT API test apple product', 1,
  (select id from measure_conversions where short_name = 'ct'), 0.25);

select lives_ok(
  $$select gpt_add_grocery_lots('[{"productId":"a2000000-0000-4000-8000-000000000001","quantity":2,"unit":"ct","location":"fridge","totalPrice":5,"outOfPocketCost":5,"paidBy":"self","costIsEstimated":false,"priceAsOf":"2026-09-02","acquiredAt":"2026-09-02T12:00:00-04:00","acquiredTimePrecision":"dateOnly"}]', 'pgTAP', 'b0000000-0000-4000-8000-000000000001')$$,
  'GPT grocery RPC accepts a structured product lot'
);

select lives_ok(
  $$select gpt_add_grocery_lots('[{"productId":"a2000000-0000-4000-8000-000000000001","quantity":2,"unit":"ct","location":"fridge","totalPrice":5,"outOfPocketCost":5,"paidBy":"self","costIsEstimated":false,"priceAsOf":"2026-09-02","acquiredAt":"2026-09-02T12:00:00-04:00","acquiredTimePrecision":"dateOnly"}]', 'pgTAP', 'b0000000-0000-4000-8000-000000000001')$$,
  'Retrying a grocery request with the same request ID succeeds'
);

select is(
  (select count(*) from inventory_lots where product = 'a2000000-0000-4000-8000-000000000001'),
  1::bigint,
  'A retried grocery request creates only one lot'
);

select is(
  (select remaining_qty from inventory_lots where product = 'a2000000-0000-4000-8000-000000000001'),
  2::numeric,
  'GPT grocery RPC stores canonical base quantity'
);

select lives_ok(
  $$select gpt_consume_inventory('a1000000-0000-4000-8000-000000000001', 1, 'ct', '2026-09-02T12:00:00-04:00', 'dateOnly', 'b0000000-0000-4000-8000-000000000002', 'Test apple', null)$$,
  'GPT inventory consumption is atomic'
);

select lives_ok(
  $$select gpt_consume_inventory('a1000000-0000-4000-8000-000000000001', 1, 'ct', '2026-09-02T12:00:00-04:00', 'dateOnly', 'b0000000-0000-4000-8000-000000000002', 'Test apple', null)$$,
  'Retrying consumption with the same request ID succeeds'
);

select is(
  (select count(*) from food_logs where label = 'Test apple'),
  1::bigint,
  'A retried consumption request creates only one history event'
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

select is(
  (select servings from food_logs where label = 'Test apple'),
  4::numeric,
  'Food-level inventory consumption stores nutritional servings, not item count'
);

insert into products(id, food, name, package_qty_base, package_unit, serving_qty_base)
values ('a2000000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-000000000001', 'Exact-lot apple product', 2,
  (select id from measure_conversions where short_name = 'ct'), 0.25);

select lives_ok(
  $$select gpt_add_grocery_lots('[{"productId":"a2000000-0000-4000-8000-000000000002","quantity":2,"unit":"ct","location":"fridge","note":"exact-target","totalPrice":4,"outOfPocketCost":4,"paidBy":"self","costIsEstimated":false,"priceAsOf":"2026-09-02","acquiredAt":"2026-09-02T12:00:00-04:00","acquiredTimePrecision":"dateOnly"}]', 'pgTAP', 'b0000000-0000-4000-8000-000000000003')$$,
  'A second lot of the same canonical food can be acquired'
);

select lives_ok(
  $$select gpt_consume_inventory(
    'a1000000-0000-4000-8000-000000000001', 1.5, 'ct', now(), 'exact', 'b0000000-0000-4000-8000-000000000004', 'Exact lot apple', null,
    (select id from inventory_lots where product = 'a2000000-0000-4000-8000-000000000002' and note = 'exact-target')
  )$$,
  'GPT inventory consumption can target a known lot'
);

select is(
  (select remaining_qty from inventory_lots where product = 'a2000000-0000-4000-8000-000000000001' and not is_external),
  1::numeric,
  'Exact-lot consumption leaves the older FEFO lot untouched'
);

select is(
  (select remaining_qty from inventory_lots where product = 'a2000000-0000-4000-8000-000000000002'),
  0.5::numeric,
  'Exact-lot consumption deducts the requested package'
);

select is(
  (select product from food_logs where label = 'Exact lot apple'),
  'a2000000-0000-4000-8000-000000000002'::uuid,
  'An exact-lot log retains exact product provenance'
);

select is(
  (select servings from food_logs where label = 'Exact lot apple'),
  6::numeric,
  'Exact-lot consumption uses the selected product serving size'
);

select throws_like(
  $$select gpt_consume_inventory(
    'a1000000-0000-4000-8000-000000000001', 1, 'ct', now(), 'exact', 'b0000000-0000-4000-8000-000000000005', 'No spillover', null,
    (select id from inventory_lots where product = 'a2000000-0000-4000-8000-000000000002')
  )$$,
  'Lot has only % remaining',
  'An insufficient exact lot fails instead of spilling into another lot'
);

select is(
  (select remaining_qty from inventory_lots where product = 'a2000000-0000-4000-8000-000000000001' and not is_external),
  1::numeric,
  'A failed exact-lot consumption does not deduct the available FEFO lot'
);

select is(
  (select count(*) from food_logs where label = 'No spillover'),
  0::bigint,
  'A failed exact-lot consumption does not create history'
);

select lives_ok(
  $$select consume_product_purchase('a2000000-0000-4000-8000-000000000001', 1, 0.5, 'ct', 'restaurant', 1.25, 1.25, 'self', false, 'pgTAP', current_date, 'b0000000-0000-4000-8000-000000000006', 'fridge', now(), 'exact', 'Away apple', null)$$,
  'GPT purchased-product acquisition and partial consumption are atomic'
);

select is(
  (select acquisition_food_log from inventory_lots where product = 'a2000000-0000-4000-8000-000000000001' and is_external),
  (select id from food_logs where label = 'Away apple'),
  'A purchase-and-consume lot explicitly links to its originating history event'
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

insert into base_foods(id, name, measure_style, display_unit, nutrition_basis_qty, kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg)
values ('a1000000-0000-4000-8000-000000000002', 'GPT API test weighed food', 'weight',
  (select id from measure_conversions where short_name = 'g'), 100, 200, 20, 10, 8, 1, 2, 100);

insert into products(id, food, name, package_qty_base, package_unit, serving_qty_base, nutrition_basis_qty)
values ('a2000000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-000000000002', 'GPT API test weighed product', 28.349523125,
  (select id from measure_conversions where short_name = 'oz'), 28.349523125, 100);

select lives_ok(
  $$select consume_product_purchase('a2000000-0000-4000-8000-000000000003', 2, 0.5, 'oz', 'grocery', 8, 8, 'self', false, 'Unit conversion test', current_date, 'b0000000-0000-4000-8000-00000000000b', 'freezer', now(), 'exact', 'Weighed purchase', null)$$,
  'Purchased-product consumption accepts an explicit human unit'
);

select ok(
  abs((select initial_qty from inventory_lots where product = 'a2000000-0000-4000-8000-000000000003') - 56.69904625) < 0.000001,
  'Two ounces are converted once to the canonical gram quantity'
);

select ok(
  abs((select remaining_qty from inventory_lots where product = 'a2000000-0000-4000-8000-000000000003') - 42.5242846875) < 0.000001,
  'The remainder is stored after converting the consumed half ounce once'
);

select is(
  (consume_product_purchase('a2000000-0000-4000-8000-000000000003', 2, 0.5, 'oz', 'grocery', 8, 8, 'self', false, 'Unit conversion test', current_date, 'b0000000-0000-4000-8000-00000000000b', 'freezer', now(), 'exact', 'Weighed purchase', null) ->> 'quantityUnit'),
  'oz',
  'An idempotent retry reports the same caller-facing quantity unit'
);

select is(
  (select event_cost.cost from inventory_event_costs event_cost join inventory_events event on event.id = event_cost.inventory_event_id join food_logs log on log.id = event.food_log where log.label = 'Away apple'),
  0.6250::numeric,
  'Partial consumption allocates only the consumed share of purchase cost'
);

select is(
  (select kind from food_logs where label = 'Away apple'),
  'inventory',
  'Purchased products use the unified inventory food-log kind'
);

select lives_ok(
  $$select gpt_update_consumption((select id from food_logs where label = 'Away apple'), '{"purchaseTotalPrice":4.05,"purchaseOutOfPocketCost":4.05,"purchasePaidBy":"self","purchasePriceAsOf":"2026-09-02","costIsEstimated":false,"costSource":"Receipt"}')$$,
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
  (select event_cost.cost from inventory_event_costs event_cost join inventory_events event on event.id = event_cost.inventory_event_id join food_logs log on log.id = event.food_log where log.label = 'Away apple'),
  2.0250::numeric,
  'Corrected purchase cost is allocated to the consumed portion'
);

select is(
  (select count(*) from record_edits where resource = 'consumption' and record_id = (select id from food_logs where label = 'Away apple')),
  1::bigint,
  'Consumption correction stores an audit record'
);

select lives_ok(
  $$select log_manual_consumption('Spaghetti at Mom''s', '1 large plate', '2026-09-01T19:15:00-04:00', 'estimated', null, null, '[{"label":"Spaghetti","portionLabel":"1 large plate"}]', 'home', null, 0, 'parents', false, 'Shared family meal', null, 'b0000000-0000-4000-8000-000000000007', null)$$,
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
  $$select log_manual_consumption('Estimated snack', '1 bowl', now(), 'estimated', '{"calories":320,"proteinG":8,"estimated":true,"source":"Visual estimate"}', '{"confidence":"low","rationale":"Visual estimate"}', '[{"label":"Snack","portionLabel":"1 bowl"}]', 'grocery', 2.50, 2.50, 'self', true, 'Memory', current_date, 'b0000000-0000-4000-8000-000000000008', null)$$,
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

select throws_ok(
  $$select log_manual_consumption('Unpriced takeout', '1 item', now(), 'exact', null, null, '[{"label":"Takeout"}]', 'takeout', null, 0, 'friend', false, 'No price', null, 'b0000000-0000-4000-8000-00000000000c', null)$$,
  'Purchased manual food cannot omit its full price'
);

select throws_ok(
  $$select log_manual_consumption('Componentless meal', '1 item', now(), 'exact', null, null, '[]', 'home', null, 0, 'self', false, 'Home food', null, 'b0000000-0000-4000-8000-00000000000d', null)$$,
  'Manual consumption cannot omit meaningful components'
);

select throws_ok(
  $$select log_manual_consumption('Unqualified estimate', '1 item', now(), 'estimated', '{"calories":100,"estimated":true,"source":"Visual"}', null, '[{"label":"Estimated item"}]', 'home', null, 0, 'self', false, 'Home food', null, 'b0000000-0000-4000-8000-00000000000e', null)$$,
  'Estimated manual nutrition requires structured confidence metadata'
);

select lives_ok(
  $$select gpt_update_consumption((select id from food_logs where label = 'Spaghetti at Mom''s'), '{"portionLabel":"2 small plates","nutrition":{"calories":700,"proteinG":25,"carbsG":90,"fatG":24,"fiberG":6,"sugarG":12,"sodiumMg":900,"estimated":true,"source":"Family recipe estimate"},"nutritionEstimate":{"confidence":"medium","rationale":"Family recipe and recalled portion"}}')$$,
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

select throws_ok(
  $$select gpt_void_consumption((select id from food_logs where label = 'Away apple'), 'Incorrect event')$$,
  'This purchase lot was used again; void its later inventory events before voiding the originating purchase',
  'An originating purchase cannot be voided after its lot was adjusted or reused'
);

select lives_ok(
  $$select gpt_update_product('a2000000-0000-4000-8000-000000000001', '{"name":"Corrected apple product","estimatedCost":4.05,"costSource":"Receipt","costAsOf":"2026-09-02"}')$$,
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
  $$select gpt_replace_weekly_plan(current_date, jsonb_build_array(jsonb_build_object(
    'date', current_date, 'slot', 'dinner', 'source', 'recipe',
    'sourceId', 'a3000000-0000-4000-8000-000000000001',
    'scaleFactor', 2, 'plannedServings', 0.5
  )))$$,
  'GPT weekly planning stores preparation and consumption quantities separately'
);

select is(
  (select scale_factor from meal_plans where recipe = 'a3000000-0000-4000-8000-000000000001'),
  2::numeric,
  'GPT weekly planning preserves preparation scale'
);

select is(
  (select consumption.servings from planned_consumptions consumption join meal_plans plan on plan.id = consumption.meal_plan where plan.recipe = 'a3000000-0000-4000-8000-000000000001'),
  0.5::numeric,
  'GPT weekly planning stores expected eaten servings independently'
);

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

select lives_ok(
  $$select gpt_update_food('a1000000-0000-4000-8000-000000000001', '{"alwaysAvailable":true}')$$,
  'A canonical food can be marked always available'
);

select ok(
  (select always_available from base_foods where id = 'a1000000-0000-4000-8000-000000000001'),
  'Always-available status is stored on the canonical food'
);

select lives_ok(
  $$select consume_product_purchase('a2000000-0000-4000-8000-000000000001', 2, 1, 'ct', 'grocery', 4, 4, 'self', true, 'Exact-store listing', '2026-08-20', 'b0000000-0000-4000-8000-000000000009', 'fridge', '2026-08-20T17:00:00-04:00', 'estimated', 'Voidable grocery apple', null)$$,
  'A purchased product can be classified as grocery stock'
);

select is(
  (select is_external from inventory_lots where acquisition_food_log = (select id from food_logs where label = 'Voidable grocery apple')),
  false,
  'Grocery purchase-and-consume lots are not counted as away-from-home spending'
);

select lives_ok(
  $$select gpt_void_consumption((select id from food_logs where label = 'Voidable grocery apple'), 'Duplicate entry')$$,
  'A duplicate purchase-and-consume history event can be voided'
);

select ok(
  (select voided_at is not null from food_logs where label = 'Voidable grocery apple'),
  'Voiding preserves the history row as an inactive audit record'
);

select is(
  (select remaining_qty from inventory_lots where acquisition_food_log = (select id from food_logs where label = 'Voidable grocery apple')),
  0::numeric,
  'Voiding also compensates the lot acquired by the same action'
);

select lives_ok(
  $$select restore_food_log((select id from food_logs where label = 'Voidable grocery apple'))$$,
  'A voided purchase-and-consume action can be restored'
);

select is(
  (select remaining_qty from inventory_lots where acquisition_food_log = (select id from food_logs where label = 'Voidable grocery apple')),
  1::numeric,
  'Restoring reapplies the original acquisition and consumed portion'
);

update base_foods
set always_available = false
where id = 'a1000000-0000-4000-8000-000000000001';

select lives_ok(
  $$select gpt_prepare_recipe('a3000000-0000-4000-8000-000000000001', 0.3, 'fridge', null, 'Historical prep test', '2026-08-20T18:15:00-04:00', 'estimated', 'b0000000-0000-4000-8000-00000000000a')$$,
  'GPT recipe preparation accepts an explicit historical timestamp'
);

select is(
  (select prepped_at from preps where note = 'Historical prep test'),
  '2026-08-20T18:15:00-04:00'::timestamptz,
  'Historical preparation stores the supplied prep time'
);

select is(
  (select lot.acquired_at from inventory_lots lot join preps prep on prep.id = lot.prep where prep.note = 'Historical prep test'),
  '2026-08-20T18:15:00-04:00'::timestamptz,
  'Historical preparation timestamps its output lot'
);

select ok(
  (select bool_and(event.occurred_at = '2026-08-20T18:15:00-04:00'::timestamptz)
   from inventory_events event join preps prep on prep.id = event.prep where prep.note = 'Historical prep test'),
  'Historical preparation timestamps every ingredient deduction'
);

select ok(
  (select lot.acquisition_type = 'home'
     and lot.out_of_pocket_cost is not null
     and nullif(trim(lot.paid_by), '') is not null
     and lot.cost_source like 'Carried forward from ingredient lots:%'
   from inventory_lots lot join preps prep on prep.id = lot.prep
   where prep.note = 'Historical prep test'),
  'Recipe preparation carries ingredient payment provenance into its output lot'
);

select * from finish();
rollback;
