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

  test('repeated recipe portions scale ingredients into separate entries', () {
    final store = PantryStore.demo(now: DateTime(2026, 8, 23));
    final recipe = store.recipes.firstWhere(
      (item) => item.id == 'scrambled-eggs',
    );
    final eggsBefore = store.totalFor('egg');

    final events = store.cookPortions(
      recipe,
      servingsPerPortion: 0.5,
      count: 3,
      portionName: 'Half plate',
    );

    expect(events, hasLength(3));
    expect(
      events.map((event) => event.label),
      everyElement('Half plate of ${recipe.name}'),
    );
    expect(events.map((event) => event.id).toSet(), hasLength(3));
    expect(store.totalFor('egg'), eggsBefore - 3);
    expect(
      events,
      everyElement(
        predicate<ConsumptionEvent>((event) => event.deductions.isNotEmpty),
      ),
    );

    store.undo(events[1].id);
    expect(store.totalFor('egg'), eggsBefore - 2);
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

  test('food definitions reject a display unit without a conversion', () {
    final store = PantryStore.demo(now: DateTime(2026, 8, 23));
    final food = store.food('flour').copyWith(displayUnit: 'bag');

    expect(() => store.saveFood(food), throwsA(isA<ArgumentError>()));
  });

  test('product lookup treats UPC-A and EAN-13 barcodes as equivalent', () {
    final store = PantryStore.demo();
    final food = store.foods.first;
    const upc = '034000470693';
    store.saveProduct(
      ProductDefinition(
        id: 'barcode-product',
        foodId: food.id,
        name: 'Barcode product',
        barcode: upc,
      ),
    );

    expect(store.productForBarcode('0034000470693')?.id, 'barcode-product');
    expect(
      () => store.saveProduct(
        ProductDefinition(
          id: 'duplicate-barcode-product',
          foodId: food.id,
          name: 'Duplicate barcode product',
          barcode: '0034000470693',
        ),
      ),
      throwsArgumentError,
    );
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

  test('recipe preparation reminders require unique valid rules', () {
    final store = PantryStore.demo(now: DateTime(2026, 8, 23));
    final recipe = store.recipes.first.copyWith(
      preparationRules: const [
        RecipePreparationRule(
          id: 'thaw-chicken',
          kind: 'thaw',
          label: 'Move chicken to the refrigerator',
          leadHours: 24,
        ),
        RecipePreparationRule(
          id: 'thaw-chicken',
          kind: 'thaw',
          label: 'Duplicate',
          leadHours: 12,
        ),
      ],
    );

    expect(() => store.saveRecipe(recipe), throwsArgumentError);
  });

  test(
    'recipe nutrition override replaces ingredient nutrition and scales',
    () {
      final store = PantryStore.demo(now: DateTime(2026, 8, 23));
      final baseRecipe = store.recipes.firstWhere(
        (item) => item.id == 'scrambled-eggs',
      );
      final recipe = baseRecipe.copyWith(
        nutritionOverride: const NutritionTotals(
          calories: 600,
          proteinG: 20,
          carbsG: 75,
          fatG: 25,
        ),
      );

      final total = store.nutritionForRecipe(
        recipe,
        servings: recipe.servings / 2,
      )!;

      expect(total.calories, closeTo(300, 0.001));
      expect(total.proteinG, closeTo(10, 0.001));
      expect(total.carbsG, closeTo(37.5, 0.001));
      expect(total.fatG, closeTo(12.5, 0.001));
    },
  );

  test('recipe nutrition override must contain valid prepared totals', () {
    final store = PantryStore.demo(now: DateTime(2026, 8, 23));
    final recipe = store.recipes.first.copyWith(
      nutritionOverride: const NutritionTotals(calories: -1),
    );

    expect(() => store.saveRecipe(recipe), throwsArgumentError);
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

  test('food preferences are normalized and retained', () {
    final store = PantryStore.demo();

    store.saveFoodPreferences(
      const FoodPreferences(
        allergies: [' Tree nuts ', 'tree nuts'],
        dislikes: ['Raw tomatoes'],
        favorites: ['Indian food'],
        dietaryRules: ['Limit red meat'],
        planningNotes: ' Prefer easy weeknights. ',
      ),
    );

    expect(store.foodPreferences.allergies, ['Tree nuts']);
    expect(store.foodPreferences.dislikes, ['Raw tomatoes']);
    expect(store.foodPreferences.favorites, ['Indian food']);
    expect(store.foodPreferences.dietaryRules, ['Limit red meat']);
    expect(store.foodPreferences.planningNotes, 'Prefer easy weeknights.');
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

  test('meal plans derive grocery shortages from recipes and inventory', () {
    final store = PantryStore.demo(now: DateTime(2026, 8, 23));
    final recipe = store.recipes.firstWhere((item) => item.id == 'pancakes');
    store.savePlannedMeal(
      PlannedMeal(
        id: 'monday-pancakes',
        date: DateTime(2026, 8, 24),
        slot: MealSlot.dinner,
        source: PlannedMealSource.recipe,
        sourceId: recipe.id,
        name: recipe.name,
        emoji: recipe.emoji,
        servings: 20,
      ),
    );

    expect(store.plannedMeals, hasLength(1));
    expect(store.groceryItems, isNotEmpty);
    for (final item in store.groceryItems) {
      expect(item.fromPlan, isTrue);
      expect(item.foodId, isNotNull);
      final required = store.plannedRequirementsBase[item.foodId]!;
      expect(
        item.quantityBase,
        closeTo(required - store.totalFor(item.foodId!), 0.0001),
      );
      expect(item.firstNeededDate, DateTime(2026, 8, 24));
    }

    store.setPlannedMealCompleted('monday-pancakes', true);

    expect(store.groceryItems.where((item) => item.fromPlan), isEmpty);
  });

  test('leftover recipe plans retain identity without adding groceries', () {
    final store = PantryStore.demo(now: DateTime(2026, 8, 23));
    final recipe = store.recipes.firstWhere((item) => item.id == 'pancakes');
    store.savePlannedMeal(
      PlannedMeal(
        id: 'leftover-pancakes',
        groupId: 'monday-dinner',
        intent: PlannedMealIntent.leftover,
        date: DateTime(2026, 8, 24),
        slot: MealSlot.dinner,
        source: PlannedMealSource.recipe,
        sourceId: recipe.id,
        name: recipe.name,
        emoji: recipe.emoji,
        servings: 2,
      ),
    );

    expect(store.plannedMeals.single.sourceId, recipe.id);
    expect(store.plannedRequirementsBase, isEmpty);
    expect(store.groceryItems.where((item) => item.fromPlan), isEmpty);
  });

  test('a later leftover can reference an earlier planned meal', () {
    final store = PantryStore.demo(now: DateTime(2026, 8, 23));
    final recipe = store.recipes.firstWhere((item) => item.id == 'pancakes');
    store.savePlannedMeal(
      PlannedMeal(
        id: 'monday-pancakes',
        groupId: 'monday-dinner',
        date: DateTime(2026, 8, 24),
        slot: MealSlot.dinner,
        source: PlannedMealSource.recipe,
        sourceId: recipe.id,
        name: recipe.name,
        emoji: recipe.emoji,
        servings: 4,
      ),
    );
    final requirementsForOriginalCook = store.plannedRequirementsBase;

    store.savePlannedMeal(
      PlannedMeal(
        id: 'wednesday-pancakes',
        groupId: 'wednesday-lunch',
        leftoverOfGroupId: 'monday-dinner',
        intent: PlannedMealIntent.leftover,
        date: DateTime(2026, 8, 26),
        slot: MealSlot.lunch,
        source: PlannedMealSource.recipe,
        sourceId: recipe.id,
        name: recipe.name,
        emoji: recipe.emoji,
        servings: 2,
      ),
    );

    final leftover = store.plannedMeals.last;
    expect(leftover.leftoverOfGroupId, 'monday-dinner');
    expect(
      store.plannedRequirementsBase,
      requirementsForOriginalCook,
      reason: 'only the original cook should add ingredient demand',
    );
  });

  test('grouped recipe components can be removed as one meal', () {
    final store = PantryStore.demo(now: DateTime(2026, 8, 23));
    final recipes = store.recipes.take(2).toList();
    for (final recipe in recipes) {
      store.savePlannedMeal(
        PlannedMeal(
          id: 'group-${recipe.id}',
          groupId: 'monday-dinner',
          date: DateTime(2026, 8, 24),
          slot: MealSlot.dinner,
          source: PlannedMealSource.recipe,
          sourceId: recipe.id,
          name: recipe.name,
          emoji: recipe.emoji,
          servings: 2,
        ),
      );
    }

    expect(store.plannedMeals, hasLength(2));
    store.deletePlannedMealGroup('monday-dinner');
    expect(store.plannedMeals, isEmpty);
  });

  test('planned grocery need dates follow meal order, not insertion order', () {
    PantryStore buildStore(Iterable<DateTime> dates) {
      final store = PantryStore.demo(now: DateTime(2026, 8, 23));
      final recipe = store.recipes.firstWhere((item) => item.id == 'pancakes');
      for (final date in dates) {
        store.savePlannedMeal(
          PlannedMeal(
            id: 'pancakes-${date.day}',
            date: date,
            slot: MealSlot.dinner,
            source: PlannedMealSource.recipe,
            sourceId: recipe.id,
            name: recipe.name,
            emoji: recipe.emoji,
            servings: 20,
          ),
        );
      }
      return store;
    }

    final laterFirst = buildStore([
      DateTime(2026, 8, 28),
      DateTime(2026, 8, 24),
    ]);
    final earlierFirst = buildStore([
      DateTime(2026, 8, 24),
      DateTime(2026, 8, 28),
    ]);
    final laterFirstDates = {
      for (final item in laterFirst.groceryItems)
        item.foodId: item.firstNeededDate,
    };
    final earlierFirstDates = {
      for (final item in earlierFirst.groceryItems)
        item.foodId: item.firstNeededDate,
    };

    expect(laterFirstDates, isNotEmpty);
    expect(laterFirstDates, earlierFirstDates);
    expect(laterFirstDates.values, contains(DateTime(2026, 8, 24)));
  });

  test('manual grocery items can be checked and removed independently', () {
    final store = PantryStore.demo();

    store.addManualGroceryItem('Coffee filters', quantityLabel: '1 box');
    final item = store.groceryItems.single;
    store.toggleGroceryItem(item.id);

    expect(store.groceryItems.single.checked, isTrue);
    expect(store.groceryItems.single.quantityLabel, '1 box');

    store.deleteGroceryItem(item.id);
    expect(store.groceryItems, isEmpty);
  });

  test('manual groceries infer and retain their Safeway section', () {
    final store = PantryStore.demo();

    store.addManualGroceryItem('Dog treats');

    expect(
      store.groceryItems.single.grocerySection,
      GrocerySection.householdPets,
    );
  });

  test('product lots contribute to their canonical recipe ingredient', () {
    final store = PantryStore.demo();
    final rice = store.foods.firstWhere((food) => food.id == 'flour');
    const product = ProductDefinition(
      id: 'store-flour',
      foodId: 'flour',
      name: 'Store-brand all-purpose flour',
      brand: 'Store Brand',
      conversions: [
        UnitConversion(unit: 'bag', symbol: 'bag', baseAmount: 2268),
      ],
    );
    final before = store.totalFor(rice.id);

    store.saveProduct(product);
    store.addLot(
      food: rice,
      product: product,
      amount: 1,
      unit: 'bag',
      location: StorageLocation.pantry,
    );

    expect(store.lots.last.productId, product.id);
    expect(store.totalFor(rice.id), closeTo(before + 2268, 0.0001));
  });

  test('preparing a recipe creates servings without logging them as eaten', () {
    final store = PantryStore.demo(now: DateTime(2026, 8, 23));
    final recipe = store.recipes.firstWhere((item) => item.id == 'pancakes');
    final flourBefore = store.totalFor('flour');

    final batch = store.prepareRecipe(recipe);

    expect(store.history, isEmpty);
    expect(store.activePreparedBatches.single.id, batch.id);
    expect(batch.remainingServings, recipe.servings);
    expect(store.totalFor('flour'), lessThan(flourBefore));

    final event = store.consumePreparedBatch(batch, 1);
    expect(event.preparedDeductions.single.batchId, batch.id);
    expect(
      store.activePreparedBatches.single.remainingServings,
      recipe.servings - 1,
    );

    store.undo(event.id);
    expect(
      store.activePreparedBatches.single.remainingServings,
      recipe.servings,
    );
  });

  test('preparing a recipe group validates and creates every component', () {
    final store = PantryStore.demo(now: DateTime(2026, 8, 23));
    final pancakes = store.recipes.firstWhere((item) => item.id == 'pancakes');
    final eggs = store.recipes.firstWhere(
      (item) => item.id == 'scrambled-eggs',
    );

    final batches = store.prepareRecipeGroup({pancakes.id: 2, eggs.id: 1});

    expect(batches, hasLength(2));
    expect(
      batches.map((batch) => batch.sourceId),
      containsAll([pancakes.id, eggs.id]),
    );
    expect(store.history, isEmpty);
  });

  test('a recipe group shortage leaves every component unprepared', () {
    final store = PantryStore.demo(now: DateTime(2026, 8, 23));
    final pancakes = store.recipes.firstWhere((item) => item.id == 'pancakes');
    final eggs = store.recipes.firstWhere(
      (item) => item.id == 'scrambled-eggs',
    );
    final lotsBefore = store.lots;

    expect(
      () => store.prepareRecipeGroup({pancakes.id: 1000, eggs.id: 1000}),
      throwsA(isA<InsufficientInventoryException>()),
    );
    expect(store.preparedBatches, isEmpty);
    expect(store.lots, lotsBefore);
  });

  test('recipe make feedback produces personal averages and make history', () {
    final store = PantryStore.demo(now: DateTime(2026, 8, 24));
    final recipe = store.recipes.firstWhere((item) => item.id == 'pancakes');
    final firstBatch = store.prepareRecipe(recipe);
    final secondBatch = store.addPreparedBatch(
      name: recipe.name,
      servings: recipe.servings,
      source: PreparedSource.recipe,
      sourceId: recipe.id,
      madeAt: DateTime(2026, 8, 20),
    );

    store.saveRecipeMakeFeedback(
      RecipeMakeFeedback(
        id: 'feedback-1',
        recipeId: recipe.id,
        preparedBatchId: firstBatch.id,
        createdAt: DateTime(2026, 8, 24),
        tasteRating: 5,
        easeRating: 4,
        actualMinutes: 20,
      ),
    );
    store.saveRecipeMakeFeedback(
      RecipeMakeFeedback(
        id: 'feedback-2',
        recipeId: recipe.id,
        preparedBatchId: secondBatch.id,
        createdAt: DateTime(2026, 8, 20),
        tasteRating: 3,
        easeRating: 5,
        actualMinutes: 30,
      ),
    );

    expect(store.recipeMakesThisYear(recipe.id), 2);
    expect(store.lastMadeRecipe(recipe.id), firstBatch.madeAt);
    expect(store.averageTasteForRecipe(recipe.id), 4);
    expect(store.averageEaseForRecipe(recipe.id), 4.5);
    expect(store.averageMinutesForRecipe(recipe.id), 25);

    store.saveRecipe(recipe.copyWith(promptForFeedback: false));
    expect(
      store.recipes
          .firstWhere((item) => item.id == recipe.id)
          .promptForFeedback,
      isFalse,
    );
  });

  test('combined meals consume independent prepared recipe components', () {
    final store = PantryStore.demo(now: DateTime(2026, 8, 23));
    final pancakes = store.recipes.firstWhere((item) => item.id == 'pancakes');
    final eggs = store.recipes.firstWhere(
      (item) => item.id == 'scrambled-eggs',
    );
    store.addPreparedBatch(
      name: pancakes.name,
      servings: 4,
      source: PreparedSource.recipe,
      sourceId: pancakes.id,
      nutritionPerServing: const NutritionTotals(calories: 100),
    );
    store.addPreparedBatch(
      name: eggs.name,
      servings: 2,
      source: PreparedSource.recipe,
      sourceId: eggs.id,
      nutritionPerServing: const NutritionTotals(calories: 150),
    );
    final meal = MealTemplate(
      id: 'breakfast-plate',
      name: 'Breakfast plate',
      servings: 1,
      components: [
        MealComponent(recipeId: pancakes.id, servings: 2),
        MealComponent(recipeId: eggs.id, servings: 1),
      ],
    );
    store.saveMealTemplate(meal);

    final event = store.consumeMealTemplate(meal);

    expect(event.preparedDeductions, hasLength(2));
    expect(event.nutrition!.calories, 350);
    expect(
      store.activePreparedBatches.map((batch) => batch.remainingServings),
      containsAll([2, 1]),
    );
  });
}
