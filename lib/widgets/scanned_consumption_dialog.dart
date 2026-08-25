import 'package:flutter/material.dart';

import '../data/pantry_store.dart';
import '../models/pantry_models.dart';
import '../services/barcode_lookup_service.dart';
import 'barcode_scanner_dialog.dart';
import 'external_food_editor_dialog.dart';

enum _ConsumptionSource { inventory, outside }

class _ConsumptionChoice {
  const _ConsumptionChoice({required this.source, required this.servings});

  final _ConsumptionSource source;
  final double servings;
}

Future<void> scanConsumption(
  BuildContext context,
  PantryStore store, {
  OpenFoodFactsBarcodeLookup? lookup,
}) async {
  final scanned = await scanBarcodeValue(context);
  if (scanned == null || !context.mounted) return;
  final barcode = normalizeBarcode(scanned);

  var product = store.productForBarcode(barcode);
  final savedOutsideFood = store.externalFoodForBarcode(barcode);
  final service = lookup ?? OpenFoodFactsBarcodeLookup();

  if (product != null) {
    var enrichedProduct = product;
    if (product.nutrition == null ||
        store.productPackageBaseAmount(product) == null) {
      final suggestion = await _lookupSuggestion(context, service, barcode);
      if (!context.mounted) return;
      if (suggestion != null) {
        enrichedProduct = _enrichProduct(store, product, suggestion);
      }
    }
    final available = store.productPackagesAvailable(enrichedProduct);
    final choice = await _showProductChoice(
      context,
      product: enrichedProduct,
      availablePackages: available,
      nutrition: _productNutrition(store, enrichedProduct),
    );
    if (choice == null || !context.mounted) return;
    if (!identical(enrichedProduct, product)) {
      store.saveProduct(enrichedProduct);
    }
    final event = choice.source == _ConsumptionSource.inventory
        ? store.consumeProduct(enrichedProduct, choice.servings)
        : store.logProductOutside(enrichedProduct, choice.servings);
    _showLogged(context, event);
    return;
  }

  var outsideFood = savedOutsideFood;
  if (outsideFood == null) {
    final suggestion = await _lookupSuggestion(context, service, barcode);
    if (!context.mounted) return;
    outsideFood = await showExternalFoodEditor(
      context,
      store,
      seed: ExternalFoodEditorSeed(
        barcode: barcode,
        name: suggestion?.name ?? '',
        brand: suggestion?.brand ?? '',
        servingLabel: suggestion?.nutritionServingLabel.isNotEmpty == true
            ? suggestion!.nutritionServingLabel
            : suggestion?.quantityLabel.isNotEmpty == true
            ? suggestion!.quantityLabel
            : '1 item',
        nutrition: suggestion?.nutritionPerPackage ?? const NutritionTotals(),
        source: suggestion?.source ?? '',
        estimated: false,
      ),
    );
    if (outsideFood == null || !context.mounted) return;
  }

  final servings = await _showOutsideChoice(context, outsideFood);
  if (servings == null || !context.mounted) return;
  final event = store.logExternalFood(
    outsideFood,
    servings: servings,
    note: 'Scanned barcode · not deducted from inventory',
  );
  _showLogged(context, event);
}

Future<BarcodeProductSuggestion?> _lookupSuggestion(
  BuildContext context,
  OpenFoodFactsBarcodeLookup lookup,
  String barcode,
) async {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Checking saved label data…'),
      duration: Duration(seconds: 2),
    ),
  );
  try {
    final suggestion = await lookup.lookup(barcode);
    if (suggestion == null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No public label data was found. Review the food and nutrition manually.',
          ),
        ),
      );
    }
    return suggestion;
  } on BarcodeLookupException catch (exception) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${exception.message} Enter the label manually.'),
        ),
      );
    }
    return null;
  }
}

