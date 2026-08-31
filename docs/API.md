# Pantry GPT API

The Pantry GPT API is a Supabase Edge Function backed by PostgreSQL. It is the
stable boundary between plain-English requests and Pantry data: the GPT resolves
intent and ambiguity, while the API accepts only structured JSON and performs
validated database operations.

Base URL:

```text
https://xaetuqdtnolzspfvqvja.supabase.co/functions/v1/pantry-api
```

The complete Custom GPT contract is `docs/pantry-gpt-openapi.yaml`.

## Authentication

Every request uses the private integration credential:

```text
Authorization: Bearer <PANTRY_API_TOKEN>
```

Generate and deploy it with:

```powershell
.\tools\setup_api_secret.ps1
```

The script sends the value to Supabase without printing it and stores a matching
DPAPI-encrypted copy under the current Windows account. The token must never be
placed in browser code, source control, logs, GPT instructions, Knowledge files,
or a conversation. Only the Custom GPT Action authentication field should receive
the copied plaintext value.

The Edge Function deliberately disables Supabase JWT verification because the
Action uses its own bearer credential. It compares the credential before creating
a server-only Supabase client. The service-role key is supplied automatically by
the Edge Function environment and is never exposed to ChatGPT.

## Data and transaction boundaries

Normal reads and single-row settings updates use the generated Supabase Data API.
Compound writes call narrowly scoped PostgreSQL functions:

- grocery hauls insert all lots or none;
- inventory reconciliation records auditable adjustments and replacement lots;
- recipes and their ingredients are replaced together;
- weekly plans and generated groceries are rebuilt together;
- preparation deducts ingredients and creates a prepared lot together;
- consumption deducts FEFO lots and records nutrition together;
- outside-food definition creation updates its canonical food and product together.

GPT-only database functions are executable by `service_role` and not by browser
roles. Owner RLS continues to protect direct browser access.

## Read operations

```text
GET /v1/inventory
GET /v1/foods?q=<optional search>
GET /v1/foods/{uuid}
GET /v1/recipes?q=<optional search>
GET /v1/recipes/{uuid}
GET /v1/prepared-batches
GET /v1/external-foods?q=<optional search>&brand=<optional exact brand>
GET /v1/history?days=30
GET /v1/plans
GET /v1/targets
GET /v1/preferences
GET /v1/routine
```

Food lookup returns canonical foods, supported measurement units, and matching
products. Inventory reads return exact `foodId`, `productId`, and `lotId` values.
The GPT must reuse those identifiers rather than inventing them.

## Definitions and groceries

Create or update a canonical food:

```http
POST /v1/foods
Content-Type: application/json

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

Create a product only after its canonical food exists:

```http
POST /v1/products
Content-Type: application/json

{
  "foodId": "<food uuid>",
  "name": "Whole Milk 1 gal",
  "brand": "Lucerne",
  "packageQuantity": 1,
  "packageUnit": "gal",
  "servingQuantity": 8
}
```

Add reviewed lots atomically:

```http
POST /v1/groceries
Content-Type: application/json

{
  "source": "Safeway receipt",
  "items": [
    {
      "productId": "<product uuid>",
      "quantity": 1,
      "unit": "gal",
      "location": "fridge",
      "bestBy": "2026-09-12",
      "totalCost": 4.99
    }
  ]
}
```

`quantity` is converted to the canonical base quantity inside the database. The
unit may be a returned unit UUID, full name, or short name.

## Cooking and eating

Cooking and eating remain separate operations.

```http
POST /v1/prepare/recipe
Content-Type: application/json

{
  "recipeId": "<recipe uuid>",
  "servings": 4,
  "location": "fridge",
  "bestBy": "2026-09-04"
}
```

This deducts raw ingredients FEFO and creates a prepared batch. Eating it uses
the returned lot ID as `batchId`:

```http
POST /v1/consume/prepared
Content-Type: application/json

{
  "batchId": "<prepared lot uuid>",
  "servings": 1,
  "timestamp": "2026-08-31T19:00:00-04:00"
}
```

Quick consumption of one canonical food is also atomic:

```http
POST /v1/consume/inventory
Content-Type: application/json

{
  "foodId": "<food uuid>",
  "quantity": 1,
  "unit": "ct",
  "label": "Apple"
}
```

## Outside food

Search before saving. Saved outside foods are reusable `products` with
`is_external = true` and nutrition per consumed unit.

```http
POST /v1/external-foods
Content-Type: application/json

{
  "name": "Chicken Sandwich",
  "brand": "Chick-fil-A",
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

Log the saved food without inventory deduction:

```http
POST /v1/meals
Content-Type: application/json

{"externalFoodId":"<outside product uuid>","servings":1}
```

A one-off unidentified meal may instead provide `label` and nutrition fields.

## Planning and settings

`POST /v1/plans` replaces exactly the seven dates beginning at `weekStart`, then
rebuilds unchecked generated grocery shortages while preserving manual items.
Recipe and meal entries use `sourceId` and `scaleFactor`.

`POST /v1/grocery-items` adds a manual item. `POST /v1/targets`,
`POST /v1/preferences`, and `POST /v1/routine` replace their respective singleton
settings.

Google Calendar operations are intentionally not exposed in the Supabase GPT API
yet. Weekly planning uses the saved routine and any conflicts supplied in the
conversation; the GPT must state that external calendar conflicts were not checked.

## Errors

- `401` means the integration bearer credential is missing or invalid.
- `404` means the requested route or resource does not exist.
- `422` means validation or a database constraint rejected the request. Compound
  database functions roll back before returning this response.
- `500` indicates an unexpected server failure; do not claim the write succeeded.

Test the deployed API without exposing the token:

```powershell
.\tools\pantry_api.ps1 -Method GET -Path /v1/inventory
```
