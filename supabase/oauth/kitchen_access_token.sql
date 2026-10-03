-- Approval-only template, deliberately outside automatic migrations.
-- Replace both UUID placeholders with reviewed public identifiers before installation.
begin;
create schema kitchen_oauth;
revoke all on schema kitchen_oauth from public, anon, authenticated;
grant usage on schema kitchen_oauth to supabase_auth_admin;
create function kitchen_oauth.custom_access_token(event jsonb)
returns jsonb
language plpgsql stable security invoker
set search_path = ''
as $$
declare
  owner_id constant uuid := '__OWNER_UUID__';
  client_id constant uuid := '__CLIENT_UUID__';
  claims jsonb := event->'claims';
  scopes text[];
begin
  -- No table reads, network, logging, or mutation of ordinary login/refresh claims.
  if claims->>'client_id' is distinct from client_id::text then
    return jsonb_build_object('claims', claims);
  end if;
  scopes := regexp_split_to_array(trim(coalesce(claims->>'scope', '')), ' +');
  if event->>'user_id' is distinct from owner_id::text
    or claims->>'sub' is distinct from owner_id::text
    or claims->>'iss' is distinct from 'https://xaetuqdtnolzspfvqvja.supabase.co/auth/v1'
    or claims->>'role' is distinct from 'authenticated'
    or claims->'is_anonymous' is distinct from 'false'::jsonb
    or coalesce(claims->>'session_id', '') !~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
    or claims->>'session_id' = '00000000-0000-0000-0000-000000000000'
    or not ('openid' = any(scopes))
    or not (scopes <@ array['openid', 'email', 'profile', 'phone']) then
    return jsonb_build_object('error', jsonb_build_object('http_code', 403,
      'message', 'Kitchen OAuth requires its configured owner and identity scopes'));
  end if;
  return jsonb_build_object('claims', jsonb_set(claims, '{aud}',
    '"https://xaetuqdtnolzspfvqvja.supabase.co/functions/v1/kitchen-mcp/mcp"'::jsonb));
end;
$$;
revoke all on function kitchen_oauth.custom_access_token(jsonb) from public, anon, authenticated;
grant execute on function kitchen_oauth.custom_access_token(jsonb) to supabase_auth_admin;
commit;
