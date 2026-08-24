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

    for (final page in ['Inventory', 'Recipes', 'Eating out', 'Food log']) {
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

  testWidgets('redesigned mobile navigation renders without overflow', (
    tester,
  ) async {
    await pumpPantry(tester, const Size(390, 844));
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Inventory').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
