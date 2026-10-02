#!/bin/sh
# Only inside the disposable container. Same shopping lock for scopes, receipt and undo.
set -eu
psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$ declare email text; u uuid; begin
 if to_regclass('isolated_test.marker') is null then raise exception 'Isolated database required'; end if;
 select (regexp_match(pg_get_functiondef('public.is_app_owner()'::regprocedure), $re$email = '([^']+)'$re$))[1] into strict email;
 insert into auth.users(id,email,email_confirmed_at) values('98380000-0000-0000-0000-000000000001',email,now());
 insert into auth.sessions(id,user_id) values('98380000-0000-0000-0000-000000000011','98380000-0000-0000-0000-000000000001');
 select id into strict u from public.measure_conversions where short_name='ct';
 insert into public.base_foods(id,name,measure_style,display_unit) values('98380000-0000-0000-0000-000000000020','Concurrent yogurt','discrete',u);
 insert into public.products(id,food,name,package_qty_base,package_unit,serving_qty_base) values('98380000-0000-0000-0000-000000000021','98380000-0000-0000-0000-000000000020','Concurrent yogurt',1,u,1);
 insert into public.inventory_lots(product,initial_qty,remaining_qty,acquisition_type,out_of_pocket_cost,paid_by,cost_source,total_cost,price_as_of) values('98380000-0000-0000-0000-000000000021',2,2,'gift',0,'Fixture','Synthetic gift',0,current_date);
 for i in 0..4 loop insert into public.meal_plans(product,consume_from_inventory,intent,plan_date,daypart) values('98380000-0000-0000-0000-000000000021',true,'consume',current_date+i,'lunch'); end loop;
end $$;
SQL
claims='{"role":"authenticated","sub":"98380000-0000-0000-0000-000000000001","session_id":"98380000-0000-0000-0000-000000000011"}'
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

pair 'select public.rebuild_shopping_from_plan();' 'select public.rebuild_shopping_from_plan();' success
item=$(psql -U postgres -Atc "select id from public.shopping_items where generated_product='98380000-0000-0000-0000-000000000021'")
payload='{"productId":"98380000-0000-0000-0000-000000000021","quantity":3,"unit":"ct","totalPrice":3}'
pair "select public.receive_shopping_item('98380000-0000-0000-0000-000000000040','$item','$payload');" 'select public.rebuild_shopping_from_plan();' success
psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$ begin
 if (select count(*) from public.shopping_items where generated_product='98380000-0000-0000-0000-000000000021')<>1 or exists(select 1 from public.shopping_items where generated_product='98380000-0000-0000-0000-000000000021' and generated_active) then raise exception 'Concurrent receipt/rebuild duplicated or failed to satisfy scope'; end if;
end $$;
SQL
lot=$(psql -U postgres -Atc "select lot from public.shopping_items where id='$item'")
pair 'select public.rebuild_shopping_from_plan();' "select public.undo_inventory_receipt('98380000-0000-0000-0000-000000000041','$lot');" success
psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$ begin
 if (select count(*) from public.shopping_items where generated_product='98380000-0000-0000-0000-000000000021')<>1 or not exists(select 1 from public.shopping_items where generated_product='98380000-0000-0000-0000-000000000021' and generated_active and generated_shortage_base=3 and lot is null and qty_needed=3) then raise exception 'Concurrent undo/rebuild lost original shortage'; end if;
end $$;
SQL
echo 'PASS: concurrent grocery rebuild, matching receipt and undo retain one product scope'
