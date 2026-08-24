import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/pantry_models.dart';

class CloudPantryData {
  const CloudPantryData({
    required this.foods,
    required this.lots,
    required this.recipes,
    required this.history,
  });

  final List<FoodDefinition> foods;
  final List<InventoryLot> lots;
  final List<Recipe> recipes;
  final List<ConsumptionEvent> history;

  bool get isEmpty => foods.isEmpty && lots.isEmpty && recipes.isEmpty;
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
    ]);
    return CloudPantryData(
      foods: results[0].docs.map(_foodFromDoc).toList(),
      lots: results[1].docs.map(_lotFromDoc).toList(),
      recipes: results[2].docs.map(_recipeFromDoc).toList(),
      history: results[3].docs.map(_eventFromDoc).toList(),
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
