-- Quantities below one millionth of a food's canonical unit are conversion
-- residue, not usable inventory. Keep that rule at the ledger boundary so all
-- callers (web, GPT, recipes, and future clients) observe the same invariant.
create or replace function public.normalize_inventory_event_quantity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  excluded_event uuid;
  available_without_event numeric;
  next_remaining numeric;
begin
  if new.voided_at is not null or new.quantity_delta >= 0 then
    return new;
  end if;

  select id
  into excluded_event
  from public.inventory_lots
  where id = new.lot
  for update;

  if excluded_event is null then
    return new;
  end if;

  excluded_event := case when tg_op = 'UPDATE' then old.id else null end;

  select lot.initial_qty + coalesce(sum(event.quantity_delta) filter (
    where event.voided_at is null
      and (excluded_event is null or event.id <> excluded_event)
  ), 0)
  into available_without_event
  from public.inventory_lots lot
  left join public.inventory_events event on event.lot = lot.id
  where lot.id = new.lot
  group by lot.initial_qty;

  next_remaining := available_without_event + new.quantity_delta;
  if available_without_event > 0 and abs(next_remaining) <= 0.000001 then
    new.quantity_delta := -available_without_event;
  end if;

  return new;
end;
$$;

drop trigger if exists inventory_events_normalize_quantity on public.inventory_events;
create trigger inventory_events_normalize_quantity
before insert or update of lot, quantity_delta, voided_at on public.inventory_events
for each row execute function public.normalize_inventory_event_quantity();

revoke all on function public.normalize_inventory_event_quantity() from public, anon, authenticated;

create or replace function public.refresh_inventory_lot(p_lot uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  next_remaining numeric;
begin
  perform 1
  from public.inventory_lots
  where id = p_lot
  for update;

  select
    lot.initial_qty + coalesce(sum(event.quantity_delta) filter (
      where event.voided_at is null
    ), 0)
  into next_remaining
  from public.inventory_lots lot
  left join public.inventory_events event on event.lot = lot.id
  where lot.id = p_lot
  group by lot.initial_qty;

  if next_remaining is null then
    raise exception 'Inventory lot % does not exist', p_lot;
  end if;

  if next_remaining < 0 then
    raise exception 'Inventory event would make lot % negative', p_lot;
  end if;

  if next_remaining <= 0.000001 then
    next_remaining := 0;
  end if;

  perform set_config('pantry.refreshing_inventory_lot', 'on', true);
  update public.inventory_lots
  set remaining_qty = next_remaining
  where id = p_lot;
  perform set_config('pantry.refreshing_inventory_lot', 'off', true);
end;
$$;

revoke execute on function public.refresh_inventory_lot(uuid) from public, anon, authenticated;

create or replace function public.set_inventory_lot_quantity(
  p_lot uuid,
  p_remaining numeric,
  p_discard boolean default false
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  lot_row public.inventory_lots%rowtype;
  normalized_remaining numeric;
  quantity_change numeric;
  new_event uuid;
begin
  if not public.is_app_owner() then
    raise exception 'Only the app owner may adjust inventory' using errcode = '42501';
  end if;
  if p_remaining < 0 then raise exception 'Remaining quantity cannot be negative'; end if;

  normalized_remaining := case when p_remaining <= 0.000001 then 0 else p_remaining end;
  select * into lot_row from public.inventory_lots where id = p_lot for update;
  if not found then raise exception 'Inventory lot does not exist'; end if;
  quantity_change := normalized_remaining - lot_row.remaining_qty;
  if quantity_change = 0 then return null; end if;
  if p_discard and normalized_remaining <> 0 then raise exception 'Discarding a lot must set it to zero'; end if;

  insert into public.inventory_events(lot, quantity_delta, reason, note)
  values (p_lot, quantity_change, (case when p_discard then 'waste' else 'adjust' end)::public.inventory_event_reason, case when p_discard then 'Discarded from lot details' else 'Adjusted from lot details' end)
  returning id into new_event;

  return new_event;
end;
$$;

revoke all on function public.set_inventory_lot_quantity(uuid, numeric, boolean) from public, anon;
grant execute on function public.set_inventory_lot_quantity(uuid, numeric, boolean) to authenticated;

-- Preserve the ledger history while clearing any residue that predates the
-- invariant. The adjustment itself is the audit record for the repair.
insert into public.inventory_events(lot, quantity_delta, reason, note)
select id, -remaining_qty, 'adjust', 'Automatically cleared unit-conversion residue'
from public.inventory_lots
where remaining_qty > 0 and remaining_qty <= 0.000001;
