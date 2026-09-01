create or replace function public.set_inventory_lot_quantity(
  p_lot uuid,
  p_remaining numeric,
  p_discard boolean default false
)
returns void
language plpgsql
set search_path = ''
as $$
declare
  lot_row public.inventory_lots%rowtype;
  quantity_change numeric;
begin
  if not public.is_app_owner() then
    raise exception 'Only the app owner may adjust inventory' using errcode = '42501';
  end if;
  if p_remaining < 0 then raise exception 'Remaining quantity cannot be negative'; end if;

  select * into lot_row from public.inventory_lots where id = p_lot for update;
  if not found then raise exception 'Inventory lot does not exist'; end if;
  quantity_change := p_remaining - lot_row.remaining_qty;
  if quantity_change = 0 then return; end if;
  if p_discard and p_remaining <> 0 then raise exception 'Discarding a lot must set it to zero'; end if;

  insert into public.inventory_events(lot, quantity_delta, reason, note)
  values (
    p_lot,
    quantity_change,
    (case when p_discard then 'waste' else 'adjust' end)::public.inventory_event_reason,
    case when p_discard then 'Discarded from lot details' else 'Adjusted from lot details' end
  );
end;
$$;

revoke all on function public.set_inventory_lot_quantity(uuid, numeric, boolean) from public, anon;
grant execute on function public.set_inventory_lot_quantity(uuid, numeric, boolean) to authenticated;
