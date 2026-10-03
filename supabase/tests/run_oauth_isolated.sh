#!/bin/sh
# Synthetic-only Postgres test. No Supabase CLI, project link, or credentials.
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
name="kitchen-oauth-test-$$"
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
sql() { docker exec -i "$name" psql -U postgres -v ON_ERROR_STOP=1; }
sql <<'SQL'
create role anon;
create role authenticated;
create role supabase_auth_admin;
SQL
sed -e 's/__OWNER_UUID__/10000000-0000-4000-8000-000000000001/g' \
    -e 's/__CLIENT_UUID__/10000000-0000-4000-8000-000000000002/g' \
    "$repo/supabase/oauth/kitchen_access_token.sql" | sql
sql < "$repo/supabase/tests/kitchen_oauth.sql"
