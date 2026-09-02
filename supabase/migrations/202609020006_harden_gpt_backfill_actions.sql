-- Make GPT logging corrections reversible, cost-complete, correctly classified,
-- and historically timestamped. This migration also repairs the Wednesday data
-- that exposed the contract gaps.

alter table public.inventory_lots
  add column acquisition_food_log uuid references public.food_logs(id),
  add column acquisition_void_event uuid references public.inventory_events(id);

create unique index inventory_lots_acquisition_food_log_key
  on public.inventory_lots(acquisition_food_log)
  where acquisition_food_log is not null;

create unique index inventory_lots_acquisition_void_event_key
  on public.inventory_lots(acquisition_void_event)
  where acquisition_void_event is not null;

comment on column public.inventory_lots.acquisition_food_log is
  'The consumption log created by the same atomic purchase-and-consume action as this lot.';
comment on column public.inventory_lots.acquisition_void_event is
  'The compensating event that removes an acquisition lot while its originating consumption is voided.';

-- Existing immediate-purchase lots were not linked explicitly. The old action
-- always classified them external and gave the lot and first eaten event the
-- same timestamp, which makes the unambiguous one-to-one cases recoverable.
with candidates as (
  select
    lot.id as lot_id,
    event.food_log,
    count(*) over (partition by lot.id) as lot_matches,
    count(*) over (partition by event.food_log) as log_matches
  from public.inventory_lots lot
  join public.inventory_events event
    on event.lot = lot.id
   and event.reason = 'eaten'
   and event.food_log is not null
   and event.occurred_at = lot.acquired_at
  where lot.product is not null
    and lot.is_external
)
update public.inventory_lots lot
set acquisition_food_log = candidate.food_log
from candidates candidate
where candidate.lot_id = lot.id
  and candidate.lot_matches = 1
  and candidate.log_matches = 1;

-- Oikos Remix containers are discrete 4.5 oz / 128 g cups. The imported record
-- incorrectly used eight fluid ounces as one container, making four cups look
-- like 32 base units. Convert the definition, its lots, and its ledger together.
do $$
declare
  count_unit uuid;
  oikos_product constant uuid := 'af57ecf7-7d51-5819-9e25-68e02428a7a1';
  oikos_food constant uuid := '9789c966-86f8-5b5f-b1d9-66bf348a267e';
  lot_id uuid;
begin
  select id into count_unit
  from public.measure_conversions
  where measure_style = 'discrete' and base_to_this_ratio = 1
  order by full_name
  limit 1;

  if count_unit is null then raise exception 'A count unit is required for the Oikos migration'; end if;

  alter table public.inventory_events disable trigger inventory_events_refresh_lot;
  alter table public.inventory_lots disable trigger inventory_lots_protect_cache;

  update public.inventory_events event
  set quantity_delta = event.quantity_delta / 8
  from public.inventory_lots lot
  where lot.id = event.lot
    and lot.product = oikos_product;

  update public.inventory_lots
  set initial_qty = initial_qty / 8,
      remaining_qty = remaining_qty / 8
  where product = oikos_product;

  alter table public.inventory_lots enable trigger inventory_lots_protect_cache;
  alter table public.inventory_events enable trigger inventory_events_refresh_lot;

  for lot_id in select id from public.inventory_lots where product = oikos_product
  loop
    perform public.refresh_inventory_lot(lot_id);
  end loop;

  alter table public.base_foods disable trigger base_foods_immutable_style;

  update public.base_foods
  set measure_style = 'discrete',
      display_unit = count_unit,
      g_per_fl_oz = null,
      g_per_count = 128,
      nutrition_basis_qty = 1,
      updated_at = now()
  where id = oikos_food;

  alter table public.base_foods enable trigger base_foods_immutable_style;

  update public.products
  set package_qty_base = 4,
      package_unit = count_unit,
      serving_qty_base = 1,
      nutrition_basis_qty = 1,
      updated_at = now()
  where id = oikos_product;
end;
$$;

-- The three Safeway purchases logged on Wednesday are groceries, not
-- away-from-home spending. Their prices were subsequently researched, so remove
-- the stale note that said no purchase total was available.
update public.inventory_lots
set is_external = false,
    note = replace(note, 'Purchase total not provided.', 'Purchase price estimated from the Safeway Gambrills listing.')
