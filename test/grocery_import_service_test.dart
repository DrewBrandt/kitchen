import 'package:flutter_test/flutter_test.dart';
import 'package:pantry_inventory/data/seed_data.dart';
import 'package:pantry_inventory/models/pantry_models.dart';
import 'package:pantry_inventory/services/grocery_import_service.dart';

void main() {
  const parser = GroceryImportService();

  test('parses reviewed grocery rows with relative best-by dates', () {
    final lines = parser.parse(
      'food, amount, unit, location, best_by\nEggs, 12, each, fridge, +14\nMilk, 1, liter, fridge, 2026-09-01',
      SeedData.foods(),
      today: DateTime(2026, 8, 23),
    );

    expect(lines, hasLength(2));
    expect(lines.first.isValid, isTrue);
    expect(lines.first.foodId, 'egg');
    expect(lines.first.bestBy, DateTime(2026, 9, 6));
    expect(lines.last.bestBy, DateTime(2026, 9, 1));
  });

  test('rejects unknown foods and unsupported units without guessing', () {
    final lines = parser.parse(
      'Dragonfruit, 2, each\nButter, 1, gallon',
      SeedData.foods(),
    );

    expect(lines, hasLength(2));
    expect(lines.first.error, 'Food is not defined yet');
    expect(lines.last.error, contains('not configured'));
  });

  test('uses the food default location when the column is omitted', () {
    final line = parser.parse('Egg, 6, each', SeedData.foods()).single;

    expect(line.isValid, isTrue);
    expect(line.location, StorageLocation.fridge);
  });
}
