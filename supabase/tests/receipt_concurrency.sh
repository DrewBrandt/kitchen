#!/bin/sh
# Run inside the disposable PostgreSQL container, never against a linked database.
set -eu
psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$ begin if to_regclass('isolated_test.marker') is null then raise exception 'Isolated database required'; end if; end $$;
do $$ declare owner_email text; u uuid; begin
  select (regexp_match(pg_get_functiondef('public.is_app_owner()'::regprocedure), $re$email = '([^']+)'$re$))[1] into strict owner_email;
  insert into auth.users(id,email,email_confirmed_at) values('99300000-0000-0000-0000-000000000001',owner_email,now());
  insert into auth.sessions(id,user_id) values('99300000-0000-0000-0000-000000000011','99300000-0000-0000-0000-000000000001');
  select id into strict u from public.measure_conversions where short_name='g';
  insert into public.base_foods(id,name,measure_style,display_unit) values('99300000-0000-0000-0000-000000000020','Concurrent receipt QA','weight',u);
  insert into public.products(id,food,name,package_qty_base,package_unit) values('99300000-0000-0000-0000-000000000021','99300000-0000-0000-0000-000000000020','Concurrent receipt QA',100,u);
  insert into public.shopping_items(id,food,qty_needed,unit) select id,'99300000-0000-0000-0000-000000000020',100,u from unnest(array['99300000-0000-0000-0000-000000000030'::uuid,'99300000-0000-0000-0000-000000000031'::uuid]) id;
end $$;
SQL
claims='{"role":"authenticated","sub":"99300000-0000-0000-0000-000000000001","session_id":"99300000-0000-0000-0000-000000000011"}'
payload='{"productId":"99300000-0000-0000-0000-000000000021","quantity":100,"unit":"g","totalPrice":null,"acquiredAt":"2026-10-01T12:00:00Z"}'
pair() {
  first_sql=$1; second_sql=$2; expected=$3
  psql -U postgres -v ON_ERROR_STOP=1 -At > /tmp/receipt-a.out 2>&1 <<SQL &
begin;
set application_name='receipt-concurrency-a';
set local role authenticated;
set local request.jwt.claims='$claims';
$first_sql
select pg_sleep(3);
commit;
SQL
  first=$!
  ready=0
  for attempt in $(seq 1 40); do
    if [ "$(psql -U postgres -Atc "select count(*) from pg_stat_activity where application_name='receipt-concurrency-a' and wait_event='PgSleep'")" = 1 ]; then ready=1; break; fi
    sleep 0.1
  done
  [ "$ready" = 1 ] || { cat /tmp/receipt-a.out; exit 1; }
  psql -U postgres -v ON_ERROR_STOP=1 -At > /tmp/receipt-b.out 2>&1 <<SQL &
begin;
set application_name='receipt-concurrency-b';
set local role authenticated;
set local request.jwt.claims='$claims';
$second_sql
commit;
SQL
  second=$!
  blocked=0
  for attempt in $(seq 1 20); do
    if [ "$(psql -U postgres -Atc "select count(*) from pg_stat_activity where application_name='receipt-concurrency-b' and wait_event_type='Lock'")" = 1 ]; then blocked=1; break; fi
    sleep 0.1
  done
  [ "$blocked" = 1 ] || { cat /tmp/receipt-b.out; exit 1; }
  wait "$first" || { cat /tmp/receipt-a.out; exit 1; }
  if wait "$second"; then [ "$expected" = success ] || { echo 'Expected dependency rejection'; exit 1; }
  else [ "$expected" = failure ] || { cat /tmp/receipt-b.out; exit 1; }; fi
}
receive="select public.receive_shopping_item('99300000-0000-0000-0000-000000000040','99300000-0000-0000-0000-000000000030','$payload');"
pair "$receive" "$receive" success
pair "select public.receive_shopping_item('99300000-0000-0000-0000-000000000041','99300000-0000-0000-0000-000000000031','$payload');" "select public.receive_shopping_item('99300000-0000-0000-0000-000000000042','99300000-0000-0000-0000-000000000031','$payload');" failure
grep -q 'already has a receipt' /tmp/receipt-b.out
lot=$(psql -U postgres -Atc "select lot from public.shopping_items where id='99300000-0000-0000-0000-000000000030'")
pair "select public.rebuild_shopping_from_plan();" "select public.undo_inventory_receipt('99300000-0000-0000-0000-000000000043','$lot');" success
other_lot=$(psql -U postgres -Atc "select lot from public.shopping_items where id='99300000-0000-0000-0000-000000000031'")
pair "select public.consume_inventory_lot('99300000-0000-0000-0000-000000000044','$other_lot',10,now());" "select public.undo_inventory_receipt('99300000-0000-0000-0000-000000000045','$other_lot');" failure
grep -q 'stock has been used or adjusted' /tmp/receipt-b.out
psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$ begin
  if (select count(*) from public.inventory_lots where product='99300000-0000-0000-0000-000000000021')<>2 then raise exception 'Concurrent duplicate receipt'; end if;
  if (select sum(remaining_qty) from public.inventory_lots where product='99300000-0000-0000-0000-000000000021')<>90 then raise exception 'Unexpected final stock'; end if;
end $$;
SQL
echo 'PASS: concurrent same-request replay, distinct receipt rejection, rebuild/undo serialization, consumption/undo dependency'
