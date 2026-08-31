create or replace function public.is_app_owner()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(auth.role() = 'service_role', false) or exists (
    select 1
    from auth.users app_user
    join auth.sessions app_session on app_session.user_id = app_user.id
    where app_user.id = auth.uid()
      and app_user.email = 'xdrewbrandtx@gmail.com'
      and app_user.email_confirmed_at is not null
      and app_session.id = case
        when auth.jwt() ->> 'session_id' ~ '^[0-9a-f-]{36}$'
          then (auth.jwt() ->> 'session_id')::uuid
        else null
      end
  );
$$;
