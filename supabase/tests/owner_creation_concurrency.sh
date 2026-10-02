#!/bin/sh
# Executed only inside the disposable PostgreSQL harness.
set -eu
psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$ declare email text; begin
  if to_regclass('isolated_test.marker') is null then raise exception 'Isolated database required'; end if;
  select (regexp_match(pg_get_functiondef('public.is_app_owner()'::regprocedure), $re$email = '([^']+)'$re$))[1] into strict email;
  insert into auth.users(id,email,email_confirmed_at) values('99510000-0000-0000-0000-000000000001',email,now());
  insert into auth.sessions(id,user_id) values('99510000-0000-0000-0000-000000000011','99510000-0000-0000-0000-000000000001');
  insert into public.recipes(id,name) values('99510000-0000-0000-0000-000000000040','Concurrent plan source');
end $$;
SQL
claims='{"role":"authenticated","sub":"99510000-0000-0000-0000-000000000001","session_id":"99510000-0000-0000-0000-000000000011"}'
pair() {
  action=$1
  psql -U postgres -v ON_ERROR_STOP=1 -At > /tmp/owner-create-a.out 2>&1 <<SQL &
begin;
set application_name='owner-create-a';
set local role authenticated;
set local request.jwt.claims='$claims';
$action
select pg_sleep(3);
commit;
SQL
  first=$!
  ready=0
  for attempt in $(seq 1 40); do
    if [ "$(psql -U postgres -Atc "select count(*) from pg_stat_activity where application_name='owner-create-a' and wait_event='PgSleep'")" = 1 ]; then ready=1; break; fi
    sleep 0.1
  done
  [ "$ready" = 1 ] || { cat /tmp/owner-create-a.out; exit 1; }
  psql -U postgres -v ON_ERROR_STOP=1 -At > /tmp/owner-create-b.out 2>&1 <<SQL &
begin;
set application_name='owner-create-b';
set local role authenticated;
set local request.jwt.claims='$claims';
$action
commit;
SQL
  second=$!
  blocked=0
  for attempt in $(seq 1 20); do
    if [ "$(psql -U postgres -Atc "select count(*) from pg_stat_activity where application_name='owner-create-b' and wait_event_type='Lock'")" = 1 ]; then blocked=1; break; fi
    sleep 0.1
  done
  [ "$blocked" = 1 ] || { cat /tmp/owner-create-b.out; exit 1; }
  wait "$first" || { cat /tmp/owner-create-a.out; exit 1; }
  wait "$second" || { cat /tmp/owner-create-b.out; exit 1; }
  # Both committed calls must return exactly the same object/IDs.
  sed -n '/^{/p' /tmp/owner-create-a.out > /tmp/owner-create-result-a
  sed -n '/^{/p' /tmp/owner-create-b.out > /tmp/owner-create-result-b
  cmp /tmp/owner-create-result-a /tmp/owner-create-result-b
}
pair "select public.owner_create_recipe('99510000-0000-0000-0000-000000000020','{\"name\":\"Concurrent created recipe\",\"ingredients\":[]}');"
pair "select public.owner_append_plan('99510000-0000-0000-0000-000000000030','{\"recipe\":\"99510000-0000-0000-0000-000000000040\",\"plan_date\":\"2026-10-02\",\"daypart\":\"dinner\",\"planned_servings\":2}');"
psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$ begin
  if (select count(*) from public.recipes where name='Concurrent created recipe')<>1
    or (select count(*) from public.meal_plans where recipe='99510000-0000-0000-0000-000000000040')<>1
    or (select count(*) from public.planned_consumptions c join public.meal_plans p on p.id=c.meal_plan where p.recipe='99510000-0000-0000-0000-000000000040' and c.servings=2)<>1 then
    raise exception 'Concurrent request duplicated or lost portions';
  end if;
end $$;
SQL
pair "select public.owner_append_plan('99510000-0000-0000-0000-000000000031','{\"plan_date\":\"2026-10-02\",\"daypart\":\"lunch\",\"dishes\":[{\"recipe\":\"99510000-0000-0000-0000-000000000040\",\"scale_factor\":1,\"planned_servings\":1.5},{\"recipe\":\"99510000-0000-0000-0000-000000000040\",\"scale_factor\":2,\"planned_servings\":0.5}]}');"
psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$ begin
 if (select count(*) from public.meal_plans where recipe='99510000-0000-0000-0000-000000000040' and daypart='lunch')<>2
   or (select count(distinct group_id) from public.meal_plans where recipe='99510000-0000-0000-0000-000000000040' and daypart='lunch')<>1
 then raise exception 'Concurrent grouped request duplicated or split the meal'; end if;
end $$;
SQL

echo 'PASS: concurrent owner recipe/plan requests serialize and return identical IDs'
