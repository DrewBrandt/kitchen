import '../models/pantry_models.dart';

class SeedData {
  static List<FoodDefinition> foods() => const [
    FoodDefinition(
      id: 'egg',
      name: 'Eggs',
      mode: QuantityMode.counted,
      baseUnit: 'each',
      conversions: [
        UnitConversion(unit: 'each', symbol: 'eggs', baseAmount: 1),
      ],
      emoji: '🥚',
      defaultLocation: StorageLocation.fridge,
      grocerySection: GrocerySection.eggsCheeseDough,
      ingredientRole: IngredientRole.main,
    ),
    FoodDefinition(
      id: 'onion',
      name: 'Onions',
      mode: QuantityMode.counted,
      baseUnit: 'each',
      conversions: [
        UnitConversion(unit: 'each', symbol: 'onions', baseAmount: 1),
      ],
      emoji: '🧅',
      grocerySection: GrocerySection.produceDeli,
    ),
    FoodDefinition(
      id: 'butter',
      name: 'Butter',
      mode: QuantityMode.measured,
      baseUnit: 'gram',
      conversions: [
        UnitConversion(unit: 'gram', symbol: 'g', baseAmount: 1),
        UnitConversion(unit: 'ounce', symbol: 'oz', baseAmount: 28.3495),
        UnitConversion(unit: 'pound', symbol: 'lb', baseAmount: 453.592),
        UnitConversion(unit: 'tablespoon', symbol: 'tbsp', baseAmount: 14.175),
        UnitConversion(unit: 'cup', symbol: 'cups', baseAmount: 226.8),
        UnitConversion(unit: 'stick', symbol: 'sticks', baseAmount: 113.4),
      ],
      emoji: '🧈',
      defaultLocation: StorageLocation.fridge,
      grocerySection: GrocerySection.dairyFrozenMeals,
      ingredientRole: IngredientRole.staple,
    ),
    FoodDefinition(
      id: 'milk',
      name: 'Milk',
      mode: QuantityMode.measured,
      baseUnit: 'milliliter',
      conversions: [
        UnitConversion(unit: 'milliliter', symbol: 'mL', baseAmount: 1),
        UnitConversion(unit: 'liter', symbol: 'L', baseAmount: 1000),
        UnitConversion(unit: 'cup', symbol: 'cups', baseAmount: 236.588),
        UnitConversion(unit: 'tablespoon', symbol: 'tbsp', baseAmount: 14.7868),
      ],
      emoji: '🥛',
      defaultLocation: StorageLocation.fridge,
      grocerySection: GrocerySection.dairyFrozenMeals,
    ),
    FoodDefinition(
      id: 'flour',
      name: 'All-purpose flour',
      mode: QuantityMode.measured,
      baseUnit: 'gram',
      conversions: [
        UnitConversion(unit: 'gram', symbol: 'g', baseAmount: 1),
        UnitConversion(unit: 'ounce', symbol: 'oz', baseAmount: 28.3495),
        UnitConversion(unit: 'pound', symbol: 'lb', baseAmount: 453.592),
        UnitConversion(unit: 'cup', symbol: 'cups', baseAmount: 120),
        UnitConversion(unit: 'tablespoon', symbol: 'tbsp', baseAmount: 7.5),
      ],
      emoji: '🌾',
      grocerySection: GrocerySection.bakingMeat,
      ingredientRole: IngredientRole.staple,
    ),
    FoodDefinition(
      id: 'salt',
      name: 'Salt',
      mode: QuantityMode.measured,
      baseUnit: 'gram',
      conversions: [
        UnitConversion(unit: 'gram', symbol: 'g', baseAmount: 1),
        UnitConversion(unit: 'teaspoon', symbol: 'tsp', baseAmount: 6),
        UnitConversion(unit: 'tablespoon', symbol: 'tbsp', baseAmount: 18),
      ],
      emoji: '🧂',
      ingredientRole: IngredientRole.staple,
    ),
  ];

  static List<InventoryLot> lots(DateTime now) => [
    InventoryLot(
      id: 'eggs-a',
      foodId: 'egg',
      quantityBase: 8,
      location: StorageLocation.fridge,
      purchasedAt: now.subtract(const Duration(days: 5)),
      bestBy: now.add(const Duration(days: 6)),
    ),
    InventoryLot(
      id: 'eggs-b',
      foodId: 'egg',
      quantityBase: 6,
      location: StorageLocation.fridge,
      purchasedAt: now.subtract(const Duration(days: 1)),
      bestBy: now.add(const Duration(days: 15)),
    ),
    InventoryLot(
      id: 'onions-a',
      foodId: 'onion',
      quantityBase: 3.5,
      location: StorageLocation.pantry,
      bestBy: now.add(const Duration(days: 12)),
    ),
    InventoryLot(
      id: 'butter-a',
      foodId: 'butter',
      quantityBase: 340.2,
      location: StorageLocation.fridge,
      bestBy: now.add(const Duration(days: 45)),
    ),
    InventoryLot(
      id: 'milk-a',
      foodId: 'milk',
      quantityBase: 1400,
      location: StorageLocation.fridge,
      bestBy: now.add(const Duration(days: 3)),
    ),
    InventoryLot(
      id: 'flour-a',
      foodId: 'flour',
      quantityBase: 1100,
      location: StorageLocation.pantry,
    ),
    InventoryLot(
      id: 'salt-a',
      foodId: 'salt',
      quantityBase: 300,
      location: StorageLocation.pantry,
    ),
  ];

  static List<Recipe> recipes() => const [
    Recipe(
      id: 'scrambled-eggs',
      name: 'Soft Scrambled Eggs',
      servings: 1,
      emoji: '🍳',
      ingredients: [
        RecipeIngredient(foodId: 'egg', amount: 2, unit: 'each'),
        RecipeIngredient(foodId: 'butter', amount: 0.5, unit: 'tablespoon'),
        RecipeIngredient(foodId: 'salt', amount: 0.125, unit: 'teaspoon'),
      ],
      instructions: [
        'Beat the eggs with a pinch of salt.',
        'Melt butter over medium-low heat.',
        'Stir gently until softly set.',
      ],
    ),
    Recipe(
      id: 'pancakes',
      name: 'Simple Pancakes',
      servings: 4,
      emoji: '🥞',
      ingredients: [
        RecipeIngredient(foodId: 'flour', amount: 1.5, unit: 'cup'),
        RecipeIngredient(foodId: 'milk', amount: 1.25, unit: 'cup'),
        RecipeIngredient(foodId: 'egg', amount: 1, unit: 'each'),
        RecipeIngredient(foodId: 'butter', amount: 2, unit: 'tablespoon'),
        RecipeIngredient(foodId: 'salt', amount: 0.5, unit: 'teaspoon'),
      ],
      instructions: [
        'Whisk the dry ingredients.',
        'Whisk in milk and egg until just combined.',
        'Cook portions in butter on a hot skillet.',
      ],
    ),
  ];
}
