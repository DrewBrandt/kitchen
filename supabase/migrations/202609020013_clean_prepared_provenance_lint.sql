-- Keep the prepared-lot provenance derivation lint-clean.

create or replace function public.refresh_prepared_lot_provenance(p_prep uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  derived_out_of_pocket numeric;
  derived_paid_by text;
  derived_is_estimated boolean;
  derived_source text;
  derived_price_as_of date;
begin
  select
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
  into derived_out_of_pocket, derived_paid_by,
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

revoke all on function public.refresh_prepared_lot_provenance(uuid)
  from public, anon, authenticated, service_role;
