begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(17);

select ok(
  not public.is_app_owner(),
  'database test session is not treated as the application owner'
);

insert into base_foods (
  id,
  name,
  measure_style,
  display_unit,
  nutrition_basis_qty,
  kcal,
  protein_g,
  carbs_g,
  fat_g,
  fiber_g,
  sodium_mg
) values (
  '10000000-0000-0000-0000-000000000001',
  'Test flour',
  'weight',
  (select id from measure_conversions where short_name = 'g'),
  100,
  364,
  10,
  76,
  1,
  3,
  2
);

insert into products (
  id,
  food,
  name,
  brand,
  package_qty_base,
  package_unit
) values (
  '20000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  'All-purpose flour',
  'Test brand',
  453.59237,
  (select id from measure_conversions where short_name = 'oz')
);

insert into inventory_lots (
  id,
  product,
  initial_qty,
  remaining_qty,
  total_cost,
  location,
  acquired_at
) values (
  '30000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000001',
  453.59237,
  0,
  4.99,
  'pantry',
  '2026-08-29 12:00:00-04'
);

select is(
  round((select remaining_qty from inventory_lots where id = '30000000-0000-0000-0000-000000000001'), 5),
  453.59237::numeric,
  'A new lot always starts at its initial quantity'
);

select is(
  round(to_base_quantity(
    '10000000-0000-0000-0000-000000000001',
    16,
    (select id from measure_conversions where short_name = 'oz')
  ), 5),
  453.59237::numeric,
  'Weight units convert to the gram base quantity'
);

insert into food_logs (
  id,
  label,
  kind,
  occurred_at,
  kcal,
  protein_g,
  carbs_g,
  fat_g,
  fiber_g,
  sugar_g,
  sodium_mg
) values (
  '41000000-0000-0000-0000-000000000001',
  'Test flour serving',
  'inventory',
  '2026-08-30 02:00:00+00',
  364,
  10,
  76,
  1,
  3,
  0,
  2
);

insert into inventory_events (
  id,
  lot,
  quantity_delta,
  reason,
  occurred_at,
  food_log
) values (
  '40000000-0000-0000-0000-000000000001',
  '30000000-0000-0000-0000-000000000001',
  -100,
  'eaten',
  '2026-08-30 02:00:00+00',
  '41000000-0000-0000-0000-000000000001'
);

select is(
  round((select remaining_qty from inventory_lots where id = '30000000-0000-0000-0000-000000000001'), 5),
  353.59237::numeric,
  'A negative inventory event reduces the cached quantity'
);

update inventory_events
set voided_at = now()
where id = '40000000-0000-0000-0000-000000000001';

select is(
  round((select remaining_qty from inventory_lots where id = '30000000-0000-0000-0000-000000000001'), 5),
  453.59237::numeric,
  'Voiding an event restores its quantity'
);

update inventory_events
set voided_at = null
where id = '40000000-0000-0000-0000-000000000001';

select is(
  round((select remaining_qty from inventory_lots where id = '30000000-0000-0000-0000-000000000001'), 5),
  353.59237::numeric,
  'Clearing voided_at reapplies the event'
);

select throws_ok(
  $$
    insert into inventory_events(lot, quantity_delta, reason)
    values (
      '30000000-0000-0000-0000-000000000001',
      -1000,
      'waste'
    )
  $$,
  'P0001',
  'Inventory event would make lot 30000000-0000-0000-0000-000000000001 negative',
  'Inventory cannot become negative'
);

select is(
  round((
    select cost from inventory_event_costs
    where inventory_event_id = '40000000-0000-0000-0000-000000000001'
  ), 2),
  1.10::numeric,
  'A partial-lot event receives the same fraction of the purchase cost'
);

select is(
  round((
    select kcal from lot_nutrition_per_base_unit(
      '30000000-0000-0000-0000-000000000001'
    )
  ), 2),
  3.64::numeric,
  'A product inherits base-food nutrition per base unit'
);

select is(
  (select local_date from daily_nutrition where local_date = '2026-08-29'),
  '2026-08-29'::date,
  'Daily nutrition uses the configured local time zone'
);

update personal_settings
set nutrition_calories = 2500,
    allergies = array['Test allergy'],
    commute_minutes = 45
where singleton;

select is(
  (select nutrition_calories from personal_settings where singleton),
  2500::numeric,
  'Personal nutrition targets are stored in the settings singleton'
);

select throws_ok(
  $$
    update personal_settings
    set time_zone = 'Not/A_Time_Zone'
    where singleton
  $$,
  'P0001',
  'Unknown IANA time zone: Not/A_Time_Zone',
  'Personal settings reject invalid time zones'
);

insert into recipes (
  id,
  name,
  servings,
  instructions
) values (
  '50000000-0000-0000-0000-000000000001',
  'Test dough',
  2,
  '["Mix", "Divide"]'
);

insert into recipe_ingredients (
  recipe,
  ingredient,
  qty,
  unit
) values (
  '50000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  100,
  (select id from measure_conversions where short_name = 'g')
);

insert into preps (
  id,
  recipe,
  actual_yield_qty
) values (
  '60000000-0000-0000-0000-000000000001',
  '50000000-0000-0000-0000-000000000001',
  2
);

insert into inventory_events (
  lot,
  quantity_delta,
  reason,
  prep
) values (
  '30000000-0000-0000-0000-000000000001',
  -100,
  'prep',
  '60000000-0000-0000-0000-000000000001'
);

insert into inventory_lots (
  id,
  prep,
  initial_qty,
  remaining_qty,
  location
) values (
  '70000000-0000-0000-0000-000000000001',
  '60000000-0000-0000-0000-000000000001',
  2,
  0,
  'fridge'
);

select is(
  (select total_cost from inventory_lots where id = '70000000-0000-0000-0000-000000000001'),
  1.10::numeric,
  'A prepared lot inherits the cost of its consumed ingredients'
);

select is(
  round((
    select kcal from lot_nutrition_per_base_unit(
      '70000000-0000-0000-0000-000000000001'
    )
  ), 2),
  182.00::numeric,
  'Prepared-lot nutrition derives recursively from ingredient lots'
);

insert into base_foods (
  id,
  name,
  measure_style,
  display_unit
) values (
  '10000000-0000-0000-0000-000000000002',
  'Test egg',
  'discrete',
  (select id from measure_conversions where short_name = 'ct')
);

select throws_ok(
  $$
    insert into recipe_ingredients(recipe, ingredient, qty, unit)
    values (
      '50000000-0000-0000-0000-000000000001',
      '10000000-0000-0000-0000-000000000002',
      1,
      (select id from measure_conversions where short_name = 'cup')
    )
  $$,
  'P0001',
  'Ingredient unit cannot be converted to the food stock measure',
  'Cross-style recipe quantities require food-specific conversion data'
);

select throws_ok(
  $$
    insert into inventory_events(lot, quantity_delta, reason)
    values (
      '30000000-0000-0000-0000-000000000001',
      1,
      'waste'
    )
  $$,
  '23514',
  null,
  'Non-adjustment inventory events cannot add stock'
);

insert into inventory_events (
  lot,
  quantity_delta,
  reason
) values (
  '30000000-0000-0000-0000-000000000001',
  5,
  'adjust'
);

select is(
  round((select remaining_qty from inventory_lots where id = '30000000-0000-0000-0000-000000000001'), 5),
  258.59237::numeric,
  'A positive adjustment can add stock after a recount'
);

select * from finish();
rollback;
