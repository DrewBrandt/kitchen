# Pantry Inventory

A private Flutter pantry, fridge, freezer, nutrition, and recipe tracker backed
by Firebase.

The current vertical slice includes:

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
- authenticated Firebase API scaffold for Codex-driven updates
- Google sign-in with a Firestore access allowlist
- automatic GitHub Pages deployment
- optional Google Calendar synchronization for grocery and preparation reminders
- a private Me routine with per-day sleep times, dinner windows, and planning buffers
- read-only selected-calendar agendas for schedule-aware Pantry GPT meal planning

The production app uses Firebase project `pantry-tracker-4bc45`. Firebase's web
configuration is intentionally safe to ship in a web client; access to pantry
data is enforced by Firebase Authentication and Firestore Security Rules.

## Run

```sh
flutter run
```

## Private access setup

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

No Firebase secret is required by GitHub Actions. The Pages build contains only
the normal Firebase web configuration already required by every browser client.

## Firefox mobile sign-in

Use the Firebase-hosted app at
`https://pantry-tracker-4bc45.firebaseapp.com` on Firefox mobile. The app uses a
same-origin redirect there so Firefox cannot block Firebase's authentication
handoff as cross-site storage. Build with a root base path and deploy with:

```sh
flutter build web --release --base-href / --pwa-strategy=none
firebase deploy --only hosting
```

## Codex API credential

Cloud Functions require the Firebase Blaze plan, although low-volume usage is
normally covered by its no-cost allowances. After upgrading, generate the
credential and send it directly to Firebase Secret Manager with:

```powershell
.\tools\setup_api_secret.ps1
```

The generated token is never printed. Firebase holds one copy and this Windows
account holds a DPAPI-encrypted copy outside the repository. The function
receives it at runtime; it does not belong in Flutter, GitHub Actions, chat, or
source control.

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
flutter analyze
flutter test
```

See `REQUIREMENTS.md` for the canonical model and Firebase migration plan.
See `docs/FEATURE_SPECIFICATION.md` for the UI-agnostic product capabilities,
data model, business rules, and Custom GPT operating model.
See `docs/API.md` for the Codex integration contract and deployment authentication model.
