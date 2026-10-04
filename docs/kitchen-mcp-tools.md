# Kitchen MCP ordinary tools

Approved 2026-10-03: reuse the connected owner/client/audience and existing API.
No new credentials, scopes, signing settings, role grants or database migrations.
The read increment was deployed from `8799b0e`; the following operation increment
adds writes and corrections together. Final deployment commit/version is reported
in the implementation handoff; repository presence alone is not connection proof.

## Tools and source operations

All routes below are under the existing pantry-api `/v1` namespace.

| Tools | API |
|---|---|
| get_inventory | GET inventory, existing bounded lots |
| get_preferences, get_targets, get_routine | GET preferences, targets, routine |
| find_foods, get_food, find_products | GET foods (paged canonical-name search), foods/{id}, products (paged name/brand or exact barcode) |
| find_recipes, get_recipe | GET recipes (paged name search), recipes/{id} |
| get_prepared_foods | GET prepared-batches, paged with depleted/voided flags |
| get_plan, get_groceries | GET plans, independently paged entries/groceries collections; inclusive local date filters for entries |
| get_history | GET history, paged, days 1–365 and optional voided events |
| preview_daily_nutrition | POST plans/preview, read-only despite POST |
| save_recipe, edit_recipe | POST recipes, PATCH recipes/{id} |
| save_meal_plan, add_grocery_item | POST plans, grocery-items |
| save_food, edit_food, save_product, edit_product | POST/PATCH foods and products |
| add_grocery_haul, reconcile_inventory, edit_inventory_lot | POST groceries/inventory, PATCH lots/{id} |
| prepare_batch | POST prepare/recipe; saved recipe or manually described leftovers |
| consume_prepared, consume_inventory, consume_purchased_product, log_manual_consumption | POST consume/prepared, inventory, product, manual |
| edit_consumption, void_consumption | PATCH history/{id}, POST history/void |

Total: 39 tools, 14 reads/previews and 25 writes. No settings-write or calendar tools.

## Implementation and use

Read preferences before cooking/planning; combine product inventory with prepared
batches. Resolve exact variants and IDs, preserve returned units and recipe piece
basis (GET piece_basis maps to write pieceBasis), provenance and unknown values.
Before scheduling, read routine/plan/history. A preview never saves anything.
Cooking and eating are separate. Patch existing records; omit ingredients to
preserve them, supply the complete replacement list when changing ingredients.
Undo wrong consumption using its event ID/reason rather than a cancelling event.
These concise rules are delivered in MCP initialization instructions and tool
descriptions; the old GPT instructions/configuration are unchanged.

New list calls require bounded pages, default 20, maximum 50. Query bounds and
filters run in Postgres before serialization, with deterministic ID tie-breakers,
exact totals and nextOffset. Related rows are restricted to the selected IDs;
if a relationship exceeds 1,000 rows the request fails explicitly rather than
silently truncating. Use smaller pages or exact detail reads. Pages are live,
not snapshots; restart after concurrent changes. Read groceries separately from
plan entries. Name search is substring-based, not semantic or alias search; page
the catalog or use exact barcode/IDs when needed.

Existing serializers and domain RPCs are reused. Unpaged legacy routes retain
their existing contracts; no old-GPT changes are needed. The API remains behind
its existing server-only credential. MCP validates the same owner/client/audience
before dispatch. The pantry-api adapter never receives the OAuth token.

`scripts/generate-kitchen-tools.mjs` generates operation-schemas.json from the
existing OpenAPI write bodies. Run it after changing those contracts. Tests check
for schema drift. Runtime Zod validates inputs; domain validation remains in the
existing API/database. Path IDs are removed from PATCH bodies. Empty patches and
replaceWeek without weekStart fail before sending a write.

Each call makes one upstream attempt. Stable domain requestId is required only
where already supported: reconciliation, grocery hauls, preparation and the four
consumption creates. Reuse it for the same action after an ambiguous failure;
changed arguments are a new approved action. Audit request IDs are separate.
Recipe/plan saves, manual grocery insertion and PATCH/void operations have no
generic retry guarantee: read back after ambiguous failure, never automatically
repeat. Append adds entries; replaceWeek replaces seven days and preserves manual
groceries through the existing transaction.

Read/previews have readOnlyHint=true, destructiveHint=false, idempotentHint=true.
Writes have readOnlyHint=false; only supported request-key operations advertise
idempotentHint=true. DestructiveHint=true marks edits, replacements, deductions,
preparation, purchase-and-consume, and voids; purely additive tools use false.
All tools have openWorldHint=false. Annotations describe effects, not permission.

