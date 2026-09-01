# Pantry GPT API

The Pantry GPT API is a Supabase Edge Function backed by PostgreSQL. It is the
stable boundary between plain-English requests and Pantry data: the GPT resolves
intent and ambiguity, while the API accepts only structured JSON and performs
validated database operations.

```text
https://xaetuqdtnolzspfvqvja.supabase.co/functions/v1/pantry-api
```

The complete Custom GPT contract is `docs/pantry-gpt-openapi.yaml`.

## Authentication

Every request uses:

```text
Authorization: Bearer <PANTRY_API_TOKEN>
```

Generate and deploy the credential with `tools/setup_api_secret.ps1`. The script
sends it to Supabase without printing it and stores a matching DPAPI-encrypted
copy under the current Windows account. The plaintext belongs only in the Custom
GPT Action authentication field—not browser code, Git, logs, GPT instructions,
Knowledge files, or conversations.

The Edge Function verifies this token before creating a server-only Supabase
client. Its service-role key comes from the Edge Function environment and is
never sent to ChatGPT.

## Transaction boundaries

Simple reads use Supabase's Data API. Compound writes call narrowly scoped
PostgreSQL functions:

- grocery hauls insert all lots or none;
- reconciliation records adjustment events and replacement lots together;
- recipes and ingredients are replaced together;
- weekly plans and generated groceries are rebuilt together;
- preparation deducts ingredients and creates a prepared lot together;
- consumption deducts FEFO lots and records nutrition together;
- purchased-product logging creates a lot and consumes its reported portion together.

GPT-only functions are executable by `service_role`, not browser roles. Owner RLS
continues to protect direct browser access.

## Routes

Reads:

```text
GET /v1/inventory
GET /v1/foods?q=<optional search>
GET /v1/foods/{uuid}
GET /v1/recipes?q=<optional search>
GET /v1/recipes/{uuid}
GET /v1/prepared-batches
GET /v1/history?days=30
GET /v1/plans
GET /v1/targets
GET /v1/preferences
GET /v1/routine
```

Writes:

```text
POST /v1/inventory
POST /v1/foods
POST /v1/products
POST /v1/groceries
POST /v1/recipes
POST /v1/prepare/recipe
POST /v1/consume/prepared
POST /v1/consume/inventory
POST /v1/consume/product
POST /v1/plans
POST /v1/grocery-items
POST /v1/targets
POST /v1/preferences
POST /v1/routine
```

Food lookup returns supported measurement units and products. Inventory returns
exact `foodId`, `productId`, and `lotId` values. The GPT must reuse these IDs.

## Definitions and groceries

Create a canonical food before its branded product:

```json
{
  "name": "Whole milk",
  "measureStyle": "volume",
  "displayUnit": "fl oz",
  "gPerFlOz": 30.6,
  "groceryCategory": "Eggs, yogurt, cheese & dough",
  "ingredientRole": "supporting",
  "nutrition": {
    "basisQuantity": 240,
    "calories": 149,
    "proteinG": 7.7,
    "carbsG": 11.7,
    "fatG": 7.9,
    "fiberG": 0,
    "sugarG": 12.3,
    "sodiumMg": 105,
    "source": "Package label",
    "estimated": false
  }
}
```

`POST /v1/products` accepts `foodId`, name, `packageQuantity`, and
`packageUnit`. Package and serving quantities are converted to the food's base
quantity on the server.

Add reviewed lots atomically:

```json
{
  "source": "Safeway receipt",
  "items": [{
    "productId": "<product uuid>",
    "quantity": 1,
    "unit": "gal",
    "location": "fridge",
    "bestBy": "2026-09-12",
    "totalCost": 4.99
  }]
}
```

The unit may be a returned unit UUID, full name, or short name.

## Cooking and eating

Cooking and eating are separate. `POST /v1/prepare/recipe` deducts raw
ingredients FEFO and creates a prepared batch:

```json
{"recipeId":"<recipe uuid>","servings":4,"location":"fridge","bestBy":"2026-09-04"}
```

Eat from its returned lot ID using `POST /v1/consume/prepared`:

```json
{"batchId":"<prepared lot uuid>","servings":1,"timestamp":"2026-08-31T19:00:00-04:00"}
```

Quick use of one food goes through `POST /v1/consume/inventory`:

```json
{"foodId":"<food uuid>","quantity":1,"unit":"ct","label":"Apple"}
```

All three operations roll back completely on insufficient inventory.

## Purchased food and retained leftovers

Restaurant, takeout, and other away-from-home items use the same food and product
definitions as groceries. Search first, then create only a missing canonical food
or exact product variant. Acquire and consume it through `POST /v1/consume/product`:

```json
{
  "productId": "<product uuid>",
  "purchasedQuantity": 1,
  "consumedQuantity": 0.5,
  "location": "fridge",
  "timestamp": "2026-09-01T08:30:00-04:00",
  "totalCost": 7.49,
  "costSource": "Receipt"
}
```

This atomically creates a lot classified as an away-from-home purchase, consumes
half through the ordinary inventory ledger, and leaves half in the fridge. When
the full purchase was eaten, set both quantities to the same value. Distinct
products use distinct calls; repeated units of one exact product can use quantity.

## Planning and settings

`POST /v1/plans` replaces exactly the seven dates beginning at `weekStart`, then
rebuilds unchecked generated grocery shortages while preserving manual items.
Recipe and meal entries use `sourceId` and `scaleFactor`.

`POST /v1/grocery-items` adds a manual item. The target, preference, and routine
POST routes replace their respective singleton settings.

Calendar is not exposed yet. Planning uses the saved routine and any conflicts
provided in conversation; the GPT must say external calendar conflicts were not
checked.

## Errors and testing

- `401`: missing or invalid integration bearer token.
- `404`: route or resource does not exist.
- `422`: validation or a database constraint rejected the request.
- `500`: unexpected server failure; never claim that a write succeeded.

Test without exposing the token:

```powershell
.\tools\pantry_api.ps1 -Method GET -Path /v1/inventory
```
