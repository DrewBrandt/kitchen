begin;

create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select plan(21);

select is(
  (select count(*) from history_quality_issues),
  0::bigint,
  'The operational history-quality audit is clean'
);

select is(
  (select count(*) from food_logs where label = 'Half glass of Chocolate Milk' and voided_at is null),
  1::bigint,
  'Only one active half-glass chocolate-milk event remains'
);

select is(
  (select count(*) from food_logs where id in ('05ab2dff-17dd-5341-bea2-0267034c4951','c696e1ef-b822-5b59-bd10-4a147ec28cbf') and voided_at is not null),
  2::bigint,
  'The two legacy retry duplicates are auditably voided'
);

select is(
  (select product from food_logs where id = 'e1487808-d4f7-5639-896f-0fdc0fab0229'),
  '1702bb0f-746c-420f-8f03-114045ae99dc'::uuid,
  'The Chick-n-Minis event references a Chick-n-Minis product'
);

select is(
  (select product from food_logs where id = 'efa44b47-0292-419d-9467-2d9bb1bc1671'),
  'cb5bc9b0-d129-5038-8618-db0827971aa8'::uuid,
  'Chicken Biscuit history references the retained product'
);

select ok(
  (select archived_at is not null and merged_into = 'cb5bc9b0-d129-5038-8618-db0827971aa8' from products where id = 'ccb25d14-4406-442f-9e64-457db779d599'),
  'The duplicate Chicken Biscuit product is archived with a merge target'
);

select ok(
  (select estimated_cost = 4.29 and cost_source is not null and cost_as_of is not null
   from products where id = '4507778e-e63a-498e-a36c-cd2ef4e51d65'),
  'The Fairlife chocolate protein shake has a sourced package-price estimate'
);

select is(
  (select concat(servings, '/', kcal) from food_logs where id = 'fdc18d70-96dd-4ffd-b1e1-72a74ea3c9a0'),
  '9/1170',
  'Muddy Buddies uses the printed nine-serving package total'
);

select is(
  (select concat(servings, '/', kcal) from food_logs where id = 'ad0892d8-21b3-4d15-aba6-ea56d9a04bde'),
  '8/1120',
  'Ritz Drizzled Minis uses the printed eight-serving package total'
);

select ok(
  (select kind = 'prepared' and servings = 1 and kcal = 340 and not nutrition_is_estimated from food_logs where id = 'c58f8c67-f81e-4f7d-a130-3d8f1e8d78c6'),
  'Friday orange-chicken leftovers retain exact label nutrition as prepared food'
);

select ok(
  (select prep is not null and remaining_qty = 0 from inventory_lots where id = 'e7c29900-d5b8-5cc3-a776-f95ea124e9e7'),
  'The reconstructed orange-chicken batch is depleted'
);

select is(
  (select count(*) from inventory_events where lot = 'e7c29900-d5b8-5cc3-a776-f95ea124e9e7' and food_log = 'c58f8c67-f81e-4f7d-a130-3d8f1e8d78c6' and quantity_delta = -1),
  1::bigint,
  'Friday orange chicken has one ledger deduction'
);

select ok(
  (select count(*) = 5 and bool_and(total_price is not null and out_of_pocket_cost = 0 and paid_by = 'parents' and price_as_of = '2026-09-02' and time_precision = 'estimated' and jsonb_array_length(components) > 0 and nutrition_estimate is not null)
   from food_logs where voided_at is null and label ilike '%Annapolis Yacht Club%'),
  'All five Yacht Club entries separate full value from parents-paid out-of-pocket cost'
);

select ok(
  (select count(*) = 3 and bool_and(acquisition_type = 'office' and paid_by = 'employer' and out_of_pocket_cost = 0 and acquired_time_precision = 'dateOnly')
   from inventory_lots where acquisition_food_log in ('23d52d45-b044-4d88-b160-360af2e16425','512e8bc6-7c0a-43eb-920b-72c05309573f','7f7eef33-0276-4bc9-ae4d-724208061d98')),
  'The Wednesday-through-Friday office lollipops are free office acquisitions'
);

select ok(
  (select bool_and(jsonb_array_length(components) > 0 and acquisition_type is not null and out_of_pocket_cost is not null and nullif(trim(paid_by), '') is not null and nullif(trim(cost_source), '') is not null and (not nutrition_is_estimated or nutrition_estimate is not null))
   from food_logs where voided_at is null and kind = 'manual'),
  'Every active manual log has components, payment provenance, and estimate metadata'
);

select ok(
  (select count(*) = 2
     and bool_and(remaining_qty between 663 and 804)
     and bool_and(total_cost is not null and out_of_pocket_cost = total_cost)
   from inventory_lots where id in ('4ef6bbe9-cd88-453f-8af4-6ff57b46227e','56820e85-ce95-4375-a8d4-84b696dcd8cf')),
  'The pork-tenderloin lots contain recovered ounce amounts, not dozens of packages'
);

select is(
  (select count(*) from inventory_events where lot = 'e79cd9a4-31d6-5276-8fbf-fd3680b3cf5e' and food_log = 'd671891e-9f16-4e1a-a080-60d6c6323e2e' and quantity_delta = -4.5),
  1::bigint,
  'The Baileys consumed while cooking now deducts the existing bottle lot'
);

select is(
  (select remaining_qty from inventory_lots where id = '8bd01078-77db-4d28-b3f9-d87daab08a09'),
  0::numeric,
  'The broccoli lot is exactly depleted rather than retaining conversion residue'
);

select is(
  (select count(*) from inventory_events where lot = '8bd01078-77db-4d28-b3f9-d87daab08a09' and note = 'Automatically cleared unit-conversion residue'),
  1::bigint,
  'The broccoli residue repair remains explicit in the inventory ledger'
);

select ok(
  (select indisunique from pg_index where indexrelid = 'products_active_normalized_identity_idx'::regclass),
  'Active normalized product identity is protected by a unique index'
);

select ok(
  (select count(*) > 10 from record_edits where after_state ? 'auditRepairReason'),
  'The historical repairs retain before-and-after audit snapshots'
);

select * from finish();
rollback;
