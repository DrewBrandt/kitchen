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
- reversible history
- responsive desktop and mobile navigation
- food-definition and conversion editing
- recipe creation and editing
- reviewed bulk grocery import
- authenticated Firebase API scaffold for Codex-driven updates
- Google sign-in with a Firestore access allowlist
- automatic GitHub Pages deployment

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

## Codex API credential

The Cloud Function uses the `PANTRY_API_TOKEN` secret. Set it directly through
Firebase Secret Manager rather than committing it:

```sh
firebase functions:secrets:set PANTRY_API_TOKEN
```

The command prompts locally for the value. The function receives it at runtime;
it does not belong in Flutter, GitHub Actions, or source control.

## Verify

```sh
flutter analyze
flutter test
```

See `REQUIREMENTS.md` for the canonical model and Firebase migration plan.
See `docs/API.md` for the Codex integration contract and deployment authentication model.