ProductDefinition _enrichProduct(
  PantryStore store,
  ProductDefinition product,
  BarcodeProductSuggestion suggestion,
) {
  final definition = store.food(product.foodId);
  final suggestedConversion = suggestion.packageConversionFor(definition);
  final conversions = product.conversions.isEmpty && suggestedConversion != null
      ? [suggestedConversion]
      : product.conversions;
  final packageBase =
      product.conversionFor('package')?.baseAmount ??
      suggestedConversion?.baseAmount ??
      (definition.baseUnit == 'each' ? 1.0 : null);
  final suggestedNutrition = suggestion.nutritionPerPackage;
  final nutrition =
      product.nutrition == null &&
          suggestedNutrition != null &&
          packageBase != null
      ? NutritionFacts(
          basisBaseAmount: packageBase,
          totals: suggestedNutrition,
          source: suggestion.source,
        )
      : product.nutrition;
  if (conversions == product.conversions && nutrition == product.nutrition) {
    return product;
  }
  return product.copyWith(conversions: conversions, nutrition: nutrition);
}

NutritionTotals? _productNutrition(
  PantryStore store,
  ProductDefinition product,
) {
  final packageBase = store.productPackageBaseAmount(product);
  if (packageBase == null) return null;
  return (product.nutrition ?? store.food(product.foodId).nutrition)
      ?.forBaseAmount(packageBase);
}

Future<_ConsumptionChoice?> _showProductChoice(
  BuildContext context, {
  required ProductDefinition product,
  required double availablePackages,
  required NutritionTotals? nutrition,
}) async {
  final servings = TextEditingController(text: '1');
  var source = availablePackages >= 1
      ? _ConsumptionSource.inventory
      : _ConsumptionSource.outside;
  String? error;
  final name = product.brand.isEmpty
      ? product.name
      : '${product.brand} ${product.name}';
  final result = await showDialog<_ConsumptionChoice>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text('Log $name'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                availablePackages >= 1
                    ? '${_compact(availablePackages)} packages found in exact product inventory.'
                    : 'No exact matching package is currently in inventory.',
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Use inventory'),
                    selected: source == _ConsumptionSource.inventory,
                    onSelected: availablePackages > 0
                        ? (_) => setDialogState(
                            () => source = _ConsumptionSource.inventory,
                          )
                        : null,
                  ),
                  ChoiceChip(
                    label: const Text('Outside food'),
                    selected: source == _ConsumptionSource.outside,
                    onSelected: (_) => setDialogState(
                      () => source = _ConsumptionSource.outside,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: servings,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Packages consumed',
                ),
              ),
              const SizedBox(height: 12),
              _NutritionPreview(nutrition: nutrition),
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final amount = double.tryParse(servings.text.trim());
              if (amount == null || amount <= 0) {
                setDialogState(() => error = 'Enter a positive package count.');
              } else if (source == _ConsumptionSource.inventory &&
                  amount > availablePackages + 0.000001) {
                setDialogState(
                  () => error =
                      'Only ${_compact(availablePackages)} packages are in inventory.',
                );
              } else {
                Navigator.pop(
                  context,
                  _ConsumptionChoice(source: source, servings: amount),
                );
              }
            },
            child: const Text('Log consumption'),
          ),
        ],
      ),
    ),
  );
  servings.dispose();
  return result;
}

Future<double?> _showOutsideChoice(
  BuildContext context,
  ExternalFood food,
) async {
  final servings = TextEditingController(text: '1');
  String? error;
  final result = await showDialog<double>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text('Log ${food.name}'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'No exact matching inventory was found, so this will be logged as outside food.',
              ),
              const SizedBox(height: 14),
              TextField(
                controller: servings,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(labelText: food.servingLabel),
              ),
              const SizedBox(height: 12),
              _NutritionPreview(nutrition: food.nutrition),
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final amount = double.tryParse(servings.text.trim());
              if (amount == null || amount <= 0) {
                setDialogState(() => error = 'Enter a positive serving count.');
              } else {
                Navigator.pop(context, amount);
              }
            },
            child: const Text('Log outside food'),
          ),
        ],
      ),
    ),
  );
  servings.dispose();
  return result;
}

class _NutritionPreview extends StatelessWidget {
  const _NutritionPreview({required this.nutrition});

  final NutritionTotals? nutrition;

  @override
  Widget build(BuildContext context) {
    final value = nutrition;
    if (value == null) {
      return Text(
        'Nutrition is not saved for this package yet.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Text(
      '${_compact(value.calories)} cal · ${_compact(value.proteinG)} g protein · '
      '${_compact(value.carbsG)} g carbs · ${_compact(value.sodiumMg)} mg sodium',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}

void _showLogged(BuildContext context, ConsumptionEvent event) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('${event.label} logged.')));
}

String _compact(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1);