where id in (
  'ed9bf99e-552a-42cf-a1df-62579e64e5e1',
  'f98e511f-a2e1-441e-bc67-dda15f73c7b1',
  '6b983a83-6e6e-438b-8955-81d7d5c3f576'
);

-- The historical chocolate-milk batch was prepared on the day it was consumed,
-- not when the backfill was entered.
update public.preps
set prepped_at = '2026-08-26T20:00:00-04:00'
where id = '3c4a7e5f-f37b-4f05-a27d-e84cb768cdf7';

update public.inventory_lots
set acquired_at = '2026-08-26T20:00:00-04:00'
where prep = '3c4a7e5f-f37b-4f05-a27d-e84cb768cdf7';

update public.inventory_events
set occurred_at = '2026-08-26T20:00:00-04:00'
where prep = '3c4a7e5f-f37b-4f05-a27d-e84cb768cdf7';

-- The purchase action now requires explicit cost provenance and purchase type,
-- and records which history event owns the acquired lot.
drop function public.consume_product_purchase(uuid, numeric, numeric, text, timestamptz, numeric, boolean, text, text, text);

create function public.consume_product_purchase(
  p_product uuid,
  p_purchased_quantity numeric,
  p_consumed_quantity numeric,
  p_purchase_type text,
  p_total_cost numeric,
  p_cost_is_estimated boolean,
  p_cost_source text,
  p_location text default null,
  p_occurred_at timestamptz default now(),
  p_label text default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  lot_id uuid;
  log_id uuid;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  if p_purchased_quantity <= 0 then raise exception 'Purchased quantity must be positive'; end if;
  if p_consumed_quantity < 0 then raise exception 'Consumed quantity cannot be negative'; end if;
  if p_consumed_quantity > p_purchased_quantity then raise exception 'Consumed quantity cannot exceed purchased quantity'; end if;
  if p_purchase_type is null or p_purchase_type not in ('grocery', 'awayFromHome') then raise exception 'purchaseType must be grocery or awayFromHome'; end if;
  if p_consumed_quantity < p_purchased_quantity and nullif(p_location, '') is null then
    raise exception 'A location is required when purchased food remains';
  end if;
  if p_total_cost is null or p_total_cost < 0 then raise exception 'Total cost must be provided and nonnegative'; end if;
  if p_cost_is_estimated is null then raise exception 'Cost estimate status must be provided'; end if;
  if nullif(trim(coalesce(p_cost_source, '')), '') is null then raise exception 'Cost source must be provided'; end if;

  perform 1 from public.products where id = p_product for update;
  if not found then raise exception 'Product does not exist'; end if;

  insert into public.inventory_lots(
    product, initial_qty, remaining_qty, total_cost, cost_is_estimated,
    cost_source, acquired_at, is_external, location, note
  ) values (
    p_product, p_purchased_quantity, p_purchased_quantity, p_total_cost, p_cost_is_estimated,
    trim(p_cost_source), p_occurred_at, p_purchase_type = 'awayFromHome', nullif(p_location, ''), p_note
  ) returning id into lot_id;

  if p_consumed_quantity > 0 then
    log_id := public.consume_inventory_lot(lot_id, p_consumed_quantity, p_occurred_at);
    update public.food_logs
    set label = coalesce(nullif(p_label, ''), label), note = p_note
    where id = log_id;
    update public.inventory_lots set acquisition_food_log = log_id where id = lot_id;
  end if;

  update public.products
  set use_count = use_count + case when p_consumed_quantity > 0 then 1 else 0 end,
      last_used_at = case when p_consumed_quantity > 0 then p_occurred_at else last_used_at end,
      estimated_cost = round(p_total_cost * package_qty_base / p_purchased_quantity, 2),
      cost_source = trim(p_cost_source),
      cost_as_of = (p_occurred_at at time zone (select time_zone from public.app_settings where singleton))::date
  where id = p_product;

  return jsonb_build_object(
    'status', case when p_consumed_quantity > 0 then 'consumed' else 'acquired' end,
    'lotId', lot_id,
    'logId', log_id,
    'purchaseType', p_purchase_type,
    'remainingQuantity', p_purchased_quantity - p_consumed_quantity,
    'location', nullif(p_location, '')
  );
end;
$$;

revoke all on function public.consume_product_purchase(uuid, numeric, numeric, text, numeric, boolean, text, text, timestamptz, text, text) from public, anon;
grant execute on function public.consume_product_purchase(uuid, numeric, numeric, text, numeric, boolean, text, text, timestamptz, text, text) to authenticated, service_role;

-- Historical preparation writes the same timestamp to the prep, its output lot,
-- and every ingredient deduction made by the transaction.
drop function public.gpt_prepare_recipe(uuid, numeric, text, date, text);

create function public.gpt_prepare_recipe(
  p_recipe uuid,
  p_servings numeric,
  p_location text default 'fridge',
  p_use_by date default null,
  p_note text default null,
  p_prepared_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  recipe_row public.recipes%rowtype;
  prep_id uuid;
  lot_id uuid;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  select * into recipe_row from public.recipes where id = p_recipe;
  if not found then raise exception 'Recipe does not exist'; end if;
  if p_servings <= 0 then raise exception 'servings must be positive'; end if;
  if p_prepared_at is null then raise exception 'preparedAt cannot be null'; end if;

  prep_id := public.cook_recipe(p_recipe, p_servings / recipe_row.servings, p_servings, p_location);
  update public.preps set prepped_at = p_prepared_at, note = p_note where id = prep_id;
  update public.inventory_events set occurred_at = p_prepared_at where prep = prep_id;

  select id into lot_id from public.inventory_lots where prep = prep_id;
  if lot_id is null then
    insert into public.inventory_lots(prep, initial_qty, remaining_qty, location, use_by, acquired_at, note)
    values (prep_id, p_servings, p_servings, p_location, p_use_by, p_prepared_at, p_note)
    returning id into lot_id;
  else
    update public.inventory_lots
    set use_by = p_use_by, acquired_at = p_prepared_at, note = p_note
    where id = lot_id;
  end if;

  return jsonb_build_object('status', 'prepared', 'prepId', prep_id, 'lotId', lot_id, 'preparedAt', p_prepared_at);
end;
$$;

revoke all on function public.gpt_prepare_recipe(uuid, numeric, text, date, text, timestamptz) from public, anon, authenticated;
grant execute on function public.gpt_prepare_recipe(uuid, numeric, text, date, text, timestamptz) to service_role;

-- Voiding a normal consumption returns the deducted inventory. If the same
-- action also acquired its lot, compensate the complete acquisition as well so
-- an accidental duplicate cannot leave phantom stock behind.
create or replace function public.void_food_log(p_food_log uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  log_row public.food_logs%rowtype;
  acquisition_lot public.inventory_lots%rowtype;
  reversal_id uuid;
begin
  if not public.is_app_owner() then
    raise exception 'Only the app owner may void food logs' using errcode = '42501';
  end if;

  select * into log_row from public.food_logs where id = p_food_log for update;
  if not found then raise exception 'Food log entry does not exist'; end if;
  select * into acquisition_lot
  from public.inventory_lots
  where acquisition_food_log = p_food_log
  for update;

  if acquisition_lot.id is not null and exists (
    select 1
    from public.inventory_events event
    where event.lot = acquisition_lot.id
      and event.voided_at is null
      and event.food_log is distinct from p_food_log
      and event.id is distinct from acquisition_lot.acquisition_void_event
  ) then
    raise exception 'This purchase lot was used again; void its later inventory events before voiding the originating purchase';
  end if;

  if log_row.voided_at is null then
    update public.food_logs set voided_at = now() where id = p_food_log;
    update public.inventory_events set voided_at = now()
    where food_log = p_food_log and voided_at is null;
    update public.planned_consumptions set status = 'planned'
    where food_log = p_food_log and status = 'fulfilled';
  end if;

  if acquisition_lot.id is not null then
    if acquisition_lot.acquisition_void_event is null then
      insert into public.inventory_events(lot, quantity_delta, reason, note)
      values (acquisition_lot.id, -acquisition_lot.initial_qty, 'adjust', 'Originating purchase-and-consume action voided')
      returning id into reversal_id;
      update public.inventory_lots set acquisition_void_event = reversal_id where id = acquisition_lot.id;
    else
      update public.inventory_events set voided_at = null
      where id = acquisition_lot.acquisition_void_event and voided_at is not null;
    end if;
  end if;
end;
$$;

create or replace function public.restore_food_log(p_food_log uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  log_row public.food_logs%rowtype;
  acquisition_lot public.inventory_lots%rowtype;
begin
  if not public.is_app_owner() then
    raise exception 'Only the app owner may restore food logs' using errcode = '42501';
  end if;

  select * into log_row from public.food_logs where id = p_food_log for update;
  if not found then raise exception 'Food log entry does not exist'; end if;
  if log_row.voided_at is null then return; end if;
  if exists (
    select 1 from public.food_log_replacements replacement
    where replacement.original_log = p_food_log
  ) then
    raise exception 'This food log was split into individual items and cannot be restored';
  end if;

  select * into acquisition_lot
  from public.inventory_lots
  where acquisition_food_log = p_food_log
  for update;

  if acquisition_lot.acquisition_void_event is not null then
    update public.inventory_events set voided_at = now()
    where id = acquisition_lot.acquisition_void_event and voided_at is null;
  end if;

  update public.food_logs set voided_at = null where id = p_food_log;
  update public.inventory_events set voided_at = null
  where food_log = p_food_log and voided_at is not null;
  update public.planned_consumptions set status = 'fulfilled'
  where food_log = p_food_log and status = 'planned';
end;
$$;

create function public.gpt_void_consumption(p_food_log uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  before_state jsonb;
  after_state jsonb;
  reverses_acquisition boolean;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  if nullif(trim(coalesce(p_reason, '')), '') is null then raise exception 'reason is required'; end if;
  if not exists (select 1 from public.food_logs where id = p_food_log) then raise exception 'Consumption event does not exist'; end if;

  select jsonb_build_object(
    'consumption', to_jsonb(log),
    'purchaseLot', case when lot.id is null then null else to_jsonb(lot) end
  ), lot.id is not null
  into before_state, reverses_acquisition
  from public.food_logs log
  left join public.inventory_lots lot on lot.acquisition_food_log = log.id
  where log.id = p_food_log;

  perform public.void_food_log(p_food_log);

  select jsonb_build_object(
    'consumption', to_jsonb(log),
    'purchaseLot', case when lot.id is null then null else to_jsonb(lot) end,
    'voidReason', trim(p_reason)
  )
  into after_state
  from public.food_logs log
  left join public.inventory_lots lot on lot.acquisition_food_log = log.id
  where log.id = p_food_log;

  insert into public.record_edits(resource, record_id, before_state, after_state)
  values ('consumption', p_food_log, before_state, after_state);

  return jsonb_build_object(
    'status', 'voided',
    'id', p_food_log,
    'acquisitionReversed', reverses_acquisition
  );
end;
$$;

revoke all on function public.gpt_void_consumption(uuid, text) from public, anon, authenticated;
grant execute on function public.gpt_void_consumption(uuid, text) to service_role;

-- Lot edits use the same explicit purchase classification as creation.
create or replace function public.gpt_update_inventory_lot(p_lot uuid, p_patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  lot_row public.inventory_lots%rowtype;
  updated_row public.inventory_lots%rowtype;
  bad_key text;
  purchase_type text;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  if jsonb_typeof(p_patch) <> 'object' or p_patch = '{}'::jsonb then raise exception 'patch must be a non-empty object'; end if;
  select key into bad_key from jsonb_object_keys(p_patch) key
  where key <> all(array['remainingQuantity','location','bestBy','acquiredAt','totalCost','costIsEstimated','costSource','purchaseType','note']) limit 1;
  if bad_key is not null then raise exception 'Unsupported inventory-lot edit field: %', bad_key; end if;
  if p_patch ? 'purchaseType' then
    purchase_type := p_patch ->> 'purchaseType';
    if purchase_type is null or purchase_type not in ('grocery', 'awayFromHome') then raise exception 'purchaseType must be grocery or awayFromHome'; end if;
  end if;

  select * into lot_row from public.inventory_lots where id = p_lot for update;
  if not found then raise exception 'Inventory lot does not exist'; end if;
  if p_patch ? 'remainingQuantity' then
    if (p_patch ->> 'remainingQuantity')::numeric < 0 then raise exception 'remainingQuantity cannot be negative'; end if;
    perform public.set_inventory_lot_quantity(p_lot, (p_patch ->> 'remainingQuantity')::numeric, false);
  end if;

  update public.inventory_lots set
    location = case when p_patch ? 'location' then nullif(p_patch ->> 'location', '') else location end,
    use_by = case when p_patch ? 'bestBy' then nullif(p_patch ->> 'bestBy', '')::date else use_by end,
    acquired_at = case when p_patch ? 'acquiredAt' then (p_patch ->> 'acquiredAt')::timestamptz else acquired_at end,
    total_cost = case when p_patch ? 'totalCost' then nullif(p_patch ->> 'totalCost', '')::numeric else total_cost end,
    cost_is_estimated = case when p_patch ? 'costIsEstimated' then (p_patch ->> 'costIsEstimated')::boolean else cost_is_estimated end,
    cost_source = case when p_patch ? 'costSource' then nullif(p_patch ->> 'costSource', '') else cost_source end,
    is_external = case when p_patch ? 'purchaseType' then purchase_type = 'awayFromHome' else is_external end,
    note = case when p_patch ? 'note' then nullif(p_patch ->> 'note', '') else note end
  where id = p_lot returning * into updated_row;

  if updated_row.is_external and updated_row.remaining_qty > 0 and updated_row.location is null then
    raise exception 'A location is required when away-from-home food remains';
  end if;

  insert into public.record_edits(resource, record_id, before_state, after_state)
  values ('inventory_lot', p_lot, to_jsonb(lot_row), to_jsonb(updated_row));
  return jsonb_build_object(
    'status', 'updated',
    'id', p_lot,
    'purchaseType', case when updated_row.is_external then 'awayFromHome' else 'grocery' end,
    'remainingQuantity', updated_row.remaining_qty
  );
end;
$$;

-- Purchase-cost corrections follow the explicit action link, so grocery and
-- away-from-home acquisitions behave identically and never depend on a flag.
create or replace function public.gpt_update_consumption(p_food_log uuid, p_patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  log_row public.food_logs%rowtype;
  updated_row public.food_logs%rowtype;
  lot_row public.inventory_lots%rowtype;
  updated_lot public.inventory_lots%rowtype;
  bad_key text;
  bad_nutrition_key text;
  before_state jsonb;
  after_state jsonb;
  edits_purchase_cost boolean;
  edits_direct_cost boolean;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  if jsonb_typeof(p_patch) <> 'object' or p_patch = '{}'::jsonb then raise exception 'patch must be a non-empty object'; end if;
  select key into bad_key from jsonb_object_keys(p_patch) key
  where key <> all(array['label','portionLabel','timestamp','note','nutrition','directCost','purchaseTotalCost','costIsEstimated','costSource']) limit 1;
  if bad_key is not null then raise exception 'Unsupported consumption edit field: %', bad_key; end if;
  if p_patch ? 'nutrition' and p_patch -> 'nutrition' <> 'null'::jsonb and jsonb_typeof(p_patch -> 'nutrition') <> 'object' then
    raise exception 'nutrition must be an object or null';
  end if;
  select key into bad_nutrition_key
  from jsonb_object_keys(case when jsonb_typeof(p_patch -> 'nutrition') = 'object' then p_patch -> 'nutrition' else '{}'::jsonb end) key
  where key <> all(array['calories','proteinG','carbsG','fatG','fiberG','sugarG','sodiumMg','estimated','source']) limit 1;
  if bad_nutrition_key is not null then raise exception 'Unsupported nutrition field: %', bad_nutrition_key; end if;

  select * into log_row from public.food_logs where id = p_food_log for update;
  if not found then raise exception 'Consumption event does not exist'; end if;
  if log_row.voided_at is not null then raise exception 'Voided consumption events cannot be edited'; end if;
  if p_patch ? 'label' and trim(coalesce(p_patch ->> 'label', '')) = '' then raise exception 'label cannot be empty'; end if;

  edits_purchase_cost := p_patch ? 'purchaseTotalCost';
  edits_direct_cost := p_patch ? 'directCost' or (log_row.kind = 'manual' and p_patch ?| array['costIsEstimated','costSource']);
  if edits_purchase_cost and edits_direct_cost then raise exception 'Edit either directCost or purchaseTotalCost, not both'; end if;
  if p_patch ? 'directCost' and nullif(p_patch ->> 'directCost', '')::numeric < 0 then raise exception 'directCost cannot be negative'; end if;
  if p_patch ? 'purchaseTotalCost' and nullif(p_patch ->> 'purchaseTotalCost', '')::numeric < 0 then raise exception 'purchaseTotalCost cannot be negative'; end if;

  if edits_purchase_cost or (log_row.kind <> 'manual' and p_patch ?| array['costIsEstimated','costSource']) then
    select * into lot_row
    from public.inventory_lots
    where acquisition_food_log = p_food_log
    for update;
    if not found then raise exception 'Purchase cost correction requires an originating purchase lot'; end if;
  end if;

  before_state := jsonb_build_object('consumption', to_jsonb(log_row), 'purchaseLot', case when lot_row.id is null then null else to_jsonb(lot_row) end);

  update public.food_logs set
    label = case when p_patch ? 'label' then trim(p_patch ->> 'label') else label end,
    portion_label = case when p_patch ? 'portionLabel' then nullif(trim(coalesce(p_patch ->> 'portionLabel', '')), '') else portion_label end,
    occurred_at = case when p_patch ? 'timestamp' then (p_patch ->> 'timestamp')::timestamptz else occurred_at end,
    note = case when p_patch ? 'note' then nullif(p_patch ->> 'note', '') else note end,
    kcal = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,calories}', '')::numeric else kcal end,
    protein_g = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,proteinG}', '')::numeric else protein_g end,
    carbs_g = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,carbsG}', '')::numeric else carbs_g end,
    fat_g = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,fatG}', '')::numeric else fat_g end,
    fiber_g = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,fiberG}', '')::numeric else fiber_g end,
    sugar_g = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,sugarG}', '')::numeric else sugar_g end,
    sodium_mg = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,sodiumMg}', '')::numeric else sodium_mg end,
    nutrition_is_estimated = case when p_patch ? 'nutrition' then coalesce((p_patch #>> '{nutrition,estimated}')::boolean, false) else nutrition_is_estimated end,
    nutrition_source = case when p_patch ? 'nutrition' then nullif(p_patch #>> '{nutrition,source}', '') else nutrition_source end,
    cost = case when p_patch ? 'directCost' then nullif(p_patch ->> 'directCost', '')::numeric else cost end,
    cost_is_estimated = case when edits_direct_cost and p_patch ? 'costIsEstimated' then (p_patch ->> 'costIsEstimated')::boolean else cost_is_estimated end,
    cost_source = case when edits_direct_cost and p_patch ? 'costSource' then nullif(p_patch ->> 'costSource', '') else cost_source end
  where id = p_food_log returning * into updated_row;

  if updated_row.cost is null and updated_row.cost_is_estimated then raise exception 'A missing direct cost cannot be marked estimated'; end if;
  if p_patch ? 'timestamp' then
    update public.inventory_events set occurred_at = updated_row.occurred_at where food_log = p_food_log;
    update public.inventory_lots set acquired_at = updated_row.occurred_at where acquisition_food_log = p_food_log;
  end if;

  if lot_row.id is not null then
    update public.inventory_lots set
      total_cost = case when p_patch ? 'purchaseTotalCost' then nullif(p_patch ->> 'purchaseTotalCost', '')::numeric else total_cost end,
      cost_is_estimated = case when p_patch ? 'costIsEstimated' then (p_patch ->> 'costIsEstimated')::boolean else cost_is_estimated end,
      cost_source = case when p_patch ? 'costSource' then nullif(p_patch ->> 'costSource', '') else cost_source end
    where id = lot_row.id returning * into updated_lot;
  end if;

  after_state := jsonb_build_object('consumption', to_jsonb(updated_row), 'purchaseLot', case when updated_lot.id is null then null else to_jsonb(updated_lot) end);
  insert into public.record_edits(resource, record_id, before_state, after_state)
  values ('consumption', p_food_log, before_state, after_state);
  return jsonb_build_object('status', 'updated', 'id', p_food_log, 'lotId', case when updated_lot.id is null then null else updated_lot.id end);
end;
$$;
