# Pantry Inventory Requirements

Last updated: 2026-08-23

## Product goal

A personal kitchen inventory that tracks pantry, fridge, and freezer stock; stores recipes; deducts ingredients when food is cooked or consumed; and makes expiration, nutrition, grocery, and recipe decisions easier.

## Core vocabulary

- **Counted food:** Stored as units and optionally consumed fractionally. Examples: `2 eggs`, `0.5 onion`, `1 yogurt`.
- **Measured food:** Stored in a canonical weight or volume and displayed in convenient recipe units. Examples: `1/4 cup butter`, `240 mL milk`.
- **Canonical food:** The brand-independent ingredient identity and recipe conversion rules.
- **Product:** A purchasable branded item mapped to one canonical food, with optional barcode, aliases, package conversions, and label nutrition.
- **Inventory lot:** A separately purchased quantity with its own location and best-by date.
- **Consumption:** An atomic, reversible set of lot deductions caused by cooking or quick use.

## MVP behavior

1. Show totals across pantry, fridge, and freezer lots.
2. Add groceries as new lots.
3. Show counted/measured status clearly.
4. Accept fractional counted quantities.
5. Convert recipe units through food-specific conversion tables.
6. Deduct the earliest-expiring eligible lots first.
7. Reject an entire cooking action if any ingredient is insufficient.
8. Record exact lot deductions and allow one-click undo.
9. Highlight lots expiring within seven days.
10. Create and edit food definitions, conversions, and recipes in the app.
11. Review structured grocery rows before applying any of them.

## Codex interaction contract

The normal long-term workflow is conversational:

1. The user describes groceries in English or asks Codex to import a recipe.
2. Codex reads the current structured inventory through the authenticated API.
3. Codex resolves names and units, preserving a recipe source URL when applicable.
4. Codex asks about materially ambiguous package quantities instead of guessing.
5. Codex sends validated JSON to the food, grocery, or recipe endpoint.
6. The API validates the complete request before committing any writes.

Natural language is deliberately not accepted by the mutation endpoint. Interpretation belongs in the conversation layer; the durable API remains deterministic and testable. The bearer token is stored as a Supabase Edge Function secret and is never embedded in a client.

## Canonical data model

### `foods`

- `name`
- `quantity_mode`: `counted | measured`
- `base_unit`: `each | gram | milliliter`
- `allowed_units[]`: `{unit, symbol, base_amount}`
- `default_location`: `pantry | fridge | freezer`
- `nutrition_per_base_amount` (future)
- `aliases[]`

Recipes and grocery shortages reference canonical foods only.

### `products`

- `food_id`
- `name`
- `brand`
- `aliases[]`
- `barcode` (nullable)
- `conversions[]`: product/package units expressed in the canonical food's base unit
- `nutrition` (nullable label nutrition)

Conversions are food-specific. One cup of butter and one cup of flour do not share a weight conversion.

### `inventory_lots`

- `food_id`
- `product_id` (nullable for legacy or genuinely generic stock)
- `quantity_base`
- `location`
- `purchased_at`
- `best_by`
- `opened_at` (future)
- `price` (future)

### `recipes`

- `name`
- `servings`
- `ingredients[]`: `{food_id, amount, unit, optional}`
- `instructions[]`
- `tags[]` (future)
- `nutrition_snapshot` (future)

### `consumption_history`

- `label`
- `recipe_id` (nullable)
- `servings` (nullable)
- `timestamp`
- `deductions[]`: `{lot_id, food_id, quantity_base}`
- `undone_at` (nullable)

## Transaction rules

Cooking is all-or-nothing. The service first converts every ingredient to its food's base unit, validates the complete demand, and plans deductions ordered by best-by date. Only after every ingredient is available are lot quantities updated and a history record written. Undo restores the exact lots originally used.

The PostgreSQL implementation performs validation, deductions, and history creation in one transaction.

## Next milestones

1. Configure the private GPT with the deployed Supabase Action.
2. Replace the paused calendar synchronization with a Supabase-native server integration.
3. Add receipt capture and opened-item shelf life. Nutrition and reviewed
   barcode lookup are implemented.
