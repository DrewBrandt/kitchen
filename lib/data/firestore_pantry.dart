import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/pantry_models.dart';

class CloudPantryData {
  const CloudPantryData({
    required this.foods,
    required this.lots,
    required this.recipes,
    required this.history,
    required this.nutritionTargets,
    required this.foodPreferences,
    required this.externalFoods,
    required this.plannedMeals,
    required this.groceryItems,
  });

  final List<FoodDefinition> foods;
  final List<InventoryLot> lots;
  final List<Recipe> recipes;
  final List<ConsumptionEvent> history;
  final NutritionTargets nutritionTargets;
  final FoodPreferences foodPreferences;
  final List<ExternalFood> externalFoods;
  final List<PlannedMeal> plannedMeals;
  final List<GroceryListItem> groceryItems;

  bool get isEmpty =>
      foods.isEmpty &&
      lots.isEmpty &&
      recipes.isEmpty &&
      externalFoods.isEmpty &&
      plannedMeals.isEmpty;
}

class FirestorePantry {
  FirestorePantry(this.db);

  final FirebaseFirestore db;

  Future<CloudPantryData> load() async {
    final results = await Future.wait([
      db.collection('foods').get(),
      db.collection('inventory_lots').get(),
      db.collection('recipes').get(),
      db.collection('consumption_history').orderBy('timestamp').get(),
      db.collection('external_foods').get(),
      db.collection('meal_plan').get(),
      db.collection('grocery_list').get(),
    ]);
    final settings = await Future.wait([
      db.collection('settings').doc('nutrition').get(),
      db.collection('settings').doc('food_profile').get(),
    ]);
    final targets = settings[0];
    final profile = settings[1];
    return CloudPantryData(
      foods: results[0].docs.map(_foodFromDoc).toList(),
      lots: results[1].docs.map(_lotFromDoc).toList(),
      recipes: results[2].docs.map(_recipeFromDoc).toList(),
      history: results[3].docs.map(_eventFromDoc).toList(),
      nutritionTargets: targets.exists
          ? _nutritionTargetsFromData(targets.data()!)
          : NutritionTargets.defaults,
      foodPreferences: profile.exists
          ? _foodPreferencesFromData(profile.data()!)
          : FoodPreferences.empty,
      externalFoods: results[4].docs.map(_externalFoodFromDoc).toList(),
      plannedMeals: results[5].docs.map(_plannedMealFromDoc).toList(),
      groceryItems: results[6].docs.map(_groceryItemFromDoc).toList(),
    );
  }

  Future<void> seed(CloudPantryData data) async {
    final batch = db.batch();
    for (final food in data.foods) {
      batch.set(db.collection('foods').doc(food.id), _foodData(food));
    }
    for (final lot in data.lots) {
      batch.set(db.collection('inventory_lots').doc(lot.id), _lotData(lot));
    }
    for (final recipe in data.recipes) {
      batch.set(db.collection('recipes').doc(recipe.id), _recipeData(recipe));
    }
    for (final food in data.externalFoods) {
      batch.set(
        db.collection('external_foods').doc(food.id),
        _externalFoodData(food),
      );
    }
    for (final meal in data.plannedMeals) {
      batch.set(
        db.collection('meal_plan').doc(meal.id),
        _plannedMealData(meal),
      );
    }
    for (final item in data.groceryItems) {
      batch.set(
        db.collection('grocery_list').doc(item.id),
        _groceryItemData(item),
      );
    }
    batch.set(
      db.collection('settings').doc('nutrition'),
      _nutritionTargetsData(data.nutritionTargets),
    );
    batch.set(
      db.collection('settings').doc('food_profile'),
      _foodPreferencesData(data.foodPreferences),
    );
    await batch.commit();
  }

  Future<void> saveFood(FoodDefinition food) =>
      db.collection('foods').doc(food.id).set(_foodData(food));

  Future<void> deleteFood(String id) => db.collection('foods').doc(id).delete();