Validation errors return locally authored actionable categories (stock, units,
provenance, missing records or bounds), never raw database/network errors. Logs
contain tool name, generated audit ID, status and optional row count, not arguments,
inventory content or credentials. Request bodies remain capped at 16 KiB.

## Deliberate gaps and verification

Calendar sync remains unsupported. General consumption does not fulfill a chosen
plan entry; use fulfill_planned_entry. Use edit_consumption for supported metadata,
nutrition/manual portion and linked-purchase corrections. Use the bounded correction
adapters below for whole preparation undo, app shopping receipt undo and single-lot
consumed quantity correction.

Focused checks cover database query bounds and related-row truncation, existing
recipe/inventory serializer parity, official MCP discovery and owner rejection,
all operation schemas/routes, stable retry-ID forwarding, no automatic retries,
annotations and sanitized failures. No live test writes were needed; coordinated
browser verification remains separate. Refresh and every new live tool should
not be claimed proven by the original two inventory calls.

## Exact plan consumption and waste correction

Three narrow adapters reuse the existing authenticated app RPCs directly at the
same project's `/rest/v1/rpc/` endpoint. They use the verified owner OAuth session,
just as the existing is_app_owner check does, plus the existing public project
key. There are no new grants, migrations, scopes or credentials; the service-role
pantry API is not used for these authenticated-only transactions. The endpoint and
RPC names are fixed, redirects fail, and each invocation makes one attempt.

| Tool | Existing app RPC | Result |
|---|---|---|
| fulfill_planned_entry | consume_planned_meals(request ID, one plan ID, one eaten serving quantity, timestamp) | foodLogIds, status fulfilled |
| discard_inventory_lot | set_inventory_lot_quantity(request ID, lot ID, remaining quantity, discard=true, reason) | adjustmentEventId, status discarded or unchanged |
| undo_inventory_adjustment | undo_inventory_adjustment(event ID) | status undone |

Fulfillment selects an exact meal-plan entry, consumes using its existing source
and stock rules, and links the food log to the planned consumption. It does not
cook an unprepared recipe. Recipe-plan fulfillment requires a batch linked to that plan. Use
prepare_planned_recipe for that linkage; prepare_batch remains unplanned.
An inventoryLot plan can instead reference a prepared batch explicitly. Discard supports prepared lots (servings) and product
lots (their returned base units); remainingQuantity means the quantity left,
not the amount discarded. Waste changes stock/cost without changing eating or
nutrition. Undo reverses the exact discard/adjustment event, not the preparation.
The event ID is returned immediately for later undo; general food history is not
a waste-event listing. Read back the affected plan and/or lot after each write.

Fulfillment and discard preserve the app's request/payload deduplication. Reuse
both requestId and identical arguments after an ambiguous outcome. Undo is itself
idempotent for the same event. All three advertise destructive writes and
idempotentHint=true. They return only validated IDs/status, never raw RPC errors.
Focused signed-token MCP tests cover discovery, owner/client/audience rejection,
exact requests, no-op discard, void responses, bounds and sanitized failures.
Existing disposable SQL tests cover plan linkage and partial waste, costs,
unchanged nutrition, retry and reversal. These tests are not a connected ChatGPT
write proof; no new live records were created for this increment.

## Planning context correction

