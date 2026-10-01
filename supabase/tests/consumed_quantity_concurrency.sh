#!/bin/sh
# Run only inside the disposable isolated PostgreSQL container as postgres.
set -eu
psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$ begin if to_regclass('isolated_test.marker') is null then raise exception 'Isolated database required'; end if; end $$;
grant execute on function public.correct_consumed_quantity(uuid,uuid,numeric,numeric) to authenticated;
do $$ declare owner_email text; unit_id uuid; begin
  select (regexp_match(pg_get_functiondef('public.is_app_owner()'::regprocedure), $re$email = '([^']+)'$re$))[1] into strict owner_email;
  insert into auth.users(id,email,email_confirmed_at) values('99100000-0000-0000-0000-000000000001',owner_email,now());
  insert into auth.sessions(id,user_id) values('99100000-0000-0000-0000-000000000011','99100000-0000-0000-0000-000000000001');
  select id into strict unit_id from public.measure_conversions where short_name='g';
  insert into public.base_foods(id,name,measure_style,display_unit) values('99100000-0000-0000-0000-000000000020','Concurrent QA','weight',unit_id);
  insert into public.products(id,food,name,package_qty_base,package_unit,serving_qty_base) values('99100000-0000-0000-0000-000000000021','99100000-0000-0000-0000-000000000020','Concurrent QA',1000,unit_id,100);
  insert into public.inventory_lots(id,product,initial_qty,remaining_qty,total_cost,location,acquisition_type,out_of_pocket_cost,paid_by,cost_source) values('99100000-0000-0000-0000-000000000022','99100000-0000-0000-0000-000000000021',1000,1000,null,'pantry','gift',0,'gift','Unknown value');
  insert into public.food_logs(id,label,kind,product,servings,occurred_at) values
    ('99100000-0000-0000-0000-000000000031','Concurrent first','inventory','99100000-0000-0000-0000-000000000021',2,'2026-09-04T12:00:00Z'),
    ('99100000-0000-0000-0000-000000000032','Concurrent second','inventory','99100000-0000-0000-0000-000000000021',2,'2026-09-04T12:00:00Z');
  insert into public.inventory_events(lot,quantity_delta,reason,food_log) values
    ('99100000-0000-0000-0000-000000000022',-200,'eaten','99100000-0000-0000-0000-000000000031'),
    ('99100000-0000-0000-0000-000000000022',-200,'eaten','99100000-0000-0000-0000-000000000032');
end $$;
SQL
claims='{"role":"authenticated","sub":"99100000-0000-0000-0000-000000000001","session_id":"99100000-0000-0000-0000-000000000011"}'
pair() {
  log=$1; request_a=$2; request_b=$3; amount_b=$4; expect_failure=$5
  psql -U postgres -v ON_ERROR_STOP=1 -At > /tmp/correction-a.out 2>&1 <<SQL &
begin;
set application_name='correction-a';
set local role authenticated;
set local request.jwt.claims='$claims';
select public.correct_consumed_quantity('$request_a','$log',200,100)->>'id';
select pg_sleep(3);
commit;
SQL
  first=$!
  # Wait until the first correction holds its locks, without guessing launch order.
  ready=0
  for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    active=$(psql -U postgres -Atc "select count(*) from pg_stat_activity where application_name='correction-a' and wait_event='PgSleep'")
    if [ "$active" = 1 ]; then ready=1; break; fi
    sleep 0.1
  done
  [ "$ready" = 1 ] || { echo 'First transaction did not reach lock-holding checkpoint'; exit 1; }
  psql -U postgres -v ON_ERROR_STOP=1 -At > /tmp/correction-b.out 2>&1 <<SQL &
begin;
set application_name='correction-b';
set local role authenticated;
set local request.jwt.claims='$claims';
select public.correct_consumed_quantity('$request_b','$log',200,$amount_b)->>'id';
commit;
SQL
  second=$!
  blocked=0
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    active=$(psql -U postgres -Atc "select count(*) from pg_stat_activity where application_name='correction-b' and wait_event_type='Lock'")
    if [ "$active" = 1 ]; then blocked=1; break; fi
    sleep 0.1
  done
  [ "$blocked" = 1 ] || { echo 'Second transaction did not demonstrate lock contention'; exit 1; }
  wait "$first"
  if wait "$second"; then
    [ "$expect_failure" = 0 ] || { echo 'Competing stale correction unexpectedly succeeded'; exit 1; }
    result_a=$(sed -n '/^[0-9a-f-]\{36\}$/p' /tmp/correction-a.out)
    result_b=$(sed -n '/^[0-9a-f-]\{36\}$/p' /tmp/correction-b.out)
    [ -n "$result_a" ] && [ "$result_a" = "$result_b" ] || { echo 'Concurrent replay result mismatch'; exit 1; }
  else
    [ "$expect_failure" = 1 ] && grep -q 'removed or replaced' /tmp/correction-b.out || { cat /tmp/correction-b.out; exit 1; }
  fi
}
pair 99100000-0000-0000-0000-000000000031 99100000-0000-0000-0000-000000000041 99100000-0000-0000-0000-000000000041 100 0
pair 99100000-0000-0000-0000-000000000032 99100000-0000-0000-0000-000000000042 99100000-0000-0000-0000-000000000043 50 1
psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$ begin
  if (select remaining_qty from public.inventory_lots where id='99100000-0000-0000-0000-000000000022')<>800 then raise exception 'Concurrent stock mismatch'; end if;
  if (select count(*) from public.food_log_replacements where original_log in ('99100000-0000-0000-0000-000000000031','99100000-0000-0000-0000-000000000032'))<>2 then raise exception 'Duplicate replacement'; end if;
  if exists(select 1 from public.gpt_action_requests where request_id='99100000-0000-0000-0000-000000000043') then raise exception 'Rejected transaction left a request record'; end if;
end $$;
revoke all on function public.correct_consumed_quantity(uuid,uuid,numeric,numeric) from authenticated;
SQL
echo 'PASS: concurrent identical retries serialize to one result; competing requests reject stale original; inventory conserved.'
