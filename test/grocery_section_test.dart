import 'package:flutter_test/flutter_test.dart';
import 'package:pantry_inventory/models/pantry_models.dart';

void main() {
  test('Safeway sections retain the configured walking order', () {
    expect(GrocerySection.produceDeli.storeOrder, 0);
    expect(
      GrocerySection.eggsCheeseDough.storeOrder,
      lessThan(GrocerySection.deliBakery.storeOrder),
    );
  });

  test('common food names infer a useful section and meal role', () {
    expect(
      inferGrocerySection('Fresh salmon'),
      GrocerySection.seafoodBreadInternational,
    );
    expect(inferGrocerySection('Vanilla ice cream'), GrocerySection.frozen);
    expect(
      inferGrocerySection('Laundry detergent'),
      GrocerySection.householdPets,
    );
    expect(
      inferIngredientRole('Chicken breasts', GrocerySection.bakingMeat),
      IngredientRole.main,
    );
    expect(
      inferIngredientRole('Kosher salt', GrocerySection.pantryOther),
      IngredientRole.staple,
    );
  });
}