Prepared reads already return preparedAt, timePrecision, location and bestBy.
Their status=available means nonvoided quantity remains, not verified usability.
MCP inventory/prepared results now put a locally authored planningContext before
stock data. Tool descriptions and initialization instructions require stale or
missing storage/date caveats BEFORE any recommendation, and offer fresh cooking
or verified alternatives rather than relying on old refrigerated stock. No rows,
dates or quantities are changed or silently filtered. Missing bestBy is not
reassurance; dates alone are not a safety diagnosis. The narrow cooked meat/poultry
refrigeration guidance and continuous-freezing distinction cite
[FoodSafety.gov](https://www.foodsafety.gov/food-safety-charts/cold-food-storage-charts).
There is no generalized shelf-life classifier or inferred freeze/thaw history.

Plan reads and save_meal_plan discovery describe one preparation followed by
linked leftovers: save/read back the prepare entry, then append later leftover
entries referencing its exact ID and recipe. Group IDs are not source links.
Already-cooked food uses inventoryLot/consume. MCP rejects missing/contradictory
leftover source arguments before forwarding. Existing database validation still
checks source existence and recipe; comparing source and leftover dates/portions
requires reading the plan as instructed, not a new database constraint.

Synthetic checks preserve old/fridge, frozen and unknown records while returning
context first, verify serialization of original date/storage fields, and exercise
rejected/valid linked-plan arguments. They do not prove model recommendation
quality: repeat the focused dinner scenario in a fresh @Mise chat after refreshing
tools. No live plan, cooking or inventory mutation was used for this correction.

## Planned recipe preparation

`prepare_planned_recipe` adds one authenticated adapter to the existing retryable
app `prepare_recipe` overloads. No grants, migrations, scopes or credentials are
changed. `prepare_batch` retains its existing unplanned/manual/backfill behavior.
Never invoke both for one cooking event. The new tool always sets eaten servings
to zero: preparation and eating remain separate actions.

Callable arguments (unknown properties rejected):

| Field | Type / meaning |
|---|---|
| requestId | Required UUID; identical ID and payload on ambiguous retry |
| recipeId | Required saved recipe UUID |
| mealPlanId | Required UUID of an existing matching recipe preparation plan |
| timestamp | Required offset-bearing date-time for cooking now; app records batch creation now, so this tool is not historical backfill |
| location | Required `fridge` or `freezer` |
| servingsMade | Optional positive actual yield; omit for recipe servings × effective scale |
| pieceInputs | Optional nonempty array, maximum 50, distinct ingredient IDs |
| pieceInputs[].ingredientId | Required recipe ingredient UUID |
| pieceInputs[].lotId | Required matching inventory lot UUID |
| pieceInputs[].pieces | Required positive multiple of 0.25; requested pieces, not servings or evidence of a physically counted lot |
| pieceInputs[].expectedRemaining | Required positive latest lot quantity in grams; stale stock is rejected |
| pieceInputs[].weightGrams | Optional positive actual selected-piece weight; requires saved recipe piece basis |
| pieceInputs[].scaleRecipe | Optional boolean; true on an anchor uses selected weight / anchor grams as whole-recipe scale |
| pieceInputs[].useIngredientNutrition | Optional boolean; explicitly choose ingredient nutrition for changed proportions |

Without pieceInputs the adapter sends the normal retryable overload. With them it
sends the piece overload, once, without fallback or retries. It never supplies
lotPieces: if neither a saved recipe basis nor a recorded lot basis exists, the
transaction rejects the input instead of inventing/writing a count. Explicit
weight changes grams; it does not prove that a lighter whole lot contains four
pieces. All other ingredients still must cover the effective scale. Existing
nutrition-override checks apply. Plan scale is used unless an explicitly selected
anchor overrides it; servingsMade changes yield, not ingredient deduction scale.

The result contains prepId, lotId, mealPlanId, servingsMade, servingsRemaining,
location, foodLogId=null, and auditRequestId. Read back the plan and prepared lot;
then fulfill_planned_entry can consume the dinner and exact linked leftover entry.
Do not append a second dinner consumption row: a preparation plan already owns its
planned consumption. A small synthetic SQL check verifies this linkage, shortage
rollback, replay, weight-derived yield, and unchanged null piece count.

Minimal invocation shape (replace placeholders with actual returned UUIDs and the
current offset-bearing cooking timestamp; do not execute as literal text):

```json
{
  "requestId": "<stable UUID>",
  "recipeId": "<saved recipe UUID>",
  "mealPlanId": "<saved preparation plan UUID>",
  "timestamp": "<current cooking-action timestamp>",
  "location": "fridge"
}
```

For selected pieces, add pieceInputs with verified ingredient/lot IDs and the
latest remaining quantity. Do not fill in a physical count or selected weight
from the recipe estimate. A representative verification path is: read all
ingredients/inventory and generated shortages; save/read back preparation and
linked leftover plans; cook once with this tool; read back matching mealPlanId and
actual yield; fulfill the chosen entry only when eating is actually reported.
No live cooking was performed for this adapter. The browser-observed stale batch
“Ready to eat”/unknown-status label in the existing app UI remains a separate gap;
this change does not redesign that UI or food-storage policy.

## Cross-week grocery dependencies

A saved grocery list has its own persisted date range. Selecting a different UI
week does not regenerate it. The UI explicitly warns when stored ranges are
unknown, mixed or do not all cover the selected week. MCP requires checking those
ranges against requested meal AND source-preparation dates before claiming
coverage; empty results do not prove that all ingredients are present.

reconcile_shopping_demand now expands its requested range to include pending
source preparations referenced by unfulfilled leftovers across week boundaries.
Expansion closes over dependencies exposed by the wider range. Each pending
preparation still counts once; already-made sources add no raw-ingredient demand.
Effective dates are saved on existing grocery rows. No new tables or grants,
historical repair DML, or live fixture rebuild are part of deployment. Existing
row IDs, manual items, checks, notes, pins, edited quantities and receipt fields
are retained. Inactive generated rows remain stored; their range metadata still
describes the latest reconciliation, as before.

The paged grocery API filters inactive generated rows before counting/paging. It
hydrates only selected food/product/unit IDs and supplies name, foodName,
requiredProductName, pinnedProductName, unitAbbreviation and quantityDisplay.
Canonical qty_needed and source/range fields remain unchanged. Significant-digit
formatting keeps small positive quantities nonzero. Unknown names remain null.
This is a saved unacquired list, not an automatic forecast for read-time dates.

Focused SQL checks cover successive Sunday preparation/Monday leftover appends,
source shortages without duplicate demand, existing plans, manual items,
checked/edited progress, repeated rebuilds and retained inactive rows. The live
fixture needs an explicit owner rebuild for Oct 5-11 (now expanded to Oct 4-11)
to refresh its snapshot after deployment. No live rebuild or plan edit was run.


## Bounded reversal and quantity correction

Consumption tools, correction/void tools and history discovery now distinguish a
pending approval from a committed event. A revision of an unexecuted action must
revise that intent, not select a similar older history entry. Corrections require
a successful returned event in the current conversation or an existing meal the
user explicitly identifies; ambiguous targets require clarification. Superseded
approvals must be declined/cancelled before a replacement can execute. Ambiguous
outcomes require reconciliation; identical retries retain their request ID,
whereas revised actions use a fresh one. Clear new eating reports need no extra
confirmation merely because a similar meal exists.

These instructions are emitted in both initialize and tools/list (including the
quantity correction foodLogId field), not only this document. Date-only eating
reports use dateOnly/local noon rather than claiming the logging clock is the
exact eating time. The planned-fulfillment RPC lacks a precision field, so unknown
actual times need clarification without abandoning plan linkage. This is model
guidance, not a server-enforced conversation ledger or proof of correct intent.

These three authenticated RPC adapters preserve the existing owner, client, audience
and scopes. Existing authenticated execution privileges are reused; no migration,
new grant or credential is required. All three advertise readOnlyHint=false,
destructiveHint=true, idempotentHint=true and openWorldHint=false.

Exact argument objects (all fields required; additional fields rejected):

```ts
undo_preparation({ prepId: UUID })
undo_grocery_receipt({ requestId: UUID, lotId: UUID })
correct_consumed_quantity({ requestId: UUID, foodLogId: UUID,
  expectedQuantity: number /* > 0 */, quantity: number /* > 0 */ })
```

- undo_preparation calls undo_prep. It restores ingredients, reverses remaining
  output stock, retains history and resets its source preparation plan. Any active
  output stock event blocks undo, including eating, waste, adjustment or downstream
  cooking. There is no automatic cascade. Future leftovers wait for preparation
  again; review exact-lot plans. Repeating the same prepId is harmless.
- undo_grocery_receipt calls undo_inventory_receipt. Only lots from the app's
  receive-shopping-item workflow qualify, with their source item still present.
  Generic hauls, imports and purchase-and-consume logs do not qualify. Active stock
  events, changed stock or a pending exact-lot plan block reversal. It retains
  history and later shopping edits/progress, and conditionally restores only receipt
  seeded prices that have not subsequently changed. Results are lotId, optional
  itemId and status `undone` or `already undone`.
- correct_consumed_quantity calls the identically named RPC. Only one active raw
  inventory/prepared lot deduction qualifies; manual, purchase-linked, multi-lot,
  voided/replaced or stale events are rejected. expectedQuantity is the positive
  magnitude of the active eaten inventoryEvents[].quantity_delta from get_history.
  Both quantities use that lot's canonical unit (g, fl oz, count, or prepared
  servings). Increased consumption cannot exceed original consumption plus remaining
  stock. Zero requires void_consumption. Replacement retains audit history, scales
  nutrition/cost and rebinds planned consumption. The result is status, id,
  originalId, lotId, quantity and unit (unit omitted for unchanged quantity).
  Subsequent correction/void calls must use the returned replacement id.

For the request-key operations, reuse the same requestId and identical arguments
only for an ambiguous retry. No adapter retries automatically. Dependency failures
return a safe local explanation and require readback, never compensating writes,
automatic dependent reversals or plan deletion.

Representative connected verification after refreshing Mise: read get_history,
select an explicitly authorized eligible single-lot consumption, capture its current
canonical quantity and ID, call correct_consumed_quantity with a fresh requestId,
then read history and inventory to verify the replacement ID and stock delta. This
requires user-authorized live data changes; synthetic tests and deployment alone do
not prove that connected path. Preparation and receipt undo likewise need eligible
records and separate user intent. No existing dev data is reset for verification.
