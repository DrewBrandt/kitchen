# Set up the private Pantry GPT

This gives every conversation opened with the private GPT live access to the
Supabase pantry. A Knowledge upload alone cannot authenticate.

## 1. Deploy and verify the API

```powershell
npm run db:push -- --agent no
.\tools\setup_api_secret.ps1
npx supabase functions deploy pantry-api `
  --no-verify-jwt `
  --use-api `
  --project-ref xaetuqdtnolzspfvqvja `
  --agent no
.\tools\pantry_api.ps1 -Method GET -Path /v1/inventory
```

The secret script never prints the token. Supabase stores one copy and Windows
stores a DPAPI-encrypted copy outside the repository.

## 2. Configure the GPT

In ChatGPT, open or create the private **My Pantry** GPT and configure:

- Name: `My Pantry`
- Visibility: **Only me**
- Description: `Private pantry, nutrition, recipe, and weekly meal-planning assistant.`
- Enable Web Search. It is required for missing product and current nutrition
  research.

Paste all of `docs/PANTRY_GPT_INSTRUCTIONS.md` into Instructions. Keep it under
the editor's 8,000-character limit; the test suite enforces this.

Suggested starters:

- `Plan next week using what I have, while avoiding meals I ate recently.`
- `I just got groceries. Help me reconcile the list and upload it.`
- `Find three dinners I can make with one small store run.`
- `I ate this today; log it and compare it with my targets.`
- `What if I had a Chipotle burrito tomorrow? Do not save it.`

## 3. Add the Action

In **Actions**, create an Action:

1. Paste `docs/pantry-gpt-openapi.yaml` into Schema.
2. Set Authentication to **API key** and **Bearer**.
3. Run `tools/copy_api_token.ps1`.
4. Paste the clipboard value only into the Action authentication secret field.
5. Save, then clear the clipboard with `Set-Clipboard -Value ''`.

Never place the token in the schema, instructions, Knowledge, Git, or a chat.
The GPT-facing schema is intentionally capped at 30 operations for the Action
importer. Backend routes that are redundant for the GPT may remain available
without appearing in this schema.

## 4. Preview tests

Run these in Preview before relying on writes:

1. `Read my pantry and tell me how many eggs I have.`
2. `Search my saved foods and products for Chick-fil-A. Do not create anything.`
3. `Research the exact nutrition for a packaged product that is not saved. Cite
   the source and do not write anything.`
4. `What if I had one researched Chipotle burrito tomorrow? Compare it with
   everything logged and planned for that date, but do not save anything.`
5. `Show my current meal plan and grocery list.`
6. `Propose adding Coffee filters as a manual grocery item, but do not add it.`
7. Inspect the imported schema for `consumePurchasedProduct` and confirm its request
   body lists `productId`, `purchasedQuantity`, `consumedQuantity`, `quantityUnit`, `location`,
   timestamp, cost, label, and note fields.
8. Inspect `editConsumptionEvent` and confirm it exposes `purchaseTotalPrice`,
   `costIsEstimated`, and `costSource` without requiring nutrition fields.
9. Inspect `logManualConsumption` and confirm timestamp/precision, components,
   acquisition, price/payer provenance, and a stable request ID are required;
   verify it has no `foodId`, `productId`, or inventory-location field.
10. Inspect `saveMealPlan`: it must require `mode` and `entries`, support
    `append`/`replaceWeek`, and expose product, inventory-lot, and
    `consumeFromInventory` fields. Confirm `previewDailyNutrition` is not marked
    consequential. Spot-check every write Action for a non-empty body.

The first two should call read Actions; the third and fourth should use Web
Search and cite sources. The sixth must stop before writing. The seventh through tenth catch
imported empty `{}` tool contracts before they can
reach the database. Then explicitly confirm the test write, verify it in the web
app, and remove it.

Current-editor caveat (observed 2026-09-02): an Action row's **Test** button
immediately sends a generic “Call the API” prompt to Preview instead of opening
an inspectable request-body form. Do not click **Test** on a consequential
operation merely to inspect its fields. Verify the parsed operation list and
schema here, run `npm test`, and use an explicitly read-only Preview prompt.

`401` means the Action bearer value does not match the Supabase secret. `422`
means validation rejected the request without a partial compound write.

Ordinary ChatGPT conversations do not inherit this private Action; use **My Pantry**
whenever live access is needed.

## Updating the integration

Repository changes do not update the deployed function or private GPT. After an
API or behavior change:

1. Apply new migrations.
2. Deploy `pantry-api`.
3. Replace the complete GPT Instructions.
4. Replace the complete Action schema.
5. Repeat the read-only Preview tests.
