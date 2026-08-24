# Potentially planned features

These ideas are recorded for future prioritization. They are not committed delivery promises unless promoted into an active milestone.

## Grocery intake and inventory capture

- Mobile **Put away groceries** mode with rapid barcode scanning, a review cart, package quantity, storage location, purchase date, and best-by date.
- Exact known-barcode matches that add inventory without re-entering product details.
- Reviewed unknown-product onboarding with product lookup, canonical-food mapping, package conversions, aliases, and label nutrition.
- Receipt-photo import that extracts products, quantities, and prices, matches known products, and flags ambiguous rows for review before an atomic import.
- Package, nutrition-label, and printed best-by-date photos to help fill unfamiliar product metadata while preserving human review.
- Quick scan-out for consuming, finishing, moving, opening, or discarding a product.
- Printable QR labels for homemade prepared batches and freezer containers so scans identify an exact batch rather than only a commercial product.

## Planning, cooking, and shopping

- Expiry-aware **Use this soon** recipe suggestions ranked by expiring ingredients, inventory coverage, and required grocery additions.
- Pantry minimums/par levels that automatically add staples to the grocery list when stock falls below a preferred amount.
- Focused shopping mode with large controls, aisle grouping, offline tolerance, quantity adjustments, and a reviewed **I bought this** conversion into inventory lots.
- Store-specific aisle ordering and, later, preferred-store or price-aware shopping suggestions.
- Calendar meal events in addition to grocery and preparation reminders after calendar reconciliation is proven reliable.
- Explicit recipe preparation rules for thawing, marinating, soaking, and batch preparation.

## Freshness, leftovers, and accuracy

- Opened-item tracking with food/product-specific refrigerated shelf life and recalculated use-by dates.
- Leftover and prepared-batch reminders based on best-by dates and remaining servings.
- Waste tracking for expired or discarded food, including recurring-waste insights and suggested package-size changes.
- Short, confidence-based inventory audits that prioritize old or uncertain records instead of requiring full recounts.

## Cost and convenience

- Receipt-derived price history, package-value comparisons, grocery-total estimates, and staple purchase forecasting.
- Voice-friendly quick actions for adding, consuming, moving, opening, and checking inventory.

## Active promotion

Google Calendar synchronization has been promoted from this backlog into active implementation. Its design and delivery sequence live in `docs/GOOGLE_CALENDAR_INTEGRATION.md`.
