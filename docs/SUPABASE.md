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

The frontend uses a Supabase publishable key. Elevated secret keys and personal
access tokens must never be included in browser code.

## Historical import

The original application data has already been imported and validated. The
applied migration that preserves import identifiers remains in the migration
chain because applied migrations must not be rewritten. It is historical SQL
only and does not require access to the former service.
