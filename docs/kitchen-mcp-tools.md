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

Total: 32 tools, 14 reads/previews and 18 writes. No settings-write or calendar tools.

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
before dispatch and never forwards the OAuth token upstream.

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

No exact planned-entry fulfillment, preparation undo/discard, receipt undo, or
calendar sync is claimed. General consumption does not fulfill a chosen plan
entry. edit_consumption supports the existing metadata/nutrition/manual portion
and linked-purchase corrections; it does not expose the separate app-only stock
consumed-quantity correction RPC. Do not pretend those unsupported actions ran.

Focused checks cover database query bounds and related-row truncation, existing
recipe/inventory serializer parity, official MCP discovery and owner rejection,
all operation schemas/routes, stable retry-ID forwarding, no automatic retries,
annotations and sanitized failures. No live test writes were needed; coordinated
browser verification remains separate. Refresh and every new live tool should
not be claimed proven by the original two inventory calls.
