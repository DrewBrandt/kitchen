-- Carry ingredient cost provenance into prepared output lots and enforce the
-- structured invariants that the public actions promise.

create function public.refresh_prepared_lot_provenance(p_prep uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  source_count integer;
  derived_out_of_pocket numeric;
  derived_paid_by text;
  derived_is_estimated boolean;
  derived_source text;
  derived_price_as_of date;
begin
  select
    count(*),
    case when count(*) = 0 then 0
      when bool_and(source_lot.out_of_pocket_cost is not null)
        then round(sum(-event.quantity_delta * source_lot.out_of_pocket_cost / source_lot.initial_qty), 2)
      else null end,
    coalesce(string_agg(distinct nullif(trim(source_lot.paid_by), ''), '; '), 'household'),
    coalesce(bool_or(source_lot.cost_is_estimated), false),
    case when count(*) = 0 then 'Prepared entirely from always-available household ingredients'
      else 'Carried forward from ingredient lots: ' || coalesce(
        string_agg(distinct nullif(trim(source_lot.cost_source), ''), '; '),
        'ingredient purchase records') end,
    max(source_lot.price_as_of)
  into source_count, derived_out_of_pocket, derived_paid_by,
       derived_is_estimated, derived_source, derived_price_as_of
  from public.inventory_events event
  join public.inventory_lots source_lot on source_lot.id = event.lot
  where event.prep = p_prep
    and event.reason = 'prep'
    and event.voided_at is null;

  update public.inventory_lots output_lot
  set acquisition_type = 'home',
      is_external = false,
      out_of_pocket_cost = derived_out_of_pocket,
      paid_by = derived_paid_by,
      cost_is_estimated = derived_is_estimated,
      cost_source = derived_source,
      price_as_of = case when output_lot.total_cost is null then null else derived_price_as_of end,
      acquired_time_precision = prep.time_precision
  from public.preps prep
  where output_lot.prep = p_prep and prep.id = p_prep;
end;
$$;

revoke all on function public.refresh_prepared_lot_provenance(uuid) from public, anon, authenticated, service_role;

create or replace function public.gpt_prepare_recipe(
  p_recipe uuid,
  p_servings numeric,
  p_location text,
  p_use_by date,
  p_note text,
  p_prepared_at timestamptz,
  p_time_precision text,
  p_request_id uuid
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
  prior_result jsonb;
  action_result jsonb;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  prior_result := public.gpt_claim_request(p_request_id, 'prepareFoodBatch');
  if prior_result is not null then return prior_result; end if;
  select * into recipe_row from public.recipes where id = p_recipe;
  if not found then raise exception 'Recipe does not exist'; end if;
  if p_servings <= 0 then raise exception 'servings must be positive'; end if;
  if p_prepared_at is null then raise exception 'preparedAt cannot be null'; end if;
  if p_time_precision not in ('exact', 'estimated', 'dateOnly') then raise exception 'Invalid timePrecision'; end if;
  prep_id := public.cook_recipe(p_recipe, p_servings / recipe_row.servings, p_servings, p_location);
  update public.preps
  set prepped_at = p_prepared_at, time_precision = p_time_precision, note = p_note
  where id = prep_id;
  update public.inventory_events set occurred_at = p_prepared_at where prep = prep_id;
  select id into lot_id from public.inventory_lots where prep = prep_id;
  update public.inventory_lots
  set use_by = p_use_by, acquired_at = p_prepared_at,
      acquired_time_precision = p_time_precision, note = p_note
  where id = lot_id;
  perform public.refresh_prepared_lot_provenance(prep_id);
  action_result := jsonb_build_object(
    'status', 'prepared', 'prepId', prep_id, 'lotId', lot_id,
    'preparedAt', p_prepared_at, 'timePrecision', p_time_precision
  );
  perform public.gpt_complete_request(p_request_id, action_result);
  return action_result;
end;
$$;

revoke all on function public.gpt_prepare_recipe(uuid, numeric, text, date, text, timestamptz, text, uuid) from public, anon, authenticated;
grant execute on function public.gpt_prepare_recipe(uuid, numeric, text, date, text, timestamptz, text, uuid) to service_role;

create temporary table prepared_lot_before on commit drop as
select id, to_jsonb(lot) as before_state
from public.inventory_lots lot
where prep is not null;

do $$
declare prep_id uuid;
begin
  for prep_id in select id from public.preps where voided_at is null
  loop
    perform public.refresh_prepared_lot_provenance(prep_id);
  end loop;
end;
$$;

update public.inventory_lots lot
set price_as_of = (lot.acquired_at at time zone (select time_zone from public.app_settings where singleton))::date
where lot.total_cost is not null and lot.price_as_of is null;

insert into public.record_edits(resource, record_id, before_state, after_state)
select 'inventory_lot', before.id, before.before_state,
       to_jsonb(lot) || jsonb_build_object(
         'auditRepairReason', 'Prepared-lot ingredient cost provenance repair on 2026-09-02')
from prepared_lot_before before
join public.inventory_lots lot on lot.id = before.id
where before.before_state is distinct from to_jsonb(lot);

alter table public.food_logs drop constraint food_logs_manual_provenance_required;
alter table public.food_logs add constraint food_logs_manual_provenance_required check (
  kind <> 'manual' or (
    acquisition_type is not null
    and out_of_pocket_cost is not null
    and nullif(trim(paid_by), '') is not null
    and nullif(trim(cost_source), '') is not null
    and (acquisition_type not in ('grocery', 'restaurant', 'takeout') or total_price is not null)
    and (total_price is null or price_as_of is not null)
  )
) not valid;
alter table public.food_logs validate constraint food_logs_manual_provenance_required;

alter table public.inventory_lots add constraint inventory_lots_provenance_required check (
  acquisition_type is not null
  and out_of_pocket_cost is not null
  and nullif(trim(paid_by), '') is not null
  and nullif(trim(cost_source), '') is not null
  and (acquisition_type not in ('grocery', 'restaurant', 'takeout') or total_cost is not null)
  and (total_cost is null or price_as_of is not null)
) not valid;
alter table public.inventory_lots validate constraint inventory_lots_provenance_required;

alter table public.products add constraint products_estimated_cost_provenance_required check (
  estimated_cost is null or (
    nullif(trim(cost_source), '') is not null and cost_as_of is not null
  )
) not valid;
alter table public.products validate constraint products_estimated_cost_provenance_required;

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
select 'manual_components_missing', log.id, jsonb_build_object('label', log.label)
from active_logs log
where log.kind = 'manual' and jsonb_array_length(log.components) = 0
union all
select 'manual_estimate_metadata_missing', log.id, jsonb_build_object('label', log.label)
from active_logs log
where log.kind = 'manual' and log.nutrition_is_estimated and log.nutrition_estimate is null
union all
select 'manual_provenance_missing', log.id, jsonb_build_object('label', log.label)
from active_logs log
where log.kind = 'manual' and (
  log.acquisition_type is null or log.out_of_pocket_cost is null
  or nullif(trim(log.paid_by), '') is null or nullif(trim(log.cost_source), '') is null
  or (log.acquisition_type in ('grocery', 'restaurant', 'takeout') and log.total_price is null)
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
select 'inventory_lot_provenance_missing', lot.id,
  jsonb_build_object('acquisitionType', lot.acquisition_type, 'costSource', lot.cost_source)
from public.inventory_lots lot
where lot.acquisition_type is null or lot.out_of_pocket_cost is null
  or nullif(trim(lot.paid_by), '') is null or nullif(trim(lot.cost_source), '') is null
  or (lot.acquisition_type in ('grocery', 'restaurant', 'takeout') and lot.total_cost is null)
  or (lot.total_cost is not null and lot.price_as_of is null)
union all
select 'product_price_provenance_missing', product.id,
  jsonb_build_object('brand', product.brand, 'name', product.name)
from public.products product
where product.archived_at is null and product.estimated_cost is not null
  and (nullif(trim(product.cost_source), '') is null or product.cost_as_of is null);

revoke all on public.history_quality_issues from public, anon;
grant select on public.history_quality_issues to authenticated, service_role;
