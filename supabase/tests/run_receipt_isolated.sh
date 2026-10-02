#!/bin/sh
# Requires Docker with cached postgres:17 and Python 3. No live DB or Supabase CLI.
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
name="pantry-receipt-test-$$"
created=no
cleanup() { if [ "$created" = yes ]; then docker rm -f "$name" >/dev/null; fi; }
trap cleanup EXIT INT TERM
docker image inspect postgres:17 >/dev/null
docker run -d --pull=never --name "$name" --network none -e POSTGRES_HOST_AUTH_METHOD=trust postgres:17 >/dev/null
created=yes
attempt=0
until docker exec "$name" pg_isready -U postgres >/dev/null; do
  attempt=$((attempt+1)); [ "$attempt" -lt 30 ] || exit 1; sleep 1
done
sql() { docker exec -i "$name" psql -U postgres -v ON_ERROR_STOP=1 --single-transaction; }
sql < "$repo/supabase/tests/isolated_bootstrap.sql" >/dev/null
for migration in "$repo"/supabase/migrations/*.sql; do
  case "$(basename "$migration")" in
    202609020009_audit_and_repair_history.sql)
      python3 "$repo/supabase/tests/isolated_history_schema.py" "$migration" | sql >/dev/null ;;
    202609020019_guard_preview_nutrient_cast.sql)
      # 018 already contains this exact guard on clean installs; 019 repairs older deployments.
      sql <<'SQL'
do $$ begin
  if position('then nutrient.value::numeric < 0' in pg_get_functiondef('public.gpt_preview_daily_nutrition(date,jsonb)'::regprocedure))=0 then
    raise exception 'Clean-install nutrient guard missing';
  end if;
end $$;
SQL
      ;;
    202610010013_atomic_owner_creation.sql)
      sql <<'SQL'
create table isolated_test.gpt_before as
select oid,pg_get_functiondef(oid) definition,proacl from pg_proc
where oid in ('public.gpt_save_plan(text,date,jsonb)'::regprocedure,'public.gpt_save_recipe(jsonb)'::regprocedure,'public.is_app_owner()'::regprocedure);
SQL
      sql < "$migration" >/dev/null
      sql <<'SQL'
do $$ begin
if exists(select 1 from isolated_test.gpt_before b join pg_proc p using(oid)
where b.definition is distinct from pg_get_functiondef(p.oid) or b.proacl is distinct from p.proacl)
then raise exception 'Existing GPT/owner function or ACL changed'; end if;
end $$;
SQL
      ;;
    202610010014_allow_future_food_log_undo.sql)
      sql <<'SQL'
create table isolated_test.undo_constraints_before as
select oid,pg_get_constraintdef(oid) definition from pg_constraint
where conrelid='public.food_logs'::regclass and conname<>'food_logs_check';
create table isolated_test.undo_functions_before as
select oid,pg_get_functiondef(oid) definition,proacl from pg_proc
where pronamespace='public'::regnamespace and prokind='f';
create table isolated_test.undo_table_acl_before as
select oid,relacl from pg_class where relnamespace='public'::regnamespace;
SQL
      sql < "$migration" >/dev/null
      sql <<'SQL'
do $$ begin
if exists(select 1 from pg_constraint where conrelid='public.food_logs'::regclass and conname='food_logs_check')
  or exists(select 1 from isolated_test.undo_constraints_before b left join pg_constraint c using(oid)
    where b.definition is distinct from pg_get_constraintdef(c.oid))
  or exists(select 1 from isolated_test.undo_functions_before b left join pg_proc p using(oid)
    where b.definition is distinct from pg_get_functiondef(p.oid) or b.proacl is distinct from p.proacl)
  or exists(select 1 from isolated_test.undo_table_acl_before b left join pg_class c using(oid)
    where c.oid is null or b.relacl is distinct from c.relacl)
then raise exception 'Undo migration changed more than the single chronology constraint'; end if;
end $$;
SQL
      ;;
    202610010015_preserve_recipe_post_updates.sql)
      sql <<'SQL'
create table isolated_test.post_functions_before as
select oid,pg_get_functiondef(oid) definition,proacl,prosecdef,proconfig from pg_proc
where pronamespace='public'::regnamespace and prokind='f';
SQL
      sql < "$migration" >/dev/null
      sql <<'SQL'
do $$ begin
if exists(select 1 from isolated_test.post_functions_before b left join pg_proc p using(oid)
 where p.oid is null or b.proacl is distinct from p.proacl or b.prosecdef is distinct from p.prosecdef
 or b.proconfig is distinct from p.proconfig
 or (p.oid<>'public.gpt_save_recipe(jsonb)'::regprocedure and b.definition is distinct from pg_get_functiondef(p.oid)))
then raise exception 'POST migration altered other functions, permissions or security settings'; end if;
end $$;
SQL
      ;;
    202610010016_planned_pantry_groceries.sql)
      sql <<'SQL'
create table isolated_test.grocery_functions_before as
select oid,pg_get_functiondef(oid) definition,proacl,prosecdef,proconfig from pg_proc
where pronamespace='public'::regnamespace and prokind='f';
create table isolated_test.grocery_rows_before as select id,to_jsonb(s) value from public.shopping_items s;
SQL
      sql < "$migration" >/dev/null
      sql <<'SQL'
do $$ begin
if exists(select 1 from isolated_test.grocery_functions_before b left join pg_proc p using(oid)
 where p.oid is null or b.proacl is distinct from p.proacl or b.prosecdef is distinct from p.prosecdef or b.proconfig is distinct from p.proconfig
 or (p.oid not in ('public.rebuild_shopping_from_plan(date,date)'::regprocedure,'public.receive_shopping_item(uuid,uuid,jsonb)'::regprocedure,'public.undo_inventory_receipt(uuid,uuid)'::regprocedure) and b.definition is distinct from pg_get_functiondef(p.oid)))
 then raise exception 'Grocery migration changed unrelated functions or existing permissions'; end if;
if exists(select 1 from isolated_test.grocery_rows_before b left join public.shopping_items s using(id) where b.value is distinct from (to_jsonb(s)-'generated_product') or s.generated_product is not null)
 then raise exception 'Grocery migration rewrote historical shopping rows'; end if;
end $$;
SQL
      ;;
    *) sql < "$migration" >/dev/null ;;
  esac
done
docker exec -i "$name" psql -U postgres -v ON_ERROR_STOP=1 < "$repo/supabase/tests/receipt_lifecycle.sql"
docker exec -i "$name" psql -U postgres -v ON_ERROR_STOP=1 < "$repo/supabase/tests/receipt_regressions.sql"
docker exec -i "$name" sh < "$repo/supabase/tests/receipt_concurrency.sh"
docker exec -i "$name" psql -U postgres -v ON_ERROR_STOP=1 < "$repo/supabase/tests/recipe_edit.sql"

docker exec -i "$name" psql -U postgres -v ON_ERROR_STOP=1 < "$repo/supabase/tests/owner_creation.sql"
docker exec -i "$name" sh < "$repo/supabase/tests/owner_creation_concurrency.sh"
docker exec -i "$name" psql -U postgres -v ON_ERROR_STOP=1 < "$repo/supabase/tests/grouped_workflow.sql"

docker exec -i "$name" psql -U postgres -v ON_ERROR_STOP=1 < "$repo/supabase/tests/future_food_log_undo.sql"

docker exec -i "$name" psql -U postgres -v ON_ERROR_STOP=1 < "$repo/supabase/tests/multi_dish_plan.sql"
docker exec -i "$name" psql -U postgres -v ON_ERROR_STOP=1 < "$repo/supabase/tests/recipe_post_preservation.sql"
docker exec -i "$name" sh < "$repo/supabase/tests/recipe_post_concurrency.sh"

docker exec -i "$name" psql -U postgres -v ON_ERROR_STOP=1 < "$repo/supabase/tests/grouped_post_metadata.sql"

docker exec -i "$name" psql -U postgres -v ON_ERROR_STOP=1 < "$repo/supabase/tests/grocery_demand.sql"

docker exec -i "$name" sh < "$repo/supabase/tests/grocery_demand_concurrency.sh"

echo 'PASS: isolated PostgreSQL 17 receipt lifecycle (synthetic auth, actual roles)'
