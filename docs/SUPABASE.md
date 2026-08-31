# Supabase database

The Pantry database is defined entirely by the SQL migrations in
`supabase/migrations`. Do not create or change production tables manually in
the Supabase dashboard.

## First-time setup

Install the locked workspace dependencies and authenticate the CLI:

```powershell
npm ci
npx supabase login --no-browser --name pantry-codex --agent no
npx supabase link --project-ref xaetuqdtnolzspfvqvja --agent no
```

Paste a temporary Supabase personal access token only when the login command
prompts for it. Never put tokens, database passwords, or secret API keys in a
command, source file, or `.env` file committed to Git.

## Applying changes

Create a new timestamped migration for every database change. Preview and
apply pending migrations with:

```powershell
npx supabase db push --dry-run --agent no
npm run db:push -- --agent no
```

Never edit a migration after it has been applied. Add a new migration instead.

## Verification

The database tests run inside a transaction and roll back all fixture data:

```powershell
npm run db:test -- --agent no
npm run db:lint -- --agent no
npx supabase db advisors --linked --type security --level warn --fail-on warn --agent no
npx supabase db advisors --linked --type performance --level warn --fail-on warn --agent no
```

Generate the client types after the deployed schema passes verification:

```powershell
npx supabase gen types typescript --linked --schema public --agent no |
  Set-Content -LiteralPath src\database.types.ts -Encoding utf8
```

The frontend will eventually use a Supabase publishable key. Elevated secret
keys and personal access tokens must never be included in browser code.

## Migrating the Firebase data

The migration is intentionally split into a private snapshot and a generated
SQL transaction. Snapshot and SQL output files contain personal data and must
stay in the system temporary directory; never commit them.

```powershell
npm run data:firebase-export -- --output "$env:TEMP\pantry-firestore.json"
npm run data:firebase-transform -- `
  --input "$env:TEMP\pantry-firestore.json" `
  --output "$env:TEMP\pantry-supabase-validate.sql" `
  --rollback --replace
npx supabase db query --linked `
  --file "$env:TEMP\pantry-supabase-validate.sql" --agent no
```

The rollback pass performs real inserts and validates record counts, every lot
balance, all migrated lot costs, and aggregate food-log nutrition. Remove
`--rollback` and generate a new output filename only after it succeeds. The
`--replace` option deletes only rows tagged with a legacy Firebase ID, inside
the same transaction, so a corrected import can be applied atomically.

Nutrition and replacement-cost estimates live in
`tools/firebase-migration-estimates.json`. They are explicitly marked as
estimated in PostgreSQL and include provenance. Review that file whenever a
receipt, barcode, package size, or better nutrition label becomes available.
