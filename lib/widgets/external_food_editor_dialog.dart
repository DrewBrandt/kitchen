import 'package:flutter/material.dart';

import '../data/pantry_store.dart';
import '../models/pantry_models.dart';

class ExternalFoodEditorSeed {
  const ExternalFoodEditorSeed({
    required this.barcode,
    this.name = '',
    this.brand = '',
    this.servingLabel = '1 item',
    this.nutrition = const NutritionTotals(),
    this.source = '',
    this.estimated = false,
  });

  final String barcode;
  final String name;
  final String brand;
  final String servingLabel;
  final NutritionTotals nutrition;
  final String source;
  final bool estimated;
}

Future<ExternalFood?> showExternalFoodEditor(
  BuildContext context,
  PantryStore store, {
  ExternalFood? existing,
  ExternalFoodEditorSeed? seed,
}) async {
  final name = TextEditingController(text: existing?.name ?? seed?.name ?? '');
  final brand = TextEditingController(
    text: existing?.brand ?? seed?.brand ?? '',
  );
  final serving = TextEditingController(
    text: existing?.servingLabel ?? seed?.servingLabel ?? '1 item',
  );
  final emoji = TextEditingController(text: existing?.emoji ?? '🍽️');
  final source = TextEditingController(
    text: existing?.source ?? seed?.source ?? '',
  );
  final barcode = TextEditingController(
    text: existing?.barcode ?? seed?.barcode ?? '',
  );
  TextEditingController value(double number) => TextEditingController(
    text: number == 0 ? '' : number.toStringAsFixed(number % 1 == 0 ? 0 : 1),
  );

  final initialNutrition = existing?.nutrition ?? seed?.nutrition;
  final calories = value(initialNutrition?.calories ?? 0);
  final protein = value(initialNutrition?.proteinG ?? 0);
  final carbs = value(initialNutrition?.carbsG ?? 0);
  final fat = value(initialNutrition?.fatG ?? 0);
  final fiber = value(initialNutrition?.fiberG ?? 0);
  final sugar = value(initialNutrition?.sugarG ?? 0);
  final sodium = value(initialNutrition?.sodiumMg ?? 0);
  final fields = <(String, TextEditingController, String)>[
    ('Calories', calories, 'cal'),
    ('Protein', protein, 'g'),
    ('Carbs', carbs, 'g'),
    ('Fat', fat, 'g'),
    ('Fiber', fiber, 'g'),
    ('Sugar', sugar, 'g'),
    ('Sodium', sodium, 'mg'),
  ];
  var estimated = existing?.estimated ?? seed?.estimated ?? false;
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
                TextField(
                  controller: barcode,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Barcode / UPC',
                    helperText: 'Future scans will recognize this food.',
                  ),
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
    final food = ExternalFood(
      id: existing?.id ?? store.nextId('${brand.text} ${name.text}'),
      name: name.text.trim(),
      brand: brand.text.trim(),
      servingLabel: serving.text.trim(),
      emoji: emoji.text.trim().isEmpty ? '🍽️' : emoji.text.trim(),
      source: source.text.trim(),
      estimated: estimated,
      barcode: barcode.text.trim().isEmpty
          ? null
          : normalizeBarcode(barcode.text),
      nutrition: NutritionTotals(
        calories: number(calories),
        proteinG: number(protein),
        carbsG: number(carbs),
        fatG: number(fat),
        fiberG: number(fiber),
        sugarG: number(sugar),
        sodiumMg: number(sodium),
      ),
    );
    store.saveExternalFood(food);
    for (final controller in [
      name,
      brand,
      serving,
      emoji,
      source,
      barcode,
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
    return food;
  }
  for (final controller in [
    name,
    brand,
    serving,
    emoji,
    source,
    barcode,
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
  return null;
}
