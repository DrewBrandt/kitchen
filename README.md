# Pantry Inventory

A Flutter prototype for personal pantry, fridge, freezer, and recipe tracking.

The current vertical slice includes:

- counted and measured foods
- fractional counted quantities
- food-specific kitchen conversions
- separately expiring inventory lots
- recipe availability
- earliest-expiry-first recipe deductions
- quick consumption
- reversible history
- responsive desktop and mobile navigation

The app currently starts with local demo data so the domain behavior can be tested without connecting it to the SMD inventory Firebase project.

## Run

```sh
flutter run
```

## Verify

```sh
flutter analyze
flutter test
```

See `REQUIREMENTS.md` for the canonical model and Firebase migration plan.
