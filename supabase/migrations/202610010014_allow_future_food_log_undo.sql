-- occurred_at is an owner-entered event time (possibly date-only or mistaken).
-- voided_at records the actual undo action, which may precede that event time.
-- Fail closed if this constraint ever acquires another invariant.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.food_logs'::regclass
      and conname = 'food_logs_check' and contype = 'c'
      and pg_get_constraintdef(oid) = 'CHECK (((voided_at IS NULL) OR (voided_at >= occurred_at)))'
  ) then
    raise exception 'Unexpected food_logs_check definition; review before removing';
  end if;
  alter table public.food_logs drop constraint food_logs_check;
end;
$$;
