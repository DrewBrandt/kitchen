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

  void _save() {
    final servingCount = double.tryParse(servings.text);
    final parsedIngredients = <RecipeIngredient>[];
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
        emoji: emoji.text.trim().isEmpty ? '🍽️' : emoji.text.trim(),
      ),
    );
  }
}
