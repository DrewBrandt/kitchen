import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pantry_inventory/data/pantry_store.dart';
import 'package:pantry_inventory/models/pantry_models.dart';
import 'package:pantry_inventory/pages/home_page.dart';

void main() {
  Future<void> pumpPantry(
    WidgetTester tester,
    Size size, {
    PantryStore? store,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: PantryHomePage(
          store: store ?? PantryStore.demo(),
          onSignOut: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('redesigned desktop pages render without layout exceptions', (
    tester,
  ) async {
    await pumpPantry(tester, const Size(1440, 980));
    expect(tester.takeException(), isNull);

    for (final page in [
      'Inventory',
      'Recipes',
      'Eating out',
      'Food log',
      'History',
      'Trends',
      'This week',
      'Grocery list',
    ]) {
      await tester.tap(find.text(page).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$page should render');
    }
  });

  testWidgets('food log graph identifies each food contribution', (
    tester,
  ) async {
    final store = PantryStore.demo();
    store.logExternalMeal(
      label: 'Chicken sandwich',
      nutrition: const NutritionTotals(calories: 550, proteinG: 34),
    );
    store.logExternalMeal(
      label: 'Chocolate milk',
      nutrition: const NutritionTotals(calories: 280, proteinG: 16),
    );

    await pumpPantry(tester, const Size(1440, 980), store: store);
    await tester.tap(find.text('Food log').first);
    await tester.pumpAndSettle();

    expect(find.text('How each food built your day'), findsOneWidget);
    expect(find.text('Chicken sandwich'), findsWidgets);
    expect(find.text('Chocolate milk'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same-day repeat foods collapse in the graph and lists', (
    tester,
  ) async {
    final store = PantryStore.demo();
    final now = DateTime.now();
    for (var index = 0; index < 2; index++) {
      store.logExternalMeal(
        label: 'Repeat test yogurt',
        timestamp: now.add(Duration(microseconds: index)),
        nutrition: const NutritionTotals(calories: 140, proteinG: 15),
      );
    }

    await pumpPantry(tester, const Size(1440, 980), store: store);
    await tester.tap(find.text('Food log').first);
    await tester.pumpAndSettle();

    expect(find.text('2× Repeat test yogurt'), findsNWidgets(2));
    expect(find.text('Repeat test yogurt'), findsNothing);
    expect(find.text('Remove all'), findsOneWidget);

    await tester.tap(find.text('History').first);
    await tester.pumpAndSettle();

    expect(find.text('2× Repeat test yogurt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('eating out groups saved foods by place or brand', (
    tester,
  ) async {
    final store = PantryStore.demo();
    store.saveExternalFood(
      const ExternalFood(
        id: 'chick-fil-a-sandwich',
        name: 'Chicken sandwich',
        brand: 'Chick-fil-A',
        servingLabel: '1 sandwich',
        emoji: '🥪',
        nutrition: NutritionTotals(calories: 420, proteinG: 29),
      ),
    );

    await pumpPantry(tester, const Size(1440, 980), store: store);
    await tester.tap(find.text('Eating out').first);
    await tester.pumpAndSettle();

    expect(find.text('Chick-fil-A'), findsOneWidget);
    expect(find.text('Chicken sandwich'), findsOneWidget);
    expect(find.text('1 saved item'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history surfaces repetition and trends show contributors', (
    tester,
  ) async {
    final store = PantryStore.demo();
    final now = DateTime.now();
    for (var index = 0; index < 3; index++) {
      store.logExternalMeal(
        label: 'Chicken sandwich',
        timestamp: now.subtract(Duration(days: index * 2)),
        nutrition: const NutritionTotals(
          calories: 420,
          proteinG: 29,
          sodiumMg: 1460,
        ),
      );
    }
    store.logExternalMeal(
      label: 'Greek yogurt',
      timestamp: now.subtract(const Duration(days: 1)),
      nutrition: const NutritionTotals(calories: 140, proteinG: 15, sugarG: 10),
    );

    await pumpPantry(tester, const Size(1440, 980), store: store);
    await tester.tap(find.text('History').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('4 meals'), findsOneWidget);
    expect(find.text('Most repeated'), findsOneWidget);
    expect(find.text('3×'), findsOneWidget);

    await tester.tap(find.text('Trends').first);
    await tester.pumpAndSettle();

    expect(find.text('Protein, day by day'), findsOneWidget);
    expect(find.text('What drives each nutrient'), findsOneWidget);
    expect(find.text('Chicken sandwich'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('redesigned mobile navigation renders without overflow', (
    tester,
  ) async {
    await pumpPantry(tester, const Size(390, 844));
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Inventory').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('planning shows meals and generated grocery shortages', (
    tester,
  ) async {
    final store = PantryStore.demo();
    final recipe = store.recipes.firstWhere((item) => item.id == 'pancakes');
    store.savePlannedMeal(
      PlannedMeal(
        id: 'planned-pancakes',
        date: DateTime.now(),
        slot: MealSlot.dinner,
        source: PlannedMealSource.recipe,
        sourceId: recipe.id,
        name: recipe.name,
        emoji: recipe.emoji,
        servings: 20,
      ),
    );

    await pumpPantry(tester, const Size(1440, 980), store: store);
    await tester.tap(find.text('This week').first);
    await tester.pumpAndSettle();

    expect(find.text(recipe.name), findsWidgets);
    expect(find.text('Grocery list'), findsWidgets);
    expect(find.textContaining('Built from unfinished'), findsOneWidget);

    await tester.tap(find.text('Grocery list').first);
    await tester.pumpAndSettle();
    expect(find.text('Add item'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('planning exposes an editable food preference profile', (
    tester,
  ) async {
    final store = PantryStore.demo();
    await pumpPantry(tester, const Size(1440, 980), store: store);
    await tester.tap(find.text('This week').first);
    await tester.pumpAndSettle();

    expect(find.text('Food profile'), findsOneWidget);
    await tester.tap(find.text('Set up'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Allergies and intolerances'),
      'Tree nuts',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Foods to avoid'),
      'Raw tomatoes',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Favorites'),
      'Indian food',
    );
    await tester.tap(find.text('Save profile'));
    await tester.pumpAndSettle();

    expect(store.foodPreferences.allergies, ['Tree nuts']);
    expect(find.text('Tree nuts'), findsOneWidget);
    expect(find.text('Raw tomatoes'), findsOneWidget);
    expect(find.text('Indian food'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
