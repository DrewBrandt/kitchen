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
    *) sql < "$migration" >/dev/null ;;
  esac
done
docker exec -i "$name" psql -U postgres -v ON_ERROR_STOP=1 < "$repo/supabase/tests/receipt_lifecycle.sql"
docker exec -i "$name" psql -U postgres -v ON_ERROR_STOP=1 < "$repo/supabase/tests/receipt_regressions.sql"
docker exec -i "$name" sh < "$repo/supabase/tests/receipt_concurrency.sh"
docker exec -i "$name" psql -U postgres -v ON_ERROR_STOP=1 < "$repo/supabase/tests/recipe_edit.sql"

docker exec -i "$name" psql -U postgres -v ON_ERROR_STOP=1 < "$repo/supabase/tests/owner_creation.sql"
docker exec -i "$name" sh < "$repo/supabase/tests/owner_creation_concurrency.sh"

echo 'PASS: isolated PostgreSQL 17 receipt lifecycle (synthetic auth, actual roles)'