  Future<void> saveLot(InventoryLot lot) =>
      db.collection('inventory_lots').doc(lot.id).set(_lotData(lot));

  Future<void> saveRecipe(Recipe recipe) =>
      db.collection('recipes').doc(recipe.id).set(_recipeData(recipe));

  Future<void> deleteRecipe(String id) =>
      db.collection('recipes').doc(id).delete();

  Future<void> saveNutritionTargets(NutritionTargets targets) => db
      .collection('settings')
      .doc('nutrition')
      .set(_nutritionTargetsData(targets));

  Future<void> saveFoodPreferences(FoodPreferences preferences) => db
      .collection('settings')
      .doc('food_profile')
      .set(_foodPreferencesData(preferences));

  Future<void> saveExternalFood(ExternalFood food) =>
      db.collection('external_foods').doc(food.id).set(_externalFoodData(food));

  Future<void> replacePlanning(
    Iterable<PlannedMeal> meals,
    Iterable<GroceryListItem> groceries,
  ) async {
    final current = await Future.wait([
      db.collection('meal_plan').get(),
      db.collection('grocery_list').get(),
    ]);
    final batch = db.batch();
    for (final document in [...current[0].docs, ...current[1].docs]) {
      batch.delete(document.reference);
    }
    for (final meal in meals) {
      batch.set(
        db.collection('meal_plan').doc(meal.id),
        _plannedMealData(meal),
      );
    }
    for (final item in groceries) {
      batch.set(
        db.collection('grocery_list').doc(item.id),
        _groceryItemData(item),
      );
    }
    await batch.commit();
  }

  Future<void> saveConsumption(
    ConsumptionEvent event,
    Iterable<InventoryLot> updatedLots,
  ) async {
    final batch = db.batch();
    for (final lot in updatedLots) {
      batch.update(db.collection('inventory_lots').doc(lot.id), {
        'quantity_base': lot.quantityBase,
        'updated_at': FieldValue.serverTimestamp(),
      });
    }
    batch.set(
      db.collection('consumption_history').doc(event.id),
      _eventData(event),
    );
    await batch.commit();
  }

  Future<void> saveConsumptions(
    Iterable<ConsumptionEvent> events,
    Iterable<InventoryLot> updatedLots,
  ) async {
    final batch = db.batch();
    for (final lot in updatedLots) {
      batch.update(db.collection('inventory_lots').doc(lot.id), {
        'quantity_base': lot.quantityBase,
        'updated_at': FieldValue.serverTimestamp(),
      });
    }
    for (final event in events) {
      batch.set(
        db.collection('consumption_history').doc(event.id),
        _eventData(event),
      );
    }
    await batch.commit();
  }

  Future<void> saveUndo(
    ConsumptionEvent event,
    Iterable<InventoryLot> restoredLots,
  ) async {
    final batch = db.batch();
    for (final lot in restoredLots) {
      batch.update(db.collection('inventory_lots').doc(lot.id), {
        'quantity_base': lot.quantityBase,
        'updated_at': FieldValue.serverTimestamp(),
      });
    }
    batch.update(db.collection('consumption_history').doc(event.id), {
      'undone_at': Timestamp.fromDate(event.undoneAt!),
    });
    await batch.commit();
  }

  Map<String, Object?> _foodData(FoodDefinition food) => {
    'name': food.name,
    'quantity_mode': food.mode.name,
    'base_unit': food.baseUnit,
    'default_location': food.defaultLocation.name,
    'emoji': food.emoji,
    'conversions': food.conversions
        .map(
          (item) => {
            'unit': item.unit,
            'symbol': item.symbol,
            'base_amount': item.baseAmount,
          },
        )
        .toList(),
    'display_unit': food.displayUnit,
    'nutrition': food.nutrition == null
        ? null
        : {
            'basis_base_amount': food.nutrition!.basisBaseAmount,
            'calories': food.nutrition!.totals.calories,
            'protein_g': food.nutrition!.totals.proteinG,
            'carbs_g': food.nutrition!.totals.carbsG,
            'fat_g': food.nutrition!.totals.fatG,
            'fiber_g': food.nutrition!.totals.fiberG,
            'sugar_g': food.nutrition!.totals.sugarG,
            'sodium_mg': food.nutrition!.totals.sodiumMg,
            'source': food.nutrition!.source,
            'estimated': food.nutrition!.estimated,
          },
    'updated_at': FieldValue.serverTimestamp(),
  };

