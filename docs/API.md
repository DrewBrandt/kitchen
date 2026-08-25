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

Search before saving so an existing definition can be reused without loading
the complete pantry snapshot:

```http
GET /v1/external-foods?q=chicken%20sandwich&brand=Chick-fil-A
```

Omit both query parameters to list all saved outside foods. `q` partially
matches the ID, name, brand, or serving label; `brand` is an exact normalized
match.

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

Each call to `POST /v1/meals` creates one history event and retains the
`externalFoodId` reference. Log repeated physical items with separate calls and
`servings: 1` unless the user explicitly wants a grouped entry.

## Consume a saved recipe

This route deducts the recipe ingredients from the earliest-expiring inventory
lots and records one nutrition-history event in the same Firestore transaction:

```http
POST /v1/consume/recipe
Content-Type: application/json

{
  "recipeId": "butter-chicken",
  "servings": 1,
  "timestamp": "2026-08-23T19:30:00-04:00",
  "note": "Dinner"
}
```

`timestamp`, `label`, and `note` are optional. The write fails without changing
anything when a recipe is unknown or inventory is insufficient.

## Consume an individual pantry item

Use this for things such as one yogurt or a measured glass of milk. It deducts
inventory and logs nutrition together:

```http
POST /v1/consume/inventory
Content-Type: application/json

{
  "food": "Lucerne 2% milk",
  "amount": 2.25,
  "unit": "cup",
  "label": "Tall glass of milk"
}
```

`foodId` can be used instead of `food`. The requested unit must already exist
in that food's conversion list.

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

## Save food preferences and allergies

This private profile is returned with inventory reads so apps and Pantry GPT can
apply it before suggesting recipes or planning meals:

```http
POST /v1/preferences
Content-Type: application/json

{
  "allergies": ["Tree nuts"],
  "dislikes": ["Raw tomatoes"],
  "favorites": ["Indian food", "Cheeseburgers"],
  "dietaryRules": ["Limit red meat to twice per week"],
  "planningNotes": "Prefer simple weeknight dinners and planned leftovers."
}
```

All arrays are optional and replace their previous values. Allergies are treated
as hard safety constraints by the Pantry GPT instructions.

## Save the personal routine

`GET /v1/routine` reads the private routine used for schedule-aware planning.
`POST /v1/routine` replaces it. Wake and bedtime are stored for every weekday;
all times use local 24-hour `HH:mm` values in the named IANA time zone.

```json
{
  "timeZone": "America/New_York",
  "days": {
    "monday": {"wakeTime": "07:00", "bedTime": "23:00"},
    "tuesday": {"wakeTime": "07:00", "bedTime": "23:00"},
    "wednesday": {"wakeTime": "07:00", "bedTime": "23:00"},
    "thursday": {"wakeTime": "07:00", "bedTime": "23:00"},
    "friday": {"wakeTime": "07:00", "bedTime": "23:30"},
    "saturday": {"wakeTime": "08:00", "bedTime": "23:30"},
    "sunday": {"wakeTime": "08:00", "bedTime": "23:00"}
  },
  "dinnerWindow": {"start": "18:00", "end": "20:30"},
  "commuteMinutes": 30,
  "preparationBufferMinutes": 30,
  "defaultThawHours": 24,
  "notes": "Avoid cooking after 9 PM."
}
```

## Read current inventory

```http
GET /v1/inventory
```

Returns compact stock `items`. Each item contains the canonical food ID and name,
quantity mode, base/display units, total quantity in the base unit, and its
positive lots with location, best-by date, and optional product identity. It
does not include full food or product definitions, history, targets, preferences,
recipes, plans, groceries, or prepared foods. Use the focused endpoints below
for that context.

## Find a food definition

```http
GET /v1/foods?q=white%20rice
GET /v1/foods/{id}
```

The search matches canonical IDs, names, and aliases and returns the complete
definition, including supported units, conversions, and nutrition. Omit `q` only
when the complete definition list is actually needed.

## Find a recipe

```http
GET /v1/recipes?q=orange%20chicken
GET /v1/recipes/{id}
```

