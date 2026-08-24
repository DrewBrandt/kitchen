enum QuantityMode { counted, measured }

enum StorageLocation { pantry, fridge, freezer }

enum ConsumptionKind { recipe, inventory, external }

enum MealSlot { breakfast, lunch, dinner, snack }

enum PlannedMealSource { recipe, meal, external, custom }

enum PreparedSource { recipe, external, manual }

class NutritionTotals {
  const NutritionTotals({
    this.calories = 0,
    this.proteinG = 0,
    this.carbsG = 0,
    this.fatG = 0,
    this.fiberG = 0,
    this.sugarG = 0,
    this.sodiumMg = 0,
  });

  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double fiberG;
  final double sugarG;
  final double sodiumMg;

  NutritionTotals scale(double factor) => NutritionTotals(
    calories: calories * factor,
    proteinG: proteinG * factor,
    carbsG: carbsG * factor,
    fatG: fatG * factor,
    fiberG: fiberG * factor,
    sugarG: sugarG * factor,
    sodiumMg: sodiumMg * factor,
  );

  NutritionTotals operator +(NutritionTotals other) => NutritionTotals(
    calories: calories + other.calories,
    proteinG: proteinG + other.proteinG,
    carbsG: carbsG + other.carbsG,
    fatG: fatG + other.fatG,
    fiberG: fiberG + other.fiberG,
    sugarG: sugarG + other.sugarG,
    sodiumMg: sodiumMg + other.sodiumMg,
  );
}

class NutritionFacts {
  const NutritionFacts({
    required this.basisBaseAmount,
    required this.totals,
    this.source = '',
    this.estimated = false,
  });

  final double basisBaseAmount;
  final NutritionTotals totals;
  final String source;
  final bool estimated;

  NutritionTotals forBaseAmount(double amount) =>
      totals.scale(amount / basisBaseAmount);
}

class NutritionTargets {
  const NutritionTargets({
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.fiberG,
    required this.sodiumMg,
    this.label = '',
  });

  static const defaults = NutritionTargets(
    calories: 2000,
    proteinG: 50,
    carbsG: 275,
    fatG: 78,
    fiberG: 28,
    sodiumMg: 2300,
    label: 'General FDA Daily Values',
  );

  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double fiberG;
  final double sodiumMg;
  final String label;
}

class FoodPreferences {
  const FoodPreferences({
    this.allergies = const [],
    this.dislikes = const [],
    this.favorites = const [],
    this.dietaryRules = const [],
    this.planningNotes = '',
  });

  static const empty = FoodPreferences();

  final List<String> allergies;
  final List<String> dislikes;
  final List<String> favorites;
  final List<String> dietaryRules;
  final String planningNotes;

  bool get isEmpty =>
      allergies.isEmpty &&
      dislikes.isEmpty &&
      favorites.isEmpty &&
      dietaryRules.isEmpty &&
      planningNotes.trim().isEmpty;
}

class ExternalFood {
  const ExternalFood({
    required this.id,
    required this.name,
    required this.servingLabel,
    required this.nutrition,
    this.brand = '',
    this.emoji = '🍽️',
    this.source = '',
    this.estimated = false,
  });

  final String id;
  final String name;
  final String servingLabel;
  final NutritionTotals nutrition;
  final String brand;
  final String emoji;
  final String source;
  final bool estimated;
}

extension StorageLocationLabel on StorageLocation {
  String get label => switch (this) {
    StorageLocation.pantry => 'Pantry',
    StorageLocation.fridge => 'Fridge',
    StorageLocation.freezer => 'Freezer',
  };
}

class UnitConversion {
  const UnitConversion({
    required this.unit,
    required this.symbol,
    required this.baseAmount,
  });

  final String unit;
  final String symbol;
  final double baseAmount;
}

class FoodDefinition {
  const FoodDefinition({
    required this.id,
    required this.name,
    required this.mode,
    required this.baseUnit,
    required this.conversions,
    this.displayUnit,
    this.emoji = '🥫',
    this.defaultLocation = StorageLocation.pantry,
    this.nutrition,
    this.aliases = const [],
  });

