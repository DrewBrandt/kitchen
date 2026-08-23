import 'package:flutter/material.dart';

import '../data/pantry_store.dart';
import '../models/pantry_models.dart';

Future<void> showFoodEditor(
  BuildContext context,
  PantryStore store, {
  FoodDefinition? existing,
}) async {
  final result = await showDialog<FoodDefinition>(
    context: context,
    builder: (context) => _FoodEditorDialog(store: store, existing: existing),
  );
  if (result != null) store.saveFood(result);
}

class _FoodEditorDialog extends StatefulWidget {
  const _FoodEditorDialog({required this.store, this.existing});
  final PantryStore store;
  final FoodDefinition? existing;

  @override
  State<_FoodEditorDialog> createState() => _FoodEditorDialogState();
}

class _FoodEditorDialogState extends State<_FoodEditorDialog> {
  late final name = TextEditingController(text: widget.existing?.name ?? '');
  late final emoji = TextEditingController(
    text: widget.existing?.emoji ?? '🥫',
  );
  late final conversions = TextEditingController(
    text: _conversionText(widget.existing),
  );
  late final nutrition = TextEditingController(
    text: _nutritionText(widget.existing),
  );
  late final nutritionSource = TextEditingController(
    text: widget.existing?.nutrition?.source ?? '',
  );
  late bool nutritionEstimated = widget.existing?.nutrition?.estimated ?? false;
  late QuantityMode mode = widget.existing?.mode ?? QuantityMode.counted;
  late StorageLocation location =
      widget.existing?.defaultLocation ?? StorageLocation.pantry;
  String? error;

  static String _conversionText(FoodDefinition? food) {
    if (food == null) return 'each, each, 1';
    return food.conversions
        .map((item) => '${item.unit}, ${item.symbol}, ${item.baseAmount}')
        .join('\n');
  }

  static String _nutritionText(FoodDefinition? food) {
    final facts = food?.nutrition;
    if (facts == null) return '';
    final totals = facts.totals;
    return [
      facts.basisBaseAmount,
      totals.calories,
      totals.proteinG,
      totals.carbsG,
      totals.fatG,
      totals.fiberG,
      totals.sugarG,
      totals.sodiumMg,
    ].join(', ');
  }

  @override
  void dispose() {
    name.dispose();
    emoji.dispose();
    conversions.dispose();
    nutrition.dispose();
    nutritionSource.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.existing == null
          ? 'Define a food'
          : 'Edit ${widget.existing!.name}',
    ),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
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
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<QuantityMode>(
                    initialValue: mode,
                    decoration: const InputDecoration(
                      labelText: 'Quantity style',
                    ),
                    items: QuantityMode.values
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(
                              item == QuantityMode.counted
                                  ? 'Counted'
                                  : 'Measured',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() {
                      mode = value!;
                      if (mode == QuantityMode.counted &&
                          widget.existing == null) {
                        conversions.text = 'each, each, 1';
                      }
                      if (mode == QuantityMode.measured &&
                          widget.existing == null) {
                        conversions.text = 'gram, g, 1';
                      }
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<StorageLocation>(
                    initialValue: location,
                    decoration: const InputDecoration(
                      labelText: 'Default location',
                    ),
                    items: StorageLocation.values
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(item.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => location = value!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: conversions,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Unit conversions',
                helperText:
                    'One per line: unit, display symbol, amount in base units. The first line is the base unit and must equal 1.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nutrition,
              decoration: const InputDecoration(
                labelText: 'Nutrition (optional)',
                helperText:
                    'Base amount, calories, protein g, carbs g, fat g, fiber g, sugar g, sodium mg',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nutritionSource,
              decoration: const InputDecoration(
                labelText: 'Nutrition source',
                hintText: 'Package label, manufacturer, or USDA estimate',
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Nutrition values are estimated'),
              value: nutritionEstimated,
              onChanged: (value) =>
                  setState(() => nutritionEstimated = value ?? false),
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
      FilledButton(onPressed: _save, child: const Text('Save food')),
    ],
  );

  void _save() {
    try {
      final parsed = conversions.text
          .split(RegExp(r'\r?\n'))
          .where((line) => line.trim().isNotEmpty)
          .map((line) {
            final parts = line.split(',').map((item) => item.trim()).toList();
            if (parts.length != 3) {
              throw const FormatException(
                'Each conversion needs unit, symbol, and base amount',
              );
            }
            final amount = double.tryParse(parts[2]);
            if (parts[0].isEmpty ||
                parts[1].isEmpty ||
                amount == null ||
                amount <= 0) {
              throw const FormatException(
                'Conversion names and positive amounts are required',
              );
            }
            return UnitConversion(
              unit: parts[0].toLowerCase(),
              symbol: parts[1],
              baseAmount: amount,
            );
          })
          .toList();
      if (name.text.trim().isEmpty ||
          parsed.isEmpty ||
          (parsed.first.baseAmount - 1).abs() > 0.000001) {
        throw const FormatException(
          'Name and a first/base conversion of 1 are required',
        );
      }
      NutritionFacts? parsedNutrition;
      if (nutrition.text.trim().isNotEmpty) {
        final values = nutrition.text
            .split(',')
            .map((value) => double.tryParse(value.trim()))
            .toList();
        if (values.length != 8 ||
            values.any((value) => value == null || value < 0) ||
            values.first! <= 0) {
          throw const FormatException(
            'Nutrition needs eight non-negative numbers and a positive base amount',
          );
        }
        parsedNutrition = NutritionFacts(
          basisBaseAmount: values[0]!,
          totals: NutritionTotals(
            calories: values[1]!,
            proteinG: values[2]!,
            carbsG: values[3]!,
            fatG: values[4]!,
            fiberG: values[5]!,
            sugarG: values[6]!,
            sodiumMg: values[7]!,
          ),
          source: nutritionSource.text.trim(),
          estimated: nutritionEstimated,
        );
      }
      Navigator.pop(
        context,
        FoodDefinition(
          id: widget.existing?.id ?? widget.store.nextId(name.text),
          name: name.text.trim(),
          mode: mode,
          baseUnit: parsed.first.unit,
          conversions: parsed,
          emoji: emoji.text.trim().isEmpty ? '🥫' : emoji.text.trim(),
          defaultLocation: location,
          nutrition: parsedNutrition,
        ),
      );
    } on FormatException catch (exception) {
      setState(() => error = exception.message);
    }
  }
}
