-- Synthetic auth only. No GoTrue service, network, credentials, or production records.
create schema extensions;
create schema auth;
create schema isolated_test;
create table isolated_test.marker(id integer);
create role anon nologin;
create role authenticated nologin;
create role service_role nologin;
create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz);
create table auth.sessions(id uuid primary key,user_id uuid references auth.users);
create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb $$;
create function auth.uid() returns uuid language sql stable as $$ select (auth.jwt()->>'sub')::uuid $$;
create function auth.role() returns text language sql stable as $$ select auth.jwt()->>'role' $$;
grant usage on schema public,auth,extensions to anon,authenticated,service_role;
grant execute on all functions in schema auth to anon,authenticated,service_role;
alter default privileges in schema public grant all on tables to authenticated,service_role;
alter default privileges in schema public grant all on sequences to authenticated,service_role;
