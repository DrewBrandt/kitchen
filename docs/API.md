# Codex pantry API

The API is the durable boundary between plain-English requests and pantry data. Codex interprets the request, checks uncertainties with the user when necessary, converts it to this structured contract, and sends it with a private bearer token.

The API never accepts arbitrary natural language. This keeps interpretation separate from inventory mutation and makes every write reviewable.

## Authentication

Every request uses:

```text
Authorization: Bearer <PANTRY_API_TOKEN>
```

Cloud Functions and Secret Manager require the Firebase Blaze plan. Generate a
random token, store it in Firebase, and keep a Windows-encrypted local copy by
running from the repository root:

```powershell
.\tools\setup_api_secret.ps1
```

The token is not displayed or passed through chat. Never store it in the Flutter
client or commit it to Git. Use `tools/pantry_api.ps1` for authenticated calls;
POST bodies are supplied as JSON files with `-BodyFile`.

## Allow a Google account

Firestore access is denied until the authenticated account's Firebase UID is
explicitly allowlisted. The signed-in app displays the UID when access is
missing. Approve it through the private API:

```http
POST /v1/access
Content-Type: application/json

{"uid": "firebase-auth-uid"}
```

This route is protected by the same private bearer token. A UID identifies an
account but is not itself a credential.

## Read current inventory

```http
GET /v1/inventory
```

Returns food definitions, positive inventory lots, and recipes. Codex can use this to answer “what can I make?” before writing anything.

## Define or update a food

```http
POST /v1/foods
Content-Type: application/json

{
  "id": "butter",
  "name": "Butter",
  "emoji": "🧈",
  "quantityMode": "measured",
  "baseUnit": "gram",
  "defaultLocation": "fridge",
  "conversions": [
    {"unit": "gram", "symbol": "g", "baseAmount": 1},
    {"unit": "tablespoon", "symbol": "tbsp", "baseAmount": 14.175},
    {"unit": "cup", "symbol": "cups", "baseAmount": 226.8},
    {"unit": "stick", "symbol": "sticks", "baseAmount": 113.4}
  ]
}
```

## Add a grocery haul

The entire request is validated before any lots are created.

```http
POST /v1/groceries
Content-Type: application/json

{
  "source": "Sunday grocery run",
  "items": [
    {"food": "Eggs", "amount": 12, "unit": "each", "location": "fridge", "bestBy": "2026-09-08"},
    {"food": "Milk", "amount": 1, "unit": "liter", "location": "fridge", "bestBy": "2026-08-30"}
  ]
}
```

Unknown foods and unsupported units return `422` without a partial write. Codex should define a new food first or ask the user for the missing package amount.

## Save a recipe

```http
POST /v1/recipes
Content-Type: application/json

{
  "name": "Soft Scrambled Eggs",
  "emoji": "🍳",
  "servings": 1,
  "sourceUrl": "https://example.com/original-recipe",
  "ingredients": [
    {"food": "Eggs", "amount": 2, "unit": "each"},
    {"food": "Butter", "amount": 0.5, "unit": "tablespoon"}
  ],
  "instructions": ["Beat the eggs.", "Cook gently in butter."]
}
```

When importing an online recipe, retain its source URL and paraphrase instructions unless the source explicitly permits redistribution.
