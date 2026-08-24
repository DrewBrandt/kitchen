import 'package:flutter/material.dart';

import '../data/pantry_store.dart';
import '../models/pantry_models.dart';

Future<void> showExternalFoodEditor(
  BuildContext context,
  PantryStore store, {
  ExternalFood? existing,
}) async {
  final name = TextEditingController(text: existing?.name ?? '');
  final brand = TextEditingController(text: existing?.brand ?? '');
  final serving = TextEditingController(
    text: existing?.servingLabel ?? '1 item',
  );
  final emoji = TextEditingController(text: existing?.emoji ?? '🍽️');
  final source = TextEditingController(text: existing?.source ?? '');
  TextEditingController value(double number) => TextEditingController(
    text: number == 0 ? '' : number.toStringAsFixed(number % 1 == 0 ? 0 : 1),
  );

  final calories = value(existing?.nutrition.calories ?? 0);
  final protein = value(existing?.nutrition.proteinG ?? 0);
  final carbs = value(existing?.nutrition.carbsG ?? 0);
  final fat = value(existing?.nutrition.fatG ?? 0);
  final fiber = value(existing?.nutrition.fiberG ?? 0);
  final sugar = value(existing?.nutrition.sugarG ?? 0);
  final sodium = value(existing?.nutrition.sodiumMg ?? 0);
  final fields = <(String, TextEditingController, String)>[
    ('Calories', calories, 'cal'),
    ('Protein', protein, 'g'),
    ('Carbs', carbs, 'g'),
    ('Fat', fat, 'g'),
    ('Fiber', fiber, 'g'),
    ('Sugar', sugar, 'g'),
    ('Sodium', sodium, 'mg'),
  ];
  var estimated = existing?.estimated ?? false;
  String? error;
  double number(TextEditingController controller) =>
      double.tryParse(controller.text.trim()) ?? 0;

  final submitted = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(
          existing == null ? 'Save food from away' : 'Edit saved food',
        ),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 82,
                      child: TextField(
                        controller: emoji,
                        decoration: const InputDecoration(labelText: 'Emoji'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: name,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Food name',
                          hintText: 'Chicken sandwich',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: brand,
                        decoration: const InputDecoration(
                          labelText: 'Place or brand',
                          hintText: 'Chick-fil-A, Greene Turtle, Fairlife',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: serving,
                        decoration: const InputDecoration(
                          labelText: 'Serving description',
                          hintText: '1 sandwich',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: fields
                      .map(
                        (field) => SizedBox(
                          width: 150,
                          child: TextField(
                            controller: field.$2,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: field.$1,
                              suffixText: field.$3,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: source,
                  decoration: const InputDecoration(
                    labelText: 'Nutrition source',
                    hintText: 'Menu URL, package label, or note',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Nutrition is estimated'),
                  value: estimated,
                  onChanged: (value) => setDialogState(() => estimated = value),
                ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final values = fields.map((field) => number(field.$2));
              if (name.text.trim().isEmpty ||
                  brand.text.trim().isEmpty ||
                  serving.text.trim().isEmpty) {
                setDialogState(
                  () =>
                      error = 'Name, place or brand, and serving are required.',
                );
              } else if (values.any((item) => item < 0) ||
                  !values.any((item) => item > 0)) {
                setDialogState(
                  () => error = 'Enter at least one positive nutrition value.',
                );
              } else {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Save food'),
          ),
        ],
      ),
    ),
  );

  if (submitted == true) {
    store.saveExternalFood(
      ExternalFood(
        id: existing?.id ?? store.nextId('${brand.text} ${name.text}'),
        name: name.text.trim(),
        brand: brand.text.trim(),
        servingLabel: serving.text.trim(),
        emoji: emoji.text.trim().isEmpty ? '🍽️' : emoji.text.trim(),
        source: source.text.trim(),
        estimated: estimated,
        nutrition: NutritionTotals(
          calories: number(calories),
          proteinG: number(protein),
          carbsG: number(carbs),
          fatG: number(fat),
          fiberG: number(fiber),
          sugarG: number(sugar),
          sodiumMg: number(sodium),
        ),
      ),
    );
  }
  for (final controller in [
    name,
    brand,
    serving,
    emoji,
    source,
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
}
