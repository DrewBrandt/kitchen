import 'package:flutter/material.dart';

import '../data/pantry_store.dart';
import '../models/pantry_models.dart';

Future<void> showRecipeEditor(
  BuildContext context,
  PantryStore store, {
  Recipe? existing,
}) async {
  final result = await showDialog<Recipe>(
    context: context,
    builder: (context) => _RecipeEditorDialog(store: store, existing: existing),
  );
  if (result != null) store.saveRecipe(result);
}

class _IngredientDraft {
  _IngredientDraft({
    required this.foodId,
    required double amount,
    required this.unit,
  }) : amount = TextEditingController(text: amount.toString());

  String foodId;
  String unit;
  final TextEditingController amount;

  void dispose() => amount.dispose();
}

class _RecipeEditorDialog extends StatefulWidget {
  const _RecipeEditorDialog({required this.store, this.existing});
  final PantryStore store;
  final Recipe? existing;

  @override
  State<_RecipeEditorDialog> createState() => _RecipeEditorDialogState();
}

class _RecipeEditorDialogState extends State<_RecipeEditorDialog> {
  String _nutritionValue(double value) => value == 0 ? '' : value.toString();

  late final name = TextEditingController(text: widget.existing?.name ?? '');
  late final emoji = TextEditingController(
    text: widget.existing?.emoji ?? '🍽️',
  );
  late final servings = TextEditingController(
    text: (widget.existing?.servings ?? 1).toString(),
  );
  late final instructions = TextEditingController(
    text: widget.existing?.instructions.join('\n') ?? '',
  );
  late final sourceUrl = TextEditingController(
    text: widget.existing?.sourceUrl ?? '',
  );
  late final sourceNote = TextEditingController(
    text: widget.existing?.sourceNote ?? '',
  );
  late bool promptForFeedback = widget.existing?.promptForFeedback ?? true;
  late final portions = TextEditingController(
    text: widget.existing?.portions
        .map((portion) => '${portion.name} = ${portion.servings}')
        .join('\n'),
  );
  late bool overrideNutrition = widget.existing?.nutritionOverride != null;
  late final calories = TextEditingController(
    text: _nutritionValue(widget.existing?.nutritionOverride?.calories ?? 0),
  );
  late final protein = TextEditingController(
    text: _nutritionValue(widget.existing?.nutritionOverride?.proteinG ?? 0),
  );
  late final carbs = TextEditingController(
    text: _nutritionValue(widget.existing?.nutritionOverride?.carbsG ?? 0),
  );
  late final fat = TextEditingController(
    text: _nutritionValue(widget.existing?.nutritionOverride?.fatG ?? 0),
  );
  late final fiber = TextEditingController(
    text: _nutritionValue(widget.existing?.nutritionOverride?.fiberG ?? 0),
  );
  late final sugar = TextEditingController(
    text: _nutritionValue(widget.existing?.nutritionOverride?.sugarG ?? 0),
  );
  late final sodium = TextEditingController(
    text: _nutritionValue(widget.existing?.nutritionOverride?.sodiumMg ?? 0),
  );
  late final List<_IngredientDraft> ingredients = widget.existing == null
      ? [_newIngredient()]
      : widget.existing!.ingredients
            .map(
              (item) => _IngredientDraft(
                foodId: item.foodId,
                amount: item.amount,
                unit: item.unit,
              ),
            )
            .toList();
  String? error;

  _IngredientDraft _newIngredient() {
    final food = widget.store.foods.first;
    return _IngredientDraft(
      foodId: food.id,
      amount: 1,
      unit: food.conversions.first.unit,
    );
  }

