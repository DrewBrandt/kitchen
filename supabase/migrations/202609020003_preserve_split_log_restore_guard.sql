-- The meal-lifecycle replacement of restore_food_log must preserve the earlier
-- invariant that a superseded aggregate cannot be restored over its itemized
-- replacements. Keep that guard while also restoring the linked meal status.
create or replace function public.restore_food_log(p_food_log uuid)
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
  if exists (
    select 1
    from public.food_log_replacements replacement
    where replacement.original_log = p_food_log
  ) then
    raise exception 'This food log was split into individual items and cannot be restored';
  end if;

  update public.food_logs set voided_at = null where id = p_food_log;
  update public.inventory_events set voided_at = null
  where food_log = p_food_log and voided_at is not null;
  update public.planned_consumptions set status = 'fulfilled'
  where food_log = p_food_log and status = 'planned';
end;
$$;