  Map<String, Object?> _lotData(InventoryLot lot) => {
    'food_id': lot.foodId,
    'quantity_base': lot.quantityBase,
    'location': lot.location.name,
    'best_by': lot.bestBy == null ? null : Timestamp.fromDate(lot.bestBy!),
    'purchased_at': lot.purchasedAt == null
        ? FieldValue.serverTimestamp()
        : Timestamp.fromDate(lot.purchasedAt!),
    'updated_at': FieldValue.serverTimestamp(),
  };

  Map<String, Object?> _recipeData(Recipe recipe) => {
    'name': recipe.name,
    'emoji': recipe.emoji,
    'servings': recipe.servings,
    'ingredients': recipe.ingredients
        .map(
          (item) => {
            'food_id': item.foodId,
            'amount': item.amount,
            'unit': item.unit,
          },
        )
        .toList(),
    'instructions': recipe.instructions,
    'portions': recipe.portions
        .map((portion) => {'name': portion.name, 'servings': portion.servings})
        .toList(),
    'updated_at': FieldValue.serverTimestamp(),
  };

  Map<String, Object?> _eventData(ConsumptionEvent event) => {
    'label': event.label,
    'kind': event.kind.name,
    'recipe_id': event.recipeId,
    'timestamp': Timestamp.fromDate(event.timestamp),
    'deductions': event.deductions
        .map(
          (item) => {
            'lot_id': item.lotId,
            'food_id': item.foodId,
            'quantity_base': item.quantityBase,
          },
        )
        .toList(),
    'undone_at': event.undoneAt == null
        ? null
        : Timestamp.fromDate(event.undoneAt!),
    'nutrition': event.nutrition == null
        ? null
        : _nutritionTotalsData(event.nutrition!),
    'nutrition_estimated': event.nutritionEstimated,
    'note': event.note,
  };

  Map<String, Object?> _nutritionTotalsData(NutritionTotals totals) => {
    'calories': totals.calories,
    'protein_g': totals.proteinG,
    'carbs_g': totals.carbsG,
    'fat_g': totals.fatG,
    'fiber_g': totals.fiberG,
    'sugar_g': totals.sugarG,
    'sodium_mg': totals.sodiumMg,
  };

  Map<String, Object?> _nutritionTargetsData(NutritionTargets targets) => {
    'calories': targets.calories,
    'protein_g': targets.proteinG,
    'carbs_g': targets.carbsG,
    'fat_g': targets.fatG,
    'fiber_g': targets.fiberG,
    'sodium_mg': targets.sodiumMg,
    'label': targets.label,
    'updated_at': FieldValue.serverTimestamp(),
  };

  Map<String, Object?> _foodPreferencesData(FoodPreferences preferences) => {
    'allergies': preferences.allergies,
    'dislikes': preferences.dislikes,
    'favorites': preferences.favorites,
    'dietary_rules': preferences.dietaryRules,
    'planning_notes': preferences.planningNotes,
    'updated_at': FieldValue.serverTimestamp(),
  };

  Map<String, Object?> _externalFoodData(ExternalFood food) => {
    'name': food.name,
    'brand': food.brand,
    'emoji': food.emoji,
    'serving_label': food.servingLabel,
    'nutrition': _nutritionTotalsData(food.nutrition),
    'source': food.source,
    'estimated': food.estimated,
    'updated_at': FieldValue.serverTimestamp(),
  };

