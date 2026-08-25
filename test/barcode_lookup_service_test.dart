import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pantry_inventory/models/pantry_models.dart';
import 'package:pantry_inventory/services/barcode_lookup_service.dart';

void main() {
  test('normalizes equivalent UPC-A and EAN-13 values', () {
    expect(normalizeBarcode('034000470693'), '0034000470693');
    expect(normalizeBarcode('0034000470693'), '0034000470693');
    expect(normalizeBarcode(' 12345670 '), '12345670');
  });

  test('reads a product suggestion from Open Food Facts', () async {
    final lookup = OpenFoodFactsBarcodeLookup(
      client: MockClient((request) async {
        expect(request.url.path, '/api/v2/product/0034000470693.json');
        expect(request.url.queryParameters['fields'], contains('product_name'));
        return http.Response('''
          {
            "status": 1,
            "product": {
              "code": "0034000470693",
              "product_name": "Chocolate Bar",
              "brands": "Example Foods",
              "quantity": "200 g",
              "product_quantity": 200,
              "product_quantity_unit": "g"
            }
          }
        ''', 200);
      }),
    );

    final result = await lookup.lookup('034000470693');

    expect(result, isNotNull);
    expect(result!.name, 'Chocolate Bar');
    expect(result.brand, 'Example Foods');
    expect(result.barcode, '0034000470693');
    expect(result.packageAmount, 200);
    expect(result.packageUnit, 'g');
  });

  test('returns null when Open Food Facts does not know the barcode', () async {
    final lookup = OpenFoodFactsBarcodeLookup(
      client: MockClient(
        (_) async =>
            http.Response('{"status": 0, "status_verbose": "not found"}', 200),
      ),
    );

    expect(await lookup.lookup('123456789012'), isNull);
  });

  group('package conversion suggestion', () {
    const suggestion = BarcodeProductSuggestion(
      barcode: '1234567890123',
      name: 'Rice',
      brand: 'Example',
      source: 'Open Food Facts',
      packageAmount: 2,
      packageUnit: 'kg',
      quantityLabel: '2 kg',
    );
    const food = FoodDefinition(
      id: 'rice',
      name: 'Rice',
      mode: QuantityMode.measured,
      baseUnit: 'gram',
      conversions: [UnitConversion(unit: 'gram', symbol: 'g', baseAmount: 1)],
    );

    test('converts package mass to the canonical base unit', () {
      final conversion = suggestion.packageConversionFor(food);

      expect(conversion, isNotNull);
      expect(conversion!.unit, 'package');
      expect(conversion.symbol, '2 kg');
      expect(conversion.baseAmount, 2000);
    });

    test('does not guess across incompatible measurement dimensions', () {
      const liquid = FoodDefinition(
        id: 'milk',
        name: 'Milk',
        mode: QuantityMode.measured,
        baseUnit: 'milliliter',
        conversions: [
          UnitConversion(unit: 'milliliter', symbol: 'mL', baseAmount: 1),
        ],
      );

      expect(suggestion.packageConversionFor(liquid), isNull);
    });
  });
}
