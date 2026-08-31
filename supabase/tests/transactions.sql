begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(7);

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

select ok(public.is_app_owner(), 'Test JWT resolves to the live owner and temporary session');

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

select lives_ok(
  $$select cook_recipe('94000000-0000-0000-0000-000000000001')$$,
  'Cooking succeeds as one owner-authorized transaction'
);

select is(
  (select remaining_qty from inventory_lots where id = '93000000-0000-0000-0000-000000000001'),
  100::numeric,
  'Cooking deducts the required ingredient quantity'
);

select lives_ok(
  $$select consume_prepared_lot((select id from inventory_lots where prep is not null and id <> '93000000-0000-0000-0000-000000000001'), 1)$$,
  'Consuming a prepared unit logs food and deducts the prepared lot atomically'
);

select is(
  (select remaining_qty from inventory_lots where prep is not null),
  1::numeric,
  'Prepared inventory decreases by the consumed quantity'
);

insert into meal_plans(plan_date, daypart, recipe, scale_factor, status)
values (current_date, 'dinner', '94000000-0000-0000-0000-000000000001', 2, 'planned');

select is(
  rebuild_shopping_from_plan(current_date, current_date),
  1,
  'Rebuilding the plan creates one grocery shortage'
);

select is(
  (select round(qty_needed, 2) from shopping_items where food = '91000000-0000-0000-0000-000000000001' and source = 'generated'),
  100.00::numeric,
  'Generated grocery quantity subtracts available inventory'
);

select * from finish();
rollback;
