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
    _nutritionTargets = NutritionTargets.defaults;
    _externalFoods = [];
    _plannedMeals = [];
    _groceryItems = [];
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
    _nutritionTargets = data.nutritionTargets;
    _externalFoods = data.externalFoods;
    _plannedMeals = data.plannedMeals;
    _groceryItems = data.groceryItems;
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
        nutritionTargets: seeded.nutritionTargets,
        externalFoods: seeded.externalFoods,
        plannedMeals: seeded.plannedMeals,
        groceryItems: seeded.groceryItems,
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
  late NutritionTargets _nutritionTargets;
  late List<ExternalFood> _externalFoods;
  late List<PlannedMeal> _plannedMeals;
  late List<GroceryListItem> _groceryItems;
  final List<ConsumptionEvent> _history = [];
  Future<void> _planningWrite = Future.value();
  int _pendingWrites = 0;
  Object? _syncError;

  List<FoodDefinition> get foods => List.unmodifiable(_foods.values);
  List<InventoryLot> get lots => List.unmodifiable(_lots);
  List<Recipe> get recipes => List.unmodifiable(_recipes);
  List<ConsumptionEvent> get history => List.unmodifiable(_history.reversed);
  NutritionTargets get nutritionTargets => _nutritionTargets;
  List<ExternalFood> get externalFoods => List.unmodifiable(_externalFoods);
  List<PlannedMeal> get plannedMeals => List.unmodifiable(
    [..._plannedMeals]..sort((a, b) {
      final date = a.date.compareTo(b.date);
      return date != 0 ? date : a.slot.index.compareTo(b.slot.index);
    }),
  );
  List<GroceryListItem> get groceryItems => List.unmodifiable(_groceryItems);
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
        _recipes.any((item) => item.id == candidate) ||
        _externalFoods.any((item) => item.id == candidate)) {
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

  List<ConsumptionEvent> eventsForDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return history
        .where(
          (event) =>
              event.undoneAt == null &&
              !event.timestamp.isBefore(start) &&
              event.timestamp.isBefore(end),
        )
        .toList();
  }

  NutritionTotals nutritionForDay(DateTime day) => eventsForDay(day).fold(
    const NutritionTotals(),
    (total, event) => total + (event.nutrition ?? const NutritionTotals()),
  );

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
      kind: ConsumptionKind.recipe,
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
    _refreshPlannedGroceries();
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
      kind: ConsumptionKind.inventory,
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
    _refreshPlannedGroceries();
    notifyListeners();
    return event;
  }

  ConsumptionEvent logExternalMeal({
    required String label,
    required NutritionTotals nutrition,
    DateTime? timestamp,
    bool estimated = true,
    String note = '',
  }) {
    if (label.trim().isEmpty) throw ArgumentError('Meal name is required');
    final values = [
      nutrition.calories,
      nutrition.proteinG,
      nutrition.carbsG,
      nutrition.fatG,
      nutrition.fiberG,
      nutrition.sugarG,
      nutrition.sodiumMg,
    ];
    if (values.any((value) => !value.isFinite || value < 0) ||
        !values.any((value) => value > 0)) {
      throw ArgumentError('Enter at least one non-negative nutrition value');
    }
    final event = ConsumptionEvent(
      id: 'event-${DateTime.now().microsecondsSinceEpoch}',
      label: label.trim(),
      timestamp: timestamp ?? DateTime.now(),
      kind: ConsumptionKind.external,
      deductions: const [],
      nutrition: nutrition,
      nutritionEstimated: estimated,
      note: note.trim(),
    );
    _history.add(event);
    _queue(_cloud?.saveConsumption(event, const []));
    notifyListeners();
    return event;
  }

  ConsumptionEvent logExternalFood(
    ExternalFood food, {
    double servings = 1,
    DateTime? timestamp,
    String note = '',
  }) {
    if (servings <= 0 || !servings.isFinite) {
      throw ArgumentError('Servings must be positive');
    }
    final servingText = servings == 1
        ? food.name
        : '${units.formatAmount(servings)} servings of ${food.name}';
    final details = [
      if (food.brand.isNotEmpty) food.brand,
      food.servingLabel,
      if (note.trim().isNotEmpty) note.trim(),
    ].join(' · ');
    return logExternalMeal(
      label: servingText,
      nutrition: food.nutrition.scale(servings),
      timestamp: timestamp,
      estimated: food.estimated,
      note: details,
    );
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
    _refreshPlannedGroceries();
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
    _refreshPlannedGroceries();
    notifyListeners();
  }

  void saveNutritionTargets(NutritionTargets targets) {
    final values = [
      targets.calories,
      targets.proteinG,
      targets.carbsG,
      targets.fatG,
      targets.fiberG,
      targets.sodiumMg,
    ];
    if (values.any((value) => !value.isFinite || value <= 0)) {
      throw ArgumentError('Nutrition targets must be positive numbers');
    }
    _nutritionTargets = targets;
    _queue(_cloud?.saveNutritionTargets(targets));
    notifyListeners();
  }

  void saveExternalFood(ExternalFood food) {
    final values = [
      food.nutrition.calories,
      food.nutrition.proteinG,
      food.nutrition.carbsG,
      food.nutrition.fatG,
      food.nutrition.fiberG,
      food.nutrition.sugarG,
      food.nutrition.sodiumMg,
    ];
    if (food.name.trim().isEmpty || food.servingLabel.trim().isEmpty) {
      throw ArgumentError('Name and serving are required');
    }
    if (values.any((value) => !value.isFinite || value < 0) ||
        !values.any((value) => value > 0)) {
      throw ArgumentError('Enter at least one nutrition value');
    }
    final index = _externalFoods.indexWhere((item) => item.id == food.id);
    if (index < 0) {
      _externalFoods = [..._externalFoods, food];
    } else {
      _externalFoods[index] = food;
    }
    _queue(_cloud?.saveExternalFood(food));
    notifyListeners();
  }

  List<PlannedMeal> plannedForDay(DateTime day) => plannedMeals
      .where(
        (meal) =>
            meal.date.year == day.year &&
            meal.date.month == day.month &&
            meal.date.day == day.day,
      )
      .toList();

  Map<String, double> get plannedRequirementsBase {
    final requirements = <String, double>{};
    for (final meal in _plannedMeals.where(
      (item) => item.completedAt == null,
    )) {
      if (meal.source != PlannedMealSource.recipe || meal.sourceId == null) {
        continue;
      }
      final recipeIndex = _recipes.indexWhere(
        (item) => item.id == meal.sourceId,
      );
      if (recipeIndex < 0) continue;
      final recipe = _recipes[recipeIndex];
      final scale = meal.servings / recipe.servings;
      for (final ingredient in recipe.ingredients) {
        final definition = food(ingredient.foodId);
        final amountBase = units.toBase(
          definition,
          ingredient.amount * scale,
          ingredient.unit,
        );
        requirements[ingredient.foodId] =
            (requirements[ingredient.foodId] ?? 0) + amountBase;
      }
    }
    return requirements;
  }

  void savePlannedMeal(PlannedMeal meal) {
    if (meal.name.trim().isEmpty || meal.servings <= 0) {
      throw ArgumentError('Planned meals need a name and positive servings');
    }
    if (meal.source == PlannedMealSource.recipe &&
        !_recipes.any((recipe) => recipe.id == meal.sourceId)) {
      throw ArgumentError('Planned recipe does not exist');
    }
    final index = _plannedMeals.indexWhere((item) => item.id == meal.id);
    if (index < 0) {
      _plannedMeals = [..._plannedMeals, meal];
    } else {
      _plannedMeals[index] = meal;
    }
    _rebuildGroceryList();
    _savePlanning();
  }

  void replacePlannedMeals(Iterable<PlannedMeal> meals) {
    _plannedMeals = [...meals];
    _rebuildGroceryList();
    _savePlanning();
  }

  void deletePlannedMeal(String id) {
    _plannedMeals = _plannedMeals.where((meal) => meal.id != id).toList();
    _rebuildGroceryList();
    _savePlanning();
  }

  void setPlannedMealCompleted(String id, bool completed) {
    final index = _plannedMeals.indexWhere((meal) => meal.id == id);
    if (index < 0) throw StateError('Unknown planned meal $id');
    _plannedMeals[index] = _plannedMeals[index].copyWith(
      completedAt: completed ? DateTime.now() : null,
      clearCompletedAt: !completed,
    );
    _rebuildGroceryList();
    _savePlanning();
  }

  void toggleGroceryItem(String id) {
    final index = _groceryItems.indexWhere((item) => item.id == id);
    if (index < 0) throw StateError('Unknown grocery item $id');
    _groceryItems[index] = _groceryItems[index].copyWith(
      checked: !_groceryItems[index].checked,
    );
    _savePlanning();
  }

  void addManualGroceryItem(String name, {String quantityLabel = ''}) {
    if (name.trim().isEmpty) throw ArgumentError('Grocery name is required');
    _groceryItems = [
      ..._groceryItems,
      GroceryListItem(
        id: 'manual-${DateTime.now().microsecondsSinceEpoch}',
        name: name.trim(),
        emoji: '🛒',
        checked: false,
        fromPlan: false,
        quantityLabel: quantityLabel.trim(),
      ),
    ];
    _savePlanning();
  }

  void deleteGroceryItem(String id) {
    final index = _groceryItems.indexWhere((entry) => entry.id == id);
    if (index < 0) return;
    final item = _groceryItems[index];
    if (item.fromPlan) {
      throw StateError(
        'Planned grocery items are removed by changing the plan',
      );
    }
    _groceryItems = _groceryItems.where((entry) => entry.id != id).toList();
    _savePlanning();
  }

  void _rebuildGroceryList() {
    final checkedByFood = {
      for (final item in _groceryItems)
        if (item.fromPlan && item.foodId != null) item.foodId!: item.checked,
    };
    final manual = _groceryItems.where((item) => !item.fromPlan).toList();
    final planned = <GroceryListItem>[];
    for (final requirement in plannedRequirementsBase.entries) {
      final shortage = requirement.value - totalFor(requirement.key);
      if (shortage <= 0.0001) continue;
      final definition = food(requirement.key);
      planned.add(
        GroceryListItem(
          id: 'plan-${requirement.key}',
          name: definition.name,
          emoji: definition.emoji,
          checked: checkedByFood[requirement.key] ?? false,
          fromPlan: true,
          foodId: requirement.key,
          quantityBase: shortage,
        ),
      );
    }
    planned.sort((a, b) => a.name.compareTo(b.name));
    _groceryItems = [...planned, ...manual];
  }

  void _refreshPlannedGroceries() {
    if (!_plannedMeals.any(
      (meal) =>
          meal.completedAt == null && meal.source == PlannedMealSource.recipe,
    )) {
      return;
    }
    _rebuildGroceryList();
    _savePlanning(notify: false);
  }

  void _savePlanning({bool notify = true}) {
    final cloud = _cloud;
    if (cloud != null) {
      final meals = [..._plannedMeals];
      final groceries = [..._groceryItems];
      _planningWrite = _planningWrite
          .catchError((_) {})
          .then((_) => cloud.replacePlanning(meals, groceries));
      _queue(_planningWrite);
    }
    if (notify) notifyListeners();
  }

  void deleteRecipe(String recipeId) {
    _recipes = _recipes.where((item) => item.id != recipeId).toList();
    _queue(_cloud?.deleteRecipe(recipeId));
    _refreshPlannedGroceries();
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
    _refreshPlannedGroceries();
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
