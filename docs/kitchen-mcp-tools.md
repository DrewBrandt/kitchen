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

Total: 35 tools, 14 reads/previews and 21 writes. No settings-write or calendar tools.

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

Preparation undo, receipt undo, and calendar sync remain unsupported. General
consumption does not fulfill a chosen plan entry; use fulfill_planned_entry. edit_consumption supports the existing metadata/nutrition/manual portion
and linked-purchase corrections; it does not expose the separate app-only stock
consumed-quantity correction RPC. Do not pretend those unsupported actions ran.

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
cook an unprepared recipe. Recipe-plan fulfillment requires a batch already
linked to that plan by the app; prepare_batch does not create that linkage.
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
