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
- food-definition and conversion editing
- recipe creation and editing
- reviewed bulk grocery import
- authenticated Firebase API scaffold for Codex-driven updates

The app currently starts with local demo data so the domain behavior can be tested without connecting it to the SMD inventory Firebase project. The separately deployable API scaffold in `functions/` defines how Codex will read inventory and upload grocery hauls or recipes after a pantry Firebase project is configured.

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
See `docs/API.md` for the Codex integration contract and deployment authentication model.
