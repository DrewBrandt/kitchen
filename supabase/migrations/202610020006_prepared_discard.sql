-- Partial waste uses the existing adjustment ledger, costing and reversal.
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
  if p_remaining is null or p_remaining::text in ('NaN', 'Infinity', '-Infinity') or p_remaining < 0 then raise exception 'Remaining quantity cannot be negative'; end if;

  normalized_remaining := case when p_remaining <= 0.000001 then 0 else p_remaining end;
  select * into lot_row from public.inventory_lots where id = p_lot for update;
  if not found then raise exception 'Inventory lot does not exist'; end if;
  quantity_change := normalized_remaining - lot_row.remaining_qty;
  if quantity_change = 0 then return null; end if;
  if p_discard and quantity_change > 0 then raise exception 'Discard must reduce stock'; end if;

  insert into public.inventory_events(lot, quantity_delta, reason, note)
  values (p_lot, quantity_change, (case when p_discard then 'waste' else 'adjust' end)::public.inventory_event_reason, case when p_discard then 'Discarded from lot details' else 'Adjusted from lot details' end)
  returning id into new_event;

  return new_event;
end;
$$;


-- Migrate the existing owner-only retry RPC; retain its authenticated access.
drop function public.set_inventory_lot_quantity(uuid, uuid, numeric, boolean);
create function public.set_inventory_lot_quantity(p_request_id uuid, p_lot uuid, p_remaining numeric, p_discard boolean default false, p_note text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare prior jsonb; result uuid;
begin
  if not public.is_app_owner() then raise exception 'Unauthorized' using errcode = '42501'; end if;
  prior := public.claim_mutation_payload(p_request_id, 'set_inventory_lot_quantity', jsonb_build_object('p_lot', p_lot, 'p_remaining', p_remaining, 'p_discard', p_discard, 'p_note', nullif(btrim(p_note), '')));
  if prior is not null then return (prior #>> '{}')::uuid; end if;
  result := public.set_inventory_lot_quantity(p_lot, p_remaining, p_discard);
  if result is not null and nullif(btrim(p_note), '') is not null then
    update public.inventory_events set note=btrim(p_note) where id=result;
  end if;
  perform public.gpt_complete_request(p_request_id, coalesce(to_jsonb(result), 'null'::jsonb));
  return result;
end;
$$;
revoke all on function public.set_inventory_lot_quantity(uuid, uuid, numeric, boolean, text) from public, anon, authenticated, service_role;

grant execute on function public.set_inventory_lot_quantity(uuid, uuid, numeric, boolean, text) to authenticated;
