import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/pantry_models.dart';
import '../services/inventory_service.dart';
import '../services/unit_service.dart';
import 'firestore_pantry.dart';
import 'seed_data.dart';

class PantryStore extends ChangeNotifier {
  PantryStore.demo({DateTime? now})
    : _now = now ?? DateTime.now(),
      _cloud = null {
    final foods = SeedData.foods();
    _foods = {for (final food in foods) food.id: food};
    _lots = SeedData.lots(_now);
    _recipes = SeedData.recipes();
  }

  PantryStore._cloud({
    required DateTime now,
    required CloudPantryData data,
    required FirestorePantry cloud,
  }) : _now = now,
       _cloud = cloud {
    _foods = {for (final food in data.foods) food.id: food};
    _lots = data.lots;
    _recipes = data.recipes;
    _history.addAll(data.history);
  }

  static Future<PantryStore> loadCloud({
    FirebaseFirestore? firestore,
    DateTime? now,
  }) async {
    final currentTime = now ?? DateTime.now();
    final cloud = FirestorePantry(firestore ?? FirebaseFirestore.instance);
    final data = await cloud.load();
    if (!data.isEmpty) {
      return PantryStore._cloud(now: currentTime, data: data, cloud: cloud);
    }
    final seeded = PantryStore.demo(now: currentTime);
    await cloud.seed(
      CloudPantryData(
        foods: seeded.foods,
        lots: seeded.lots,
        recipes: seeded.recipes,
        history: seeded.history,
      ),
    );
    seeded._cloud = cloud;
    return seeded;
  }

  final DateTime _now;
  final InventoryService inventory = InventoryService();
  final UnitService units = const UnitService();
  FirestorePantry? _cloud;
  late final Map<String, FoodDefinition> _foods;
  late List<InventoryLot> _lots;
  late List<Recipe> _recipes;
  final List<ConsumptionEvent> _history = [];
  int _pendingWrites = 0;
  Object? _syncError;

  List<FoodDefinition> get foods => List.unmodifiable(_foods.values);
  List<InventoryLot> get lots => List.unmodifiable(_lots);
  List<Recipe> get recipes => List.unmodifiable(_recipes);
  List<ConsumptionEvent> get history => List.unmodifiable(_history.reversed);
  DateTime get now => _now;
  bool get isSyncing => _pendingWrites > 0;
  Object? get syncError => _syncError;

  FoodDefinition food(String id) =>
      _foods[id] ?? (throw StateError('Unknown food $id'));

  String nextId(String name) {
    final base = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    var candidate = base.isEmpty ? 'item' : base;
    var suffix = 2;
    while (_foods.containsKey(candidate) ||
        _recipes.any((item) => item.id == candidate)) {
      candidate = '$base-${suffix++}';
    }
    return candidate;
  }

  double totalFor(String foodId) => inventory.totalFor(foodId, _lots);

  NutritionTotals? nutritionForBaseAmount(
    FoodDefinition food,
    double baseAmount,
  ) => food.nutrition?.forBaseAmount(baseAmount);

  NutritionTotals? nutritionForAmount(
    FoodDefinition food,
    double amount,
    String unit,
  ) => nutritionForBaseAmount(food, units.toBase(food, amount, unit));