  @override
  void dispose() {
    name.dispose();
    emoji.dispose();
    servings.dispose();
    instructions.dispose();
    sourceUrl.dispose();
    sourceNote.dispose();
    portions.dispose();
    for (final controller in [
      calories,
      protein,
      carbs,
      fat,
      fiber,
      sugar,
      sodium,
    ]) {
      controller.dispose();
    }
    for (final ingredient in ingredients) {
      ingredient.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.existing == null
          ? 'Create a recipe'
          : 'Edit ${widget.existing!.name}',
    ),
    content: SizedBox(
      width: 720,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: emoji,
                    decoration: const InputDecoration(labelText: 'Emoji'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: name,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Recipe name'),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: servings,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Servings'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text('Ingredients', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...ingredients.indexed.map(
              (entry) => _ingredientRow(entry.$1, entry.$2),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    setState(() => ingredients.add(_newIngredient())),
                icon: const Icon(Icons.add),
                label: const Text('Add ingredient'),
              ),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Override calculated nutrition'),
              subtitle: const Text(
                'Use prepared-recipe totals instead of adding ingredient nutrition.',
              ),
              value: overrideNutrition,
              onChanged: (value) => setState(() => overrideNutrition = value),
            ),
            if (overrideNutrition) ...[
              const SizedBox(height: 4),
              Text(
                'Totals for the whole recipe',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _nutritionField('Calories', calories, 'cal'),
                  _nutritionField('Protein', protein, 'g'),
                  _nutritionField('Carbs', carbs, 'g'),
                  _nutritionField('Fat', fat, 'g'),
                  _nutritionField('Fiber', fiber, 'g'),
                  _nutritionField('Sugar', sugar, 'g'),
                  _nutritionField('Sodium', sodium, 'mg'),
                ],
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: portions,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Named portions (optional)',
                helperText:
                    'One per line, such as “Tall glass = 2.25” or “Half glass = 1.25”.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: instructions,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Instructions',
                helperText: 'One step per line',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: sourceUrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Source website (optional)',
                hintText: 'https://example.com/recipe',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: sourceNote,
              decoration: const InputDecoration(
                labelText: 'Source note (optional)',
                hintText: 'Adapted from…',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ask how it went after making'),
              subtitle: const Text('Taste, ease, and actual cooking time'),
              value: promptForFeedback,
              onChanged: (value) => setState(() => promptForFeedback = value),
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
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
      FilledButton(onPressed: _save, child: const Text('Save recipe')),
    ],
  );

  Widget _ingredientRow(int index, _IngredientDraft draft) {
    final food = widget.store.food(draft.foodId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              initialValue: draft.foodId,
              decoration: const InputDecoration(labelText: 'Food'),
              items: widget.store.foods
                  .map(
                    (item) => DropdownMenuItem(
                      value: item.id,
                      child: Text('${item.emoji} ${item.name}'),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() {
                draft.foodId = value!;
                draft.unit = widget.store.food(value).conversions.first.unit;
              }),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: draft.amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Amount'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String>(
              key: ValueKey('${draft.foodId}-${draft.unit}'),
              initialValue: draft.unit,
              decoration: const InputDecoration(labelText: 'Unit'),
              items: food.conversions
                  .map(
                    (item) => DropdownMenuItem(
                      value: item.unit,
                      child: Text(item.symbol),
                    ),
                  )
                  .toList(),
              onChanged: (value) => draft.unit = value!,
            ),
          ),
          IconButton(
            tooltip: 'Remove ingredient',
            onPressed: ingredients.length == 1
                ? null
                : () => setState(() => ingredients.removeAt(index).dispose()),
            icon: const Icon(Icons.remove_circle_outline),
          ),
        ],
      ),
    );
  }

  Widget _nutritionField(
    String label,
    TextEditingController controller,
    String suffix,
  ) => SizedBox(
    width: 150,
    child: TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, suffixText: suffix),
    ),
  );

  void _save() {
    final servingCount = double.tryParse(servings.text);
    NutritionTotals? nutritionOverride;
    if (overrideNutrition) {
      final values = [calories, protein, carbs, fat, fiber, sugar, sodium].map((
        controller,
      ) {
        final text = controller.text.trim();
        return text.isEmpty ? 0.0 : double.tryParse(text);
      }).toList();
      if (values.any(
        (value) => value == null || !value.isFinite || value < 0,
      )) {
        setState(
          () => error = 'Nutrition values must be non-negative numbers.',
        );
        return;
      }
      if (values.every((value) => value == 0)) {
        setState(() => error = 'Enter at least one prepared nutrition value.');
        return;
      }
      nutritionOverride = NutritionTotals(
        calories: values[0]!,
        proteinG: values[1]!,
        carbsG: values[2]!,
        fatG: values[3]!,
        fiberG: values[4]!,
        sugarG: values[5]!,
        sodiumMg: values[6]!,
      );
    }
    final parsedIngredients = <RecipeIngredient>[];
    final parsedPortions = <RecipePortion>[];
    for (final line in portions.text.split(RegExp(r'\r?\n'))) {
      if (line.trim().isEmpty) continue;
      final separator = line.lastIndexOf('=');
      final portionName = separator < 0
          ? ''
          : line.substring(0, separator).trim();
      final portionServings = separator < 0
          ? null
          : double.tryParse(line.substring(separator + 1).trim());
      if (portionName.isEmpty ||
          portionServings == null ||
          portionServings <= 0) {
        setState(
          () => error = 'Named portions must use “Name = positive number”.',
        );
        return;
      }
      parsedPortions.add(
        RecipePortion(name: portionName, servings: portionServings),
      );
    }
    for (final draft in ingredients) {
      final amount = double.tryParse(draft.amount.text);
      if (amount == null || amount <= 0) {
        setState(() => error = 'Every ingredient needs a positive amount.');
        return;
      }
      parsedIngredients.add(
        RecipeIngredient(
          foodId: draft.foodId,
          amount: amount,
          unit: draft.unit,
        ),
      );
    }
    if (name.text.trim().isEmpty || servingCount == null || servingCount <= 0) {
      setState(() => error = 'Recipe name and positive servings are required.');
      return;
    }
    Navigator.pop(
      context,
      Recipe(
        id: widget.existing?.id ?? widget.store.nextId(name.text),
        name: name.text.trim(),
        servings: servingCount,
        ingredients: parsedIngredients,
        instructions: instructions.text
            .split(RegExp(r'\r?\n'))
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList(),
        portions: parsedPortions,
        emoji: emoji.text.trim().isEmpty ? '🍽️' : emoji.text.trim(),
        nutritionOverride: nutritionOverride,
        sourceUrl: sourceUrl.text.trim(),
        sourceNote: sourceNote.text.trim(),
        promptForFeedback: promptForFeedback,
      ),
    );
  }
}