  final String id;
  final String name;
  final QuantityMode mode;
  final String baseUnit;
  final List<UnitConversion> conversions;
  final String? displayUnit;
  final String emoji;
  final StorageLocation defaultLocation;
  final NutritionFacts? nutrition;
  final List<String> aliases;

  UnitConversion conversionFor(String unit) => conversions.firstWhere(
    (conversion) => conversion.unit.toLowerCase() == unit.toLowerCase(),
    orElse: () => throw ArgumentError('Unsupported unit "$unit" for $name'),
  );

  FoodDefinition copyWith({
    String? id,
    String? name,
    QuantityMode? mode,
    String? baseUnit,
    List<UnitConversion>? conversions,
    String? displayUnit,
    bool clearDisplayUnit = false,
    String? emoji,
    StorageLocation? defaultLocation,
    NutritionFacts? nutrition,
    bool clearNutrition = false,
    List<String>? aliases,
  }) => FoodDefinition(
    id: id ?? this.id,
    name: name ?? this.name,
    mode: mode ?? this.mode,
    baseUnit: baseUnit ?? this.baseUnit,
    conversions: conversions ?? this.conversions,
    displayUnit: clearDisplayUnit ? null : displayUnit ?? this.displayUnit,
    emoji: emoji ?? this.emoji,
    defaultLocation: defaultLocation ?? this.defaultLocation,
    nutrition: clearNutrition ? null : nutrition ?? this.nutrition,
    aliases: aliases ?? this.aliases,
  );
}

/// A purchasable branded or store-specific version of a canonical food.
///
/// Recipes always reference [foodId]. Inventory lots may additionally retain a
/// [ProductDefinition.id], allowing a new brand to satisfy the same recipe
/// without losing the product name, barcode, package conversions, or label
/// nutrition.
class ProductDefinition {
  const ProductDefinition({
    required this.id,
    required this.foodId,
    required this.name,
    this.brand = '',
    this.aliases = const [],
    this.barcode,
    this.conversions = const [],
    this.nutrition,
  });

  final String id;
  final String foodId;
  final String name;
  final String brand;
  final List<String> aliases;
  final String? barcode;
  final List<UnitConversion> conversions;
  final NutritionFacts? nutrition;

  UnitConversion? conversionFor(String unit) {
    final normalized = unit.toLowerCase();
    for (final conversion in conversions) {
      if (conversion.unit.toLowerCase() == normalized) return conversion;
    }
    return null;
  }
}

class InventoryLot {
  const InventoryLot({
    required this.id,
    required this.foodId,
    required this.quantityBase,
    required this.location,
    this.bestBy,
    this.purchasedAt,
    this.productId,
  });

  final String id;
  final String foodId;
  final double quantityBase;
  final StorageLocation location;
  final DateTime? bestBy;
  final DateTime? purchasedAt;
  final String? productId;

  InventoryLot copyWith({double? quantityBase}) => InventoryLot(
    id: id,
    foodId: foodId,
    quantityBase: quantityBase ?? this.quantityBase,
    location: location,
    bestBy: bestBy,
    purchasedAt: purchasedAt,
    productId: productId,
  );
}

class RecipeIngredient {
  const RecipeIngredient({
    required this.foodId,
    required this.amount,
    required this.unit,
  });

  final String foodId;
  final double amount;
  final String unit;
}

class RecipePortion {
  const RecipePortion({required this.name, required this.servings});

  final String name;
  final double servings;
}

class Recipe {
  const Recipe({
    required this.id,
    required this.name,
    required this.servings,
    required this.ingredients,
    required this.instructions,
    this.portions = const [],
    this.emoji = '🍽️',
    this.nutritionOverride,
    this.sourceUrl = '',
    this.sourceNote = '',
    this.promptForFeedback = true,
  });

  final String id;
  final String name;
  final double servings;
  final List<RecipeIngredient> ingredients;
  final List<String> instructions;
  final List<RecipePortion> portions;
  final String emoji;
  final NutritionTotals? nutritionOverride;
  final String sourceUrl;
  final String sourceNote;
  final bool promptForFeedback;

