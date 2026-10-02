# Grocery demand repair (local candidate)

Based on frozen b323af3. Migration 202610010016 is separate from the held 202610020001 piece work. No live operations or publication.

Weekly pending pantry portions now share stock once with preparation demand. Exact-lot quantities are accounted for first, then required products, then generic ingredients. These are forecasts, not reservations or guarantees about later consumption. No expiry inference or changes to single-event consumption.

The single new nullable shopping_items.generated_product field identifies hard product demand separately from editable pinned_product preferences. Existing rows remain generic, with their IDs, receipts and user state intact. Rows with no current shortage become inactive, not deleted. Required products are shown compactly in shopping/receipt UI. A different-product receipt remains truthful and does not discharge required-product demand. Exact-lot overcommit within the displayed calendar week shows Check source alongside existing portion/remove controls.

Rebuild, generated-row receipt and receipt undo share reconcile_shopping_demand. Receipt-triggered reconciliation is limited to that food and the row's recorded window. Existing RPC signatures, security modes and ACLs remain unchanged. The new helper is security invoker, checks is_app_owner, and grants execute only to authenticated (besides its owner); no table grant or owner guard changes.

Validation covers separate one-portion occasions, mixed recipe demand, ingredient pins versus shopping preferences, product scopes, actual receipt substitution, unknown/free costs via existing regressions, preserved user state, canonical units, excluded portions, leftovers, repeated rebuild/undo and concurrent rebuild/receipt/undo.

Limits: shopping still records one receipt per row; a further purchase uses another row. A single product-consumption event still requires one sufficiently large lot. Exact-lot shortages are not automatically replaced with another source. Each requested window is forecast independently. Existing prepared-output ingredient conversion behavior is unchanged. Main integration and deployment remain separate, unauthorized steps for this task.

Validation: 250 frontend tests across 29 files, TypeScript, placeholder-auth production build, and the complete disposable PostgreSQL 17 suite passed. New grocery fixtures force deferred constraints before rollback; concurrency covers rebuild/rebuild, receipt/rebuild and rebuild/undo. Existing bundle-size warning remains. Browser/live acceptance was not run.
