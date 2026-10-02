# Frozen core with optional grocery demand

Documentation/status only. No main merge, push, live read, live SQL, deployment, or GPT editor change was performed. Feature work is frozen.

## Select an exact release scope

- Core: `codex/overnight-release-candidate` at `b323af3e79aea88806172add3603d7dbea1b1f26`, unchanged. See [core checklist](overnight-release-checklist.md).
- Optional grocery: `codex/grocery-demand`, reviewed code `519fa76b73f3e2bcdec27cfd6dec7646e5491954`, descends from core. A documentation-only successor does not change that code tree. See [grocery review](grocery-demand-review.md).
- Piece candidate `be4478587d732335c55fa7db892926aa7ff446ae` remains separate **HOLD** for incomplete security review. It is not in either release scope; exclude `202610020001`.

Local main and cached origin/main both resolve to `47cbc93a000b998a7ab6701e97a9a8ff1f5e465a`. This confirms local refs only, not current hosting, function revision, or remote migration history. No remote fetch or credentialed verification was performed.

## Order and expected migration delta

After explicit release authorization, verify actual target revisions, migration history, and historical fingerprints before any mutation. Relative to the locally recorded baseline through 012, the exact expected additions are:

1. `202610010013_atomic_owner_creation.sql`
2. `202610010014_allow_future_food_log_undo.sql`
3. `202610010015_preserve_recipe_post_updates.sql`
4. Only if grocery is included: `202610010016_planned_pantry_groceries.sql`

Stop on any unexpected migration or changed baseline; this list is not a live dry-run result. Apply only the selected reviewed sequence before deploying its dependent app. Deploy `pantry-api` from the same accepted candidate, then publish the app and verify both revisions; app hosting does not publish the function. Grocery adds no further API serializer changes beyond core. A later GPT action schema refresh is optional, separately authorized, and follows API deployment; core release does not depend on GPT configuration, and schema/configuration alone does not establish runtime action availability.

## Exact access and mutation scope

| Change | Access and mutations |
| --- | --- |
| 013 | New `public.owner_create_recipe(uuid,jsonb)` and `public.owner_append_plan(uuid,jsonb)`: authenticated EXECUTE; PUBLIC, anon and service_role EXECUTE revoked. SECURITY DEFINER with empty search_path, authenticated-role and owner checks. Atomically writes recipes/ingredients or plans/portions plus mutation-request replay records; append does not rebuild groceries. |
| 014 | Drops only `food_logs_check` after checking its exact definition. Allows actual undo time to precede an owner-entered future event time. No grant changes or timestamp rewrites. |
| 015 | Replaces existing service-only `gpt_save_recipe(jsonb)` behavior. Preserves omitted metadata and ingredient identity; rejects ambiguous/destructive legacy POST edits. Existing signature, guard, security settings and ACL retained. No bulk recipe rewrite. |
| Optional 016 | Adds nullable FK `shopping_items.generated_product`; existing rows stay generic. New **public direct RPC** `reconcile_shopping_demand(date,date,uuid)` has authenticated EXECUTE, with PUBLIC/anon/service_role revoked; SECURITY INVOKER (default), empty search_path, owner check and existing table permissions. No new internal schema or table grants. |
| 016 reconciliation | Locks shopping_items; deactivates/recalculates generated demand for the requested window, optionally filtered to one food. Inserts/updates generated shopping rows and eligible automatic quantities; keeps IDs, receipts and user-edited state. Null food means all generated food demand. Forecasts do not reserve or consume stock. Invalid/null/nonfinite/reversed dates reject before mutation. |
| 016 existing RPCs | Replaces rebuild, receipt and receipt-undo implementations without changing signatures/security modes/ACLs. Receipt retains its existing product/lot, received quantity, cost/audit and replay writes; undo retains its inverse inventory ledger and conditional seeded-price restoration. Both additionally reconcile that generated row's food and recorded window. |
| API/app | Additive inventory quantity/cost/piece-basis response fields and typed schema; UI workflow, neutral date wording and unit formatting changes. No authentication configuration, tokens, owner-guard changes or new API routes. |

The new authenticated RPC grants above are part of the release access scope; do not describe the entire release as having no access changes. Existing owner boundary and invoker permissions remain in force.

## Rollback limitations

- No reviewed automatic down-migration is supplied. Reverting app/function code does not undo migrations, generated shopping updates, receipts or other user actions. Do not delete migration history or drop generated_product as an improvised rollback; that loses product-demand identity and older reconciliation may misinterpret the new rows. Prefer a reviewed forward fix; any restore needs a separately agreed recovery point and data-loss scope.
- Reinstating the old 014 constraint can fail once future/date-only logs have been legitimately voided. Do not rewrite real action timestamps to force it back. Reverting 015 restores the legacy destructive POST behavior.
- Receipt undo is a business action, not schema rollback: consumed/adjusted stock or planned dependencies can prevent it, and later catalog price edits must survive. Forecasts are not reservations; one receipt per row and the existing single-lot consumption limit remain.

## Minimal authorized post-release acceptance

- Verify exact app/function SHAs, migration sequence, historical fingerprints and the above function ACL/security modes. Confirm owner operations succeed and non-owner/direct helper attempts are denied using approved test identities.
- Core: stage planned and unplanned copies of one recipe with distinct quantities; finish only the selected entry. Exercise grouped portions/leftovers, retry recovery, future/date-only undo, and a metadata-preserving POST edit on approved disposable records.
- Inventory: verify grams/ounces, volume and count pairs; package versus initial-lot basis; partial, unknown and zero value; unavailable conversions; legacy piece basis never presented as confirmed current count. Check pound/ounce carry and Today → Check dates → inventory.
- Grocery, if selected: combine recipe demand, multiple pantry portions, a hard product requirement and an exact-lot claim. Rebuild twice; stock is shared once and required-product rows stay distinct. Receive a different product truthfully, then undo where dependencies permit; unrelated windows/user edits must survive and required-product shortage must remain when appropriate.
- Confirm pantry product plans show Planned, external consumption No prep, and exact-lot overcommit Check source. Verify no consumption or reservation occurs merely from rebuilding. Clean up only the approved smoke fixtures and retain evidence of any partial failure.

## Evidence and remaining limits

Core: 248 tests, frontend TypeScript/build, API route/schema fixtures and full disposable PostgreSQL 013→014→015 suite passed. Grocery: independent reviewer 01a0f97e reported GO at 519fa76 with 254 tests, TypeScript/build and focused invalid-date SQL; prior full allocation/concurrency evidence remains applicable per that review. This documentation pass did not rerun those tests or independently verify live deployment. Existing bundle-size warning remains; browser/live acceptance is pending. All source branches are preserved.
