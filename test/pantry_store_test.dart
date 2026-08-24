import 'package:flutter_test/flutter_test.dart';
import 'package:pantry_inventory/data/pantry_store.dart';
import 'package:pantry_inventory/models/pantry_models.dart';

void main() {
  test('cooking deducts a recipe and undo restores every lot', () {
    final store = PantryStore.demo(now: DateTime(2026, 8, 23));
    final recipe = store.recipes.firstWhere(
      (item) => item.id == 'scrambled-eggs',
    );
    final eggsBefore = store.totalFor('egg');
    final butterBefore = store.totalFor('butter');

    final event = store.cook(recipe);

    expect(store.totalFor('egg'), eggsBefore - 2);
    expect(store.totalFor('butter'), closeTo(butterBefore - 7.0875, 0.0001));
    expect(store.history.single.id, event.id);

    store.undo(event.id);

    expect(store.totalFor('egg'), eggsBefore);
    expect(store.totalFor('butter'), closeTo(butterBefore, 0.0001));
    expect(store.history.single.undoneAt, isNotNull);
  });

  test('fractional counted foods are supported', () {
    final store = PantryStore.demo(now: DateTime(2026, 8, 23));
    final onion = store.food('onion');
    final before = store.totalFor('onion');

    store.consume(onion, 0.5, 'each');

    expect(store.totalFor('onion'), before - 0.5);
  });

  test(
    'an insufficient repeated cook leaves inventory and history unchanged',
    () {
      final store = PantryStore.demo(now: DateTime(2026, 8, 23));
      final pancakes = store.recipes.firstWhere(
        (item) => item.id == 'pancakes',
      );
      for (var count = 0; count < 4; count++) {
        store.cook(pancakes);
      }
      final milkBefore = store.totalFor('milk');
      final eggsBefore = store.totalFor('egg');
      final historyBefore = store.history.length;

      expect(
        () => store.cook(pancakes),
        throwsA(isA<InsufficientInventoryException>()),
      );

      expect(store.totalFor('milk'), milkBefore);
      expect(store.totalFor('egg'), eggsBefore);
      expect(store.history, hasLength(historyBefore));
    },
  );

  test('food definitions and recipes can be created and updated', () {
    final store = PantryStore.demo(now: DateTime(2026, 8, 23));
    final food = FoodDefinition(
      id: store.nextId('Greek yogurt'),
      name: 'Greek yogurt',
      mode: QuantityMode.counted,
      baseUnit: 'each',
      conversions: const [
        UnitConversion(unit: 'each', symbol: 'cups', baseAmount: 1),
      ],
      defaultLocation: StorageLocation.fridge,
    );
    store.saveFood(food);
    final recipe = Recipe(
      id: store.nextId('Yogurt bowl'),
      name: 'Yogurt bowl',
      servings: 1,
      ingredients: [RecipeIngredient(foodId: food.id, amount: 1, unit: 'each')],
      instructions: const ['Open and enjoy.'],
    );

    store.saveRecipe(recipe);

    expect(store.food(food.id).name, 'Greek yogurt');
    expect(store.recipes.any((item) => item.id == recipe.id), isTrue);
  });

  test('nutrition scales with food units and recipe servings', () {
    final store = PantryStore.demo(now: DateTime(2026, 8, 23));
    final eggs = store
        .food('egg')
        .copyWith(
          nutrition: const NutritionFacts(
            basisBaseAmount: 1,
            totals: NutritionTotals(calories: 70, proteinG: 6),
          ),
        );
    store.saveFood(eggs);
    final butter = store
        .food('butter')
        .copyWith(
          nutrition: const NutritionFacts(
            basisBaseAmount: 14.175,
            totals: NutritionTotals(calories: 100, fatG: 11),
          ),
        );
    store.saveFood(butter);
    final recipe = store.recipes.firstWhere(
      (item) => item.id == 'scrambled-eggs',
    );

    final total = store.nutritionForRecipe(recipe)!;

    expect(total.calories, closeTo(190, 0.001));
    expect(total.proteinG, closeTo(12, 0.001));
    expect(total.fatG, closeTo(5.5, 0.001));
  });

  test('outside meals add daily nutrition without changing inventory', () {
    final store = PantryStore.demo(now: DateTime(2026, 8, 23));
    final eggsBefore = store.totalFor('egg');
    final meal = store.logExternalMeal(
      label: 'Restaurant cheeseburger',
      note: 'Estimated from the menu',
      timestamp: DateTime(2026, 8, 23, 19, 30),
      nutrition: const NutritionTotals(
        calories: 720,
        proteinG: 38,
        carbsG: 45,
        fatG: 42,
        sodiumMg: 1280,
      ),
    );

    expect(meal.kind, ConsumptionKind.external);
    expect(meal.deductions, isEmpty);
    expect(store.totalFor('egg'), eggsBefore);
    expect(store.nutritionForDay(DateTime(2026, 8, 23)).calories, 720);
    expect(store.nutritionForDay(DateTime(2026, 8, 23)).proteinG, 38);

    store.undo(meal.id);

    expect(store.nutritionForDay(DateTime(2026, 8, 23)).calories, 0);
    expect(store.totalFor('egg'), eggsBefore);
  });

  test('nutrition targets can be personalized', () {
    final store = PantryStore.demo();
    const targets = NutritionTargets(
      calories: 2500,
      proteinG: 130,
      carbsG: 300,
      fatG: 83,
      fiberG: 38,
      sodiumMg: 2300,
      label: 'Personalized starting target',
    );

    store.saveNutritionTargets(targets);

    expect(store.nutritionTargets, same(targets));
    expect(store.nutritionTargets.proteinG, 130);
  });

  test('known outside foods can be reused without inventory changes', () {
    final store = PantryStore.demo();
    const sandwich = ExternalFood(
      id: 'restaurant-sandwich',
      name: 'Chicken sandwich',
      brand: 'Restaurant',
      servingLabel: '1 sandwich',
      nutrition: NutritionTotals(calories: 420, proteinG: 29),
    );
    final eggsBefore = store.totalFor('egg');

    store.saveExternalFood(sandwich);
    final event = store.logExternalFood(sandwich, servings: 2);

    expect(store.externalFoods.single.id, sandwich.id);
    expect(event.kind, ConsumptionKind.external);
    expect(event.nutrition!.calories, 840);
    expect(event.deductions, isEmpty);
    expect(store.totalFor('egg'), eggsBefore);
  });
}
