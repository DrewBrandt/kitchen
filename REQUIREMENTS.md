# Pantry Inventory Requirements

Last updated: 2026-08-23

## Product goal

A personal kitchen inventory that tracks pantry, fridge, and freezer stock; stores recipes; deducts ingredients when food is cooked or consumed; and makes expiration, nutrition, grocery, and recipe decisions easier.

## Core vocabulary

- **Counted food:** Stored as units and optionally consumed fractionally. Examples: `2 eggs`, `0.5 onion`, `1 yogurt`.
- **Measured food:** Stored in a canonical weight or volume and displayed in convenient recipe units. Examples: `1/4 cup butter`, `240 mL milk`.
- **Food definition:** The reusable identity and conversion rules for a food.
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

## Canonical data model

### `foods`

- `name`
- `quantity_mode`: `counted | measured`
- `base_unit`: `each | gram | milliliter`
- `allowed_units[]`: `{unit, symbol, base_amount}`
- `default_location`: `pantry | fridge | freezer`
- `nutrition_per_base_amount` (future)
- `barcode_aliases[]` (future)

Conversions are food-specific. One cup of butter and one cup of flour do not share a weight conversion.

### `inventory_lots`

- `food_id`
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

The eventual Firestore implementation must perform validation, deductions, and history creation in one transaction.

## Next milestones

1. Replace the in-memory store with a separately configured Firebase project.
2. Add recipe creation/editing and a food-definition editor.
3. Add pasted grocery text and CSV import with a review screen.
4. Add shopping-list generation and recipe suggestions.
5. Add nutrition, barcode lookup, receipt capture, and opened-item shelf life.
