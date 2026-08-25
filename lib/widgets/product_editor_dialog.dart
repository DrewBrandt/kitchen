import 'package:flutter/material.dart';

import '../data/pantry_store.dart';
import '../models/pantry_models.dart';
import '../services/barcode_lookup_service.dart';

class ProductEditorSeed {
  const ProductEditorSeed({
    required this.barcode,
    this.name = '',
    this.brand = '',
    this.source = '',
    this.packageAmount,
    this.packageUnit,
    this.quantityLabel = '',
    this.nutritionPerPackage,
    this.nutritionServingLabel = '',
  });

  factory ProductEditorSeed.fromSuggestion(BarcodeProductSuggestion value) =>
      ProductEditorSeed(
        barcode: value.barcode,
        name: value.name,
        brand: value.brand,
        source: value.source,
        packageAmount: value.packageAmount,
        packageUnit: value.packageUnit,
        quantityLabel: value.quantityLabel,
        nutritionPerPackage: value.nutritionPerPackage,
        nutritionServingLabel: value.nutritionServingLabel,
      );

  final String barcode;
  final String name;
  final String brand;
  final String source;
  final double? packageAmount;
  final String? packageUnit;
  final String quantityLabel;
  final NutritionTotals? nutritionPerPackage;
  final String nutritionServingLabel;

  BarcodeProductSuggestion get suggestion => BarcodeProductSuggestion(
    barcode: barcode,
    name: name,
    brand: brand,
    source: source,
    packageAmount: packageAmount,
    packageUnit: packageUnit,
    quantityLabel: quantityLabel,
    nutritionPerPackage: nutritionPerPackage,
    nutritionServingLabel: nutritionServingLabel,
  );
}

Future<ProductDefinition?> showProductEditor(
  BuildContext context,
  PantryStore store, {
  ProductDefinition? existing,
  FoodDefinition? initialFood,
  ProductEditorSeed? seed,
}) async {
  final result = await showDialog<ProductDefinition>(
    context: context,
    builder: (context) => _ProductEditorDialog(
      store: store,
      existing: existing,
      initialFood: initialFood,
      seed: seed,
    ),
  );
  if (result != null) store.saveProduct(result);
  return result;
}

class _ProductEditorDialog extends StatefulWidget {
  const _ProductEditorDialog({
    required this.store,
    this.existing,
    this.initialFood,
    this.seed,
  });

  final PantryStore store;
  final ProductDefinition? existing;
  final FoodDefinition? initialFood;
  final ProductEditorSeed? seed;

  @override
  State<_ProductEditorDialog> createState() => _ProductEditorDialogState();
}

class _ProductEditorDialogState extends State<_ProductEditorDialog> {
  late String foodId =
      widget.existing?.foodId ??
      widget.initialFood?.id ??
      widget.store.foods.first.id;
  late final name = TextEditingController(
    text: widget.existing?.name ?? widget.seed?.name ?? '',
  );
  late final brand = TextEditingController(
    text: widget.existing?.brand ?? widget.seed?.brand ?? '',
  );
  late final barcode = TextEditingController(
    text: widget.existing?.barcode ?? widget.seed?.barcode ?? '',
  );
  late final aliases = TextEditingController(
    text: widget.existing?.aliases.join('\n') ?? '',
  );
  late final conversions = TextEditingController(text: _initialConversions());
  String? error;

  @override
  void dispose() {
    name.dispose();
    brand.dispose();
    barcode.dispose();
    aliases.dispose();
    conversions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? 'Define a product' : 'Edit product'),
    content: SizedBox(
      width: 580,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: foodId,
              decoration: const InputDecoration(
                labelText: 'Canonical ingredient',
              ),
              items: widget.store.foods
                  .map(
                    (food) => DropdownMenuItem(
                      value: food.id,
                      child: Text('${food.emoji} ${food.name}'),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() {
                foodId = value!;
                if (widget.existing == null && widget.seed != null) {
                  conversions.text = _suggestedConversion();
                }
              }),
            ),
            if (widget.seed?.source.isNotEmpty ?? false) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Suggested from ${widget.seed!.source}. Review the ingredient, package size, and product details before saving.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Product name'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: brand,
                    decoration: const InputDecoration(labelText: 'Brand'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: barcode,
                    decoration: const InputDecoration(
                      labelText: 'Barcode / UPC',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: aliases,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Product aliases',
                helperText:
                    'One receipt, package, or former product name per line.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: conversions,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: 'Package conversions (optional)',
                helperText:
                    'unit, symbol, amount in ${widget.store.food(foodId).baseUnit}s — for example: bag, bag, 907',
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
      if (widget.existing != null)
        TextButton(
          onPressed: () {
            try {
              widget.store.deleteProduct(widget.existing!.id);
              Navigator.pop(context);
            } on StateError catch (exception) {
              setState(() => error = exception.message);
            }
          },
          child: const Text('Delete'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save product')),
    ],
  );

  void _save() {
    try {
      final parsedConversions = conversions.text
          .split(RegExp(r'\r?\n'))
          .where((line) => line.trim().isNotEmpty)
          .map((line) {
            final parts = line.split(',').map((part) => part.trim()).toList();
            final amount = parts.length == 3 ? double.tryParse(parts[2]) : null;
            if (parts.length != 3 || amount == null || amount <= 0) {
              throw const FormatException(
                'Package conversions must be unit, symbol, positive base amount.',
              );
            }
            return UnitConversion(
              unit: parts[0].toLowerCase(),
              symbol: parts[1],
              baseAmount: amount,
            );
          })
          .toList();
      if (name.text.trim().isEmpty) {
        throw const FormatException('Product name is required.');
      }
      Navigator.pop(
        context,
        ProductDefinition(
          id: widget.existing?.id ?? widget.store.nextId(name.text),
          foodId: foodId,
          name: name.text.trim(),
          brand: brand.text.trim(),
          barcode: barcode.text.trim().isEmpty ? null : barcode.text.trim(),
          aliases: aliases.text
              .split(RegExp(r'\r?\n'))
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toSet()
              .toList(),
          conversions: parsedConversions,
          nutrition: widget.existing?.nutrition,
        ),
      );
    } on FormatException catch (exception) {
      setState(() => error = exception.message);
    }
  }

  String _initialConversions() {
    final existing = widget.existing;
    if (existing != null) {
      return existing.conversions
          .map((item) => '${item.unit}, ${item.symbol}, ${item.baseAmount}')
          .join('\n');
    }
    return _suggestedConversion();
  }

  String _suggestedConversion() {
    final seed = widget.seed;
    if (seed == null) return '';
    final conversion = seed.suggestion.packageConversionFor(
      widget.store.food(foodId),
    );
    if (conversion == null) return '';
    return '${conversion.unit}, ${conversion.symbol}, ${conversion.baseAmount}';
  }
}
