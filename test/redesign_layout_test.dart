import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pantry_inventory/data/pantry_store.dart';
import 'package:pantry_inventory/pages/home_page.dart';

void main() {
  Future<void> pumpPantry(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: PantryHomePage(store: PantryStore.demo(), onSignOut: () {}),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('redesigned desktop pages render without layout exceptions', (
    tester,
  ) async {
    await pumpPantry(tester, const Size(1440, 980));
    expect(tester.takeException(), isNull);

    for (final page in ['Inventory', 'Recipes', 'Food log']) {
      await tester.tap(find.text(page).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$page should render');
    }
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
