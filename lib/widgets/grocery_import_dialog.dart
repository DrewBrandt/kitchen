import 'package:flutter/material.dart';

import '../data/pantry_store.dart';
import '../models/pantry_models.dart';
import '../services/grocery_import_service.dart';

Future<void> showGroceryImportDialog(BuildContext context, PantryStore store) =>
    showDialog<void>(
      context: context,
      builder: (context) => _GroceryImportDialog(store: store),
    );

class _GroceryImportDialog extends StatefulWidget {
  const _GroceryImportDialog({required this.store});
  final PantryStore store;

  @override
  State<_GroceryImportDialog> createState() => _GroceryImportDialogState();
}

class _GroceryImportDialogState extends State<_GroceryImportDialog> {
  final input = TextEditingController(
    text:
        'food, amount, unit, location, best_by\nEggs, 12, each, fridge, +14\nMilk, 1, liter, fridge, +7',
  );
  final parser = const GroceryImportService();
  List<GroceryImportLine> preview = const [];

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = preview.where((line) => line.isValid).toList();
    return AlertDialog(
      title: const Text('Import groceries'),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Paste CSV, tab-separated, or pipe-separated rows. Best by accepts YYYY-MM-DD or +days.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: input,
                minLines: 6,
                maxLines: 12,
                style: const TextStyle(fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  alignLabelWithHint: true,
                  labelText: 'Grocery rows',
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _preview,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Review rows'),
                ),
              ),
              if (preview.isNotEmpty) ...[
                const Divider(height: 28),
                ...preview.map(
                  (line) => ListTile(
                    dense: true,
                    leading: Icon(
                      line.isValid ? Icons.check_circle : Icons.error_outline,
                      color: line.isValid
                          ? Colors.green
                          : Theme.of(context).colorScheme.error,
                    ),
                    title: Text(
                      '${line.name} · ${line.amount} ${line.unit} · ${line.location.label}',
                    ),
                    subtitle: line.error == null
                        ? null
                        : Text('Line ${line.lineNumber}: ${line.error}'),
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
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: valid.isEmpty || valid.length != preview.length
              ? null
              : _apply,
          child: Text('Add ${valid.length} lots'),
        ),
      ],
    );
  }

  void _preview() =>
      setState(() => preview = parser.parse(input.text, widget.store.foods));

  void _apply() {
    for (final line in preview) {
      widget.store.addLot(
        food: widget.store.food(line.foodId!),
        amount: line.amount,
        unit: line.unit,
        location: line.location,
        bestBy: line.bestBy,
      );
    }
    Navigator.pop(context);
  }
}
