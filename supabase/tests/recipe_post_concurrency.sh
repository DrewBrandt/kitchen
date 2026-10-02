#!/bin/sh
# Runs only inside the disposable container. No live database.
set -eu
psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$ declare u uuid; begin
 if to_regclass('isolated_test.marker') is null then raise exception 'Isolated database required'; end if;
 select id into strict u from public.measure_conversions where short_name='g';
 insert into public.base_foods(id,name,measure_style,display_unit) values('98410000-0000-0000-0000-000000000050','Concurrent POST food','weight',u);
 insert into public.products(id,food,name,package_qty_base,package_unit) values('98410000-0000-0000-0000-000000000060','98410000-0000-0000-0000-000000000050','Concurrent POST product',100,u);
end $$;
create table isolated_test.post_identity(id uuid);
SQL
pair() {
  first_action=$1
  second_action=$2
  psql -U postgres -v ON_ERROR_STOP=1 -At > /tmp/post-save-a.out 2>&1 <<SQL &
begin;
set application_name='post-save-a';
set local role service_role;
set local request.jwt.claims='{"role":"service_role"}';
$first_action
select pg_sleep(3);
commit;
SQL
  first=$!
  ready=0
  for attempt in $(seq 1 40); do
    if [ "$(psql -U postgres -Atc "select count(*) from pg_stat_activity where application_name='post-save-a' and wait_event='PgSleep'")" = 1 ]; then ready=1; break; fi
    sleep 0.1
  done
  [ "$ready" = 1 ] || { cat /tmp/post-save-a.out; exit 1; }
  psql -U postgres -v ON_ERROR_STOP=1 -At > /tmp/post-save-b.out 2>&1 <<SQL &
begin;
set application_name='post-save-b';
set local role service_role;
set local request.jwt.claims='{"role":"service_role"}';
$second_action
commit;
SQL
  second=$!
  blocked=0
  for attempt in $(seq 1 20); do
    if [ "$(psql -U postgres -Atc "select count(*) from pg_stat_activity where application_name='post-save-b' and wait_event_type='Lock'")" = 1 ]; then blocked=1; break; fi
    sleep 0.1
  done
  [ "$blocked" = 1 ] || { cat /tmp/post-save-b.out; exit 1; }
  wait "$first" || { cat /tmp/post-save-a.out; exit 1; }
  wait "$second" || { cat /tmp/post-save-b.out; exit 1; }
  # Both committed calls must return exactly the same object/IDs.
  sed -n '/^{/p' /tmp/post-save-a.out > /tmp/post-save-result-a
  sed -n '/^{/p' /tmp/post-save-b.out > /tmp/post-save-result-b
  cmp /tmp/post-save-result-a /tmp/post-save-result-b
}
pair "select public.gpt_save_recipe('{\"id\":\"98410000-0000-0000-0000-000000000040\",\"name\":\"Concurrent POST recipe\",\"servings\":2,\"ingredients\":[{\"foodId\":\"98410000-0000-0000-0000-000000000050\",\"unit\":\"g\",\"quantity\":10,\"note\":\"Created note\"}]}'); reset role; update public.recipe_ingredients set pinned_product='98410000-0000-0000-0000-000000000060' where recipe='98410000-0000-0000-0000-000000000040'; insert into isolated_test.post_identity select id from public.recipe_ingredients where recipe='98410000-0000-0000-0000-000000000040';" "select public.gpt_save_recipe('{\"id\":\"98410000-0000-0000-0000-000000000040\",\"name\":\"Concurrent POST recipe\",\"servings\":2,\"ingredients\":[{\"foodId\":\"98410000-0000-0000-0000-000000000050\",\"unit\":\"g\",\"quantity\":20}]}');"
psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$ begin
 if (select count(*) from public.recipes where id='98410000-0000-0000-0000-000000000040')<>1 or
  not exists(select 1 from public.recipe_ingredients ri join isolated_test.post_identity e using(id)
    where recipe='98410000-0000-0000-0000-000000000040' and qty=20 and note='Created note' and pinned_product='98410000-0000-0000-0000-000000000060')
 then raise exception 'Concurrent create/update lost identity or metadata'; end if;
end $$;
SQL
pair "select public.gpt_save_recipe('{\"id\":\"98410000-0000-0000-0000-000000000040\",\"name\":\"Concurrent POST recipe\",\"servings\":2,\"ingredients\":[{\"foodId\":\"98410000-0000-0000-0000-000000000050\",\"unit\":\"g\",\"quantity\":30,\"note\":\"Updated note\"}]}');" "select public.gpt_save_recipe('{\"id\":\"98410000-0000-0000-0000-000000000040\",\"name\":\"Concurrent POST recipe\",\"servings\":2,\"ingredients\":[{\"foodId\":\"98410000-0000-0000-0000-000000000050\",\"unit\":\"g\",\"quantity\":40}]}');"
psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$ begin
 if (select count(*) from public.recipe_ingredients where recipe='98410000-0000-0000-0000-000000000040')<>1 or
  not exists(select 1 from public.recipe_ingredients ri join isolated_test.post_identity e using(id)
    where recipe='98410000-0000-0000-0000-000000000040' and qty=40 and note='Updated note' and pinned_product='98410000-0000-0000-0000-000000000060')
 then raise exception 'Concurrent updates lost identity or metadata'; end if;
end $$;
SQL
echo 'PASS: concurrent POST create/update and update/update preserve identity, notes and pins'
