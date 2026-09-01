-- Consumption is the durable event. Products, recipes, and inventory deductions
-- are optional evidence about that event, not prerequisites for recording food.
alter table public.food_logs
  add column portion_label text,
  add column nutrition_source text,
  add column cost numeric check (cost >= 0),
  add column cost_is_estimated boolean not null default false,
  add column cost_source text;

alter table public.food_logs
  drop constraint food_logs_kind_check,
  add constraint food_logs_kind_check check (
    kind in ('inventory', 'recipe', 'meal', 'prepared', 'manual')
  );

-- Completeness is derived so NULL nutrition can never be mistaken for zero.
-- Confidence remains independent in nutrition_is_estimated: a partial snapshot
-- may contain either exact or estimated values.
alter table public.food_logs
  add column nutrition_status text generated always as (
    case
      when
        (case when kcal is not null then 1 else 0 end) +
        (case when protein_g is not null then 1 else 0 end) +
        (case when carbs_g is not null then 1 else 0 end) +
        (case when fat_g is not null then 1 else 0 end) +
        (case when fiber_g is not null then 1 else 0 end) +
        (case when sugar_g is not null then 1 else 0 end) +
        (case when sodium_mg is not null then 1 else 0 end) = 0 then 'unknown'
      when
        (case when kcal is not null then 1 else 0 end) +
        (case when protein_g is not null then 1 else 0 end) +
        (case when carbs_g is not null then 1 else 0 end) +
        (case when fat_g is not null then 1 else 0 end) +
        (case when fiber_g is not null then 1 else 0 end) +
        (case when sugar_g is not null then 1 else 0 end) +
        (case when sodium_mg is not null then 1 else 0 end) = 7 then 'complete'
      else 'partial'
    end
  ) stored;

comment on column public.food_logs.nutrition_status is
  'Generated completeness of the event nutrition snapshot: complete, partial, or unknown.';
comment on column public.food_logs.cost is
  'Direct out-of-pocket cost for consumption without a linked inventory purchase lot.';

-- A prior repair split one English-muffin PB&J eaten at the user's mother's
-- house into three invented products and lots. Restore the original consumption
-- snapshot and remove only those deterministic synthetic records. The genuine
-- Good & Gather peanut-butter definition and inventory are deliberately untouched.
do $$
begin
  if exists (
    select 1 from public.food_logs
    where id = '857db559-c72c-4f15-b6b3-944a45f22140'
  ) then
    delete from public.food_log_replacements
    where original_log = '857db559-c72c-4f15-b6b3-944a45f22140';

    delete from public.inventory_events
    where food_log in (
      'a23f1d32-e8cf-464b-a539-3be2d86f17bd',
      '96dff2a5-5ded-452a-9d40-cd3d2941c8ec',
      '9a5fb13c-ce02-485c-b6c7-8fa70006dd9f'
    );
    delete from public.inventory_lots
    where id in (
      '7660e959-d202-48a9-a7c1-aa39d1791f3c',
      '1143e630-0d87-4fc5-a61e-1bd36807f9ad',
      '760185bc-dc9a-4367-82a0-9ddd74a24508'
    );
    delete from public.food_logs
    where id in (
      'a23f1d32-e8cf-464b-a539-3be2d86f17bd',
      '96dff2a5-5ded-452a-9d40-cd3d2941c8ec',
      '9a5fb13c-ce02-485c-b6c7-8fa70006dd9f'
    );

    update public.food_logs
    set
      label = 'English muffin with peanut butter and jelly',
      kind = 'manual',
      product = null,
      portion_label = '1 English muffin with peanut butter and jelly',
      voided_at = null,
      nutrition_source = 'Original whole-meal estimate',
      cost = 0,
      cost_is_estimated = false,
      cost_source = 'Provided at user''s mother''s house; no cost to user',
      note = nullif(trim(replace(coalesce(note, ''), 'Superseded by individual English muffin, peanut butter, and jelly records.', '')), '')
    where id = '857db559-c72c-4f15-b6b3-944a45f22140';

    delete from public.products
    where id in (
      '36ffaa99-b970-4fe9-b874-a188dd3332fd',
      '9efd38d2-258b-471a-9a7a-aff3c782e3e7',
      '41794c8d-bd81-4710-abf8-195fbdb97b82'
    );
    delete from public.base_foods
    where id in (
      '50c8c697-cf46-4974-8dc8-df751c88a687',
      'f59dc524-9c7b-4198-9aac-454deaff2379'
    );
  end if;
end;
$$;

