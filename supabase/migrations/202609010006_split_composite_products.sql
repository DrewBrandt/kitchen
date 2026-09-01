-- Keep the original imported log when a composite entry is replaced by its
-- individual foods. The mapping is an audit trail and prevents the obsolete
-- aggregate from being restored on top of the replacements.
create table public.food_log_replacements (
  original_log uuid not null references public.food_logs(id),
  replacement_log uuid not null references public.food_logs(id),
  created_at timestamptz not null default now(),
  primary key (original_log, replacement_log),
  check (original_log <> replacement_log)
);

create index food_log_replacements_replacement_idx
  on public.food_log_replacements(replacement_log);

alter table public.food_log_replacements enable row level security;
create policy authenticated_read_access
  on public.food_log_replacements for select to authenticated
  using (true);
grant select on public.food_log_replacements to authenticated;

create or replace function public.restore_food_log(p_food_log uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  log_row public.food_logs%rowtype;
begin
  if not public.is_app_owner() then
    raise exception 'Only the app owner may restore food logs' using errcode = '42501';
  end if;

  select * into log_row from public.food_logs where id = p_food_log for update;
  if not found then raise exception 'Food log entry does not exist'; end if;
  if log_row.voided_at is null then return; end if;
  if exists (
    select 1
    from public.food_log_replacements replacement
    where replacement.original_log = p_food_log
  ) then
    raise exception 'This food log was split into individual items and cannot be restored';
  end if;

  update public.food_logs set voided_at = null where id = p_food_log;

  update public.inventory_events
  set voided_at = null
  where food_log = p_food_log
    and voided_at is not null;
end;
$$;

do $$
declare
  count_unit uuid;
  gram_unit uuid;
  source_log public.food_logs%rowtype;
  saved_event public.inventory_events%rowtype;
  split_at timestamptz := clock_timestamp();
begin
  select id into count_unit
  from public.measure_conversions
  where lower(short_name) = 'ct';

  select id into gram_unit
  from public.measure_conversions
  where lower(short_name) = 'g';

  if count_unit is null or gram_unit is null then
    raise exception 'Count and gram units are required for the composite-product repair';
  end if;

  -- The original breakfast import was already replaced by four item-level logs.
  -- The previous migration nevertheless created a product, lot, and live event
  -- for the voided aggregate. Preserve the voided log and its replacement map,
  -- while removing only that erroneous migrated ledger data.
  if exists (
    select 1 from public.products
    where id = 'ce6baa56-2ea6-42b0-8231-af3da2afad67'
  ) then
    select * into source_log
    from public.food_logs
    where id = '74436821-9ee2-51a1-96bb-d0bf14829ff6'
    for update;

    if source_log.id is null
      or source_log.product <> 'ce6baa56-2ea6-42b0-8231-af3da2afad67'
      or source_log.voided_at is null then
      raise exception 'The composite breakfast log does not match the expected voided import';
    end if;

    if (
      select count(*)
      from public.food_logs
      where id in (
        'e1b4f038-49b8-5555-9f1a-b071604726e7',
        'e1487808-d4f7-5639-896f-0fdc0fab0229',
        'dd2e8725-8fa2-5c2a-9cb6-07cb6a773c31',
        '75ab937d-fbfe-56ad-ad35-884cb7ed9583'
      )
        and voided_at is null
    ) <> 4 then
      raise exception 'The four item-level breakfast replacements are incomplete';
    end if;

    insert into public.food_log_replacements(original_log, replacement_log)
    select source_log.id, replacement.id
    from public.food_logs replacement
    where replacement.id in (
      'e1b4f038-49b8-5555-9f1a-b071604726e7',
      'e1487808-d4f7-5639-896f-0fdc0fab0229',
      'dd2e8725-8fa2-5c2a-9cb6-07cb6a773c31',
      '75ab937d-fbfe-56ad-ad35-884cb7ed9583'
    );

    update public.food_logs
    set product = null
    where id = source_log.id;

    delete from public.inventory_events
    where lot in (
      select id from public.inventory_lots
      where product = 'ce6baa56-2ea6-42b0-8231-af3da2afad67'
    );
    delete from public.inventory_lots
    where product = 'ce6baa56-2ea6-42b0-8231-af3da2afad67';
    delete from public.products
    where id = 'ce6baa56-2ea6-42b0-8231-af3da2afad67';
    delete from public.base_foods
    where id = 'f87011a6-d58e-40d2-b54a-8dca22f1b6b4';
  end if;

  -- Repoint the breakfast drink history from the early one-count placeholders
  -- to the later exact bottle/can definitions. Quantities are rescaled into the
  -- destination foods' fluid-ounce base units before the placeholders go away.
  if exists (
    select 1 from public.products
    where id = 'c48acc5a-7fec-51e0-af87-d92dce378f7c'
  ) then
    select * into saved_event
    from public.inventory_events
    where id = '1fb075e9-96cc-4e8c-bf06-7b59ef06cde9'
      and lot = '45556644-7a05-4499-bc8d-406f35da2b9e'
    for update;
    if saved_event.id is null or saved_event.quantity_delta <> -1 then
      raise exception 'The legacy Core Power deduction does not match the expected quantity';
    end if;

    delete from public.inventory_events where id = saved_event.id;
    update public.inventory_lots
    set product = '4507778e-e63a-498e-a36c-cd2ef4e51d65',
        initial_qty = 14
    where id = saved_event.lot;
    saved_event.quantity_delta := -14;
    insert into public.inventory_events(
      id, lot, quantity_delta, reason, prep, cook_session, occurred_at,
      voided_at, note, created_at, food_log
    ) values (
      saved_event.id, saved_event.lot, saved_event.quantity_delta,
      saved_event.reason, saved_event.prep, saved_event.cook_session,
      saved_event.occurred_at, saved_event.voided_at, saved_event.note,
      saved_event.created_at, saved_event.food_log
    );
    update public.food_logs
    set product = '4507778e-e63a-498e-a36c-cd2ef4e51d65'
    where product = 'c48acc5a-7fec-51e0-af87-d92dce378f7c';
    delete from public.products where id = 'c48acc5a-7fec-51e0-af87-d92dce378f7c';
    delete from public.base_foods where id = '3ad7b157-dbc8-5c0b-8a9a-6d1c5e9ba19a';
  end if;

  if exists (
    select 1 from public.products
    where id = '87d0a782-7826-5c99-b158-b437e8faee2c'
  ) then
    select * into saved_event
    from public.inventory_events
    where id = 'c44b29c0-9d92-41a8-976b-882597c10063'
      and lot = 'e4967831-a78e-4dcc-87e2-f099e8031d93'
    for update;
    if saved_event.id is null or saved_event.quantity_delta <> -1 then
      raise exception 'The legacy CELSIUS deduction does not match the expected quantity';
    end if;

    delete from public.inventory_events where id = saved_event.id;
    update public.inventory_lots
    set product = '4f000cdb-1841-43fe-a181-4233e21c8b0e',
        initial_qty = 12
    where id = saved_event.lot;
    saved_event.quantity_delta := -12;
    insert into public.inventory_events(
      id, lot, quantity_delta, reason, prep, cook_session, occurred_at,
      voided_at, note, created_at, food_log
    ) values (
      saved_event.id, saved_event.lot, saved_event.quantity_delta,
      saved_event.reason, saved_event.prep, saved_event.cook_session,
      saved_event.occurred_at, saved_event.voided_at, saved_event.note,
      saved_event.created_at, saved_event.food_log
    );
    update public.food_logs
    set product = '4f000cdb-1841-43fe-a181-4233e21c8b0e'
    where product = '87d0a782-7826-5c99-b158-b437e8faee2c';
    delete from public.products where id = '87d0a782-7826-5c99-b158-b437e8faee2c';
    delete from public.base_foods where id = 'b7a46ee7-68b8-5722-a55e-fbff4bd366ae';
  end if;

  -- Split the English-muffin PB&J into three reusable product definitions and
  -- three consumption records. The apportioned nutrients add back to the exact
  -- original totals (280 kcal, 8.4 g protein, 42 g carbs, and so on).
  select * into source_log
  from public.food_logs
  where id = '857db559-c72c-4f15-b6b3-944a45f22140'
  for update;

  if source_log.id is not null and source_log.voided_at is null then
    if source_log.product <> 'c9b6f09e-4c79-4958-8df4-69aba1d723bf'
      or source_log.kcal <> 280
      or source_log.protein_g <> 8.4
      or source_log.carbs_g <> 42
      or source_log.fat_g <> 9
      or source_log.fiber_g <> 2.5
      or source_log.sugar_g <> 13
      or source_log.sodium_mg <> 350 then
      raise exception 'The English muffin PB&J log does not match the expected source totals';
    end if;

    insert into public.base_foods(
      id, name, plural, measure_style, emoji, display_unit,
      nutrition_basis_qty, kcal, protein_g, carbs_g, fat_g, fiber_g,
      sugar_g, sodium_mg, aliases, nutrition_source,
      nutrition_is_estimated
    ) values
      (
        '50c8c697-cf46-4974-8dc8-df751c88a687',
        'Plain English muffin', 'Plain English muffins', 'discrete', '🫓',
        count_unit, 1, 140, 4.9, 25.5, 1.5, 1.5, 1.5, 277.5,
        array['English muffin'],
        'USDA FoodData Central generic estimate, apportioned to preserve the original meal total',
        true
      ),
      (
        'f59dc524-9c7b-4198-9aac-454deaff2379',
        'Fruit jelly', 'Fruit jelly', 'weight', '🍇', gram_unit,
        20, 50, 0, 13, 0, 0, 10, 10,
        array['Jelly', 'Grape jelly'],
        'USDA FoodData Central generic estimate, apportioned to preserve the original meal total',
        true
      );

    insert into public.products(
      id, food, name, brand, aliases, package_qty_base, package_unit,
      serving_qty_base, nutrition_basis_qty, kcal, protein_g, carbs_g,
      fat_g, fiber_g, sugar_g, sodium_mg, emoji, nutrition_source,
      nutrition_is_estimated, last_used_at, use_count
    ) values
      (
        '36ffaa99-b970-4fe9-b874-a188dd3332fd',
        '50c8c697-cf46-4974-8dc8-df751c88a687',
        'Plain English muffin (brand not recorded)', null,
        array['English muffin'], 1, count_unit, 1, 1,
        140, 4.9, 25.5, 1.5, 1.5, 1.5, 277.5, '🫓',
        'USDA FoodData Central generic estimate, apportioned to preserve the original meal total',
        true, source_log.occurred_at, 1
      ),
      (
        '9efd38d2-258b-471a-9a7a-aff3c782e3e7',
        '8da3ce8c-ea4b-5ead-8712-611ec56ad818',
        'Creamy peanut butter (brand not recorded)', null,
        array['Peanut butter'], 454, gram_unit, 16, 16,
        90, 3.5, 3.5, 7.5, 1, 1.5, 62.5, '🥜',
        'Good & Gather label-equivalent estimate for the reported one-tablespoon portion',
        true, source_log.occurred_at, 1
      ),
      (
        '41794c8d-bd81-4710-abf8-195fbdb97b82',
        'f59dc524-9c7b-4198-9aac-454deaff2379',
        'Fruit jelly (brand not recorded)', null,
        array['Jelly', 'Grape jelly'], 510, gram_unit, 20, 20,
        50, 0, 13, 0, 0, 10, 10, '🍇',
        'USDA FoodData Central generic estimate, apportioned to preserve the original meal total',
        true, source_log.occurred_at, 1
      );

    insert into public.inventory_lots(
      id, product, initial_qty, total_cost, cost_is_estimated, cost_source,
      acquired_at, is_external, note, created_at
    ) values
      (
        '7660e959-d202-48a9-a7c1-aa39d1791f3c',
        '36ffaa99-b970-4fe9-b874-a188dd3332fd', 1, 0, false,
        'Provided at user''s mother''s house; no cost to user',
        source_log.occurred_at, true, 'Split from English muffin PB&J composite',
        source_log.created_at
      ),
      (
        '1143e630-0d87-4fc5-a61e-1bd36807f9ad',
        '9efd38d2-258b-471a-9a7a-aff3c782e3e7', 16, 0, false,
        'Provided at user''s mother''s house; no cost to user',
        source_log.occurred_at, true, 'Split from English muffin PB&J composite',
        source_log.created_at
      ),
      (
        '760185bc-dc9a-4367-82a0-9ddd74a24508',
        '41794c8d-bd81-4710-abf8-195fbdb97b82', 20, 0, false,
        'Provided at user''s mother''s house; no cost to user',
        source_log.occurred_at, true, 'Split from English muffin PB&J composite',
        source_log.created_at
      );

    insert into public.food_logs(
      id, label, kind, product, servings, occurred_at, kcal, protein_g,
      carbs_g, fat_g, fiber_g, sugar_g, sodium_mg,
      nutrition_is_estimated, note, created_at
    ) values
      (
        'a23f1d32-e8cf-464b-a539-3be2d86f17bd',
        'Plain English muffin', 'inventory',
        '36ffaa99-b970-4fe9-b874-a188dd3332fd', 1,
        source_log.occurred_at, 140, 4.9, 25.5, 1.5, 1.5, 1.5, 277.5,
        true, source_log.note, source_log.created_at
      ),
      (
        '96dff2a5-5ded-452a-9d40-cd3d2941c8ec',
        'Creamy peanut butter, about 1 tbsp', 'inventory',
        '9efd38d2-258b-471a-9a7a-aff3c782e3e7', 1,
        source_log.occurred_at, 90, 3.5, 3.5, 7.5, 1, 1.5, 62.5,
        true, source_log.note, source_log.created_at
      ),
      (
        '9a5fb13c-ce02-485c-b6c7-8fa70006dd9f',
        'Fruit jelly, about 1 tbsp', 'inventory',
        '41794c8d-bd81-4710-abf8-195fbdb97b82', 1,
        source_log.occurred_at, 50, 0, 13, 0, 0, 10, 10,
        true, source_log.note, source_log.created_at
      );

    insert into public.inventory_events(
      id, lot, quantity_delta, reason, food_log, occurred_at, note, created_at
    ) values
      (
        '27fec062-6fbc-4407-afcc-8b4768ccb913',
        '7660e959-d202-48a9-a7c1-aa39d1791f3c', -1, 'eaten',
        'a23f1d32-e8cf-464b-a539-3be2d86f17bd', source_log.occurred_at,
        'Split from English muffin PB&J composite', source_log.created_at
      ),
      (
        'a4b596c1-d200-43fc-9037-69ef35c7bb36',
        '1143e630-0d87-4fc5-a61e-1bd36807f9ad', -16, 'eaten',
        '96dff2a5-5ded-452a-9d40-cd3d2941c8ec', source_log.occurred_at,
        'Split from English muffin PB&J composite', source_log.created_at
      ),
      (
        'e7d4e041-61b5-49da-85f4-32838f816b5e',
        '760185bc-dc9a-4367-82a0-9ddd74a24508', -20, 'eaten',
        '9a5fb13c-ce02-485c-b6c7-8fa70006dd9f', source_log.occurred_at,
        'Split from English muffin PB&J composite', source_log.created_at
      );

    insert into public.food_log_replacements(original_log, replacement_log)
    values
      (source_log.id, 'a23f1d32-e8cf-464b-a539-3be2d86f17bd'),
      (source_log.id, '96dff2a5-5ded-452a-9d40-cd3d2941c8ec'),
      (source_log.id, '9a5fb13c-ce02-485c-b6c7-8fa70006dd9f');

    update public.food_logs
    set voided_at = split_at,
        product = null,
        note = note || ' Superseded by individual English muffin, peanut butter, and jelly records.'
    where id = source_log.id;

    delete from public.inventory_events
    where lot in (
      select id from public.inventory_lots
      where product = 'c9b6f09e-4c79-4958-8df4-69aba1d723bf'
    );
    delete from public.inventory_lots
    where product = 'c9b6f09e-4c79-4958-8df4-69aba1d723bf';
    delete from public.products
    where id = 'c9b6f09e-4c79-4958-8df4-69aba1d723bf';
    delete from public.base_foods
    where id = '985b7bcd-21a3-4074-98b8-85feb305f736';
  end if;

  update public.products product
  set use_count = usage.active_count,
      last_used_at = usage.last_used_at
  from (
    select
      log.product,
      count(*)::integer as active_count,
      max(log.occurred_at) as last_used_at
    from public.food_logs log
    where log.product in (
      '4507778e-e63a-498e-a36c-cd2ef4e51d65',
      '4f000cdb-1841-43fe-a181-4233e21c8b0e'
    )
      and log.voided_at is null
    group by log.product
  ) usage
  where product.id = usage.product;
end;
$$;
