import 'package:flutter/material.dart';

import '../data/pantry_store.dart';
import '../models/pantry_models.dart';

class RecipeCookRequest {
  const RecipeCookRequest({
    required this.servingsPerPortion,
    required this.count,
    this.portionName,
  });

  final double servingsPerPortion;
  final int count;
  final String? portionName;
}

Future<RecipeCookRequest?> showRecipePortionDialog(
  BuildContext context,
  PantryStore store,
  Recipe recipe,
) async {
  const wholeRecipe = -1;
  const customPortion = -2;
  var selection = wholeRecipe;
  final countController = TextEditingController(text: '1');
  final customServings = TextEditingController(
    text: store.units.formatAmount(recipe.servings),
  );
  final customName = TextEditingController(text: 'Custom portion');
  String? error;

  double? selectedServings() => switch (selection) {
    wholeRecipe => recipe.servings,
    customPortion => double.tryParse(customServings.text.trim()),
    _ => recipe.portions[selection].servings,
  };
  String? selectedName() => switch (selection) {
    wholeRecipe => null,
    customPortion => customName.text.trim(),
    _ => recipe.portions[selection].name,
  };

  final result = await showDialog<RecipeCookRequest>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        final servings = selectedServings();
        final count = int.tryParse(countController.text.trim());
        final requested = servings != null && count != null
            ? servings * count
            : null;
        final missing = requested != null && requested > 0
            ? store.missingFor(recipe, servings: requested)
            : const <String, double>{};
        final factor = servings == null ? null : servings / recipe.servings;
        final ingredients = factor == null
            ? ''
            : recipe.ingredients
                  .map((ingredient) {
                    final food = store.food(ingredient.foodId);
                    return store.units.ingredientLabel(
                      food,
                      RecipeIngredient(
                        foodId: ingredient.foodId,
                        amount: ingredient.amount * factor,
                        unit: ingredient.unit,
                      ),
                    );
                  })
                  .join(' · ');
        final missingText = missing.entries
            .map((entry) {
              final food = store.food(entry.key);
              return '${food.name}: ${store.units.bestInventoryLabel(food, entry.value)} short';
            })
            .join(' · ');

        return AlertDialog(
          title: Text('Make ${recipe.name}'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: selection,
                    decoration: const InputDecoration(
                      labelText: 'Portion size',
                    ),
                    items: [
                      DropdownMenuItem(
                        value: wholeRecipe,
                        child: Text(
                          'Whole recipe (${store.units.formatAmount(recipe.servings)} servings)',
                        ),
                      ),
                      ...recipe.portions.indexed.map(
                        (entry) => DropdownMenuItem(
                          value: entry.$1,
                          child: Text(
                            '${entry.$2.name} (${store.units.formatAmount(entry.$2.servings)} servings)',
                          ),
                        ),
                      ),
                      const DropdownMenuItem(
                        value: customPortion,
                        child: Text('Custom portion'),
                      ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => selection = value!),
                  ),
                  if (selection == customPortion) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: customName,
                            onChanged: (_) => setDialogState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Portion name',
                              hintText: 'Tall glass',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: customServings,
                            onChanged: (_) => setDialogState(() {}),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Recipe servings',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: countController,
                    onChanged: (_) => setDialogState(() {}),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Number of batches this size',
                      helperText:
                          'The total becomes one prepared batch to eat later.',
                    ),
                  ),
                  if (ingredients.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('Per entry: $ingredients'),
                  ],
                  if (missingText.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Not enough inventory: $missingText',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: missing.isNotEmpty
                  ? null
                  : () {
                      final portionSize = selectedServings();
                      final portionCount = int.tryParse(
                        countController.text.trim(),
                      );
                      final portionName = selectedName();
                      if (portionSize == null ||
                          portionSize <= 0 ||
                          portionCount == null ||
                          portionCount <= 0 ||
                          (selection == customPortion &&
                              (portionName == null || portionName.isEmpty))) {
                        setDialogState(
                          () => error =
                              'Enter a positive portion size, name, and whole-number count.',
                        );
                        return;
                      }
                      Navigator.pop(
                        context,
                        RecipeCookRequest(
                          servingsPerPortion: portionSize,
                          count: portionCount,
                          portionName: portionName,
                        ),
                      );
                    },
              child: const Text('Make batch'),
            ),
          ],
        );
      },
    ),
  );
  countController.dispose();
  customServings.dispose();
  customName.dispose();
  return result;
}
