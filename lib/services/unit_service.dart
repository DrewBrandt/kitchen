import '../models/pantry_models.dart';

class UnitService {
  const UnitService();

  double toBase(FoodDefinition food, double amount, String unit) {
    if (amount < 0) {
      throw ArgumentError.value(amount, 'amount', 'Cannot be negative');
    }
    return amount * food.conversionFor(unit).baseAmount;
  }

  double fromBase(FoodDefinition food, double baseAmount, String unit) {
    return baseAmount / food.conversionFor(unit).baseAmount;
  }

  String formatAmount(double value) {
    const fractions = <(double, String)>[
      (0.125, '⅛'),
      (0.25, '¼'),
      (1 / 3, '⅓'),
      (0.5, '½'),
      (2 / 3, '⅔'),
      (0.75, '¾'),
    ];
    final whole = value.floor();
    final remainder = value - whole;
    for (final entry in fractions) {
      if ((remainder - entry.$1).abs() < 0.015) {
        return whole == 0 ? entry.$2 : '$whole${entry.$2}';
      }
    }
    if ((value - value.round()).abs() < 0.001) return value.round().toString();
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  String ingredientLabel(FoodDefinition food, RecipeIngredient ingredient) {
    final conversion = food.conversionFor(ingredient.unit);
    if (food.mode == QuantityMode.counted) {
      return formatUnitAmount(food, ingredient.amount, conversion.unit);
    }
    return '${formatUnitAmount(food, ingredient.amount, conversion.unit)} ${food.name.toLowerCase()}';
  }

  String bestInventoryLabel(FoodDefinition food, double baseAmount) {
    if (food.displayUnit != null) {
      final preferred = food.conversionFor(food.displayUnit!);
      return formatUnitAmount(
        food,
        fromBase(food, baseAmount, preferred.unit),
        preferred.unit,
        inventoryRounding: true,
      );
    }
    final candidates =
        food.conversions
            .where((unit) => baseAmount / unit.baseAmount >= 0.75)
            .toList()
          ..sort((a, b) => b.baseAmount.compareTo(a.baseAmount));
    final unit = candidates.isEmpty ? food.conversions.first : candidates.first;
    return formatUnitAmount(
      food,
      fromBase(food, baseAmount, unit.unit),
      unit.unit,
      inventoryRounding: true,
    );
  }

  String formatUnitAmount(
    FoodDefinition food,
    double amount,
    String unit, {
    bool inventoryRounding = false,
  }) {
    final conversion = food.conversionFor(unit);
    final amountText = inventoryRounding
        ? _formatInventoryAmount(amount)
        : formatAmount(amount);
    return '$amountText ${_inflect(conversion.symbol, amount)}';
  }

  String _formatInventoryAmount(double value) {
    if ((value - value.round()).abs() < 0.001) {
      return value.round().toString();
    }
    if (value >= 10) return '~${value.round()}';

    const fractions = <(double, String)>[
      (0.125, '⅛'),
      (0.25, '¼'),
      (0.375, '⅜'),
      (0.5, '½'),
      (0.625, '⅝'),
      (0.75, '¾'),
      (0.875, '⅞'),
    ];
    final whole = value.floor();
    final remainder = value - whole;
    for (final entry in fractions) {
      final difference = (remainder - entry.$1).abs();
      if (difference <= 0.03) {
        final text = whole == 0 ? entry.$2 : '$whole${entry.$2}';
        return difference < 0.001 ? text : '~$text';
      }
    }
    if ((value - value.round()).abs() <= 0.15) return '~${value.round()}';
    return '~${value.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '')}';
  }

  String _inflect(String symbol, double amount) {
    const invariant = {'g', 'kg', 'mg', 'mL', 'L', 'oz', 'lb', 'tsp', 'tbsp', 'fl oz', 'each'};
    if (invariant.contains(symbol)) return symbol;

    const singularToPlural = <String, String>{
      'bag': 'bags',
      'bottle': 'bottles',
      'box': 'boxes',
      'bun': 'buns',
      'burger': 'burgers',
      'container': 'containers',
      'cracker': 'crackers',
      'cup': 'cups',
      'egg': 'eggs',
      'glass': 'glasses',
      'jar': 'jars',
      'naan': 'naan',
      'onion': 'onions',
      'package': 'packages',
      'packet': 'packets',
      'piece': 'pieces',
      'scoop': 'scoops',
      'serving': 'servings',
      'slice': 'slices',
      'sleeve': 'sleeves',
      'stick': 'sticks',
      'tortilla': 'tortillas',
    };
    final singular = (amount - 1).abs() < 0.05;
    var result = symbol;
    for (final entry in singularToPlural.entries) {
      final from = singular ? entry.value : entry.key;
      final to = singular ? entry.key : entry.value;
      result = result.replaceAll(RegExp('\\b${RegExp.escape(from)}\\b'), to);
    }
    return result;
  }
}
