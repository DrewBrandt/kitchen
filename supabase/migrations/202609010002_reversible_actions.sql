-- Undo, as compensating events rather than deletes.
--
-- inventory_lots.remaining_qty is a cache that refresh_inventory_lot() recomputes
-- as initial_qty + sum(quantity_delta) over events where voided_at is null. So
-- marking an event void IS the reversal: the trigger restores the lot for us and
-- the ledger keeps the whole story, forward action and undo alike.
--
-- Nothing here deletes a row from inventory_events, food_logs, or preps.

-- Removing a log entry, and undoing an eat, are the same operation: the log stops
-- counting and whatever inventory it consumed comes back.
create function public.void_food_log(p_food_log uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  log_row public.food_logs%rowtype;
begin
  if not public.is_app_owner() then
    raise exception 'Only the app owner may void food logs' using errcode = '42501';
  end if;

  select * into log_row from public.food_logs where id = p_food_log for update;
  if not found then raise exception 'Food log entry does not exist'; end if;
  if log_row.voided_at is not null then return; end if;

  update public.food_logs set voided_at = now() where id = p_food_log;

  -- Giving the inventory back is the whole point; a bare log void would leave the
  -- servings deducted forever.
  update public.inventory_events
  set voided_at = now()
  where food_log = p_food_log
    and voided_at is null;
end;
$$;

-- The undo of "remove log entry": the entry counts again and its deductions
-- reapply. Fails loudly if reapplying would overdraw a lot, which can happen if
-- the freed stock was spent elsewhere before the undo.
create function public.restore_food_log(p_food_log uuid)
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

  update public.food_logs set voided_at = null where id = p_food_log;

  update public.inventory_events
  set voided_at = null
  where food_log = p_food_log
    and voided_at is not null;
end;
$$;

-- The undo of a discard or a manual lot adjustment. Scoped to the reasons the
-- lot-details panel writes, so it can never be aimed at an 'eaten' or 'prep' row.
create function public.undo_inventory_adjustment(p_event uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  event_row public.inventory_events%rowtype;
begin
  if not public.is_app_owner() then
    raise exception 'Only the app owner may adjust inventory' using errcode = '42501';
  end if;

  select * into event_row from public.inventory_events where id = p_event for update;
  if not found then raise exception 'Inventory event does not exist'; end if;
  if event_row.reason not in ('waste', 'adjust') then
    raise exception 'Only a discard or adjustment can be undone this way';
  end if;
  if event_row.voided_at is not null then return; end if;

  update public.inventory_events set voided_at = now() where id = p_event;
end;
$$;

-- The undo of a cook: the ingredients go back and the batch it produced stops
-- existing. Refused once anything has been taken from that batch, because the
-- servings eaten cannot be un-eaten by giving the ingredients back.
create function public.undo_prep(p_prep uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  prep_row public.preps%rowtype;
  produced public.inventory_lots%rowtype;
begin
  if not public.is_app_owner() then
    raise exception 'Only the app owner may undo a cook' using errcode = '42501';
  end if;

  select * into prep_row from public.preps where id = p_prep for update;
  if not found then raise exception 'Preparation does not exist'; end if;
  if prep_row.voided_at is not null then return; end if;

  select * into produced from public.inventory_lots where prep = p_prep for update;

  if produced.id is not null and exists (
    select 1 from public.inventory_events
    where lot = produced.id and voided_at is null
  ) then
    raise exception 'This batch has already been eaten from and can no longer be undone';
  end if;

  -- Zero the produced batch with a compensating event rather than deleting the lot.
  if produced.id is not null and produced.remaining_qty > 0 then
    insert into public.inventory_events(lot, quantity_delta, reason, note)
    values (produced.id, -produced.remaining_qty, 'adjust', 'Cook undone');
  end if;

  -- Hand the ingredients back.
  update public.inventory_events
  set voided_at = now()
  where prep = p_prep
    and reason = 'prep'
    and voided_at is null;

  update public.preps set voided_at = now() where id = p_prep;
end;
$$;

revoke all on function public.void_food_log(uuid) from public, anon;
grant execute on function public.void_food_log(uuid) to authenticated;
revoke all on function public.restore_food_log(uuid) from public, anon;
grant execute on function public.restore_food_log(uuid) to authenticated;
revoke all on function public.undo_inventory_adjustment(uuid) from public, anon;
grant execute on function public.undo_inventory_adjustment(uuid) to authenticated;
revoke all on function public.undo_prep(uuid) from public, anon;
grant execute on function public.undo_prep(uuid) to authenticated;

-- Discarding needs to hand back the id of the event it wrote, so the toast has
-- something to aim undo at. Returning void left the caller with nothing to hold.
drop function public.set_inventory_lot_quantity(uuid, numeric, boolean);

create function public.set_inventory_lot_quantity(
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
  quantity_change numeric;
  new_event uuid;
begin
  if not public.is_app_owner() then
    raise exception 'Only the app owner may adjust inventory' using errcode = '42501';
  end if;
  if p_remaining < 0 then raise exception 'Remaining quantity cannot be negative'; end if;

  select * into lot_row from public.inventory_lots where id = p_lot for update;
  if not found then raise exception 'Inventory lot does not exist'; end if;
  quantity_change := p_remaining - lot_row.remaining_qty;
  if quantity_change = 0 then return null; end if;
  if p_discard and p_remaining <> 0 then raise exception 'Discarding a lot must set it to zero'; end if;

  insert into public.inventory_events(lot, quantity_delta, reason, note)
  values (p_lot, quantity_change, (case when p_discard then 'waste' else 'adjust' end)::public.inventory_event_reason, case when p_discard then 'Discarded from lot details' else 'Adjusted from lot details' end)
  returning id into new_event;

  return new_event;
end;
$$;

revoke all on function public.set_inventory_lot_quantity(uuid, numeric, boolean) from public, anon;
grant execute on function public.set_inventory_lot_quantity(uuid, numeric, boolean) to authenticated;