  Recipe copyWith({
    String? id,
    String? name,
    double? servings,
    List<RecipeIngredient>? ingredients,
    List<String>? instructions,
    List<RecipePortion>? portions,
    String? emoji,
    NutritionTotals? nutritionOverride,
    bool clearNutritionOverride = false,
    String? sourceUrl,
    String? sourceNote,
    bool? promptForFeedback,
  }) => Recipe(
    id: id ?? this.id,
    name: name ?? this.name,
    servings: servings ?? this.servings,
    ingredients: ingredients ?? this.ingredients,
    instructions: instructions ?? this.instructions,
    portions: portions ?? this.portions,
    emoji: emoji ?? this.emoji,
    nutritionOverride: clearNutritionOverride
        ? null
        : nutritionOverride ?? this.nutritionOverride,
    sourceUrl: sourceUrl ?? this.sourceUrl,
    sourceNote: sourceNote ?? this.sourceNote,
    promptForFeedback: promptForFeedback ?? this.promptForFeedback,
  );
}

class RecipeMakeFeedback {
  const RecipeMakeFeedback({
    required this.id,
    required this.recipeId,
    required this.preparedBatchId,
    required this.createdAt,
    this.tasteRating,
    this.easeRating,
    this.actualMinutes,
  });

  final String id;
  final String recipeId;
  final String preparedBatchId;
  final DateTime createdAt;
  final int? tasteRating;
  final int? easeRating;
  final int? actualMinutes;
}

class MealComponent {
  const MealComponent({required this.recipeId, required this.servings});

  final String recipeId;
  final double servings;
}

class MealTemplate {
  const MealTemplate({
    required this.id,
    required this.name,
    required this.servings,
    required this.components,
    this.emoji = '🍽️',
    this.notes = '',
  });

  final String id;
  final String name;
  final double servings;
  final List<MealComponent> components;
  final String emoji;
  final String notes;
}

class PreparedBatch {
  const PreparedBatch({
    required this.id,
    required this.name,
    required this.emoji,
    required this.source,
    required this.totalServings,
    required this.remainingServings,
    required this.madeAt,
    required this.location,
    this.sourceId,
    this.bestBy,
    this.nutritionPerServing,
    this.portions = const [],
    this.ingredientDeductions = const [],
    this.note = '',
    this.discardedAt,
  });

  final String id;
  final String name;
  final String emoji;
  final PreparedSource source;
  final String? sourceId;
  final double totalServings;
  final double remainingServings;
  final DateTime madeAt;
  final StorageLocation location;
  final DateTime? bestBy;
  final NutritionTotals? nutritionPerServing;
  final List<RecipePortion> portions;
  final List<LotDeduction> ingredientDeductions;
  final String note;
  final DateTime? discardedAt;

  double get consumedServings => totalServings - remainingServings;
  bool get isActive => remainingServings > 0.000001 && discardedAt == null;

  PreparedBatch copyWith({
    double? remainingServings,
    StorageLocation? location,
    DateTime? bestBy,
    bool clearBestBy = false,
    String? note,
    DateTime? discardedAt,
    bool clearDiscardedAt = false,
  }) => PreparedBatch(
    id: id,
    name: name,
    emoji: emoji,
    source: source,
    sourceId: sourceId,
    totalServings: totalServings,
    remainingServings: remainingServings ?? this.remainingServings,
    madeAt: madeAt,
    location: location ?? this.location,
    bestBy: clearBestBy ? null : bestBy ?? this.bestBy,
    nutritionPerServing: nutritionPerServing,
    portions: portions,
    ingredientDeductions: ingredientDeductions,
    note: note ?? this.note,
    discardedAt: clearDiscardedAt ? null : discardedAt ?? this.discardedAt,
  );
}

class PlannedMeal {
  const PlannedMeal({
    required this.id,
    required this.date,
    required this.slot,
    required this.source,
    required this.name,
    required this.emoji,
    required this.servings,
    this.sourceId,
    this.groupId,
    this.leftoverOfGroupId,
    this.intent = PlannedMealIntent.prepare,
    this.note = '',
    this.completedAt,
  });

  final String id;
  final DateTime date;
  final MealSlot slot;
  final PlannedMealSource source;
  final String? sourceId;
  final String? groupId;

