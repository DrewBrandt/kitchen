-- Exercise the actual hook as the actual Auth role, never a JS reimplementation.
set role supabase_auth_admin;
do $$
declare
  claims jsonb := '{"sub":"10000000-0000-4000-8000-000000000001","client_id":"10000000-0000-4000-8000-000000000002","iss":"https://xaetuqdtnolzspfvqvja.supabase.co/auth/v1","aud":"authenticated","role":"authenticated","scope":"openid email profile phone","is_anonymous":false,"session_id":"10000000-0000-4000-8000-000000000003","iat":1790000000,"exp":1800000000,"aal":"aal1","email":"synthetic@example.test","phone":"","user_metadata":{"unchanged":true}}';
  event jsonb;
  actual jsonb;
  change jsonb;
  method text;
begin
  foreach method in array array['oauth_provider/authorization_code','token_refresh'] loop
    event := jsonb_build_object('user_id', claims->'sub', 'authentication_method', method, 'claims', claims);
    actual := kitchen_oauth.custom_access_token(event);
    assert actual = jsonb_build_object('claims', jsonb_set(claims, '{aud}', '"https://xaetuqdtnolzspfvqvja.supabase.co/functions/v1/kitchen-mcp/mcp"')), 'Only aud may change';
  end loop;
  foreach method in array array['oauth','password','token_refresh'] loop
    event := jsonb_build_object('authentication_method', method, 'claims', claims - 'client_id' - 'scope');
    assert kitchen_oauth.custom_access_token(event) = jsonb_build_object('claims',event->'claims'), 'Ordinary claims changed';
  end loop;
  event := jsonb_build_object('claims', claims || '{"client_id":"unrelated-client"}');
  assert kitchen_oauth.custom_access_token(event) = jsonb_build_object('claims',event->'claims'), 'Other client changed';
  for change in select value from jsonb_array_elements('[{"sub":"other"},{"role":"service_role"},{"is_anonymous":true},{"is_anonymous":null},{"session_id":null},{"session_id":"00000000-0000-0000-0000-000000000000"},{"iss":"wrong"},{"scope":"openid write"},{"scope":"email profile"},{"scope":null}]') loop
    event := jsonb_build_object('user_id',claims->'sub','claims',claims || change);
    assert kitchen_oauth.custom_access_token(event)#>>'{error,http_code}' = '403', 'Invalid owner claims accepted';
  end loop;
  event := jsonb_build_object('user_id','wrong-owner','claims',claims);
  assert kitchen_oauth.custom_access_token(event)#>>'{error,http_code}' = '403', 'Wrong event owner accepted';
end $$;
reset role;
do $$ begin
  assert not has_function_privilege('anon','kitchen_oauth.custom_access_token(jsonb)','execute'), 'Anonymous execute granted';
  assert not has_function_privilege('authenticated','kitchen_oauth.custom_access_token(jsonb)','execute'), 'User execute granted';
  assert not has_schema_privilege('anon','kitchen_oauth','usage'), 'Anonymous schema access';
  assert not has_schema_privilege('authenticated','kitchen_oauth','usage'), 'User schema access';
  assert not (select prosecdef from pg_proc where oid='kitchen_oauth.custom_access_token(jsonb)'::regprocedure), 'Must be invoker';
end $$;
select 'PASS: owner issuance/refresh, exact ordinary claims, negative identity/scope cases, ACLs' as result;
