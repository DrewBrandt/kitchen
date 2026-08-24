import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/pantry_store.dart';
import '../models/pantry_models.dart';
import 'recipe_editor_dialog.dart';

Future<void> showRecipeDetails(
  BuildContext context,
  PantryStore store,
  Recipe recipe, {
  required Future<void> Function() onMake,
}) => showDialog<void>(
  context: context,
  builder: (dialogContext) => _RecipeDetailDialog(
    store: store,
    recipe: recipe,
    onMake: () async {
      Navigator.pop(dialogContext);
      await onMake();
    },
  ),
);

class _RecipeDetailDialog extends StatelessWidget {
  const _RecipeDetailDialog({
    required this.store,
    required this.recipe,
    required this.onMake,
  });

  final PantryStore store;
  final Recipe recipe;
  final Future<void> Function() onMake;

  @override
  Widget build(BuildContext context) {
    final missing = store.missingFor(recipe);
    final averageMinutes = store.averageMinutesForRecipe(recipe.id);
    final lastMade = store.lastMadeRecipe(recipe.id);
    final makesThisYear = store.recipeMakesThisYear(recipe.id);
    final meta = <String>[
      '${store.units.formatAmount(recipe.servings)} ${recipe.servings == 1 ? 'serving' : 'servings'}',
      if (averageMinutes != null) '${averageMinutes.round()} min avg',
      if (lastMade != null) 'Made ${_relativeDate(store.now, lastMade)}',
      if (makesThisYear > 0) '$makesThisYear× this year',
    ];

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 24, 26, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(recipe.emoji, style: const TextStyle(fontSize: 30)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          recipe.name,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          meta.join(' · '),
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  _RatingSummary(
                    label: 'Ease',
                    value: store.averageEaseForRecipe(recipe.id),
                    color: const Color(0xFF71E59A),
                  ),
                  const SizedBox(width: 26),
                  _RatingSummary(
                    label: 'Taste',
                    value: store.averageTasteForRecipe(recipe.id),
                    color: const Color(0xFFFFB347),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _SectionLabel('Ingredients'),
                      const SizedBox(height: 8),
                      ...recipe.ingredients.map((ingredient) {
                        final food = store.food(ingredient.foodId);
                        final available = !missing.containsKey(food.id);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: available
                                      ? const Color(0xFF71E59A)
                                      : const Color(0xFF806D36),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  food.name,
                                  style: const TextStyle(fontSize: 13.5),
                                ),
                              ),
                              Text(
                                available ? 'in kitchen' : 'needed',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 18),
                              SizedBox(
                                width: 90,
                                child: Text(
                                  store.units.formatUnitAmount(
                                    food,
                                    ingredient.amount,
                                    ingredient.unit,
                                  ),
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 20),
                      const _SectionLabel('Method'),
                      const SizedBox(height: 10),
                      if (recipe.instructions.isEmpty)
                        Text(
                          'No method has been added yet.',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        )
                      else
                        ...recipe.instructions.indexed.map(
                          (entry) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 30,
                                  child: Text(
                                    '${entry.$1 + 1}',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    entry.$2,
                                    style: TextStyle(
                                      height: 1.5,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (recipe.sourceUrl.isNotEmpty ||
                          recipe.sourceNote.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        const _SectionLabel('Source'),
                        const SizedBox(height: 8),
                        if (recipe.sourceNote.isNotEmpty)
                          Text(recipe.sourceNote),
                        if (recipe.sourceUrl.isNotEmpty)
                          Row(
                            children: [
                              Expanded(
                                child: SelectableText(
                                  recipe.sourceUrl,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Copy source link',
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: recipe.sourceUrl),
                                  );
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Source link copied.'),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.copy_outlined, size: 18),
                              ),
                            ],
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Divider(),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      showRecipeEditor(context, store, existing: recipe);
                    },
                    child: const Text('Edit recipe'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: onMake,
                    child: const Text('Start cooking'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: Theme.of(context).textTheme.labelSmall?.copyWith(
      letterSpacing: 1.2,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

class _RatingSummary extends StatelessWidget {
  const _RatingSummary({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double? value;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          letterSpacing: 1,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(width: 8),
      ...List.generate(
        5,
        (index) => Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Icon(
            Icons.circle,
            size: 9,
            color: index < (value?.round() ?? 0)
                ? color
                : Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      if (value == null)
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            'not rated',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ),
    ],
  );
}

String _relativeDate(DateTime now, DateTime date) {
  final today = DateTime(now.year, now.month, now.day);
  final then = DateTime(date.year, date.month, date.day);
  final days = today.difference(then).inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  if (days < 14) return '$days days ago';
  final weeks = (days / 7).round();
  if (weeks < 8) return '$weeks weeks ago';
  final months = (days / 30).round();
  return '$months months ago';
}
