# Pantry Inventory

A private, responsive TypeScript and React pantry, fridge, freezer, nutrition,
and recipe tracker. The web-native UI is intentionally isolated from its data
provider so the Firebase-to-Supabase migration can proceed independently.

The UI represents the following product capabilities:

- counted and measured foods
- fractional counted quantities
- food-specific kitchen conversions
- separately expiring inventory lots
- recipe availability
- earliest-expiry-first recipe deductions
- quick consumption
- daily calorie, macro, fiber, sugar, and sodium totals
- private, editable nutrition targets with goal and limit percentages
- outside meal, takeout, drink, and snack logging without inventory changes
- reversible history
- responsive desktop and mobile navigation
- food-definition and conversion editing
- recipe creation and editing
- reviewed bulk grocery import
- on-device UPC/EAN scanning with reviewed Open Food Facts suggestions
- authenticated Supabase Edge Function API for Custom GPT updates
- Google sign-in with owner-only PostgreSQL row-level security
- automatic GitHub Pages deployment
- optional Google Calendar synchronization for grocery and preparation reminders
- a private Me routine with per-day sleep times, dinner windows, and planning buffers
- read-only selected-calendar agendas for schedule-aware Pantry GPT meal planning

The web frontend and private GPT now share the Supabase PostgreSQL source of
truth. Legacy Firebase functions, rules, and Flutter code remain only as
migration references and are not part of the live web or GPT path.

## Run

```sh
npm ci
npm run dev
```

Configure `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` for live data.
Without them the UI uses representative preview data.

## Legacy Firebase access setup

These steps apply only to the legacy Flutter/Firebase client during migration.

1. In Firebase Console, open **Authentication → Sign-in method** and enable
   **Google**.
2. For local setup, add `localhost` under
   **Authentication → Settings → Authorized domains**.
3. Deploy the private rules with `firebase deploy --only firestore:rules`.
4. Sign in to the app. The first attempt displays your Firebase UID because the
   account is not allowlisted yet.
5. In Firestore, create collection `app_access` and a document whose ID is that
   UID. A harmless field such as `role: "owner"` is sufficient.
6. Press **Try again** in the app.

The UID is an identifier, not a credential. Do not put passwords, OAuth tokens,
service-account JSON, or `PANTRY_API_TOKEN` in the repository or chat.

## GitHub Pages

The workflow in `.github/workflows/deploy-pages.yml` verifies, builds, and
publishes the app whenever `main` is pushed.

1. Create a GitHub repository and push this repository to it.
2. In **GitHub repository → Settings → Pages**, set **Source** to
   **GitHub Actions**.
3. Add `<your-github-name>.github.io` under
   **Firebase Authentication → Settings → Authorized domains**.

No Firebase secret is required by the frontend build.

The workflow builds the Vite app into `dist/`. Firebase Hosting serves the same
artifact and retains the existing no-cache policy for entry files.

## Private GPT API credential

Generate a private bearer credential, send it directly to Supabase Edge Function
secrets, and keep the matching Windows-encrypted local copy with:

```powershell
.\tools\setup_api_secret.ps1
```

The generated token is never printed. Supabase holds one copy and this Windows
account holds a DPAPI-encrypted copy outside the repository. It does not belong
in the browser client, GitHub Actions, chat, or source control.

After deploying the function, make an authenticated request with:

```powershell
.\tools\pantry_api.ps1 -Method GET -Path /v1/inventory
```

## Private ChatGPT access

To use the live pantry from new ChatGPT conversations without embedding an
OpenAI API in the app, create a private Custom GPT using the checked-in operator
pack:

- [Setup guide](docs/PANTRY_GPT_SETUP.md)
- [GPT instructions](docs/PANTRY_GPT_INSTRUCTIONS.md)
- [Action OpenAPI schema](docs/pantry-gpt-openapi.yaml)

The bearer credential stays out of Git and is pasted only into the private GPT
Action authentication field.

## Barcode scanning

From **Inventory**, choose **Scan barcode** on a phone or computer with a
camera. UPC and EAN recognition runs on the device. A saved barcode opens the
normal put-away dialog immediately. An unknown barcode is looked up once in
Open Food Facts and its product name, brand, and compatible package quantity
are presented for review before anything is saved.

Open Food Facts data is community-contributed and is used under its open-data
license; scanned suggestions should be reviewed against the package. A barcode
identifies a product, but it does not contain the package's best-by date.

## Verify

```sh
npm run check
npm test
npm run build
```

See `REQUIREMENTS.md` for the canonical data and conversational model.
See `docs/FEATURE_SPECIFICATION.md` for the UI-agnostic product capabilities,
data model, business rules, and Custom GPT operating model.
See `docs/API.md` for the Codex integration contract and deployment authentication model.