The search matches recipe IDs and names. An exact-ID read avoids transferring
the complete recipe collection.

## Read prepared foods

```http
GET /v1/prepared-batches
```

Returns only prepared batches with servings remaining.

## Read nutrition targets and food preferences

```http
GET /v1/targets
GET /v1/preferences
```

These return the small private settings documents independently of inventory.

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

Plan-generated grocery items include `first_needed_date`, the first planned
meal date on which chronological ingredient demand exceeds current inventory.
This field is intended for shopping deadlines and calendar synchronization;
manual grocery items leave it unset.

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
      "groupId": "monday-dinner",
      "intent": "prepare",
      "servings": 4,
      "note": "Use the naan"
    },
    {
      "date": "2026-08-26",
      "slot": "lunch",
      "source": "recipe",
      "sourceId": "butter-chicken",
      "groupId": "wednesday-lunch",
      "leftoverOfGroupId": "monday-dinner",
      "intent": "leftover",
      "servings": 1
    }
  ]
}
```

The route validates every entry, replaces only the requested seven-day range,
totals ingredients from referenced recipes, scales them to planned servings,
subtracts positive inventory lots, and rebuilds plan-generated grocery items.
Manual grocery items and checked state for unchanged foods are preserved.

`source` may be `recipe`, `meal`, `external`, or `custom`. Recipe and external
entries use `sourceId`; custom entries require `name`. Give recipe components
the same `groupId` to display them as one meal. `intent` defaults to `prepare`;
use `leftover` to retain recipe identity without adding grocery demand.
Set `leftoverOfGroupId` to the earlier meal's `groupId` to link future
leftovers directly to that planner meal before it has been cooked. The linked
entries keep their underlying recipe components; no new saved recipe or meal
template is created.

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

## Calendar synchronization

Planning writes from Flutter and `POST /v1/plans` atomically update
`settings/planning_sync`. The Firestore-triggered reconciler then updates only
events carrying Pantry's private managed-event properties. A plan write remains
successful when Google is temporarily unavailable.

```http
GET /v1/calendar/status
GET /v1/calendar/calendars
GET /v1/calendar/agenda?from=2026-09-01T00:00:00-04:00&to=2026-09-08T00:00:00-04:00
POST /v1/calendar/calendars
POST /v1/calendar/sync
DELETE /v1/calendar/events
```

The status response never contains OAuth credentials. The POST route requests
an idempotent reconciliation. The DELETE route requests removal of
Pantry-managed events only and disables future synchronization; it cannot
delete unrelated Calendar events.

The OAuth connection keeps write access confined to the dedicated Pantry
Planner calendar and separately requests read-only access to existing events.
The calendar-selection route controls which readable calendars appear in the
agenda. Agenda requests are bounded to 45 days and return event summary,
description, location, start/end, and all-day status without exposing OAuth
credentials. Reconnect once after upgrading from the earlier write-only scope.

Recipe writes may include explicit preparation reminders:

```json
{
  "preparationRules": [
    {
      "id": "thaw-chicken",
      "kind": "thaw",
      "label": "Move chicken to the refrigerator",
      "leadHours": 24
    }
  ]
}
```

The Flutter recipe editor uses the equivalent line format
`24 | thaw | Move chicken to the refrigerator`.

One meal-plan entry may instead carry an exact time and plan-specific task:

```json
{
  "date": "2026-09-03",
  "slot": "dinner",
  "scheduledTime": "20:15",
  "source": "recipe",
  "sourceId": "roast-chicken",
  "servings": 2,
  "preparationTasks": [
    {
      "id": "thaw-chicken",
      "kind": "thaw",
      "label": "Move chicken to the refrigerator",
      "leadHours": 24,
      "durationMinutes": 5
    }
  ]
}
```

For a thaw task, `leadHours` defaults to 24 if omitted. Plan-specific tasks are
preferred when the action depends on the current inventory lot; they do not
modify the saved recipe.

## Reconcile existing inventory

Use this route for corrections where the submitted lots replace all current
lots for the named foods. The entire request is validated before the atomic
write. An empty `lots` array removes an item from inventory, while
`deleteFoodIds` also removes obsolete food definitions.

```http
POST /v1/inventory
Content-Type: application/json