  /// The earlier planner meal this entry expects to eat from.
  ///
  /// The underlying [source] and [sourceId] are retained so the leftover can
  /// still be consumed and displayed without creating a saved recipe or meal.
  final String? leftoverOfGroupId;
  final PlannedMealIntent intent;
  final String name;
  final String emoji;
  final double servings;
  final String note;
  final DateTime? completedAt;

  PlannedMeal copyWith({
    DateTime? date,
    MealSlot? slot,
    PlannedMealSource? source,
    String? sourceId,
    String? groupId,
    String? leftoverOfGroupId,
    PlannedMealIntent? intent,
    String? name,
    String? emoji,
    double? servings,
    String? note,
    DateTime? completedAt,
    bool clearCompletedAt = false,
  }) => PlannedMeal(
    id: id,
    date: date ?? this.date,
    slot: slot ?? this.slot,
    source: source ?? this.source,
    sourceId: sourceId ?? this.sourceId,
    groupId: groupId ?? this.groupId,
    leftoverOfGroupId: leftoverOfGroupId ?? this.leftoverOfGroupId,
    intent: intent ?? this.intent,
    name: name ?? this.name,
    emoji: emoji ?? this.emoji,
    servings: servings ?? this.servings,
    note: note ?? this.note,
    completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
  );
}

enum PlannedMealIntent { prepare, leftover }

extension PlannedMealIntentLabel on PlannedMealIntent {
  String get label => switch (this) {
    PlannedMealIntent.prepare => 'Cook',
    PlannedMealIntent.leftover => 'Leftovers',
  };
}

extension MealSlotLabel on MealSlot {
  String get label => switch (this) {
    MealSlot.breakfast => 'Breakfast',
    MealSlot.lunch => 'Lunch',
    MealSlot.dinner => 'Dinner',
    MealSlot.snack => 'Snack',
  };
}

class GroceryListItem {
  const GroceryListItem({
    required this.id,
    required this.name,
    required this.emoji,
    required this.checked,
    required this.fromPlan,
    this.foodId,
    this.quantityBase,
    this.quantityLabel = '',
    this.firstNeededDate,
  });

  final String id;
  final String name;
  final String emoji;
  final bool checked;
  final bool fromPlan;
  final String? foodId;
  final double? quantityBase;
  final String quantityLabel;
  final DateTime? firstNeededDate;

  GroceryListItem copyWith({bool? checked}) => GroceryListItem(
    id: id,
    name: name,
    emoji: emoji,
    checked: checked ?? this.checked,
    fromPlan: fromPlan,
    foodId: foodId,
    quantityBase: quantityBase,
    quantityLabel: quantityLabel,
    firstNeededDate: firstNeededDate,
  );
}

class LotDeduction {
  const LotDeduction({
    required this.lotId,
    required this.foodId,
    required this.quantityBase,
  });

  final String lotId;
  final String foodId;
  final double quantityBase;
}

class PreparedDeduction {
  const PreparedDeduction({required this.batchId, required this.servings});

  final String batchId;
  final double servings;
}

class ConsumptionEvent {
  const ConsumptionEvent({
    required this.id,
    required this.label,
    required this.timestamp,
    required this.deductions,
    required this.kind,
    this.recipeId,
    this.undoneAt,
    this.nutrition,
    this.nutritionEstimated = false,
    this.note = '',
    this.preparedDeductions = const [],
  });

  final String id;
  final String label;
  final DateTime timestamp;
  final ConsumptionKind kind;
  final String? recipeId;
  final List<LotDeduction> deductions;
  final DateTime? undoneAt;
  final NutritionTotals? nutrition;
  final bool nutritionEstimated;
  final String note;
  final List<PreparedDeduction> preparedDeductions;

  ConsumptionEvent markUndone(DateTime at) => ConsumptionEvent(
    id: id,
    label: label,
    timestamp: timestamp,
    kind: kind,
    recipeId: recipeId,
    deductions: deductions,
    undoneAt: at,
    nutrition: nutrition,
    nutritionEstimated: nutritionEstimated,
    note: note,
    preparedDeductions: preparedDeductions,
  );
}

class InsufficientInventoryException implements Exception {
  InsufficientInventoryException(this.missing);

  final Map<String, double> missing;

  @override
  String toString() => 'Insufficient inventory: $missing';
}
