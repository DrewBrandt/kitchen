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

## Log food that does not use inventory

Restaurant meals, takeout, drinks, and packaged snacks can be added directly to
the nutrition log without changing any inventory lots:

```http
POST /v1/meals
Content-Type: application/json

{
  "label": "Restaurant cheeseburger",
  "note": "Estimated from the restaurant menu",
  "calories": 720,
  "proteinG": 38,
  "carbsG": 45,
  "fatG": 42,
  "fiberG": 3,
  "sugarG": 9,
  "sodiumMg": 1280,
  "estimated": true,
  "timestamp": "2026-08-23T19:30:00-04:00"
}
```

Only `label` and at least one positive nutrition value are required. If
`timestamp` is omitted, Firebase records the current time.

## Save and reuse an outside food

Restaurant orders and packaged snacks live in `external_foods`, entirely
separate from pantry definitions and inventory lots:

```http
POST /v1/external-foods
Content-Type: application/json

{
  "id": "chick-fil-a-chicken-sandwich",
  "name": "Chicken Sandwich",
  "brand": "Chick-fil-A",
  "emoji": "🥪",
  "servingLabel": "1 sandwich",
  "calories": 420,
  "proteinG": 29,
  "carbsG": 41,
  "fatG": 18,
  "fiberG": 1,
  "sugarG": 6,
  "sodiumMg": 1460,
  "source": "Restaurant nutrition page",
  "estimated": false
}
```

After it is saved, log any number of servings without resending nutrition:

```http
POST /v1/meals
Content-Type: application/json

{
  "externalFoodId": "chick-fil-a-chicken-sandwich",
  "servings": 1,
  "timestamp": "2026-08-23T13:00:00-04:00"
}
```

Neither request reads or changes inventory lots.

## Save daily nutrition targets

Targets are private, editable, and used by the Food Log percentage displays:

```http
POST /v1/targets
Content-Type: application/json

{
  "calories": 2500,
  "proteinG": 130,
  "carbsG": 300,
  "fatG": 83,
  "fiberG": 38,
  "sodiumMg": 2300,
  "label": "Age 28 · 6 ft · 180 lb · light activity · gradual loss"
}
```

Calories and macronutrients are planning targets; sodium is displayed as a
limit. Total sugar intentionally has no percentage because nutrition labels do
not distinguish all naturally occurring sugar from added sugar consistently.

## Read current inventory

```http
GET /v1/inventory
```

Returns food definitions, positive inventory lots, recipes, and the 500 most
recent food-log events. Codex can use this to answer “what can I make?” and
“what have I eaten today?” before writing anything.

## Read meal-planning history

```http
GET /v1/history?days=30
```

Returns active food-log events in the requested 1–365 day range plus a compact
planning summary: distinct meal count, foods repeated three or more times, the
most repeated foods, their last-eaten dates, and recent meal names. This is the
preferred context for requests such as “plan my week” because it lets Codex
avoid recent defaults without downloading the entire pantry. Undone events are
excluded.

## Read the current plan and grocery list

```http
GET /v1/plans
```

Returns dated meal-plan entries and the current grocery list. This is the
preferred read before changing a plan because manually added groceries and
checked shopping state are durable.

## Replace one week’s meal plan

```http
POST /v1/plans
Content-Type: application/json

{
  "weekStart": "2026-08-24",
  "entries": [
    {
      "date": "2026-08-24",
      "slot": "dinner",
      "source": "recipe",
      "sourceId": "butter-chicken",
      "servings": 4,
      "note": "Use the naan"
    },
    {
      "date": "2026-08-26",
      "slot": "lunch",
      "source": "custom",
      "name": "Leftovers",
      "emoji": "🥡",
      "servings": 1
    }
  ]
}
```

The route validates every entry, replaces only the requested seven-day range,
totals ingredients from referenced recipes, scales them to planned servings,
subtracts positive inventory lots, and rebuilds plan-generated grocery items.
Manual grocery items and checked state for unchanged foods are preserved.

`source` may be `recipe`, `external`, or `custom`. Recipe and external entries
use `sourceId`; custom entries require `name`.

## Add a manual grocery item

```http
POST /v1/grocery-items
Content-Type: application/json

{
  "name": "Coffee filters",
  "quantityLabel": "1 box"
}
```

Manual items remain on the list independently of meal-plan recalculation.

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
