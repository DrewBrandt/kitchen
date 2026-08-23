import 'package:flutter/foundation.dart';

import '../models/pantry_models.dart';
import '../services/inventory_service.dart';
import '../services/unit_service.dart';
import 'seed_data.dart';

class PantryStore extends ChangeNotifier {
  PantryStore.demo({DateTime? now}) : _now = now ?? DateTime.now() {
    final foods = SeedData.foods();
    _foods = {for (final food in foods) food.id: food};
    _lots = SeedData.lots(_now);
    _recipes = SeedData.recipes();
  }

  final DateTime _now;
  final InventoryService inventory = InventoryService();
  final UnitService units = const UnitService();
  late final Map<String, FoodDefinition> _foods;
  late List<InventoryLot> _lots;
  late final List<Recipe> _recipes;
  final List<ConsumptionEvent> _history = [];
  int _sequence = 0;

  List<FoodDefinition> get foods => List.unmodifiable(_foods.values);
  List<InventoryLot> get lots => List.unmodifiable(_lots);
  List<Recipe> get recipes => List.unmodifiable(_recipes);
  List<ConsumptionEvent> get history => List.unmodifiable(_history.reversed);
  DateTime get now => _now;

  FoodDefinition food(String id) =>
      _foods[id] ?? (throw StateError('Unknown food $id'));
  double totalFor(String foodId) => inventory.totalFor(foodId, _lots);

  List<InventoryLot> lotsFor(String foodId) =>
      _lots.where((lot) => lot.foodId == foodId).toList();

  Map<String, double> missingFor(Recipe recipe, {double? servings}) {
    final required = inventory.requirementsFor(
      recipe,
      servings ?? recipe.servings,
      _foods,
    );
    return {
      for (final entry in required.entries)
        if (totalFor(entry.key) + 0.000001 < entry.value)
          entry.key: entry.value - totalFor(entry.key),
    };
  }

  ConsumptionEvent cook(Recipe recipe, {double? servings}) {
    final servingCount = servings ?? recipe.servings;
    final requirements = inventory.requirementsFor(
      recipe,
      servingCount,
      _foods,
    );
    final deductions = inventory.planDeductions(requirements, _lots);
    _applyDeductions(deductions);
    final event = ConsumptionEvent(
      id: 'event-${++_sequence}',
      label: '${units.formatAmount(servingCount)} servings of ${recipe.name}',
      timestamp: DateTime.now(),
      recipeId: recipe.id,
      deductions: deductions,
    );
    _history.add(event);
    notifyListeners();
    return event;
  }

  ConsumptionEvent consume(
    FoodDefinition food,
    double amount,
    String unit, {
    String? label,
  }) {
    final requirement = units.toBase(food, amount, unit);
    final deductions = inventory.planDeductions({food.id: requirement}, _lots);
    _applyDeductions(deductions);
    final event = ConsumptionEvent(
      id: 'event-${++_sequence}',
      label:
          label ??
          '${units.formatAmount(amount)} ${food.conversionFor(unit).symbol} ${food.name.toLowerCase()}',
      timestamp: DateTime.now(),
      deductions: deductions,
    );
    _history.add(event);
    notifyListeners();
    return event;
  }

  void addLot({
    required FoodDefinition food,
    required double amount,
    required String unit,
    required StorageLocation location,
    DateTime? bestBy,
  }) {
    final quantity = units.toBase(food, amount, unit);
    _lots = [
      ..._lots,
      InventoryLot(
        id: 'lot-${DateTime.now().microsecondsSinceEpoch}',
        foodId: food.id,
        quantityBase: quantity,
        location: location,
        purchasedAt: DateTime.now(),
        bestBy: bestBy,
      ),
    ];
    notifyListeners();
  }

  void undo(String eventId) {
    final index = _history.indexWhere((event) => event.id == eventId);
    if (index < 0) throw StateError('Unknown history event $eventId');
    final event = _history[index];
    if (event.undoneAt != null) {
      throw StateError('Event has already been undone');
    }
    for (final deduction in event.deductions) {
      final lotIndex = _lots.indexWhere((lot) => lot.id == deduction.lotId);
      if (lotIndex < 0) {
        throw StateError('Cannot restore missing lot ${deduction.lotId}');
      }
      _lots[lotIndex] = _lots[lotIndex].copyWith(
        quantityBase: _lots[lotIndex].quantityBase + deduction.quantityBase,
      );
    }
    _history[index] = event.markUndone(DateTime.now());
    notifyListeners();
  }

  void _applyDeductions(List<LotDeduction> deductions) {
    final next = [..._lots];
    for (final deduction in deductions) {
      final index = next.indexWhere((lot) => lot.id == deduction.lotId);
      if (index < 0) throw StateError('Unknown lot ${deduction.lotId}');
      next[index] = next[index].copyWith(
        quantityBase: next[index].quantityBase - deduction.quantityBase,
      );
    }
    _lots = next;
  }
}
