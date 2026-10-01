-- Exact two RPC grants explicitly approved by the owner on 2026-10-01.
-- All action-time owner/live-session checks remain enforced inside the functions.
grant execute on function public.receive_shopping_item(uuid,uuid,jsonb) to authenticated;
grant execute on function public.undo_inventory_receipt(uuid,uuid) to authenticated;
