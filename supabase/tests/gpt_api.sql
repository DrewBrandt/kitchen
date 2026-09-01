begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select plan(11);

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

select * from finish();
rollback;
