import '../models/pantry_models.dart';
import 'unit_service.dart';

class InventoryService {
  InventoryService({this.units = const UnitService()});

  final UnitService units;

  double totalFor(String foodId, Iterable<InventoryLot> lots) => lots
      .where((lot) => lot.foodId == foodId)
      .fold(0, (total, lot) => total + lot.quantityBase);

  Map<String, double> requirementsFor(
    Recipe recipe,
    double servings,
    Map<String, FoodDefinition> foods,
  ) {
    if (servings <= 0) {
      throw ArgumentError.value(servings, 'servings', 'Must be positive');
    }
    final factor = servings / recipe.servings;
    final result = <String, double>{};
    for (final ingredient in recipe.ingredients) {
      final food =
          foods[ingredient.foodId] ??
          (throw StateError(
            'Recipe references unknown food ${ingredient.foodId}',
          ));
      result.update(
        food.id,
        (amount) =>
            amount +
            units.toBase(food, ingredient.amount * factor, ingredient.unit),
        ifAbsent: () =>
            units.toBase(food, ingredient.amount * factor, ingredient.unit),
      );
    }
    return result;
  }

  List<LotDeduction> planDeductions(
    Map<String, double> requirements,
    List<InventoryLot> lots,
  ) {
    final deductions = <LotDeduction>[];
    final missing = <String, double>{};
    for (final entry in requirements.entries) {
      var remaining = entry.value;
      final candidates =
          lots
              .where((lot) => lot.foodId == entry.key && lot.quantityBase > 0)
              .toList()
            ..sort(_compareLots);
      for (final lot in candidates) {
        if (remaining <= 0.000001) break;
        final amount = remaining < lot.quantityBase
            ? remaining
            : lot.quantityBase;
        deductions.add(
          LotDeduction(lotId: lot.id, foodId: lot.foodId, quantityBase: amount),
        );
        remaining -= amount;
      }
      if (remaining > 0.000001) missing[entry.key] = remaining;
    }
    if (missing.isNotEmpty) throw InsufficientInventoryException(missing);
    return deductions;
  }

  static int _compareLots(InventoryLot a, InventoryLot b) {
    final aDate = a.bestBy ?? DateTime(9999);
    final bDate = b.bestBy ?? DateTime(9999);
    final byExpiry = aDate.compareTo(bDate);
    if (byExpiry != 0) return byExpiry;
    return (a.purchasedAt ?? DateTime(9999)).compareTo(
      b.purchasedAt ?? DateTime(9999),
    );
  }
}
