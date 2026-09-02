# Pantry GPT API

The Pantry GPT API is a Supabase Edge Function backed by PostgreSQL. It is the
stable boundary between plain-English requests and Pantry data: the GPT resolves
intent and ambiguity, while the API accepts only structured JSON and performs
validated database operations.

```text
https://xaetuqdtnolzspfvqvja.supabase.co/functions/v1/pantry-api
```

The complete Custom GPT contract is `docs/pantry-gpt-openapi.yaml`.
Every mutation defines its request object directly at the operation. Component
request-body references are intentionally forbidden because the Custom GPT Action
importer can collapse them to an empty `{}` call; the contract test enforces this
for every current and future write route.

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
- purchased-product logging creates a classified lot and consumes its portion together;
- voiding consumption returns deducted stock and also reverses a same-action acquisition.

Consequential create/consume requests carry a stable `requestId` UUID. The
database stores that request and its response in the same transaction as the
mutation. Retrying the same user intent with the same UUID returns the original
response without repeating any deduction, lot, batch, or history insert.

GPT-only functions are executable by `service_role`, not browser roles. Owner RLS
continues to protect direct browser access.

## Routes

Reads:

```text
GET /v1/inventory?includeDepleted=false
GET /v1/foods?q=<optional search>
GET /v1/foods/{uuid}
GET /v1/recipes?q=<optional search>
GET /v1/recipes/{uuid}
GET /v1/prepared-batches?includeDepleted=false&includeVoided=false
GET /v1/history?days=30&includeVoided=false
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
POST /v1/consume/manual
POST /v1/history/void
POST /v1/plans
POST /v1/grocery-items
POST /v1/targets
POST /v1/preferences
POST /v1/routine
PATCH /v1/foods/{uuid}
PATCH /v1/products/{uuid}
PATCH /v1/recipes/{uuid}
PATCH /v1/lots/{uuid}
PATCH /v1/history/{uuid}
```

Food lookup searches canonical names/aliases plus product names, brands, aliases,
and barcodes. Inventory returns exact `foodId`, `productId`, and `lotId` values
and each lot's acquisition type, full price/value, out-of-pocket cost, payer,
price provenance, and time precision. The GPT must reuse these IDs.

## Editing existing records

Partial edits preserve record identity and write before/after state to
`record_edits`:

```text
PATCH /v1/foods/{uuid}
PATCH /v1/products/{uuid}
PATCH /v1/recipes/{uuid}
PATCH /v1/lots/{uuid}
PATCH /v1/history/{uuid}
```

Read the record first and send only changed fields. Recipe `ingredients`, when
present, replace the complete ingredient list. Lot `remainingQuantity` creates a
ledger adjustment instead of overwriting stock history.

History reads include each consumption's nutrition completeness, direct cost,
and any linked inventory events, lots, and derived cost. Correct a purchased-food
cost without relogging it:

```json
{"purchaseTotalPrice":4.05,"purchaseOutOfPocketCost":4.05,"purchasePaidBy":"self","purchasePriceAsOf":"2026-08-26","costIsEstimated":false,"costSource":"Receipt"}
```

The `purchase*` fields update the originating purchase lot explicitly linked to
that history event, whether grocery or away from home. Nutrition and history
remain unduplicated.

Void a duplicate or incorrect history event without deleting its audit trail:

```json
{"id":"<history uuid>","reason":"Duplicate entry"}
```

The operation restores ordinary inventory deductions. For an atomic purchase and
consume action it also compensates the full acquired lot, so no phantom stock is
left behind. It refuses the reversal when that lot has later active uses.

Manual events can be corrected in place with `portionLabel`, `nutrition`,
`nutritionEstimate`, `components`, acquisition fields, and payment fields. The
nutrition object may contain only the values actually known;
setting it to `null` returns the event to unknown nutrition.

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
  "alwaysAvailable": false,
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
`packageUnit`. Printed serving information is separate:
`servingQuantity`/`servingUnit`, `servingLabel`, and `servingsPerPackage`.
The explicit package serving count is authoritative for whole-package nutrition
when a rounded net weight does not divide evenly. It also accepts
`estimatedCost`, `costSource`, and `costAsOf`. Package and serving quantities are
converted independently to the food's base unit.

Exact barcode or normalized brand/name/package matches return the existing
product. Merge an existing duplicate by PATCHing the duplicate product with
`mergeIntoProductId`, `archiveSourceFood`, and `reason`. Archive an unused food
or product by PATCHing it with `archive: true` and `reason`; records remain in
the audit trail and are hidden from ordinary searches.

Add reviewed lots atomically:

```json
{
  "requestId": "<stable request uuid>",
  "source": "Safeway receipt",
  "items": [{
    "productId": "<product uuid>",
    "quantity": 1,
    "unit": "gal",
    "location": "fridge",
    "bestBy": "2026-09-12",
    "totalPrice": 4.99,
    "outOfPocketCost": 4.99,
    "paidBy": "self",
    "costIsEstimated": false,
    "priceAsOf": "2026-08-26",
    "acquiredAt": "2026-08-26T17:00:00-04:00",
    "acquiredTimePrecision": "estimated"
  }]
}
```

