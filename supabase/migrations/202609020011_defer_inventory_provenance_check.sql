-- Recipe preparation creates an output lot and then fills its provenance in the
-- same transaction. Enforce the invariant at commit so that valid multi-step
-- writes are allowed while incomplete lots can never be committed.

alter table public.inventory_lots
  drop constraint inventory_lots_provenance_required;

create or replace function public.enforce_inventory_lot_provenance()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_lot public.inventory_lots%rowtype;
begin
  select * into current_lot
  from public.inventory_lots
  where id = new.id;

  if not found then
    return null;
  end if;

  if current_lot.acquisition_type is null
    or current_lot.out_of_pocket_cost is null
    or nullif(trim(current_lot.paid_by), '') is null
    or nullif(trim(current_lot.cost_source), '') is null
    or (
      current_lot.acquisition_type in ('grocery', 'restaurant', 'takeout')
      and current_lot.total_cost is null
    )
    or (current_lot.total_cost is not null and current_lot.price_as_of is null)
  then
    raise exception 'Inventory lot % is missing required acquisition or cost provenance', current_lot.id
      using errcode = '23514',
        constraint = 'inventory_lots_provenance_required';
  end if;

  return null;
end;
$$;

revoke all on function public.enforce_inventory_lot_provenance()
  from public, anon, authenticated, service_role;

create constraint trigger inventory_lots_provenance_required
after insert or update on public.inventory_lots
deferrable initially deferred
for each row
execute function public.enforce_inventory_lot_provenance();
