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
    _products = {};
    _lots = SeedData.lots(_now);
    _recipes = SeedData.recipes();
    _mealTemplates = [];
    _preparedBatches = [];
    _recipeFeedback = [];
    _nutritionTargets = NutritionTargets.defaults;
    _foodPreferences = FoodPreferences.empty;
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
    _products = {for (final product in data.products) product.id: product};
    _lots = data.lots;
    _recipes = data.recipes;
    _mealTemplates = data.mealTemplates;
    _preparedBatches = data.preparedBatches;
    _recipeFeedback = data.recipeFeedback;
    _nutritionTargets = data.nutritionTargets;
    _foodPreferences = data.foodPreferences;
    _externalFoods = data.externalFoods;
    _plannedMeals = data.plannedMeals;
    _groceryItems = data.groceryItems;
    _history.addAll(data.history);
    _startCloudSync();
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
        products: seeded.products,
        lots: seeded.lots,
        recipes: seeded.recipes,
        mealTemplates: seeded.mealTemplates,
        preparedBatches: seeded.preparedBatches,
        recipeFeedback: seeded.recipeFeedback,
        history: seeded.history,
        nutritionTargets: seeded.nutritionTargets,
        foodPreferences: seeded.foodPreferences,
        externalFoods: seeded.externalFoods,
        plannedMeals: seeded.plannedMeals,
        groceryItems: seeded.groceryItems,
      ),
    );
    seeded._cloud = cloud;
    seeded._startCloudSync();
    return seeded;
  }

  final DateTime _now;
  final InventoryService inventory = InventoryService();
  final UnitService units = const UnitService();
  FirestorePantry? _cloud;
  late final Map<String, FoodDefinition> _foods;
  late final Map<String, ProductDefinition> _products;
  late List<InventoryLot> _lots;
  late List<Recipe> _recipes;
  late List<MealTemplate> _mealTemplates;
  late List<PreparedBatch> _preparedBatches;
  late List<RecipeMakeFeedback> _recipeFeedback;
  late NutritionTargets _nutritionTargets;
  late FoodPreferences _foodPreferences;
  late List<ExternalFood> _externalFoods;
  late List<PlannedMeal> _plannedMeals;
  late List<GroceryListItem> _groceryItems;
  final List<ConsumptionEvent> _history = [];
  Future<void> _planningWrite = Future.value();
  int _pendingWrites = 0;
  Object? _syncError;
  Object? _cloudWatchError;
  StreamSubscription<CloudPantryData>? _cloudSubscription;

  List<FoodDefinition> get foods => List.unmodifiable(_foods.values);
  List<ProductDefinition> get products => List.unmodifiable(_products.values);
  List<InventoryLot> get lots => List.unmodifiable(_lots);
  List<Recipe> get recipes => List.unmodifiable(_recipes);
  List<MealTemplate> get mealTemplates => List.unmodifiable(_mealTemplates);
  List<PreparedBatch> get preparedBatches => List.unmodifiable(
    [..._preparedBatches]..sort((a, b) => b.madeAt.compareTo(a.madeAt)),
  );
  List<PreparedBatch> get activePreparedBatches =>
      preparedBatches.where((batch) => batch.isActive).toList();
  List<RecipeMakeFeedback> get recipeFeedback =>
      List.unmodifiable(_recipeFeedback);
  List<ConsumptionEvent> get history => List.unmodifiable(_history.reversed);
  NutritionTargets get nutritionTargets => _nutritionTargets;
  FoodPreferences get foodPreferences => _foodPreferences;
  List<ExternalFood> get externalFoods => List.unmodifiable(_externalFoods);
  List<PlannedMeal> get plannedMeals => List.unmodifiable(
    [..._plannedMeals]..sort((a, b) {
      final date = a.date.compareTo(b.date);
      return date != 0 ? date : a.slot.index.compareTo(b.slot.index);
    }),
  );
  List<GroceryListItem> get groceryItems => List.unmodifiable(_groceryItems);
  bool get isCloudBacked => _cloud != null;
  DateTime get now => _now;
  bool get isSyncing => _pendingWrites > 0;
  Object? get syncError => _syncError ?? _cloudWatchError;

  void _startCloudSync() {
    final cloud = _cloud;
    if (cloud == null || _cloudSubscription != null) return;
    _cloudSubscription = cloud.watch().listen(
      (data) {
        _foods
          ..clear()
          ..addEntries(data.foods.map((food) => MapEntry(food.id, food)));
        _products
          ..clear()
          ..addEntries(
            data.products.map((product) => MapEntry(product.id, product)),
          );
        _lots = data.lots;
        _recipes = data.recipes;
        _mealTemplates = data.mealTemplates;
        _preparedBatches = data.preparedBatches;
        _recipeFeedback = data.recipeFeedback;
        _history
          ..clear()
          ..addAll(data.history);
        _nutritionTargets = data.nutritionTargets;
        _foodPreferences = data.foodPreferences;
        _externalFoods = data.externalFoods;
        _plannedMeals = data.plannedMeals;
        _groceryItems = data.groceryItems;
        _cloudWatchError = null;
        notifyListeners();
      },
      onError: (Object error) {
        _cloudWatchError = error;
        notifyListeners();
      },
    );
  }

  @override
  void dispose() {
    unawaited(_cloudSubscription?.cancel());
    super.dispose();
  }

  FoodDefinition food(String id) =>
      _foods[id] ?? (throw StateError('Unknown food $id'));

  ProductDefinition product(String id) =>
      _products[id] ?? (throw StateError('Unknown product $id'));

  ProductDefinition? productOrNull(String? id) =>
      id == null ? null : _products[id];

  List<ProductDefinition> productsFor(String foodId) => _products.values
      .where((product) => product.foodId == foodId)
      .toList(growable: false);

  String nextId(String name) {
    final base = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    var candidate = base.isEmpty ? 'item' : base;
    var suffix = 2;
    while (_foods.containsKey(candidate) ||
        _products.containsKey(candidate) ||
        _recipes.any((item) => item.id == candidate) ||
        _mealTemplates.any((item) => item.id == candidate) ||
        _preparedBatches.any((item) => item.id == candidate) ||
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

  List<PreparedBatch> preparationsForRecipe(String recipeId) =>
      _preparedBatches
          .where(
            (batch) =>
                batch.source == PreparedSource.recipe &&
                batch.sourceId == recipeId,
          )
          .toList()
        ..sort((a, b) => b.madeAt.compareTo(a.madeAt));

  DateTime? lastMadeRecipe(String recipeId) {
    final preparations = preparationsForRecipe(recipeId);
    return preparations.isEmpty ? null : preparations.first.madeAt;
  }

  int recipeMakesThisYear(String recipeId) => preparationsForRecipe(
    recipeId,
  ).where((batch) => batch.madeAt.year == _now.year).length;

  List<RecipeMakeFeedback> feedbackForRecipe(String recipeId) =>
      _recipeFeedback
          .where((feedback) => feedback.recipeId == recipeId)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  double? averageTasteForRecipe(String recipeId) =>
      _averageFeedback(recipeId, (feedback) => feedback.tasteRating);

  double? averageEaseForRecipe(String recipeId) =>
      _averageFeedback(recipeId, (feedback) => feedback.easeRating);

  double? averageMinutesForRecipe(String recipeId) =>
      _averageFeedback(recipeId, (feedback) => feedback.actualMinutes);

  double? _averageFeedback(
    String recipeId,
    num? Function(RecipeMakeFeedback feedback) select,
  ) {
    final values = feedbackForRecipe(
      recipeId,
    ).map(select).whereType<num>().map((value) => value.toDouble()).toList();
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  void saveRecipeMakeFeedback(RecipeMakeFeedback feedback) {
    if (feedback.tasteRating == null &&
        feedback.easeRating == null &&
        feedback.actualMinutes == null) {
      return;
    }
    for (final rating in [feedback.tasteRating, feedback.easeRating]) {
      if (rating != null && (rating < 1 || rating > 5)) {
        throw ArgumentError('Recipe ratings must be between 1 and 5');
      }
    }
    if (feedback.actualMinutes != null && feedback.actualMinutes! <= 0) {
      throw ArgumentError('Recipe time must be positive');
    }
    final index = _recipeFeedback.indexWhere((item) => item.id == feedback.id);
    if (index < 0) {
      _recipeFeedback = [..._recipeFeedback, feedback];
    } else {
      _recipeFeedback[index] = feedback;
    }
    _queue(_cloud?.saveRecipeFeedback(feedback));
    notifyListeners();
  }

  NutritionTotals? nutritionForAmount(
    FoodDefinition food,
    double amount,
    String unit,
  ) => nutritionForBaseAmount(food, units.toBase(food, amount, unit));

  NutritionTotals? nutritionForRecipe(Recipe recipe, {double? servings}) {
    final servingCount = servings ?? recipe.servings;
    final override = recipe.nutritionOverride;
    if (override != null) {
      return override.scale(servingCount / recipe.servings);
    }
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

  ConsumptionEvent cook(Recipe recipe, {double? servings}) => cookPortions(
    recipe,
    servingsPerPortion: servings ?? recipe.servings,
  ).single;

  List<ConsumptionEvent> cookPortions(
    Recipe recipe, {
    required double servingsPerPortion,
    int count = 1,
    String? portionName,
  }) {
    if (!servingsPerPortion.isFinite || servingsPerPortion <= 0) {
      throw ArgumentError('The portion size must be positive');
    }
    if (count <= 0) throw ArgumentError('The portion count must be positive');

    inventory.planDeductions(
      inventory.requirementsFor(recipe, servingsPerPortion * count, _foods),
      _lots,
    );
    var workingLots = [..._lots];
    final events = <ConsumptionEvent>[];
    final now = DateTime.now();
    final cleanName = portionName?.trim();
    for (var index = 0; index < count; index++) {
      final deductions = inventory.planDeductions(
        inventory.requirementsFor(recipe, servingsPerPortion, _foods),
        workingLots,
      );
      workingLots = _lotsAfterDeductions(workingLots, deductions);
      final portionLabel = cleanName == null || cleanName.isEmpty
          ? '${units.formatAmount(servingsPerPortion)} ${servingsPerPortion == 1 ? 'serving' : 'servings'}'
          : cleanName;
      events.add(
        ConsumptionEvent(
          id: 'event-${now.microsecondsSinceEpoch}-$index',
          label: '$portionLabel of ${recipe.name}',
          timestamp: now.add(Duration(microseconds: index)),
          kind: ConsumptionKind.recipe,
          recipeId: recipe.id,
          deductions: deductions,
          nutrition: nutritionForRecipe(recipe, servings: servingsPerPortion),
        ),
      );
    }
    _lots = workingLots;
    _history.addAll(events);
    final affectedIds = events
        .expand((event) => event.deductions)
        .map((deduction) => deduction.lotId)
        .toSet();
    _queue(
      _cloud?.saveConsumptions(
        events,
        _lots.where((lot) => affectedIds.contains(lot.id)),
      ),
    );
    _refreshPlannedGroceries();
    notifyListeners();
    return events;
  }

  PreparedBatch prepareRecipe(
    Recipe recipe, {
    double? servings,
    StorageLocation location = StorageLocation.fridge,
    DateTime? bestBy,
    String note = '',
  }) {
    final servingCount = servings ?? recipe.servings;
    if (!servingCount.isFinite || servingCount <= 0) {
      throw ArgumentError('Prepared servings must be positive');
    }
    final deductions = inventory.planDeductions(
      inventory.requirementsFor(recipe, servingCount, _foods),
      _lots,
    );
    _applyDeductions(deductions);
    final now = DateTime.now();
    final batch = PreparedBatch(
      id: 'prepared-${now.microsecondsSinceEpoch}',
      name: recipe.name,
      emoji: recipe.emoji,
      source: PreparedSource.recipe,
      sourceId: recipe.id,
      totalServings: servingCount,
      remainingServings: servingCount,
      madeAt: now,
      location: location,
      bestBy: bestBy,
      nutritionPerServing: nutritionForRecipe(recipe, servings: 1),
      portions: recipe.portions,
      ingredientDeductions: deductions,
      note: note.trim(),
    );
    _preparedBatches = [..._preparedBatches, batch];
    final affectedIds = deductions.map((item) => item.lotId).toSet();
    _queue(
      _cloud?.savePreparation(
        batch,
        _lots.where((lot) => affectedIds.contains(lot.id)),
      ),
    );
    _refreshPlannedGroceries();
    notifyListeners();
    return batch;
  }

  /// Prepares several recipe components as one cooking session.
  ///
  /// Inventory is validated for the combined request before any component is
  /// changed, so a shortage cannot leave half of a meal prepared.
  List<PreparedBatch> prepareRecipeGroup(
    Map<String, double> servingsByRecipe, {
    StorageLocation location = StorageLocation.fridge,
    DateTime? bestBy,
    String note = '',
  }) {
    if (servingsByRecipe.isEmpty ||
        servingsByRecipe.values.any(
          (servings) => !servings.isFinite || servings <= 0,
        )) {
      throw ArgumentError('Choose at least one recipe with positive servings');
    }
    final requests = servingsByRecipe.entries.map((entry) {
      final recipe = _recipes.where((item) => item.id == entry.key);
      if (recipe.isEmpty) {
        throw ArgumentError('Unknown recipe ${entry.key}');
      }
      return (recipe: recipe.first, servings: entry.value);
    }).toList();
    final combinedRequirements = <String, double>{};
    for (final request in requests) {
      final requirements = inventory.requirementsFor(
        request.recipe,
        request.servings,
        _foods,
      );
      for (final entry in requirements.entries) {
        combinedRequirements.update(
          entry.key,
          (amount) => amount + entry.value,
          ifAbsent: () => entry.value,
        );
      }
    }
    inventory.planDeductions(combinedRequirements, _lots);
    return requests
        .map(
          (request) => prepareRecipe(
            request.recipe,
            servings: request.servings,
            location: location,
            bestBy: bestBy,
            note: note,
          ),
        )
        .toList();
  }

  PreparedBatch addPreparedBatch({
    required String name,
    required double servings,
    String emoji = '🍽️',
    PreparedSource source = PreparedSource.manual,
    String? sourceId,
    StorageLocation location = StorageLocation.fridge,
    DateTime? madeAt,
    DateTime? bestBy,
    NutritionTotals? nutritionPerServing,
    String note = '',
  }) {
    if (name.trim().isEmpty || !servings.isFinite || servings <= 0) {
      throw ArgumentError('A name and positive serving count are required');
    }
    final created = madeAt ?? DateTime.now();
    final batch = PreparedBatch(
      id: 'prepared-${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim(),
      emoji: emoji.trim().isEmpty ? '🍽️' : emoji.trim(),
      source: source,
      sourceId: sourceId,
      totalServings: servings,
      remainingServings: servings,
      madeAt: created,
      location: location,
      bestBy: bestBy,
      nutritionPerServing: nutritionPerServing,
      note: note.trim(),
    );
    _preparedBatches = [..._preparedBatches, batch];
    _queue(_cloud?.savePreparedBatch(batch));
    notifyListeners();
    return batch;
  }

  ConsumptionEvent consumePreparedBatch(
    PreparedBatch batch,
    double servings, {
    String? portionName,
  }) {
    if (!servings.isFinite || servings <= 0) {
      throw ArgumentError('Servings must be positive');
    }
    if (servings > batch.remainingServings + 0.000001) {
      throw StateError(
        'Only ${units.formatAmount(batch.remainingServings)} servings remain',
      );
    }
    final index = _preparedBatches.indexWhere((item) => item.id == batch.id);
    if (index < 0 || !_preparedBatches[index].isActive) {
      throw StateError('This prepared food is no longer available');
    }
    final updated = _preparedBatches[index].copyWith(
      remainingServings: (_preparedBatches[index].remainingServings - servings)
          .clamp(0, double.infinity),
    );
    _preparedBatches[index] = updated;
    final amount = portionName?.trim().isNotEmpty == true
        ? portionName!.trim()
        : '${units.formatAmount(servings)} ${servings == 1 ? 'serving' : 'servings'}';
    final event = ConsumptionEvent(
      id: 'event-${DateTime.now().microsecondsSinceEpoch}',
      label: '$amount of ${batch.name}',
      timestamp: DateTime.now(),
      kind: batch.source == PreparedSource.external
          ? ConsumptionKind.external
          : ConsumptionKind.recipe,
      recipeId: batch.source == PreparedSource.recipe ? batch.sourceId : null,
      deductions: const [],
      preparedDeductions: [
        PreparedDeduction(batchId: batch.id, servings: servings),
      ],
      nutrition: batch.nutritionPerServing?.scale(servings),
      nutritionEstimated: batch.source == PreparedSource.manual,
      note: 'From prepared food stored in ${batch.location.name}',
    );
    _history.add(event);
    _queue(_cloud?.savePreparedConsumption(event, [updated]));
    notifyListeners();
    return event;
  }

  ConsumptionEvent consumeMealTemplate(MealTemplate meal, {double? servings}) {
    final mealServings = servings ?? meal.servings;
    if (!mealServings.isFinite || mealServings <= 0) {
      throw ArgumentError('Meal servings must be positive');
    }
    final working = [..._preparedBatches];
    final deductions = <PreparedDeduction>[];
    var nutrition = const NutritionTotals();
    var foundNutrition = false;
    for (final component in meal.components) {
      var needed = component.servings * mealServings / meal.servings;
      final candidates =
          working
              .where(
                (batch) =>
                    batch.isActive &&
                    batch.source == PreparedSource.recipe &&
                    batch.sourceId == component.recipeId,
              )
              .toList()
            ..sort((a, b) => a.madeAt.compareTo(b.madeAt));
      for (final candidate in candidates) {
        if (needed <= 0.000001) break;
        final take = needed < candidate.remainingServings
            ? needed
            : candidate.remainingServings;
        final index = working.indexWhere((item) => item.id == candidate.id);
        working[index] = candidate.copyWith(
          remainingServings: candidate.remainingServings - take,
        );
        deductions.add(
          PreparedDeduction(batchId: candidate.id, servings: take),
        );
        final componentNutrition = candidate.nutritionPerServing?.scale(take);
        if (componentNutrition != null) {
          foundNutrition = true;
          nutrition = nutrition + componentNutrition;
        }
        needed -= take;
      }
      if (needed > 0.000001) {
        final recipe = _recipes.firstWhere(
          (item) => item.id == component.recipeId,
          orElse: () => throw StateError('A component recipe is missing'),
        );
        throw StateError(
          'Prepare ${units.formatAmount(needed)} more servings of ${recipe.name}',
        );
      }
    }
    _preparedBatches = working;
    final changedIds = deductions.map((item) => item.batchId).toSet();
    final changed = working
        .where((item) => changedIds.contains(item.id))
        .toList();
    final event = ConsumptionEvent(
      id: 'event-${DateTime.now().microsecondsSinceEpoch}',
      label:
          '${units.formatAmount(mealServings)} ${mealServings == 1 ? 'serving' : 'servings'} of ${meal.name}',
      timestamp: DateTime.now(),
      kind: ConsumptionKind.recipe,
      deductions: const [],
      preparedDeductions: deductions,
      nutrition: foundNutrition ? nutrition : null,
      note: 'Compound meal: ${meal.components.length} components',
    );
    _history.add(event);
    _queue(_cloud?.savePreparedConsumption(event, changed));
    notifyListeners();
    return event;
  }

  ConsumptionEvent consumePreparedRecipe(Recipe recipe, double servings) {
    return consumeMealTemplate(
      MealTemplate(
        id: 'prepared-${recipe.id}',
        name: recipe.name,
        servings: servings,
        components: [MealComponent(recipeId: recipe.id, servings: servings)],
        emoji: recipe.emoji,
      ),
      servings: servings,
    );
  }

  void updatePreparedBatch(
    PreparedBatch batch, {
    double? remainingServings,
    StorageLocation? location,
    DateTime? bestBy,
    bool clearBestBy = false,
    bool discard = false,
  }) {
    final index = _preparedBatches.indexWhere((item) => item.id == batch.id);
    if (index < 0) throw StateError('Unknown prepared food ${batch.id}');
    final remaining = remainingServings ?? batch.remainingServings;
    if (!remaining.isFinite ||
        remaining < 0 ||
        remaining > batch.totalServings) {
      throw ArgumentError('Remaining servings must be within the batch total');
    }
    final updated = batch.copyWith(
      remainingServings: remaining,
      location: location,
      bestBy: bestBy,
      clearBestBy: clearBestBy,
      discardedAt: discard ? DateTime.now() : null,
    );
    _preparedBatches[index] = updated;
    _queue(_cloud?.savePreparedBatch(updated));
    notifyListeners();
  }

  void saveMealTemplate(MealTemplate meal) {
    if (meal.name.trim().isEmpty ||
        meal.servings <= 0 ||
        meal.components.isEmpty ||
        meal.components.any(
          (component) =>
              component.servings <= 0 ||
              !_recipes.any((recipe) => recipe.id == component.recipeId),
        )) {
      throw ArgumentError(
        'Meals need a name, servings, and valid recipe components',
      );
    }
    final index = _mealTemplates.indexWhere((item) => item.id == meal.id);
    if (index < 0) {
      _mealTemplates = [..._mealTemplates, meal];
    } else {
      _mealTemplates[index] = meal;
    }
    _queue(_cloud?.saveMealTemplate(meal));
    _refreshPlannedGroceries();
    notifyListeners();
  }

  void deleteMealTemplate(String id) {
    _mealTemplates = _mealTemplates.where((item) => item.id != id).toList();
    _queue(_cloud?.deleteMealTemplate(id));
    notifyListeners();
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
          '${units.formatUnitAmount(food, amount, unit)} ${food.name.toLowerCase()}',
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
    ProductDefinition? product,
    required double amount,
    required String unit,
    required StorageLocation location,
    DateTime? bestBy,
  }) {
    if (product != null && product.foodId != food.id) {
      throw ArgumentError('The product does not belong to ${food.name}');
    }
    final productConversion = product?.conversionFor(unit);
    final quantity = productConversion == null
        ? units.toBase(food, amount, unit)
        : amount * productConversion.baseAmount;
    final lot = InventoryLot(
      id: 'lot-${DateTime.now().microsecondsSinceEpoch}',
      foodId: food.id,
      quantityBase: quantity,
      location: location,
      purchasedAt: DateTime.now(),
      bestBy: bestBy,
      productId: product?.id,
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
    if (food.displayUnit != null &&
        !food.conversions.any((item) => item.unit == food.displayUnit)) {
      throw ArgumentError('The display unit must match a conversion');
    }
    _foods[food.id] = food;
    _queue(_cloud?.saveFood(food));
    notifyListeners();
  }

  void saveProduct(ProductDefinition product) {
    if (product.name.trim().isEmpty) {
      throw ArgumentError('Product name is required');
    }
    if (!_foods.containsKey(product.foodId)) {
      throw ArgumentError('Product references unknown food ${product.foodId}');
    }
    final barcode = product.barcode?.trim();
    if (barcode != null &&
        barcode.isNotEmpty &&
        _products.values.any(
          (item) => item.id != product.id && item.barcode == barcode,
        )) {
      throw ArgumentError('Barcode is already assigned to another product');
    }
    _products[product.id] = product;
    _queue(_cloud?.saveProduct(product));
    notifyListeners();
  }

  void deleteProduct(String productId) {
    if (_lots.any(
      (lot) => lot.productId == productId && lot.quantityBase > 0,
    )) {
      throw StateError('This product still has inventory');
    }
    _products.remove(productId);
    _queue(_cloud?.deleteProduct(productId));
    notifyListeners();
  }

  void deleteFood(String foodId) {
    if (_products.values.any((product) => product.foodId == foodId)) {
      throw StateError('Delete this food’s products first');
    }
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
    final nutritionOverride = recipe.nutritionOverride;
    if (nutritionOverride != null) {
      final values = [
        nutritionOverride.calories,
        nutritionOverride.proteinG,
        nutritionOverride.carbsG,
        nutritionOverride.fatG,
        nutritionOverride.fiberG,
        nutritionOverride.sugarG,
        nutritionOverride.sodiumMg,
      ];
      if (values.any((value) => !value.isFinite || value < 0) ||
          !values.any((value) => value > 0)) {
        throw ArgumentError('Enter at least one prepared nutrition value');
      }
    }
    for (final ingredient in recipe.ingredients) {
      final definition = food(ingredient.foodId);
      definition.conversionFor(ingredient.unit);
      if (ingredient.amount <= 0) {
        throw ArgumentError('Ingredient amounts must be positive');
      }
    }
    if (recipe.preparationRules.any(
          (rule) =>
              rule.id.trim().isEmpty ||
              rule.kind.trim().isEmpty ||
              rule.label.trim().isEmpty ||
              !rule.leadHours.isFinite ||
              rule.leadHours <= 0,
        ) ||
        recipe.preparationRules.map((rule) => rule.id).toSet().length !=
            recipe.preparationRules.length) {
      throw ArgumentError(
        'Preparation reminders need unique IDs, labels, kinds, and positive lead hours',
      );
    }
    final index = _recipes.indexWhere((item) => item.id == recipe.id);
    if (index < 0) {
      _recipes = [..._recipes, recipe];
    } else {
      _recipes = [..._recipes]..[index] = recipe;
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

  void saveFoodPreferences(FoodPreferences preferences) {
    _foodPreferences = FoodPreferences(
      allergies: _cleanPreferenceList(preferences.allergies),
      dislikes: _cleanPreferenceList(preferences.dislikes),
      favorites: _cleanPreferenceList(preferences.favorites),
      dietaryRules: _cleanPreferenceList(preferences.dietaryRules),
      planningNotes: preferences.planningNotes.trim(),
    );
    _queue(_cloud?.saveFoodPreferences(_foodPreferences));
    notifyListeners();
  }

  List<String> _cleanPreferenceList(Iterable<String> values) {
    final seen = <String>{};
    return values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty && seen.add(value.toLowerCase()))
        .toList();
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

  ({Map<String, double> requirements, Map<String, DateTime> firstNeededDates})
  get _plannedRequirementSummary {
    final requirements = <String, double>{};
    final firstNeededDates = <String, DateTime>{};
    final remainingInventory = <String, double>{};
    final availablePrepared = <String, double>{};
    for (final batch in _preparedBatches.where(
      (item) =>
          item.isActive &&
          item.source == PreparedSource.recipe &&
          item.sourceId != null,
    )) {
      availablePrepared[batch.sourceId!] =
          (availablePrepared[batch.sourceId!] ?? 0) + batch.remainingServings;
    }
    final pendingMeals =
        _plannedMeals
            .where(
              (item) =>
                  item.completedAt == null &&
                  item.intent == PlannedMealIntent.prepare,
            )
            .toList()
          ..sort((a, b) {
            final byDate = a.date.compareTo(b.date);
            if (byDate != 0) return byDate;
            final bySlot = a.slot.index.compareTo(b.slot.index);
            return bySlot != 0 ? bySlot : a.id.compareTo(b.id);
          });
    for (final meal in pendingMeals) {
      final recipeNeeds = <String, double>{};
      if (meal.source == PlannedMealSource.recipe && meal.sourceId != null) {
        recipeNeeds[meal.sourceId!] = meal.servings;
      } else if (meal.source == PlannedMealSource.meal &&
          meal.sourceId != null) {
        final templateIndex = _mealTemplates.indexWhere(
          (item) => item.id == meal.sourceId,
        );
        if (templateIndex < 0) continue;
        final template = _mealTemplates[templateIndex];
        for (final component in template.components) {
          recipeNeeds[component.recipeId] =
              (recipeNeeds[component.recipeId] ?? 0) +
              component.servings * meal.servings / template.servings;
        }
      } else {
        continue;
      }
      for (final need in recipeNeeds.entries) {
        final onHand = availablePrepared[need.key] ?? 0;
        final preparedUsed = need.value < onHand ? need.value : onHand;
        availablePrepared[need.key] = onHand - preparedUsed;
        final toPrepare = need.value - preparedUsed;
        if (toPrepare <= 0.000001) continue;
        final recipeIndex = _recipes.indexWhere((item) => item.id == need.key);
        if (recipeIndex < 0) continue;
        final recipe = _recipes[recipeIndex];
        final scale = toPrepare / recipe.servings;
        for (final ingredient in recipe.ingredients) {
          final definition = food(ingredient.foodId);
          final amountBase = units.toBase(
            definition,
            ingredient.amount * scale,
            ingredient.unit,
          );
          requirements[ingredient.foodId] =
              (requirements[ingredient.foodId] ?? 0) + amountBase;
          final remaining = remainingInventory.putIfAbsent(
            ingredient.foodId,
            () => totalFor(ingredient.foodId),
          );
          if (amountBase > remaining + 0.0001 &&
              !firstNeededDates.containsKey(ingredient.foodId)) {
            firstNeededDates[ingredient.foodId] = DateTime(
              meal.date.year,
              meal.date.month,
              meal.date.day,
            );
          }
          remainingInventory[ingredient.foodId] = remaining - amountBase;
        }
      }
    }
    return (requirements: requirements, firstNeededDates: firstNeededDates);
  }

  Map<String, double> get plannedRequirementsBase =>
      _plannedRequirementSummary.requirements;

  Map<String, DateTime> get plannedFirstNeededDates =>
      _plannedRequirementSummary.firstNeededDates;

  void savePlannedMeal(PlannedMeal meal) {
    if (meal.name.trim().isEmpty || meal.servings <= 0) {
      throw ArgumentError('Planned meals need a name and positive servings');
    }
    if (meal.source == PlannedMealSource.recipe &&
        !_recipes.any((recipe) => recipe.id == meal.sourceId)) {
      throw ArgumentError('Planned recipe does not exist');
    }
    if (meal.source == PlannedMealSource.meal &&
        !_mealTemplates.any((template) => template.id == meal.sourceId)) {
      throw ArgumentError('Planned compound meal does not exist');
    }
    if (meal.leftoverOfGroupId != null) {
      if (meal.intent != PlannedMealIntent.leftover) {
        throw ArgumentError('A planned-meal reference must be leftovers');
      }
      final sources = _plannedMeals.where(
        (item) => item.groupId == meal.leftoverOfGroupId,
      );
      if (sources.isEmpty ||
          sources.any((source) => !source.date.isBefore(meal.date))) {
        throw ArgumentError(
          'Leftovers must reference an earlier meal in the plan',
        );
      }
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

  void deletePlannedMealGroup(String groupId) {
    _plannedMeals = _plannedMeals
        .where((meal) => meal.groupId != groupId)
        .toList();
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

  void rebuildGroceryList() {
    _rebuildGroceryList();
    _savePlanning();
  }

  void addManualGroceryItem(
    String name, {
    String quantityLabel = '',
    GrocerySection? grocerySection,
  }) {
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
        grocerySection: grocerySection ?? inferGrocerySection(name),
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
    final summary = _plannedRequirementSummary;
    for (final requirement in summary.requirements.entries) {
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
          firstNeededDate: summary.firstNeededDates[requirement.key],
          grocerySection: definition.grocerySection,
        ),
      );
    }
    planned.sort((a, b) {
      final bySection = a.grocerySection.storeOrder.compareTo(
        b.grocerySection.storeOrder,
      );
      return bySection != 0 ? bySection : a.name.compareTo(b.name);
    });
    _groceryItems = [...planned, ...manual];
  }

  void _refreshPlannedGroceries() {
    if (!_plannedMeals.any(
      (meal) =>
          meal.completedAt == null &&
          (meal.source == PlannedMealSource.recipe ||
              meal.source == PlannedMealSource.meal),
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
    for (final deduction in event.preparedDeductions) {
      final batchIndex = _preparedBatches.indexWhere(
        (batch) => batch.id == deduction.batchId,
      );
      if (batchIndex < 0) {
        throw StateError(
          'Cannot restore missing prepared batch ${deduction.batchId}',
        );
      }
      final batch = _preparedBatches[batchIndex];
      final restored = batch.remainingServings + deduction.servings;
      if (restored > batch.totalServings + 0.000001) {
        throw StateError('Restoring this event would overfill ${batch.name}');
      }
      _preparedBatches[batchIndex] = batch.copyWith(
        remainingServings: restored.clamp(0, batch.totalServings),
      );
    }
    final undone = event.markUndone(DateTime.now());
    _history[index] = undone;
    final affectedIds = event.deductions.map((item) => item.lotId).toSet();
    if (event.preparedDeductions.isNotEmpty) {
      final preparedIds = event.preparedDeductions
          .map((item) => item.batchId)
          .toSet();
      _queue(
        _cloud?.savePreparedUndo(
          undone,
          _preparedBatches.where((batch) => preparedIds.contains(batch.id)),
        ),
      );
    } else {
      _queue(
        _cloud?.saveUndo(
          undone,
          _lots.where((lot) => affectedIds.contains(lot.id)),
        ),
      );
    }
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
    _lots = _lotsAfterDeductions(_lots, deductions);
  }

  List<InventoryLot> _lotsAfterDeductions(
    List<InventoryLot> lots,
    List<LotDeduction> deductions,
  ) {
    final next = [...lots];
    for (final deduction in deductions) {
      final index = next.indexWhere((lot) => lot.id == deduction.lotId);
      if (index < 0) throw StateError('Unknown lot ${deduction.lotId}');
      next[index] = next[index].copyWith(
        quantityBase: next[index].quantityBase - deduction.quantityBase,
      );
    }
    return next;
  }
}
