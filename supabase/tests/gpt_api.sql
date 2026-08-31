begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select plan(8);

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
  $$select gpt_save_external_food('{"name":"GPT API test sandwich","brand":"Test","calories":400,"proteinG":20,"carbsG":40,"fatG":15,"fiberG":2,"sugarG":5,"sodiumMg":800,"estimated":false}')$$,
  'GPT outside-food RPC creates its food and product together'
);

select is(
  (select count(*) from products where name = 'GPT API test sandwich' and is_external),
  1::bigint,
  'GPT outside-food product is reusable'
);

select * from finish();
rollback;