  Map<String, Object?> _plannedMealData(PlannedMeal meal) => {
    'date': Timestamp.fromDate(
      DateTime(meal.date.year, meal.date.month, meal.date.day),
    ),
    'slot': meal.slot.name,
    'source': meal.source.name,
    'source_id': meal.sourceId,
    'name': meal.name,
    'emoji': meal.emoji,
    'servings': meal.servings,
    'note': meal.note,
    'completed_at': meal.completedAt == null
        ? null
        : Timestamp.fromDate(meal.completedAt!),
    'updated_at': FieldValue.serverTimestamp(),
  };

  Map<String, Object?> _groceryItemData(GroceryListItem item) => {
    'name': item.name,
    'emoji': item.emoji,
    'checked': item.checked,
    'from_plan': item.fromPlan,
    'food_id': item.foodId,
    'quantity_base': item.quantityBase,
    'quantity_label': item.quantityLabel,
    'updated_at': FieldValue.serverTimestamp(),
  };

  ExternalFood _externalFoodFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return ExternalFood(
      id: doc.id,
      name: data['name'] as String,
      brand: data['brand'] as String? ?? '',
      emoji: data['emoji'] as String? ?? '🍽️',
      servingLabel: data['serving_label'] as String? ?? '1 serving',
      nutrition: _nutritionTotalsFromData(
        data['nutrition'] as Map<String, dynamic>? ?? const {},
      ),
      source: data['source'] as String? ?? '',
      estimated: data['estimated'] as bool? ?? false,
    );
  }

  PlannedMeal _plannedMealFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return PlannedMeal(
      id: doc.id,
      date: (data['date'] as Timestamp).toDate(),
      slot: MealSlot.values.byName(data['slot'] as String),
      source: PlannedMealSource.values.byName(data['source'] as String),
      sourceId: data['source_id'] as String?,
      name: data['name'] as String,
      emoji: data['emoji'] as String? ?? '🍽️',
      servings: (data['servings'] as num? ?? 1).toDouble(),
      note: data['note'] as String? ?? '',
      completedAt: (data['completed_at'] as Timestamp?)?.toDate(),
    );
  }

  GroceryListItem _groceryItemFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return GroceryListItem(
      id: doc.id,
      name: data['name'] as String,
      emoji: data['emoji'] as String? ?? '🛒',
      checked: data['checked'] as bool? ?? false,
      fromPlan: data['from_plan'] as bool? ?? false,
      foodId: data['food_id'] as String?,
      quantityBase: (data['quantity_base'] as num?)?.toDouble(),
      quantityLabel: data['quantity_label'] as String? ?? '',
    );
  }

  NutritionTargets _nutritionTargetsFromData(Map<String, dynamic> data) =>
      NutritionTargets(
        calories: (data['calories'] as num? ?? 2000).toDouble(),
        proteinG: (data['protein_g'] as num? ?? 50).toDouble(),
        carbsG: (data['carbs_g'] as num? ?? 275).toDouble(),
        fatG: (data['fat_g'] as num? ?? 78).toDouble(),
        fiberG: (data['fiber_g'] as num? ?? 28).toDouble(),
        sodiumMg: (data['sodium_mg'] as num? ?? 2300).toDouble(),
        label: data['label'] as String? ?? '',
      );

  FoodPreferences _foodPreferencesFromData(Map<String, dynamic> data) =>
      FoodPreferences(
        allergies: _stringList(data['allergies']),
        dislikes: _stringList(data['dislikes']),
        favorites: _stringList(data['favorites']),
        dietaryRules: _stringList(data['dietary_rules']),
        planningNotes: data['planning_notes'] as String? ?? '',
      );

  List<String> _stringList(Object? value) => value is Iterable
      ? value
            .whereType<String>()
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList()
      : const [];

  NutritionTotals _nutritionTotalsFromData(Map<String, dynamic> data) =>
      NutritionTotals(
        calories: (data['calories'] as num? ?? 0).toDouble(),
        proteinG: (data['protein_g'] as num? ?? 0).toDouble(),
        carbsG: (data['carbs_g'] as num? ?? 0).toDouble(),
        fatG: (data['fat_g'] as num? ?? 0).toDouble(),
        fiberG: (data['fiber_g'] as num? ?? 0).toDouble(),
        sugarG: (data['sugar_g'] as num? ?? 0).toDouble(),
        sodiumMg: (data['sodium_mg'] as num? ?? 0).toDouble(),
      );

  FoodDefinition _foodFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final nutritionData = data['nutrition'] as Map<String, dynamic>?;
    return FoodDefinition(
      id: doc.id,
      name: data['name'] as String,
      mode: QuantityMode.values.byName(data['quantity_mode'] as String),
      baseUnit: data['base_unit'] as String,
      defaultLocation: StorageLocation.values.byName(
        data['default_location'] as String,
      ),
      emoji: data['emoji'] as String? ?? '🥫',
      conversions: (data['conversions'] as List<dynamic>).map((value) {
        final item = value as Map<String, dynamic>;
        return UnitConversion(
          unit: item['unit'] as String,
          symbol: item['symbol'] as String,
          baseAmount: (item['base_amount'] as num).toDouble(),
        );
      }).toList(),
      displayUnit: data['display_unit'] as String?,
      nutrition: nutritionData == null
          ? null
          : NutritionFacts(
              basisBaseAmount: (nutritionData['basis_base_amount'] as num)
                  .toDouble(),
              totals: _nutritionTotalsFromData(nutritionData),
              source: nutritionData['source'] as String? ?? '',
              estimated: nutritionData['estimated'] as bool? ?? false,
            ),
    );
  }

  InventoryLot _lotFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return InventoryLot(
      id: doc.id,
      foodId: data['food_id'] as String,
      quantityBase: (data['quantity_base'] as num).toDouble(),
      location: StorageLocation.values.byName(data['location'] as String),
      bestBy: (data['best_by'] as Timestamp?)?.toDate(),
      purchasedAt: (data['purchased_at'] as Timestamp?)?.toDate(),
    );
  }

  Recipe _recipeFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return Recipe(
      id: doc.id,
      name: data['name'] as String,
      emoji: data['emoji'] as String? ?? '🍽️',
      servings: (data['servings'] as num).toDouble(),
      ingredients: (data['ingredients'] as List<dynamic>).map((value) {
        final item = value as Map<String, dynamic>;
        return RecipeIngredient(
          foodId: item['food_id'] as String,
          amount: (item['amount'] as num).toDouble(),
          unit: item['unit'] as String,
        );
      }).toList(),
      instructions: List<String>.from(
        data['instructions'] as List<dynamic>? ?? const [],
      ),
      portions: (data['portions'] as List<dynamic>? ?? const []).map((value) {
        final portion = value as Map<String, dynamic>;
        return RecipePortion(
          name: portion['name'] as String,
          servings: (portion['servings'] as num).toDouble(),
        );
      }).toList(),
    );
  }

  ConsumptionEvent _eventFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final nutritionData = data['nutrition'] as Map<String, dynamic>?;
    final deductions = (data['deductions'] as List<dynamic>).map((value) {
      final item = value as Map<String, dynamic>;
      return LotDeduction(
        lotId: item['lot_id'] as String,
        foodId: item['food_id'] as String,
        quantityBase: (item['quantity_base'] as num).toDouble(),
      );
    }).toList();
    final recipeId = data['recipe_id'] as String?;
    final kindName = data['kind'] as String?;
    return ConsumptionEvent(
      id: doc.id,
      label: data['label'] as String,
      kind: kindName == null
          ? (recipeId == null
                ? ConsumptionKind.inventory
                : ConsumptionKind.recipe)
          : ConsumptionKind.values.byName(kindName),
      recipeId: recipeId,
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      deductions: deductions,
      undoneAt: (data['undone_at'] as Timestamp?)?.toDate(),
      nutrition: nutritionData == null
          ? null
          : _nutritionTotalsFromData(nutritionData),
      nutritionEstimated: data['nutrition_estimated'] as bool? ?? false,
      note: data['note'] as String? ?? '',
    );
  }
}
