-- Repair the records that exposed the conversational backfill gaps and make the
-- same contradictions mechanically detectable or impossible going forward.

-- A rounded net weight and the printed servings-per-container count are only
-- interchangeable when the nutrition basis is the printed serving quantity.
-- Baileys, for example, stores nutrients per 100 mL but a different serving
-- size, so blindly applying servings_per_package doubles its nutrition.
create or replace function public.product_nutrition_multiplier(
  p_product uuid,
  p_quantity numeric
)
returns numeric
language sql
stable
set search_path = ''
as $$
  select case
    when product.servings_per_package is not null
      and product.package_qty_base > 0
      and product.serving_qty_base is not null
      and product.nutrition_basis_qty is not null
      and abs(product.nutrition_basis_qty - product.serving_qty_base) < 0.000001
      then p_quantity / product.package_qty_base * product.servings_per_package
    else p_quantity / coalesce(nullif(product.nutrition_basis_qty, 0), 1)
  end
  from public.products product
  where product.id = p_product
$$;

-- The old consume-purchased-product contract accepted an undocumented canonical
-- base amount. That is how 23.42 oz was once interpreted as 23.42 whole packages.
-- Accept an explicit human unit and convert at the database boundary instead.
create function public.consume_product_purchase(
  p_product uuid,
  p_purchased_quantity numeric,
  p_consumed_quantity numeric,
  p_quantity_unit text,
  p_acquisition_type text,
  p_total_price numeric,
  p_out_of_pocket_cost numeric,
  p_paid_by text,
  p_cost_is_estimated boolean,
  p_cost_source text,
  p_price_as_of date,
  p_request_id uuid,
  p_location text default null,
  p_occurred_at timestamptz default now(),
  p_time_precision text default 'exact',
  p_label text default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  product_food uuid;
  unit_id uuid;
  purchased_base numeric;
  consumed_base numeric;
  action_result jsonb;
begin
  if nullif(trim(coalesce(p_quantity_unit, '')), '') is null then
    raise exception 'quantityUnit is required';
  end if;
  select food into product_food
  from public.products
  where id = p_product and archived_at is null;
  if not found then raise exception 'Active product does not exist'; end if;
  unit_id := public.resolve_measure_conversion(p_quantity_unit);
  purchased_base := public.to_base_quantity(product_food, p_purchased_quantity, unit_id);
  consumed_base := case when p_consumed_quantity = 0 then 0
    else public.to_base_quantity(product_food, p_consumed_quantity, unit_id) end;

  action_result := public.consume_product_purchase(
    p_product, purchased_base, consumed_base, p_acquisition_type,
    p_total_price, p_out_of_pocket_cost, p_paid_by, p_cost_is_estimated,
    p_cost_source, p_price_as_of, p_request_id, p_location, p_occurred_at,
    p_time_precision, p_label, p_note
  );
  return (action_result - 'remainingQuantity') || jsonb_build_object(
    'remainingQuantity', p_purchased_quantity - p_consumed_quantity,
    'quantityUnit', trim(p_quantity_unit)
  );
end;
$$;

revoke all on function public.consume_product_purchase(uuid, numeric, numeric, text, text, numeric, numeric, text, boolean, text, date, uuid, text, timestamptz, text, text, text) from public, anon, authenticated;
grant execute on function public.consume_product_purchase(uuid, numeric, numeric, text, text, numeric, numeric, text, boolean, text, date, uuid, text, timestamptz, text, text, text) to service_role;
revoke execute on function public.consume_product_purchase(uuid, numeric, numeric, text, numeric, numeric, text, boolean, text, date, uuid, text, timestamptz, text, text, text) from service_role;

-- Retain a durable before/after audit trail for this one-time repair, including
-- manual preparations, which were not an editable resource when record_edits
-- was first introduced.
alter table public.record_edits drop constraint if exists record_edits_resource_check;
alter table public.record_edits add constraint record_edits_resource_check check (
  resource in ('food', 'product', 'recipe', 'prep', 'inventory_lot', 'consumption')
);

create temporary table history_repair_before (
  resource text not null,
  record_id uuid not null,
  before_state jsonb not null,
  repair_reason text not null,
  primary key (resource, record_id)
) on commit drop;

insert into history_repair_before
select 'food', id, to_jsonb(food), 'Full historical integrity audit on 2026-09-02'
from public.base_foods food;
insert into history_repair_before
select 'product', id, to_jsonb(product), 'Full historical integrity audit on 2026-09-02'
from public.products product;
insert into history_repair_before
select 'prep', id, to_jsonb(prep), 'Full historical integrity audit on 2026-09-02'
from public.preps prep;
insert into history_repair_before
select 'inventory_lot', id, to_jsonb(lot), 'Full historical integrity audit on 2026-09-02'
from public.inventory_lots lot;
insert into history_repair_before
select 'consumption', id, to_jsonb(log), 'Full historical integrity audit on 2026-09-02'
from public.food_logs log;

-- The legacy batch action emitted the same half-glass consumption three times,
-- separated only by one millisecond. Preserve the first and void the retries.
update public.food_logs
set voided_at = now(),
    note = concat_ws(' ', note, 'Voided as a duplicate created by the legacy non-idempotent batch action.')
where id in (
  '05ab2dff-17dd-5341-bea2-0267034c4951',
  'c696e1ef-b822-5b59-bd10-4a147ec28cbf'
)
  and voided_at is null;

-- The Chick-n-Minis event had correct nutrition and a corrected label, but both
-- its log and purchase lot still referenced a Chicken Biscuit product. Give the
-- menu item its own identity before merging the real duplicate biscuit product.
insert into public.base_foods(
  id, name, plural, measure_style, emoji, display_unit, nutrition_basis_qty,
  kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg,
  aliases, nutrition_source, nutrition_is_estimated
) values (
  'd660a4d4-3f6c-4958-a8f5-4ab0a60c9c58',
  'Chick-fil-A Chick-n-Minis 4-count order',
  'Chick-fil-A Chick-n-Minis 4-count orders',
  'discrete', '🐔',
  (select id from public.measure_conversions where lower(short_name) = 'ct'),
  1, 360, 20, 41, 13, 2, 8, 1060,
  array['Chick-n-Minis', '4 ct Chick-fil-A Chick-n-Minis'],
  'https://www.chick-fil-a.com/menu/breakfast/chick-n-minis', false
) on conflict (id) do nothing;

insert into public.products(
  id, food, name, brand, package_qty_base, package_unit,
  serving_qty_base, serving_unit, serving_label, servings_per_package,
  nutrition_basis_qty, kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g,
  sodium_mg, emoji, aliases, nutrition_source, nutrition_is_estimated,
  estimated_cost, cost_source, cost_as_of, last_used_at, use_count
) values (
  '1702bb0f-746c-420f-8f03-114045ae99dc',
  'd660a4d4-3f6c-4958-a8f5-4ab0a60c9c58',
  'Chick-n-Minis, 4 ct', 'Chick-fil-A', 1,
  (select id from public.measure_conversions where lower(short_name) = 'ct'),
  1, (select id from public.measure_conversions where lower(short_name) = 'ct'),
  '1 4-count order', 1, 1, 360, 20, 41, 13, 2, 8, 1060, '🐔',
  array['4 ct Chick-fil-A Chick-n-Minis'],
  'https://www.chick-fil-a.com/menu/breakfast/chick-n-minis', false,
  5.75, 'Estimated August 2026 Chick-fil-A a-la-carte price; exact receipt unavailable',
  '2026-08-24', '2026-08-24 12:31:00+00', 1
) on conflict (id) do nothing;

update public.food_logs
set product = '1702bb0f-746c-420f-8f03-114045ae99dc',
    components = jsonb_build_array(jsonb_build_object(
      'label', 'Chick-fil-A Chick-n-Minis', 'quantity', 1,
      'portionLabel', '4-count order'))
where id = 'e1487808-d4f7-5639-896f-0fdc0fab0229';

update public.inventory_lots
set product = '1702bb0f-746c-420f-8f03-114045ae99dc'
where id = '2680dfa1-3e75-45c0-aaac-95c4109bcd37';

update public.inventory_lots
set product = 'cb5bc9b0-d129-5038-8618-db0827971aa8'
where product = 'ccb25d14-4406-442f-9e64-457db779d599';
update public.food_logs
set product = 'cb5bc9b0-d129-5038-8618-db0827971aa8'
where product = 'ccb25d14-4406-442f-9e64-457db779d599';
update public.products target
set use_count = target.use_count + duplicate.use_count,
    last_used_at = greatest(target.last_used_at, duplicate.last_used_at),
    updated_at = now()
from public.products duplicate
where target.id = 'cb5bc9b0-d129-5038-8618-db0827971aa8'
  and duplicate.id = 'ccb25d14-4406-442f-9e64-457db779d599';
update public.products
set archived_at = now(), merged_into = 'cb5bc9b0-d129-5038-8618-db0827971aa8', updated_at = now()
where id = 'ccb25d14-4406-442f-9e64-457db779d599' and archived_at is null;
update public.base_foods
set archived_at = now(), merged_into = 'e1d10806-62c2-5e21-ab44-599193296622', updated_at = now()
where id = '04cb56a5-9bf1-40bf-97ae-d02baa4920cd'
  and archived_at is null
  and not exists (
    select 1 from public.products
    where food = '04cb56a5-9bf1-40bf-97ae-d02baa4920cd' and archived_at is null
  );

-- Whole-package consumption must use the printed servings-per-container count,
-- not net weight divided by the rounded serving weight.
update public.products
set servings_per_package = 9,
    serving_unit = (select id from public.measure_conversions where lower(short_name) = 'g'),
    serving_label = '1/3 cup (28 g)',
    cost_as_of = '2026-09-02',
    nutrition_source = 'https://www.generalmillsconvenience.com/products/chex-mix-muddy-buddies-peanut-butter-chocolate-9oz',
    updated_at = now()
where id = '34a6ccde-c5fb-43a6-909e-d3436e0601b1';

update public.food_logs
set servings = 9, kcal = 1170, protein_g = 18, carbs_g = 189,
    fat_g = 40.5, fiber_g = 9, sugar_g = 81, sodium_mg = 495,
    nutrition_source = 'https://www.generalmillsconvenience.com/products/chex-mix-muddy-buddies-peanut-butter-chocolate-9oz',
    note = concat_ws(' ', note, 'Corrected to the label total of 9 servings per 9 oz bag.')
where id = 'fdc18d70-96dd-4ffd-b1e1-72a74ea3c9a0';

update public.products
set servings_per_package = 8,
    serving_unit = (select id from public.measure_conversions where lower(short_name) = 'g'),
    serving_label = '21 crackers (30 g)',
    cost_as_of = '2026-09-02',
    nutrition_source = 'https://www.frysfood.com/p/ritz-drizzled-minis-fudge-crackers/0004400008481',
    updated_at = now()
where id = '20c623d4-6a22-443f-87c2-9ad098cf803b';

update public.food_logs
set servings = 8, kcal = 1120, protein_g = 8, carbs_g = 176,
    fat_g = 48, fiber_g = 8, sugar_g = 88, sodium_mg = 1080,
    nutrition_source = 'https://www.frysfood.com/p/ritz-drizzled-minis-fudge-crackers/0004400008481',
    note = concat_ws(' ', note, 'Corrected to the label total of about 8 servings per 8 oz bag.')
where id = 'ad0892d8-21b3-4d15-aba6-ea56d9a04bde';

-- Retain the research date on current estimates. Historical meal dates belong
-- on lots/logs, not in a product's current-price provenance.
update public.products
set cost_as_of = '2026-09-02', updated_at = now()
where cost_source ilike '%2026-09-02%'
  and cost_as_of is distinct from '2026-09-02'::date;

-- Reconstruct the missing orange-chicken prepared batch. The original dinner
-- was 5 of the label's 6 servings; Friday was the remaining sixth serving.
insert into public.base_foods(
  id, name, plural, measure_style, emoji, display_unit, nutrition_basis_qty,
  kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg,
  aliases, grocery_category, nutrition_source, nutrition_is_estimated
) values (
  'e4c978b7-9a61-47bb-b6a2-18f4db5ca301',
  'InnovAsian Orange Chicken', 'InnovAsian Orange Chicken servings',
  'weight', '🥡',
  (select id from public.measure_conversions where lower(short_name) = 'g'),
  170.097139, 340, 13, 46, 11, 1, 20, 650,
  array['InnovAsian family-size orange chicken'], 'Frozen foods & treats',
  'https://www.instacart.com/products/2757903-innovasian-cuisine-orange-chicken-entree-family-size-36-oz', false
) on conflict (id) do nothing;

insert into public.products(
  id, food, name, brand, package_qty_base, package_unit,
  serving_qty_base, serving_unit, serving_label, servings_per_package,
  nutrition_basis_qty, kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g,
  sodium_mg, emoji, aliases, nutrition_source, nutrition_is_estimated,
  estimated_cost, cost_source, cost_as_of, last_used_at, use_count
) values (
  '9f196ad5-e663-45d4-8633-b87a2e88a4ba',
  'e4c978b7-9a61-47bb-b6a2-18f4db5ca301',
  'Orange Chicken Family Size, 36 oz', 'InnovAsian', 1020.582833,
  (select id from public.measure_conversions where lower(short_name) = 'oz'),
  170.097139, (select id from public.measure_conversions where lower(short_name) = 'oz'),
  '1 cup prepared (1/6 package)', 6, 170.097139,
  340, 13, 46, 11, 1, 20, 650, '🥡',
  array['InnovAsian Cuisine Orange Chicken Entree Family Size 36 oz'],
  'https://www.instacart.com/products/2757903-innovasian-cuisine-orange-chicken-entree-family-size-36-oz', false,
  11.42,
  'Walmart current price via Instacart, researched 2026-09-02: https://www.instacart.com/store/walmart/products/2757903-innovasian-cuisine-orange-chicken-entree-family-size-36-oz',
  '2026-09-02', '2026-08-29 00:00:00+00', 2
) on conflict (id) do nothing;

insert into public.preps(
  id, recipe, label, emoji, scale_factor, actual_yield_qty, prepped_at,
  time_precision, kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g,
  sodium_mg, nutrition_source, nutrition_is_estimated, nutrition_estimate,
  components, note
) values (
  '32f4de5f-3156-4794-a8a3-e91b065afada', null,
  'InnovAsian Orange Chicken leftovers', '🥡', 1, 1,
  '2026-08-24 01:00:00+00', 'estimated',
  340, 13, 46, 11, 1, 20, 650,
  'https://www.instacart.com/products/2757903-innovasian-cuisine-orange-chicken-entree-family-size-36-oz',
  false, null,
  jsonb_build_array(jsonb_build_object(
    'label', 'InnovAsian Orange Chicken', 'quantity', 1,
    'portionLabel', 'remaining 1 of 6 labeled servings')),
  'Remaining labeled serving from the 36 oz package after five servings were eaten on 2026-08-23.'
) on conflict (id) do nothing;

alter table public.inventory_lots disable trigger inventory_lots_protect_cache;
update public.inventory_lots
set product = null,
    prep = '32f4de5f-3156-4794-a8a3-e91b065afada',
    initial_qty = 1,
    remaining_qty = 1,
    total_cost = 1.90,
    out_of_pocket_cost = 1.90,
    paid_by = 'self',
    cost_is_estimated = true,
    cost_source = 'One sixth of the $11.42 current 36 oz package estimate researched 2026-09-02',
    price_as_of = '2026-09-02',
    acquisition_type = 'grocery',
    is_external = false,
    acquired_at = '2026-08-24 01:00:00+00',
    acquired_time_precision = 'estimated',
    location = 'fridge',
    note = 'Reconstructed remaining 1 of 6 labeled servings from the original family-size package.'
where id = 'e7c29900-d5b8-5cc3-a776-f95ea124e9e7';
alter table public.inventory_lots enable trigger inventory_lots_protect_cache;

update public.food_logs
set kind = 'inventory',
    product = '9f196ad5-e663-45d4-8633-b87a2e88a4ba',
    servings = 5,
    components = jsonb_build_array(jsonb_build_object(
      'label', 'InnovAsian Orange Chicken', 'quantity', 5,
      'portionLabel', '5 of 6 labeled servings')),
    acquisition_type = 'grocery',
    total_price = 9.52,
    out_of_pocket_cost = 9.52,
    paid_by = 'self',
    cost = 9.52,
    cost_is_estimated = true,
    cost_source = 'Five sixths of the $11.42 current Walmart price via Instacart, researched 2026-09-02',
    price_as_of = '2026-09-02'
where id = 'fb3bd895-40d1-5d11-b580-56f0e81eef8b';

update public.food_logs
set kind = 'prepared',
    recipe = null,
    product = null,
    servings = 1,
    kcal = 340, protein_g = 13, carbs_g = 46, fat_g = 11,
    fiber_g = 1, sugar_g = 20, sodium_mg = 650,
    nutrition_is_estimated = false,
    nutrition_source = 'https://www.instacart.com/products/2757903-innovasian-cuisine-orange-chicken-entree-family-size-36-oz',
    nutrition_estimate = null,
    components = jsonb_build_array(jsonb_build_object(
      'label', 'InnovAsian Orange Chicken', 'quantity', 1,
      'portionLabel', 'remaining 1 of 6 labeled servings')),
    acquisition_type = 'grocery',
    total_price = 1.90,
    out_of_pocket_cost = 1.90,
    paid_by = 'self',
    cost = 1.90,
    cost_is_estimated = true,
    cost_source = 'One sixth of the $11.42 current Walmart price via Instacart, researched 2026-09-02',
    price_as_of = '2026-09-02',
    time_precision = 'estimated',
    note = 'Remaining 1 of 6 labeled servings from the InnovAsian 36 oz package; restored to the prepared-food ledger and deducted on Friday.'
where id = 'c58f8c67-f81e-4f7d-a130-3d8f1e8d78c6';

insert into public.inventory_events(
  id, lot, quantity_delta, reason, food_log, occurred_at, note
) values (
  'aaf3bcab-0c18-46c6-8b74-ea31e1c660b2',
  'e7c29900-d5b8-5cc3-a776-f95ea124e9e7', -1, 'eaten',
  'c58f8c67-f81e-4f7d-a130-3d8f1e8d78c6',
  '2026-08-29 00:00:00+00',
  'Audited reconstruction of the missing leftover deduction.'
) on conflict (id) do nothing;

update public.products
set archived_at = now(), merged_into = '9f196ad5-e663-45d4-8633-b87a2e88a4ba', updated_at = now()
where id = 'aca348fd-3756-566a-a700-f1dde077ffbd' and archived_at is null;
update public.base_foods
set archived_at = now(), merged_into = 'e4c978b7-9a61-47bb-b6a2-18f4db5ca301', updated_at = now()
where id = 'adb75b5a-65f9-55e8-9bd2-1f1236699276' and archived_at is null;

-- The 4.5 fl oz Baileys entry was manually logged even though the imported
-- bottle lot still existed. Attach the missing ledger deduction and retain the
-- correctly prorated bottle cost in history.
update public.food_logs
set kind = 'inventory',
    product = '14d3b3cf-b5f1-51ad-94fa-b691ee4058e6',
    servings = public.product_servings_for_quantity('14d3b3cf-b5f1-51ad-94fa-b691ee4058e6', 4.5),
    components = jsonb_build_array(jsonb_build_object(
      'label', 'Baileys Original Irish Cream', 'quantity', 4.5, 'unit', 'fl oz')),
    nutrition_estimate = jsonb_build_object(
      'confidence', 'medium',
      'rationale', 'Nutrition uses the official product basis; the user estimated the pour as about 4.5 fl oz.'),
    acquisition_type = null, total_price = null, out_of_pocket_cost = null,
    paid_by = null, price_as_of = null, cost = null,
    cost_is_estimated = false, cost_source = null
where id = 'd671891e-9f16-4e1a-a080-60d6c6323e2e';

insert into public.inventory_events(
  id, lot, quantity_delta, reason, food_log, occurred_at, note
) values (
  '3c495147-eb02-4d90-a1ef-497db3027b2f',
  'e79cd9a4-31d6-5276-8fbf-fd3680b3cf5e', -4.5, 'eaten',
  'd671891e-9f16-4e1a-a080-60d6c6323e2e',
  '2026-09-01 23:56:00+00', 'Restored missing deduction from the existing Baileys bottle lot.'
) on conflict (id) do nothing;

update public.inventory_lots
set acquired_time_precision = 'estimated',
    note = concat_ws(' ', note, 'The timestamp is the imported inventory-snapshot time, not a known purchase time.')
where id = 'e79cd9a4-31d6-5276-8fbf-fd3680b3cf5e';

-- A prior product-purchase call supplied ounce amounts to an undocumented base-
-- quantity parameter. It multiplied 23.42 oz and 28.35 oz by the nominal 23 oz
-- package again, creating impossible 33.7 lb and 40.8 lb freezer lots. Recover
-- the original ounce inputs and price them with a current Safeway reference.
update public.products
set nutrition_basis_qty = null,
    kcal = null, protein_g = null, carbs_g = null, fat_g = null,
    fiber_g = null, sugar_g = null, sodium_mg = null,
    nutrition_source = null,
    estimated_cost = 10.05,
    cost_source = 'Nominal 23 oz package at Safeway''s $6.99/lb reference, researched 2026-09-02: https://www.safeway.com/meal-plans-recipes/shop/orange-glazed-pork-tenderloin-t0dG',
    cost_as_of = '2026-09-02',
    updated_at = now()
where id = 'd013627b-eaac-4a8c-a86e-eb16463c0cd4';

alter table public.inventory_lots disable trigger inventory_lots_protect_cache;
update public.inventory_lots
set initial_qty = case id
      when '4ef6bbe9-cd88-453f-8af4-6ff57b46227e' then 663.922412416223
      else 803.695422126169 end,
    remaining_qty = case id
      when '4ef6bbe9-cd88-453f-8af4-6ff57b46227e' then 663.922412416223
      else 803.695422126169 end,
    total_cost = case id
      when '4ef6bbe9-cd88-453f-8af4-6ff57b46227e' then 10.23
      else 12.39 end,
    out_of_pocket_cost = case id
      when '4ef6bbe9-cd88-453f-8af4-6ff57b46227e' then 10.23
      else 12.39 end,
    paid_by = 'self',
    cost_is_estimated = true,
    cost_source = 'Recovered original ounce amount; estimated at Safeway''s $6.99/lb reference researched 2026-09-02: https://www.safeway.com/meal-plans-recipes/shop/orange-glazed-pork-tenderloin-t0dG',
    price_as_of = '2026-09-02',
    acquired_time_precision = 'estimated',
    note = case id
      when '4ef6bbe9-cd88-453f-8af4-6ff57b46227e'
        then 'Corrected unit-conversion error: original 23.419 oz input restored as 663.922 g, not 23.419 whole packages.'
      else 'Corrected unit-conversion error: original 28.350 oz input restored as 803.695 g, not 28.350 whole packages.' end
where id in (
  '4ef6bbe9-cd88-453f-8af4-6ff57b46227e',
  '56820e85-ce95-4375-a8d4-84b696dcd8cf'
);
alter table public.inventory_lots enable trigger inventory_lots_protect_cache;

-- Correct payment/acquisition semantics and retain estimated full value even
-- when somebody else paid.
update public.inventory_lots
set acquisition_type = 'office', is_external = false,
    total_cost = 0, out_of_pocket_cost = 0, paid_by = 'employer',
    cost_is_estimated = false, cost_source = 'Free from the office',
    price_as_of = null, acquired_time_precision = 'dateOnly'
where acquisition_food_log in (
  '23d52d45-b044-4d88-b160-360af2e16425',
  '512e8bc6-7c0a-43eb-920b-72c05309573f',
  '7f7eef33-0276-4bc9-ae4d-724208061d98'
);

update public.inventory_lots
set acquisition_type = 'gift', is_external = false,
    total_cost = 12, out_of_pocket_cost = 0, paid_by = 'friend',
    cost_is_estimated = true,
    cost_source = 'Comparable 2026 bakery-slice value estimate; homemade ingredient cost unavailable',
    price_as_of = '2026-09-02', acquired_time_precision = 'estimated'
where id = '001bf7a0-64dc-46d8-a446-137fea804666';

update public.food_logs
set acquisition_type = 'home', total_price = 4.25, out_of_pocket_cost = 0,
    paid_by = 'parents', price_as_of = '2026-09-02', cost = 0,
    cost_is_estimated = true,
    cost_source = 'Estimated ingredient value using typical 2026 grocery prices; meal provided at user''s mother''s home',
    components = jsonb_build_array(
      jsonb_build_object('label', 'cooked spaghetti', 'quantity', 0.875, 'unit', 'cup'),
      jsonb_build_object('label', 'butter', 'quantity', 0.5, 'unit', 'tbsp'),
      jsonb_build_object('label', 'tomato sauce', 'quantity', 0.125, 'unit', 'cup'),
      jsonb_build_object('label', 'large beef Italian-style meatball', 'quantity', 3, 'unit', 'count')
    )
where id = '5b4119a7-5070-4c6b-b99b-9debf5d71b76';

update public.food_logs
set acquisition_type = 'home', total_price = 0.75, out_of_pocket_cost = 0,
    paid_by = 'parents', price_as_of = '2026-09-02', cost = 0,
    cost_is_estimated = true,
    cost_source = 'Estimated ingredient value using typical 2026 grocery prices; food provided at user''s mother''s home',
    components = jsonb_build_array(
      jsonb_build_object('label', 'plain English muffin', 'quantity', 1, 'unit', 'count'),
      jsonb_build_object('label', 'peanut butter', 'quantity', 1, 'unit', 'tbsp'),
      jsonb_build_object('label', 'jelly', 'quantity', 1, 'unit', 'tbsp')
    )
where id = '857db559-c72c-4f15-b6b3-944a45f22140';

update public.food_logs
set acquisition_type = 'takeout', paid_by = 'self',
    components = jsonb_build_array(
      jsonb_build_object('label', 'Panda Express Orange Chicken entree', 'quantity', 2, 'unit', 'serving'),
      jsonb_build_object('label', 'Panda Express Chow Mein side', 'quantity', 0.5, 'unit', 'serving')
    ),
    nutrition_estimate = jsonb_build_object(
      'confidence', 'medium',
      'rationale', 'Published standard-serving nutrition was used; the Chow Mein portion was visually estimated as one half serving.')
where id = '5a034b78-e817-4e0d-ad90-5a78f4a49745';

-- Annapolis Yacht Club does not publish its member menu. Keep these explicitly
-- marked as estimates from comparable current Annapolis menus, while preserving
-- the user's actual $0 out-of-pocket amount and parents as payer.
update public.food_logs
set total_price = 14, out_of_pocket_cost = 0, paid_by = 'parents',
    price_as_of = '2026-09-02', cost = 0, cost_is_estimated = true,
    cost_source = 'Comparable Annapolis cocktail/spirit price researched 2026-09-02; exact private-club menu unavailable',
    components = jsonb_build_array(jsonb_build_object(
      'label', 'Baileys Original Irish Cream', 'quantity', 3, 'unit', 'fl oz'))
where id = '054db162-4c8d-42a5-8c8f-98a8db06780d';

update public.food_logs
set total_price = 0, out_of_pocket_cost = 0, paid_by = 'parents',
    price_as_of = '2026-09-02', cost = 0, cost_is_estimated = false,
    cost_source = 'Included bread basket; parents covered the Annapolis Yacht Club outing',
    components = jsonb_build_array(
      jsonb_build_object('label', 'small pretzel bun', 'quantity', 1, 'unit', 'count'),
      jsonb_build_object('label', 'small sweet white bread bun', 'quantity', 2, 'unit', 'count')
    )
where id = '4a150fe2-e254-4f45-b89a-d6da7316d340';

update public.food_logs
set total_price = 17.25, out_of_pocket_cost = 0, paid_by = 'parents',
    price_as_of = '2026-09-02', cost = 0, cost_is_estimated = true,
    cost_source = 'Comparable Annapolis 8 oz Burger Burger price ($17.25), researched 2026-09-02: https://static1.squarespace.com/static/5fc45ccdb8467722f1ea3fce/t/68e65eec6cd8591df37230a7/1759928044403/Annapolis%2BMenu%2BFall%2B2025%2B2026.pdf',
    components = jsonb_build_array(
      jsonb_build_object('label', 'beef patty', 'quantity', 8, 'unit', 'oz'),
      jsonb_build_object('label', 'plain hamburger bun', 'quantity', 1, 'unit', 'count'),
      jsonb_build_object('label', 'cheese slice', 'quantity', 1, 'unit', 'count')
    )
where id = '51048f0f-2090-4d21-a8db-12b392c0eb2f';

update public.food_logs
set total_price = 28, out_of_pocket_cost = 0, paid_by = 'parents',
    price_as_of = '2026-09-02', cost = 0, cost_is_estimated = true,
    cost_source = 'Estimated at $14 each from comparable current Annapolis cocktail pricing; exact private-club menu unavailable',
    components = jsonb_build_array(jsonb_build_object(
      'label', 'standard chocolate martini', 'quantity', 2, 'unit', 'cocktail'))
where id = '54b51a48-5d4f-46e3-8e3d-0e67525c9ae7';

update public.food_logs
set total_price = 15, out_of_pocket_cost = 0, paid_by = 'parents',
    price_as_of = '2026-09-02', cost = 0, cost_is_estimated = true,
    cost_source = 'Comparable Annapolis dessert estimate: $9 chocolate dessert plus $6 gelato, researched 2026-09-02: https://annapolismarkethouse.com/',
    components = jsonb_build_array(
      jsonb_build_object('label', 'deep-dish chocolate-chip cookie', 'quantity', 1, 'portionLabel', 'approximately 6 inches'),
      jsonb_build_object('label', 'vanilla ice cream', 'quantity', 1, 'unit', 'scoop')
    )
where id = '59de0902-5aff-4fd9-8f53-6c51ec223be1';

-- Every estimated manual nutrition snapshot now carries structured confidence
-- metadata. Every manual entry now has meaningful component decomposition.
update public.food_logs
set nutrition_estimate = jsonb_build_object(
  'confidence', case
    when acquisition_type = 'restaurant' then 'low'
    when label ilike '%Panda Express%' then 'medium'
    else 'medium'
  end,
  'rationale', coalesce(nullif(note, ''), 'Historical nutrition estimate; exact recipe or portion was unavailable.')
)
where voided_at is null
  and kind = 'manual'
  and nutrition_is_estimated
  and nutrition_estimate is null;

update public.food_logs
set components = jsonb_build_array(jsonb_build_object(
  'label', label,
  'portionLabel', coalesce(nullif(portion_label, ''), 'reported portion')
))
where voided_at is null
  and kind = 'manual'
  and jsonb_array_length(components) = 0;

-- Precision is metadata, not formatting. Convert explicit sorting anchors to
-- dateOnly and other stated/backfilled approximations to estimated.
update public.food_logs
set time_precision = case
  when lower(coalesce(note, '')) like '%exact time unknown%noon%'
    then 'dateOnly'
  else 'estimated'
end
where voided_at is null
  and time_precision = 'exact'
  and (
    lower(coalesce(note, '')) like '%exact time unknown%'
    or lower(coalesce(note, '')) like '%time estimated%'
    or lower(coalesce(note, '')) like '%time and cost estimated%'
    or lower(coalesce(note, '')) like '%time estimated from%'
    or created_at - occurred_at > interval '24 hours'
  );

update public.inventory_lots lot
set acquired_time_precision = log.time_precision
from public.food_logs log
where lot.acquisition_food_log = log.id
  and lot.acquired_time_precision is distinct from log.time_precision;

-- Enforce the invariants that the old interface could only express in prose.
alter table public.food_logs add constraint food_logs_manual_components_required check (
  kind <> 'manual' or jsonb_array_length(components) > 0
) not valid;
alter table public.food_logs validate constraint food_logs_manual_components_required;

alter table public.food_logs add constraint food_logs_manual_provenance_required check (
  kind <> 'manual' or (
    acquisition_type is not null
    and out_of_pocket_cost is not null
    and nullif(trim(paid_by), '') is not null
    and nullif(trim(cost_source), '') is not null
    and (total_price is null or price_as_of is not null)
  )
) not valid;
alter table public.food_logs validate constraint food_logs_manual_provenance_required;

alter table public.food_logs add constraint food_logs_manual_estimate_metadata_required check (
  kind <> 'manual' or not nutrition_is_estimated or nutrition_estimate is not null
) not valid;
alter table public.food_logs validate constraint food_logs_manual_estimate_metadata_required;

drop index if exists public.products_active_normalized_identity_idx;
create unique index products_active_normalized_identity_idx
  on public.products (
    lower(regexp_replace(coalesce(brand, ''), '[^a-zA-Z0-9]+', '', 'g')),
    lower(regexp_replace(name, '[^a-zA-Z0-9]+', '', 'g')),
    package_qty_base
  )
  where archived_at is null;

-- A zero-row result is the operational definition of a clean history audit.
-- This makes future regressions visible without relying on prose-note review.
create or replace view public.history_quality_issues
with (security_invoker = true)
as
with active_logs as (
  select * from public.food_logs where voided_at is null
), duplicate_logs as (
  select id,
    row_number() over (
      partition by lower(label), kind, coalesce(product, '00000000-0000-0000-0000-000000000000'::uuid),
        date_trunc('second', occurred_at), kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg
      order by created_at, id
    ) as copy_number
  from active_logs
)
select 'duplicate_active_consumption'::text as issue_type, log.id as record_id,
  jsonb_build_object('label', log.label, 'occurredAt', log.occurred_at) as details
from active_logs log join duplicate_logs duplicate on duplicate.id = log.id
where duplicate.copy_number > 1
union all
select 'manual_components_missing', log.id,
  jsonb_build_object('label', log.label)
from active_logs log
where log.kind = 'manual' and jsonb_array_length(log.components) = 0
union all
select 'manual_estimate_metadata_missing', log.id,
  jsonb_build_object('label', log.label)
from active_logs log
where log.kind = 'manual' and log.nutrition_is_estimated and log.nutrition_estimate is null
union all
select 'manual_provenance_missing', log.id,
  jsonb_build_object('label', log.label)
from active_logs log
where log.kind = 'manual' and (
  log.acquisition_type is null or log.out_of_pocket_cost is null
  or nullif(trim(log.paid_by), '') is null or nullif(trim(log.cost_source), '') is null
  or (log.total_price is not null and log.price_as_of is null)
)
union all
select 'time_precision_contradicts_note', log.id,
  jsonb_build_object('label', log.label, 'timePrecision', log.time_precision, 'note', log.note)
from active_logs log
where log.time_precision = 'exact' and (
  lower(coalesce(log.note, '')) like '%exact time unknown%'
  or lower(coalesce(log.note, '')) like '%time estimated%'
  or lower(coalesce(log.note, '')) like '%time and cost estimated%'
)
union all
select 'purchased_lot_price_missing', lot.id,
  jsonb_build_object('acquisitionType', lot.acquisition_type, 'costSource', lot.cost_source)
from public.inventory_lots lot
where lot.acquisition_type in ('grocery', 'restaurant', 'takeout')
  and (lot.total_cost is null or lot.price_as_of is null or nullif(trim(lot.paid_by), '') is null);

revoke all on public.history_quality_issues from public, anon;
grant select on public.history_quality_issues to authenticated, service_role;

-- Store before/after snapshots only for rows this migration actually changed.
insert into public.record_edits(resource, record_id, before_state, after_state)
select before.resource, before.record_id, before.before_state,
       current.after_state || jsonb_build_object('auditRepairReason', before.repair_reason)
from history_repair_before before
join (
  select 'food'::text resource, id record_id, to_jsonb(food) after_state from public.base_foods food
  union all
  select 'product', id, to_jsonb(product) from public.products product
  union all
  select 'prep', id, to_jsonb(prep) from public.preps prep
  union all
  select 'inventory_lot', id, to_jsonb(lot) from public.inventory_lots lot
  union all
  select 'consumption', id, to_jsonb(log) from public.food_logs log
) current using (resource, record_id)
where before.before_state is distinct from current.after_state;
