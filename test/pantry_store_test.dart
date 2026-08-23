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
}
