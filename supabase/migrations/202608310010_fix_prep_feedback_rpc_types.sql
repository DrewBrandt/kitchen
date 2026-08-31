drop function public.save_prep_feedback(uuid, smallint, smallint, integer);

create function public.save_prep_feedback(
  p_prep uuid,
  p_ease integer default 0,
  p_taste integer default 0,
  p_actual_minutes integer default 0
)
returns void
language plpgsql
set search_path = ''
as $$
begin
  if not public.is_app_owner() then
    raise exception 'Only the app owner may rate preparations' using errcode = '42501';
  end if;
  if p_ease not between 0 and 5 or p_taste not between 0 and 5 or p_actual_minutes < 0 then
    raise exception 'Ratings must be from 0 to 5 and minutes cannot be negative';
  end if;

  update public.preps
  set ease_rating = p_ease,
      taste_rating = p_taste,
      actual_minutes = p_actual_minutes
  where id = p_prep and voided_at is null;

  if not found then raise exception 'Preparation does not exist'; end if;
end;
$$;

revoke all on function public.save_prep_feedback(uuid, integer, integer, integer) from public, anon;
grant execute on function public.save_prep_feedback(uuid, integer, integer, integer) to authenticated;