create function public.log_manual_consumption(
  p_label text,
  p_portion_label text default null,
  p_occurred_at timestamptz default now(),
  p_nutrition jsonb default null,
  p_cost numeric default null,
  p_cost_is_estimated boolean default false,
  p_cost_source text default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  bad_key text;
  log_row public.food_logs%rowtype;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  if trim(coalesce(p_label, '')) = '' then raise exception 'label is required'; end if;
  if p_nutrition is not null and jsonb_typeof(p_nutrition) <> 'object' then
    raise exception 'nutrition must be an object or null';
  end if;
  select key into bad_key
  from jsonb_object_keys(coalesce(p_nutrition, '{}'::jsonb)) key
  where key <> all(array['calories','proteinG','carbsG','fatG','fiberG','sugarG','sodiumMg','estimated','source'])
  limit 1;
  if bad_key is not null then raise exception 'Unsupported nutrition field: %', bad_key; end if;
  if p_cost is not null and p_cost < 0 then raise exception 'cost cannot be negative'; end if;
  if p_cost is null and p_cost_is_estimated then raise exception 'A missing cost cannot be marked estimated'; end if;

  insert into public.food_logs(
    label, kind, portion_label, occurred_at,
    kcal, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg,
    nutrition_is_estimated, nutrition_source,
    cost, cost_is_estimated, cost_source, note
  ) values (
    trim(p_label), 'manual', nullif(trim(coalesce(p_portion_label, '')), ''), p_occurred_at,
    nullif(p_nutrition ->> 'calories', '')::numeric,
    nullif(p_nutrition ->> 'proteinG', '')::numeric,
    nullif(p_nutrition ->> 'carbsG', '')::numeric,
    nullif(p_nutrition ->> 'fatG', '')::numeric,
    nullif(p_nutrition ->> 'fiberG', '')::numeric,
    nullif(p_nutrition ->> 'sugarG', '')::numeric,
    nullif(p_nutrition ->> 'sodiumMg', '')::numeric,
    coalesce((p_nutrition ->> 'estimated')::boolean, false),
    nullif(trim(coalesce(p_nutrition ->> 'source', '')), ''),
    p_cost, p_cost_is_estimated, nullif(trim(coalesce(p_cost_source, '')), ''),
    nullif(trim(coalesce(p_note, '')), '')
  ) returning * into log_row;

  return jsonb_build_object(
    'status', 'logged',
    'id', log_row.id,
    'nutritionStatus', log_row.nutrition_status
  );
end;
$$;

revoke all on function public.log_manual_consumption(text, text, timestamptz, jsonb, numeric, boolean, text, text) from public, anon;
grant execute on function public.log_manual_consumption(text, text, timestamptz, jsonb, numeric, boolean, text, text) to authenticated, service_role;

-- Corrections preserve the original event. Direct manual costs live on the log;
-- purchased-product costs continue to live on their single originating lot.
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
  linked_lot_ids uuid[];
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
    select array_agg(distinct event.lot) into linked_lot_ids
    from public.inventory_events event
    join public.inventory_lots lot on lot.id = event.lot
    where event.food_log = p_food_log and lot.product is not null and lot.is_external;
    if coalesce(array_length(linked_lot_ids, 1), 0) <> 1 then
      raise exception 'Purchase cost correction requires exactly one linked away-from-home lot';
    end if;
    select * into lot_row from public.inventory_lots where id = linked_lot_ids[1] for update;
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
  if p_patch ? 'timestamp' then update public.inventory_events set occurred_at = updated_row.occurred_at where food_log = p_food_log; end if;

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

drop view public.daily_nutrition;
create view public.daily_nutrition
with (security_invoker = true)
as
select
  (log.occurred_at at time zone settings.time_zone)::date as local_date,
  sum(log.kcal) as kcal,
  sum(log.protein_g) as protein_g,
  sum(log.carbs_g) as carbs_g,
  sum(log.fat_g) as fat_g,
  sum(log.fiber_g) as fiber_g,
  sum(log.sugar_g) as sugar_g,
  sum(log.sodium_mg) as sodium_mg,
  count(*) as entry_count,
  count(*) filter (where log.nutrition_status = 'complete') as complete_entries,
  count(*) filter (where log.nutrition_status = 'partial') as partial_entries,
  count(*) filter (where log.nutrition_status = 'unknown') as unknown_entries,
  bool_and(log.nutrition_status = 'complete') as nutrition_is_complete
from public.food_logs log
cross join public.app_settings settings
where log.voided_at is null
group by (log.occurred_at at time zone settings.time_zone)::date;

grant select on public.daily_nutrition to authenticated;