The source and each lot's full price, out-of-pocket amount, payer, price date,
acquired time/precision, and estimate status are required. If no
receipt price is available, research a current exact-store listing or ask rather
than omitting cost. The unit may be a returned UUID, full name, or short name.

## Cooking and eating

Cooking and eating are separate. `POST /v1/prepare/recipe` is the single prepare
endpoint. `sourceType: recipe` deducts raw ingredients FEFO; `sourceType: manual`
creates ready-made or historical leftovers without a fake recipe/product or
retroactive ingredient deductions:

```json
{"requestId":"<stable request uuid>","sourceType":"recipe","recipeId":"<recipe uuid>","servings":4,"location":"fridge","bestBy":"2026-09-04","preparedAt":"2026-08-31T18:30:00-04:00","timePrecision":"estimated"}
```

`preparedAt` timestamps the preparation, output lot, and ingredient deductions;
it and `timePrecision` are required, including historical backfills.

Eat from its returned lot ID using `POST /v1/consume/prepared`:

```json
{"requestId":"<stable request uuid>","batchId":"<prepared lot uuid>","servings":1,"timestamp":"2026-08-31T19:00:00-04:00","timePrecision":"estimated"}
```

Quick use of one food goes through `POST /v1/consume/inventory`:

```json
{"requestId":"<stable request uuid>","foodId":"<food uuid>","lotId":"<exact lot uuid>","quantity":1,"unit":"ct","timestamp":"2026-08-31T12:00:00-04:00","timePrecision":"dateOnly","label":"Apple"}
```

Pass `lotId` when the user identifies the package being eaten. The lot must
belong to `foodId` and contain the whole requested quantity; the transaction
will not spill into another lot. Omit `lotId` to deduct the food FEFO. In both
cases, history `servings` is derived from the deducted product serving sizes.

All three operations roll back completely on insufficient inventory.

## Manual meals, purchased food, and retained leftovers

One-off homemade, shared, catered, or undocumented food does not need a canonical
food, product, or inventory lot. Log the consumed event directly:

```json
{
  "requestId": "<stable request uuid>",
  "label": "Spaghetti at Mom's",
  "portionLabel": "1 large plate",
  "timestamp": "2026-09-01T19:15:00-04:00",
  "timePrecision": "estimated",
  "nutrition": {
    "calories": 750,
    "proteinG": 28,
    "source": "Rough portion estimate",
    "estimated": true
  },
  "nutritionEstimate": {"confidence":"low","rationale":"Portion recalled after the meal"},
  "components": [{"label":"Spaghetti","portionLabel":"1 large plate"}],
  "acquisitionType": "home",
  "totalPrice": null,
  "outOfPocketCost": 0,
  "paidBy": "parents",
  "costIsEstimated": false,
  "costSource": "Shared family meal",
  "priceAsOf": null
}
```

Time/precision, structured components, acquisition, and payment provenance are
required. Omit `nutrition` when wholly unknown, or omit individual nutrient
properties when only a partial snapshot is known.
Unknown nutrients remain `NULL`; totals expose incomplete entry counts and must
not present known subtotals as complete daily nutrition.

Reusable, exactly identifiable restaurant, takeout, and packaged items may use
the same food and product definitions as groceries. Search first, then create only
a genuinely reusable missing canonical food or exact product variant. Acquire and
consume it through `POST /v1/consume/product`:

```json
{
  "requestId": "<stable request uuid>",
  "productId": "<product uuid>",
  "purchasedQuantity": 1,
  "consumedQuantity": 0.5,
  "quantityUnit": "ct",
  "acquisitionType": "takeout",
  "location": "fridge",
  "timestamp": "2026-09-01T08:30:00-04:00",
  "timePrecision": "exact",
  "totalPrice": 7.49,
  "outOfPocketCost": 7.49,
  "paidBy": "self",
  "costIsEstimated": false,
  "costSource": "Receipt",
  "priceAsOf": "2026-09-01"
}
```

Use `grocery`, `restaurant`, `takeout`, `office`, `gift`, `home`, or `other`.
Full value, Drew's out-of-pocket amount, payer, estimate status, source, and
price date are distinct and required (full value may be null only when genuinely
unknown). The operation
creates the classified lot, consumes half through the ordinary ledger, and leaves
half in the fridge. For a fully eaten purchase, set both quantities equal.
Both quantities must use the explicit `quantityUnit`; the API converts that unit
to the food's canonical storage unit transactionally. Never pre-convert to an
undocumented base amount.

## Planning and settings

`POST /v1/plans` replaces exactly the seven dates beginning at `weekStart`, then
rebuilds unchecked generated grocery shortages while preserving manual items.
Recipe and meal entries use `sourceId`, preparation `scaleFactor`, and
`plannedServings`. Preparation scale drives ingredient demand; planned servings
drive projected nutrition and must describe only the expected eaten portion.

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
