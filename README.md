# Pantry Inventory

A private TypeScript and React pantry, inventory, recipe, grocery, meal-planning,
and nutrition application backed by Supabase PostgreSQL.

## Architecture

- React + TypeScript + Vite frontend
- Supabase PostgreSQL, Auth, Row Level Security, and database functions
- Google sign-in through Supabase Auth
- GitHub Pages deployment through `.github/workflows/deploy-pages.yml`

Only the configured owner account can access application data. The public
frontend contains a Supabase publishable key by design; database access is
enforced by Row Level Security and a live authenticated Supabase session.

## Local development

Copy `.env.example` to `.env.local`, provide the project publishable key, then:

```sh
npm ci
npm run dev
```

The production site is [DrewBrandt.github.io/kitchen](https://drewbrandt.github.io/kitchen/).
Pushing `main` runs the test/build workflow and publishes GitHub Pages.

## Database

Schema changes live in `supabase/migrations/`. Validate linked database changes
with:

```sh
npm run db:lint
npm run db:test
npm run db:test:transactions
```

The migration chain contains one historical import migration whose name and
columns record the original data source. It remains because applied Supabase
migrations are immutable history; it does not connect to or depend on that
service at runtime.

## Application verification

```sh
npm run check
npm test
npm run build
```

## Planned integrations

Google Calendar synchronization and a private Pantry GPT API remain planned
features. Their UI/specification surfaces are retained, but no server
integration is currently deployed for them. New implementations should use
Supabase-backed server code and must preserve the database's transactional and
owner-only access guarantees.

See `docs/FEATURE_SPECIFICATION.md` for product behavior and `docs/SUPABASE.md`
for database setup.
