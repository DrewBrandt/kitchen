enum QuantityMode { counted, measured }

enum StorageLocation { pantry, fridge, freezer }

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
    this.emoji = '🥫',
    this.defaultLocation = StorageLocation.pantry,
    this.nutrition,
  });

  final String id;
  final String name;
  final QuantityMode mode;
  final String baseUnit;
  final List<UnitConversion> conversions;
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

class Recipe {
  const Recipe({
    required this.id,
    required this.name,
    required this.servings,
    required this.ingredients,
    required this.instructions,
    this.emoji = '🍽️',
  });

  final String id;
  final String name;
  final double servings;
  final List<RecipeIngredient> ingredients;
  final List<String> instructions;
  final String emoji;

  Recipe copyWith({
    String? id,
    String? name,
    double? servings,
    List<RecipeIngredient>? ingredients,
    List<String>? instructions,
    String? emoji,
  }) => Recipe(
    id: id ?? this.id,
    name: name ?? this.name,
    servings: servings ?? this.servings,
    ingredients: ingredients ?? this.ingredients,
    instructions: instructions ?? this.instructions,
    emoji: emoji ?? this.emoji,
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
    this.recipeId,
    this.undoneAt,
    this.nutrition,
  });

  final String id;
  final String label;
  final DateTime timestamp;
  final String? recipeId;
  final List<LotDeduction> deductions;
  final DateTime? undoneAt;
  final NutritionTotals? nutrition;

  ConsumptionEvent markUndone(DateTime at) => ConsumptionEvent(
    id: id,
    label: label,
    timestamp: timestamp,
    recipeId: recipeId,
    deductions: deductions,
    undoneAt: at,
    nutrition: nutrition,
  );
}

class InsufficientInventoryException implements Exception {
  InsufficientInventoryException(this.missing);

  final Map<String, double> missing;

  @override
  String toString() => 'Insufficient inventory: $missing';
}
