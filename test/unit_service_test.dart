import 'package:flutter_test/flutter_test.dart';
import 'package:pantry_inventory/models/pantry_models.dart';
import 'package:pantry_inventory/services/unit_service.dart';

void main() {
  const units = UnitService();

  FoodDefinition food({
    required String name,
    required double quantity,
    required String unit,
    required String symbol,
    QuantityMode mode = QuantityMode.measured,
  }) => FoodDefinition(
    id: name.toLowerCase().replaceAll(' ', '-'),
    name: name,
    mode: mode,
    baseUnit: 'gram',
    displayUnit: unit,
    conversions: [
      const UnitConversion(unit: 'gram', symbol: 'g', baseAmount: 1),
      UnitConversion(unit: unit, symbol: symbol, baseAmount: quantity),
    ],
  );

  group('bestInventoryLabel', () {
    test('rounds large measured amounts', () {
      final bakingPowder = food(
        name: 'Baking Powder',
        quantity: 14.4,
        unit: 'tablespoon',
        symbol: 'tbsp',
      );

      expect(units.bestInventoryLabel(bakingPowder, 207), '~14 tbsp');
    });

    test('uses practical preferred units', () {
      final baileys = food(
        name: "Bailey's",
        quantity: 1,
        unit: 'milliliter',
        symbol: 'mL',
      );
      final butter = food(
        name: 'Butter',
        quantity: 113.4,
        unit: 'stick',
        symbol: 'sticks',
      );
      final chiliPowder = food(
        name: 'Chili Powder',
        quantity: 2.7,
        unit: 'teaspoon',
        symbol: 'tsp',
      );

      expect(units.bestInventoryLabel(baileys, 375), '375 mL');
      expect(units.bestInventoryLabel(butter, 793.8), '7 sticks');
      expect(units.bestInventoryLabel(chiliPowder, 127.6), '~47 tsp');
    });

    test('pluralizes countable units from either symbol form', () {
      final buns = food(
        name: 'Hamburger Buns',
        quantity: 1,
        unit: 'each',
        symbol: 'bun',
        mode: QuantityMode.counted,
      );
      final rotini = food(
        name: 'Rotini',
        quantity: 454,
        unit: 'box',
        symbol: 'boxes',
      );

      expect(units.bestInventoryLabel(buns, 8), '8 buns');
      expect(units.bestInventoryLabel(rotini, 454), '1 box');
    });
  });
}
