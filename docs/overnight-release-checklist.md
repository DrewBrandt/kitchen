# Overnight release candidate

Feature scope is frozen. This is a local candidate; no release or live operation has been performed.

The candidate combines reviewed core `24fc3e1`, inventory API parity `5983355`, and Check dates `38ee8c2` on `codex/overnight-release-candidate`. All source branches are preserved. The separate piece-state branch is excluded.

## Later deployment requirements

After authorization and target-state verification, the core app/migration/API release needs the following:

1. Apply only the reviewed pending migrations, in order: `202610010013_atomic_owner_creation.sql`, `202610010014_allow_future_food_log_undo.sql`, and `202610010015_preserve_recipe_post_updates.sql`. Verify the deployed baseline and historical migration fingerprints first; stop on unexpected pending migrations.
2. Deploy the application from the exact accepted candidate.
3. Separately deploy the `pantry-api` function from that same candidate. App hosting does not deploy the inventory serializer.

An optional GPT action schema refresh from `docs/pantry-gpt-openapi.yaml` requires separate authorization after the matching API function is deployed. The core app/migration/API release does not depend on editing GPT configuration. Neither the repository schema nor a configuration refresh establishes runtime action availability; that requires separate verification.

No authentication configuration or owner-guard changes are required by this integration. Retain the reviewed permissions and do not alter tokens, authentication settings, or existing ACLs as a deployment workaround.

## Next-day acceptance

- Verify exact deployed app/function revisions and migration history; confirm owner and non-owner access behavior remains as reviewed.
- Build a two-dish meal with different Make/Eat quantities. Confirm atomic portions, exact plan IDs, partial-group visibility, and leftovers tied to their source batches.
- Stage the same recipe as planned and unplanned. Finish only the selected entry; verify repeated staging and uncertain-response recovery do not duplicate cooking or fulfill a different plan.
- Check immediate undo for future/date-only logs and verify POST recipe edits preserve ingredient IDs, notes, pins, and omitted nutrition basis; destructive legacy POST updates must reject atomically.
- Read representative inventory through the deployed API and GPT schema: canonical `quantityBase` pairs only with `baseUnit`; `displayQuantity` pairs with `displayUnit`. Verify package/initial quantity bases, original-lot price versus remaining value, unknown versus zero cost, and unavailable cross-dimension conversions. Legacy piece metadata must not be presented as confirmed current pieces.
- Smoke-test Today’s Check dates action, inventory detail, and pound/ounce carry formatting. Check the deployed mobile/desktop UI without extending feature scope.

## Validation limits

Local tests exercise actual API route/serializer code against fixture transport and disposable PostgreSQL with synthetic records. They do not replace deployed function, GPT action-schema, or browser acceptance. The existing large-bundle warning remains. This work does not establish the cause of the earlier unverified GPT preview prose.

## Local validation evidence

- Full frontend suite: 248 tests passed across 28 files, including actual API route/schema regressions.
- TypeScript and production build passed; existing bundle-size warning only.
- Complete disposable PostgreSQL 17 suite passed with migrations 013, 014, and 015 applied in order, including grouped cooking/consumption/undo, grouped POST metadata, concurrent requests, and preservation checks.
- Tracked changes relative to deployed baseline were inspected for credentials, live-data artifacts, and accidental build output. No such additions were found; the detected email is a synthetic example.test fixture.
