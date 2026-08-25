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
    this.nutritionPerPackage,
    this.nutritionServingLabel = '',
  });

  final String barcode;
  final String name;
  final String brand;
  final String source;
  final double? packageAmount;
  final String? packageUnit;
  final String quantityLabel;
  final NutritionTotals? nutritionPerPackage;
  final String nutritionServingLabel;

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
            'code,product_name,product_name_en,brands,quantity,product_quantity,product_quantity_unit,serving_size,serving_quantity,serving_quantity_unit,nutriments',
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
      final packageAmount = _number(product['product_quantity']);
      final packageUnit = _nullableText(product['product_quantity_unit']);
      final nutrition = _nutritionForPackage(
        product,
        packageAmount: packageAmount,
        packageUnit: packageUnit,
      );
      return BarcodeProductSuggestion(
        barcode: normalizeBarcode(
          returnedBarcode.isEmpty ? normalized : returnedBarcode,
        ),
        name: name,
        brand: _text(product['brands']),
        source: 'Open Food Facts',
        packageAmount: packageAmount,
        packageUnit: packageUnit,
        quantityLabel: _text(product['quantity']),
        nutritionPerPackage: nutrition,
        nutritionServingLabel: _firstText([
          product['quantity'],
          product['serving_size'],
        ]),
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

  static NutritionTotals? _nutritionForPackage(
    Map<String, dynamic> product, {
    required double? packageAmount,
    required String? packageUnit,
  }) {
    final nutriments = product['nutriments'] as Map<String, dynamic>?;
    if (nutriments == null) return null;

    double scale = 1;
    var suffix = '_serving';
    final servingAmount = _number(product['serving_quantity']);
    final servingUnit = _nullableText(product['serving_quantity_unit']);
    final packageAndServingMatch =
        packageAmount != null &&
        servingAmount != null &&
        servingAmount > 0 &&
        _sameDimension(packageUnit, servingUnit);
    if (packageAndServingMatch) {
      scale =
          _toStandard(packageAmount, packageUnit) /
          _toStandard(servingAmount, servingUnit);
    } else if (packageAmount != null &&
        packageAmount > 0 &&
        _supportsPerHundred(packageUnit)) {
      suffix = '_100g';
      scale = _toStandard(packageAmount, packageUnit) / 100;
    }

    double value(String key) =>
        (_number(nutriments['$key$suffix']) ?? 0) * scale;
    final totals = NutritionTotals(
      calories: value('energy-kcal'),
      proteinG: value('proteins'),
      carbsG: value('carbohydrates'),
      fatG: value('fat'),
      fiberG: value('fiber'),
      sugarG: value('sugars'),
      sodiumMg: value('sodium') * 1000,
    );
    return _hasNutrition(totals) ? totals : null;
  }

  static bool _hasNutrition(NutritionTotals value) =>
      value.calories > 0 ||
      value.proteinG > 0 ||
      value.carbsG > 0 ||
      value.fatG > 0 ||
      value.fiberG > 0 ||
      value.sugarG > 0 ||
      value.sodiumMg > 0;

  static bool _supportsPerHundred(String? unit) =>
      switch (unit?.toLowerCase()) {
        'g' ||
        'gram' ||
        'grams' ||
        'kg' ||
        'kilogram' ||
        'kilograms' ||
        'ml' ||
        'milliliter' ||
        'milliliters' ||
        'cl' ||
        'dl' ||
        'l' ||
        'liter' ||
        'liters' => true,
        _ => false,
      };

  static bool _sameDimension(String? left, String? right) {
    final leftUnit = left?.toLowerCase();
    final rightUnit = right?.toLowerCase();
    const mass = {'g', 'gram', 'grams', 'kg', 'kilogram', 'kilograms'};
    const volume = {
      'ml',
      'milliliter',
      'milliliters',
      'cl',
      'dl',
      'l',
      'liter',
      'liters',
    };
    return (mass.contains(leftUnit) && mass.contains(rightUnit)) ||
        (volume.contains(leftUnit) && volume.contains(rightUnit)) ||
        leftUnit == rightUnit;
  }

  static double _toStandard(double amount, String? unit) =>
      switch (unit?.toLowerCase()) {
        'kg' ||
        'kilogram' ||
        'kilograms' ||
        'l' ||
        'liter' ||
        'liters' => amount * 1000,
        'cl' => amount * 10,
        'dl' => amount * 100,
        _ => amount,
      };
}