  NutritionTotals? nutritionForRecipe(Recipe recipe, {double? servings}) {
    final servingCount = servings ?? recipe.servings;
    var found = false;
    var total = const NutritionTotals();
    for (final ingredient in recipe.ingredients) {
      final definition = food(ingredient.foodId);
      final nutrition = nutritionForAmount(
        definition,
        ingredient.amount * (servingCount / recipe.servings),
        ingredient.unit,
      );
      if (nutrition != null) {
        found = true;
        total = total + nutrition;
      }
    }
    return found ? total : null;
  }

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
      id: 'event-${DateTime.now().microsecondsSinceEpoch}',
      label:
          '${units.formatAmount(servingCount)} ${servingCount == 1 ? 'serving' : 'servings'} of ${recipe.name}',
      timestamp: DateTime.now(),
      recipeId: recipe.id,
      deductions: deductions,
      nutrition: nutritionForRecipe(recipe, servings: servingCount),
    );
    _history.add(event);
    final affectedIds = deductions.map((item) => item.lotId).toSet();
    _queue(
      _cloud?.saveConsumption(
        event,
        _lots.where((lot) => affectedIds.contains(lot.id)),
      ),
    );
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
      id: 'event-${DateTime.now().microsecondsSinceEpoch}',
      label:
          label ??
          '${units.formatAmount(amount)} ${food.conversionFor(unit).symbol} ${food.name.toLowerCase()}',
      timestamp: DateTime.now(),
      deductions: deductions,
      nutrition: nutritionForAmount(food, amount, unit),
    );
    _history.add(event);
    final affectedIds = deductions.map((item) => item.lotId).toSet();
    _queue(
      _cloud?.saveConsumption(
        event,
        _lots.where((lot) => affectedIds.contains(lot.id)),
      ),
    );
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
    final lot = InventoryLot(
      id: 'lot-${DateTime.now().microsecondsSinceEpoch}',
      foodId: food.id,
      quantityBase: quantity,
      location: location,
      purchasedAt: DateTime.now(),
      bestBy: bestBy,
    );
    _lots = [..._lots, lot];
    _queue(_cloud?.saveLot(lot));
    notifyListeners();
  }

  void saveFood(FoodDefinition food) {
    if (food.name.trim().isEmpty) {
      throw ArgumentError('Food name is required');
    }
    if (food.conversions.isEmpty) {
      throw ArgumentError('At least one unit conversion is required');
    }
    if (!food.conversions.any(
      (item) => item.unit == food.baseUnit && item.baseAmount == 1,
    )) {
      throw ArgumentError('The base unit must have a conversion of 1');
    }
    _foods[food.id] = food;
    _queue(_cloud?.saveFood(food));
    notifyListeners();
  }

  void deleteFood(String foodId) {
    if (_lots.any((lot) => lot.foodId == foodId && lot.quantityBase > 0)) {
      throw StateError('Remove this food from inventory before deleting it');
    }
    if (_recipes.any(
      (recipe) => recipe.ingredients.any((item) => item.foodId == foodId),
    )) {
      throw StateError('This food is still used by a recipe');
    }
    _foods.remove(foodId);
    _queue(_cloud?.deleteFood(foodId));
    notifyListeners();
  }

  void saveRecipe(Recipe recipe) {
    if (recipe.name.trim().isEmpty ||
        recipe.servings <= 0 ||
        recipe.ingredients.isEmpty) {
      throw ArgumentError(
        'Recipe name, servings, and ingredients are required',
      );
    }
    for (final ingredient in recipe.ingredients) {
      final definition = food(ingredient.foodId);
      definition.conversionFor(ingredient.unit);
      if (ingredient.amount <= 0) {
        throw ArgumentError('Ingredient amounts must be positive');
      }
    }
    final index = _recipes.indexWhere((item) => item.id == recipe.id);
    if (index < 0) {
      _recipes = [..._recipes, recipe];
    } else {
      _recipes[index] = recipe;
    }
    _queue(_cloud?.saveRecipe(recipe));
    notifyListeners();
  }

  void deleteRecipe(String recipeId) {
    _recipes = _recipes.where((item) => item.id != recipeId).toList();
    _queue(_cloud?.deleteRecipe(recipeId));
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
    final undone = event.markUndone(DateTime.now());
    _history[index] = undone;
    final affectedIds = event.deductions.map((item) => item.lotId).toSet();
    _queue(
      _cloud?.saveUndo(
        undone,
        _lots.where((lot) => affectedIds.contains(lot.id)),
      ),
    );
    notifyListeners();
  }

  void _queue(Future<void>? write) {
    if (write == null) return;
    _pendingWrites++;
    _syncError = null;
    unawaited(
      write
          .then((_) {
            _pendingWrites--;
            notifyListeners();
          })
          .catchError((Object error) {
            _pendingWrites--;
            _syncError = error;
            notifyListeners();
          }),
    );
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
