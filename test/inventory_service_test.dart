import 'package:flutter_test/flutter_test.dart';
import 'package:pantry_inventory/models/pantry_models.dart';
import 'package:pantry_inventory/services/inventory_service.dart';

void main() {
  const egg = FoodDefinition(
    id: 'egg',
    name: 'Eggs',
    mode: QuantityMode.counted,
    baseUnit: 'each',
    conversions: [UnitConversion(unit: 'each', symbol: 'eggs', baseAmount: 1)],
  );
  const butter = FoodDefinition(
    id: 'butter',
    name: 'Butter',
    mode: QuantityMode.measured,
    baseUnit: 'gram',
    conversions: [
      UnitConversion(unit: 'gram', symbol: 'g', baseAmount: 1),
      UnitConversion(unit: 'cup', symbol: 'cups', baseAmount: 226.8),
    ],
  );
  final service = InventoryService();

  test('converts recipe units into food-specific base units', () {
    const recipe = Recipe(
      id: 'test',
      name: 'Test',
      servings: 1,
      ingredients: [
        RecipeIngredient(foodId: 'egg', amount: 1, unit: 'each'),
        RecipeIngredient(foodId: 'butter', amount: 0.25, unit: 'cup'),
      ],
      instructions: [],
    );

    final result = service.requirementsFor(recipe, 1, {
      'egg': egg,
      'butter': butter,
    });

    expect(result['egg'], 1);
    expect(result['butter'], closeTo(56.7, 0.0001));
  });

  test('deducts earliest-expiring lots first', () {
    final later = DateTime(2026, 9, 10);
    final sooner = DateTime(2026, 9, 1);
    final lots = [
      InventoryLot(
        id: 'later',
        foodId: 'egg',
        quantityBase: 6,
        location: StorageLocation.fridge,
        bestBy: later,
      ),
      InventoryLot(
        id: 'sooner',
        foodId: 'egg',
        quantityBase: 2,
        location: StorageLocation.fridge,
        bestBy: sooner,
      ),
    ];

    final result = service.planDeductions({'egg': 3}, lots);

    expect(result, hasLength(2));
    expect(result.first.lotId, 'sooner');
    expect(result.first.quantityBase, 2);
    expect(result.last.lotId, 'later');
    expect(result.last.quantityBase, 1);
  });

  test('fails the whole plan when any ingredient is short', () {
    final lots = [
      const InventoryLot(
        id: 'eggs',
        foodId: 'egg',
        quantityBase: 12,
        location: StorageLocation.fridge,
      ),
      const InventoryLot(
        id: 'butter',
        foodId: 'butter',
        quantityBase: 10,
        location: StorageLocation.fridge,
      ),
    ];

    expect(
      () => service.planDeductions({'egg': 2, 'butter': 20}, lots),
      throwsA(isA<InsufficientInventoryException>()),
    );
    expect(
      lots.first.quantityBase,
      12,
      reason: 'planning must not mutate inventory',
    );
  });
}
