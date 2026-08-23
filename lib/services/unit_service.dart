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
    return '${formatAmount(ingredient.amount)} ${conversion.symbol} ${food.name.toLowerCase()}';
  }

  String bestInventoryLabel(FoodDefinition food, double baseAmount) {
    final candidates =
        food.conversions
            .where((unit) => baseAmount / unit.baseAmount >= 0.75)
            .toList()
          ..sort((a, b) => b.baseAmount.compareTo(a.baseAmount));
    final unit = candidates.isEmpty ? food.conversions.first : candidates.first;
    return '${formatAmount(fromBase(food, baseAmount, unit.unit))} ${unit.symbol}';
  }
}
