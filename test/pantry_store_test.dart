import 'package:flutter_test/flutter_test.dart';
import 'package:pantry_inventory/data/pantry_store.dart';

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
}