{
  "source": "Pantry photo reconciliation",
  "displayUnits": {
    "butter": "stick",
    "baking-powder": "tablespoon"
  },
  "foods": [
    {
      "id": "egg",
      "name": "Eggs",
      "emoji": "🥚",
      "quantityMode": "counted",
      "baseUnit": "each",
      "defaultLocation": "fridge",
      "conversions": [{"unit": "each", "symbol": "eggs", "baseAmount": 1}]
    }
  ],
  "replacements": [
    {
      "foodId": "egg",
      "lots": [
        {"amount": 10, "unit": "each", "location": "fridge", "bestBy": "2026-08-09"},
        {"amount": 16, "unit": "each", "location": "fridge", "bestBy": "2026-09-20"}
      ]
    }
  ],
  "deleteFoodIds": ["obsolete-food"]
}
```

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
  ],
  "nutrition": {
    "basisBaseAmount": 14.175,
    "calories": 100,
    "proteinG": 0,
    "carbsG": 0,
    "fatG": 11,
    "fiberG": 0,
    "sugarG": 0,
    "sodiumMg": 90,
    "source": "Package label",
    "estimated": false
  }
}
```

## Add a grocery haul

Foods are canonical recipe ingredients. Branded items are stored separately in
`products` and map back to a canonical `foodId`. Create or update a product with
`POST /v1/products`; grocery items may then identify it with `productId`, an
exact product name or alias, or a barcode. Product package conversions take
precedence over generic food conversions.

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

## Migrate existing branded foods

`POST /v1/migrations/canonical-products` converts existing branded food
definitions into canonical foods plus products. It defaults to `dryRun: true`
and reports affected lots, recipes, and history. With `dryRun: false`, it
validates every target recipe unit before changing anything, then rewrites
inventory, recipes, prepared batches, history deductions, and grocery
references in one Firestore batch. Batches are capped at 450 writes.
When `canonicalConversions` removes the food's current display unit, the
mapping must provide a supported `canonicalDisplayUnit`.

The reviewed mapping for the current pantry is
`tools/canonical_product_migration.json`. Keep it in dry-run mode until the new
Cloud Function has been deployed and its impact report has been reviewed.

## Save a recipe

```http
POST /v1/recipes
Content-Type: application/json

{
  "name": "Soft Scrambled Eggs",
  "emoji": "🍳",
  "servings": 1,
  "portions": [
    {"name": "Large plate", "servings": 1.5}
  ],
  "sourceUrl": "https://example.com/original-recipe",
  "nutritionOverride": {
    "calories": 600,
    "proteinG": 8,
    "carbsG": 90,
    "fatG": 24,
    "fiberG": 3,
    "sugarG": 55,
    "sodiumMg": 800
  },
  "ingredients": [
    {"food": "Eggs", "amount": 2, "unit": "each"},
    {"food": "Butter", "amount": 0.5, "unit": "tablespoon"}
  ],
  "instructions": ["Beat the eggs.", "Cook gently in butter."]
}
```

`nutritionOverride` is optional and represents the totals for the recipe's
entire prepared yield. When present, recipe consumption scales these totals by
the requested servings instead of adding ingredient nutrition. Inventory
deduction still uses every ingredient. This is useful for packaged mixes whose
label already includes the eggs, oil, or other preparation ingredients.

When importing an online recipe, retain its source URL and paraphrase instructions unless the source explicitly permits redistribution.

## Prepared food and combined meals

Cooking is a two-stage workflow. `POST /v1/prepare/recipe` deducts ingredients
and creates a prepared batch. `POST /v1/consume/prepared` logs nutrition and
reduces that batch's remaining servings. Use `POST /v1/prepared-batches` for a
manual leftover or ready-made item that should not retroactively deduct raw
inventory.

`POST /v1/meal-templates` stores a dinner as two or more component recipes, such
as pork tenderloin, fried potatoes, and roasted carrots. Components remain
separate prepared batches even when they are planned and eaten as one meal.
