# Pantry Inventory

A private TypeScript and React pantry, inventory, recipe, grocery, meal-planning,
and nutrition application backed by Supabase PostgreSQL.

## Architecture

- React + TypeScript + Vite frontend
- Supabase PostgreSQL, Auth, Row Level Security, and transactional functions
- Google sign-in through Supabase Auth
- private Supabase Edge Function API for the Pantry Custom GPT
- GitHub Pages deployment through `.github/workflows/deploy-pages.yml`

Only the configured owner can access application data. The browser publishable
key is public by design; owner-only RLS and a live authenticated session enforce
database access. The GPT uses a separate bearer credential stored only in
Supabase Edge Function secrets and its private Action configuration.

## Local development

Copy `.env.example` to `.env.local`, provide the project publishable key, then:

```sh
npm ci
npm run dev
```

The production site is [DrewBrandt.github.io/kitchen](https://drewbrandt.github.io/kitchen/).
Pushing `main` runs the verification/build workflow and publishes GitHub Pages.

## Database

Schema changes live in `supabase/migrations/`. Validate linked changes with:

```sh
npm run db:lint
npm run db:test
npm run db:test:transactions
npm run db:test:gpt
```

The migration chain retains historical import metadata because applied Supabase
migrations are immutable. No retired service is used at runtime.

## Private Pantry GPT

The GPT Action calls:

```text
https://xaetuqdtnolzspfvqvja.supabase.co/functions/v1/pantry-api
```

Create its private bearer credential with `tools/setup_api_secret.ps1`, then
follow [docs/PANTRY_GPT_SETUP.md](docs/PANTRY_GPT_SETUP.md). The token must never
be committed, placed in browser code, or pasted into GPT instructions, Knowledge,
or conversations.

The checked-in operator pack contains:

- [GPT instructions](docs/PANTRY_GPT_INSTRUCTIONS.md)
- [Action OpenAPI schema](docs/pantry-gpt-openapi.yaml)
- [API contract](docs/API.md)

Calendar synchronization remains planned and is not exposed to the GPT.

## Application verification

```sh
npm run check
npm test
npm run build
```

See [docs/FEATURE_SPECIFICATION.md](docs/FEATURE_SPECIFICATION.md) for product
behavior and [docs/SUPABASE.md](docs/SUPABASE.md) for database/deployment setup.
