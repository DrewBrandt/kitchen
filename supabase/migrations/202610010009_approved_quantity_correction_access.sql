-- Explicitly approved: authenticated calls remain restricted by is_app_owner().
grant execute on function public.correct_consumed_quantity(uuid,uuid,numeric,numeric) to authenticated;
