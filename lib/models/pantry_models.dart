enum QuantityMode { counted, measured }

enum StorageLocation { pantry, fridge, freezer }

enum ConsumptionKind { recipe, inventory, external }

enum MealSlot { breakfast, lunch, dinner, snack }

enum PlannedMealSource { recipe, external, custom }

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
  );
}

class InventoryLot {
  const InventoryLot({
    required this.id,
    required this.foodId,
    required this.quantityBase,
    required this.location,
    this.bestBy,
    this.purchasedAt,
  });

  final String id;
  final String foodId;
  final double quantityBase;
  final StorageLocation location;
  final DateTime? bestBy;
  final DateTime? purchasedAt;

  InventoryLot copyWith({double? quantityBase}) => InventoryLot(
    id: id,
    foodId: foodId,
    quantityBase: quantityBase ?? this.quantityBase,
    location: location,
    bestBy: bestBy,
    purchasedAt: purchasedAt,
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
  });

  final String id;
  final String name;
  final double servings;
  final List<RecipeIngredient> ingredients;
  final List<String> instructions;
  final List<RecipePortion> portions;
  final String emoji;

  Recipe copyWith({
    String? id,
    String? name,
    double? servings,
    List<RecipeIngredient>? ingredients,
    List<String>? instructions,
    List<RecipePortion>? portions,
    String? emoji,
  }) => Recipe(
    id: id ?? this.id,
    name: name ?? this.name,
    servings: servings ?? this.servings,
    ingredients: ingredients ?? this.ingredients,
    instructions: instructions ?? this.instructions,
    portions: portions ?? this.portions,
    emoji: emoji ?? this.emoji,
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
    this.note = '',
    this.completedAt,
  });

  final String id;
  final DateTime date;
  final MealSlot slot;
  final PlannedMealSource source;
  final String? sourceId;
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
    name: name ?? this.name,
    emoji: emoji ?? this.emoji,
    servings: servings ?? this.servings,
    note: note ?? this.note,
    completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
  );
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
  });

  final String id;
  final String name;
  final String emoji;
  final bool checked;
  final bool fromPlan;
  final String? foodId;
  final double? quantityBase;
  final String quantityLabel;

  GroceryListItem copyWith({bool? checked}) => GroceryListItem(
    id: id,
    name: name,
    emoji: emoji,
    checked: checked ?? this.checked,
    fromPlan: fromPlan,
    foodId: foodId,
    quantityBase: quantityBase,
    quantityLabel: quantityLabel,
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
  );
}

class InsufficientInventoryException implements Exception {
  InsufficientInventoryException(this.missing);

  final Map<String, double> missing;

  @override
  String toString() => 'Insufficient inventory: $missing';
}
