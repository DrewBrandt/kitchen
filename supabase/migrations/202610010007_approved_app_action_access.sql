-- Approved by the owner on 2026-10-01 after review of these exact ten signatures.
-- Owner/live-session guards remain in each function; internal helpers and the request ledger remain private.
grant execute on function public.log_manual_consumption(text,text,timestamptz,text,jsonb,jsonb,jsonb,text,numeric,numeric,text,boolean,text,date,uuid,text) to authenticated;
grant execute on function public.consume_product_purchase(uuid,numeric,numeric,text,text,numeric,numeric,text,boolean,text,date,uuid,text,timestamptz,text,text,text) to authenticated;
grant execute on function public.gpt_add_grocery_lots(jsonb,text,uuid) to authenticated;
grant execute on function public.consume_inventory_lot(uuid,uuid,numeric,timestamptz) to authenticated;
grant execute on function public.consume_prepared_lot(uuid,uuid,numeric,timestamptz) to authenticated;
grant execute on function public.consume_planned_meals(uuid,uuid[],numeric[],timestamptz) to authenticated;
grant execute on function public.prepare_recipe(uuid,uuid,numeric,numeric,text,uuid,numeric,timestamptz) to authenticated;
grant execute on function public.prepare_recipe(uuid,jsonb,uuid,numeric,numeric,text,uuid,numeric,timestamptz) to authenticated;
grant execute on function public.cook_recipes(uuid,uuid[]) to authenticated;
grant execute on function public.set_inventory_lot_quantity(uuid,uuid,numeric,boolean) to authenticated;
