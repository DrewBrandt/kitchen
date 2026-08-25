import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/pantry_models.dart';

class BarcodeProductSuggestion {
  const BarcodeProductSuggestion({
    required this.barcode,
    required this.name,
    required this.brand,
    required this.source,
    this.packageAmount,
    this.packageUnit,
    this.quantityLabel = '',
  });

  final String barcode;
  final String name;
  final String brand;
  final String source;
  final double? packageAmount;
  final String? packageUnit;
  final String quantityLabel;

  UnitConversion? packageConversionFor(FoodDefinition food) {
    final amount = packageAmount;
    final unit = packageUnit?.trim().toLowerCase();
    if (amount == null || amount <= 0 || unit == null || unit.isEmpty) {
      return null;
    }

    final baseAmount = switch (food.baseUnit) {
      'gram' => switch (unit) {
        'g' || 'gram' || 'grams' => amount,
        'kg' || 'kilogram' || 'kilograms' => amount * 1000,
        _ => null,
      },
      'milliliter' => switch (unit) {
        'ml' || 'milliliter' || 'milliliters' => amount,
        'cl' => amount * 10,
        'dl' => amount * 100,
        'l' || 'liter' || 'liters' => amount * 1000,
        _ => null,
      },
      'each' => switch (unit) {
        'each' || 'count' || 'piece' || 'pieces' || 'pc' || 'pcs' => amount,
        _ => null,
      },
      _ => null,
    };
    if (baseAmount == null || baseAmount <= 0) return null;
    return UnitConversion(
      unit: 'package',
      symbol: quantityLabel.trim().isEmpty ? 'package' : quantityLabel.trim(),
      baseAmount: baseAmount,
    );
  }
}

class BarcodeLookupException implements Exception {
  const BarcodeLookupException(this.message);

  final String message;

  @override
  String toString() => message;
}

class OpenFoodFactsBarcodeLookup {
  OpenFoodFactsBarcodeLookup({http.Client? client}) : _client = client;

  final http.Client? _client;

  Future<BarcodeProductSuggestion?> lookup(String barcode) async {
    final normalized = normalizeBarcode(barcode);
    final uri = Uri.https(
      'world.openfoodfacts.org',
      '/api/v2/product/$normalized.json',
      {
        'fields':
            'code,product_name,product_name_en,brands,quantity,product_quantity,product_quantity_unit',
      },
    );

    late http.Response response;
    try {
      response = await (_client?.get(uri) ?? http.get(uri)).timeout(
        const Duration(seconds: 12),
      );
    } catch (_) {
      throw const BarcodeLookupException(
        'The product lookup service could not be reached.',
      );
    }
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw BarcodeLookupException(
        'Product lookup failed (${response.statusCode}).',
      );
    }

    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if ((body['status'] as num?)?.toInt() != 1) return null;
      final product = body['product'] as Map<String, dynamic>?;
      if (product == null) return null;
      final name = _firstText([
        product['product_name_en'],
        product['product_name'],
      ]);
      final returnedBarcode = _text(product['code']);
      return BarcodeProductSuggestion(
        barcode: normalizeBarcode(
          returnedBarcode.isEmpty ? normalized : returnedBarcode,
        ),
        name: name,
        brand: _text(product['brands']),
        source: 'Open Food Facts',
        packageAmount: _number(product['product_quantity']),
        packageUnit: _nullableText(product['product_quantity_unit']),
        quantityLabel: _text(product['quantity']),
      );
    } on FormatException {
      throw const BarcodeLookupException(
        'The product lookup returned an unreadable response.',
      );
    } on TypeError {
      throw const BarcodeLookupException(
        'The product lookup returned an unreadable response.',
      );
    }
  }

  static String _firstText(Iterable<Object?> values) {
    for (final value in values) {
      final text = _text(value);
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  static String _text(Object? value) => value is String ? value.trim() : '';

  static String? _nullableText(Object? value) {
    final text = _text(value);
    return text.isEmpty ? null : text;
  }

  static double? _number(Object? value) => switch (value) {
    num number => number.toDouble(),
    String text => double.tryParse(text),
    _ => null,
  };
}
