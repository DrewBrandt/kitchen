import 'package:flutter_test/flutter_test.dart';
import 'package:pantry_inventory/models/pantry_models.dart';
import 'package:pantry_inventory/services/food_match_service.dart';

void main() {
  const rice = FoodDefinition(
    id: 'long-grain-white-rice',
    name: 'Long-grain white rice',
    mode: QuantityMode.measured,
    baseUnit: 'gram',
    conversions: [UnitConversion(unit: 'gram', symbol: 'g', baseAmount: 1)],
    aliases: ['enriched long grain rice'],
  );
  const riceProduct = ProductDefinition(
    id: 'good-gather-rice',
    foodId: 'long-grain-white-rice',
    name: 'Enriched Long Grain White Rice',
    brand: 'Good & Gather',
    aliases: ['Target long grain rice'],
    barcode: '085239018459',
    conversions: [UnitConversion(unit: 'bag', symbol: 'bag', baseAmount: 907)],
  );
  const flour = FoodDefinition(
    id: 'rice-flour',
    name: 'Rice flour',
    mode: QuantityMode.measured,
    baseUnit: 'gram',
    conversions: [UnitConversion(unit: 'gram', symbol: 'g', baseAmount: 1)],
  );
  const matcher = FoodMatchService();

  test('product aliases and barcodes resolve to the canonical food', () {
    for (final input in ['Target long grain rice', '085239018459']) {
      final result = matcher.match(input, [rice, flour], [riceProduct]);

      expect(result.canApplyAutomatically, isTrue);
      expect(result.best!.food.id, rice.id);
      expect(result.best!.product!.id, riceProduct.id);
    }
  });

  test('new brand wording can strongly suggest a canonical ingredient', () {
    final result = matcher.match(
      'Mahatma enriched long grain white rice',
      [rice, flour],
      [riceProduct],
    );

    expect(result.canApplyAutomatically, isTrue);
    expect(result.best!.food.id, rice.id);
  });

  test('does not automatically equate a one-word food with a compound', () {
    const genericRice = FoodDefinition(
      id: 'rice',
      name: 'Rice',
      mode: QuantityMode.measured,
      baseUnit: 'gram',
      conversions: [UnitConversion(unit: 'gram', symbol: 'g', baseAmount: 1)],
    );
    final result = matcher.match('rice flour', [genericRice, flour], const []);

    expect(result.best!.food.id, flour.id);
    expect(result.canApplyAutomatically, isTrue);
  });
}
