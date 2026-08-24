import 'package:flutter/material.dart';

import '../data/pantry_store.dart';
import '../models/pantry_models.dart';
import '../widgets/food_editor_dialog.dart';
import '../widgets/grocery_import_dialog.dart';
import '../widgets/recipe_editor_dialog.dart';

class PantryHomePage extends StatefulWidget {
  const PantryHomePage({
    super.key,
    required this.store,
    required this.onSignOut,
  });

  final PantryStore store;
  final VoidCallback onSignOut;

  @override
  State<PantryHomePage> createState() => _PantryHomePageState();
}

class _PantryHomePageState extends State<PantryHomePage> {
  int selectedIndex = 0;

  static const destinations = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home),
      label: 'Home',
    ),
    NavigationDestination(
      icon: Icon(Icons.kitchen_outlined),
      selectedIcon: Icon(Icons.kitchen),
      label: 'Inventory',
    ),
    NavigationDestination(
      icon: Icon(Icons.menu_book_outlined),
      selectedIcon: Icon(Icons.menu_book),
      label: 'Recipes',
    ),
    NavigationDestination(
      icon: Icon(Icons.monitor_heart_outlined),
      selectedIcon: Icon(Icons.monitor_heart),
      label: 'Food log',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = [
      _Dashboard(
        store: widget.store,
        onOpenInventory: () => setState(() => selectedIndex = 1),
        onOpenRecipes: () => setState(() => selectedIndex = 2),
      ),
      _InventoryPage(store: widget.store),
      _RecipesPage(store: widget.store),
      _FoodLogPage(store: widget.store),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 850;
        final content = AnimatedBuilder(
          animation: widget.store,
          builder: (context, _) => Column(
            children: [
              if (widget.store.isSyncing)
                const LinearProgressIndicator(minHeight: 2),
              if (widget.store.syncError != null)
                MaterialBanner(
                  content: const Text(
                    'Cloud sync failed. This change may only exist on this device; check your connection and restart before making more changes.',
                  ),
                  actions: const [SizedBox.shrink()],
                ),
              Expanded(child: pages[selectedIndex]),
            ],
          ),
        );
        if (!wide) {
          return Scaffold(
            appBar: AppBar(
              title: Text(destinations[selectedIndex].label),
              actions: [
                IconButton(
                  tooltip: 'Sign out',
                  onPressed: widget.onSignOut,
                  icon: const Icon(Icons.logout),
                ),
              ],
            ),
            body: content,
            bottomNavigationBar: NavigationBar(
              selectedIndex: selectedIndex,
              destinations: destinations,
              onDestinationSelected: (value) =>
                  setState(() => selectedIndex = value),
            ),
          );
        }
        return Scaffold(
          body: Row(
            children: [
              SafeArea(
                child: NavigationRail(
                  extended: constraints.maxWidth >= 1080,
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (value) =>
                      setState(() => selectedIndex = value),
                  leading: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🫙', style: TextStyle(fontSize: 30)),
                        if (constraints.maxWidth >= 1080) ...[
                          const SizedBox(width: 10),
                          Text(
                            'Pantry',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ],
                      ],
                    ),
                  ),
                  destinations: destinations
                      .map(
                        (item) => NavigationRailDestination(
                          icon: item.icon,
                          selectedIcon: item.selectedIcon,
                          label: Text(item.label),
                        ),
                      )
                      .toList(),
                  trailing: IconButton(
                    tooltip: 'Sign out',
                    onPressed: widget.onSignOut,
                    icon: const Icon(Icons.logout),
                  ),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: content),
            ],
          ),
        );
      },
    );
  }
}

class _PageShell extends StatelessWidget {
  const _PageShell({
    required this.title,
    required this.subtitle,
    required this.child,
    this.action,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  ?action,
                ],
              ),
              const SizedBox(height: 24),
              child,
            ],
          ),
        ),
      ),
    ),
  );
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({
    required this.store,
    required this.onOpenInventory,
    required this.onOpenRecipes,
  });

  final PantryStore store;
  final VoidCallback onOpenInventory;
  final VoidCallback onOpenRecipes;

  @override
  Widget build(BuildContext context) {
    final expiring = store.lots.where((lot) {
      final date = lot.bestBy;
      return date != null &&
          lot.quantityBase > 0 &&
          date.difference(store.now).inDays <= 7;
    }).toList()..sort((a, b) => a.bestBy!.compareTo(b.bestBy!));
    final makeable = store.recipes
        .where((recipe) => store.missingFor(recipe).isEmpty)
        .length;
    final readyRecipes =
        store.recipes
            .where((recipe) => store.missingFor(recipe).isEmpty)
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    final almostReady =
        store.recipes
            .where((recipe) => store.missingFor(recipe).isNotEmpty)
            .toList()
          ..sort((a, b) {
            final byMissing = store
                .missingFor(a)
                .length
                .compareTo(store.missingFor(b).length);
            return byMissing != 0 ? byMissing : a.name.compareTo(b.name);
          });
    return _PageShell(
      title: 'Good ${_dayPart()}',
      subtitle: 'Here is what your kitchen can do today.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _StatCard(
                value: '${store.foods.length}',
                label: 'foods tracked',
                icon: Icons.inventory_2_outlined,
              ),
              _StatCard(
                value: '$makeable',
                label: 'recipes ready',
                icon: Icons.restaurant_menu,
              ),
              _StatCard(
                value: '${expiring.length}',
                label: 'lots use soon',
                icon: Icons.schedule,
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            'Use soon',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (expiring.isEmpty)
            const _EmptyCard(
              icon: Icons.check_circle_outline,
              text: 'Nothing expires in the next week.',
            )
          else
            ...expiring.take(4).map((lot) {
              final food = store.food(lot.foodId);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    leading: Text(
                      food.emoji,
                      style: const TextStyle(fontSize: 28),
                    ),
                    title: Text(food.name),
                    subtitle: Text(
                      '${store.units.bestInventoryLabel(food, lot.quantityBase)} · ${lot.location.label}',
                    ),
                    trailing: Text(_relativeDate(store.now, lot.bestBy!)),
                  ),
                ),
              );
            }),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: Text(
                  readyRecipes.isEmpty ? 'Closest meal' : 'Cook next',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                onPressed: onOpenRecipes,
                child: const Text('Browse recipes'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (readyRecipes.isEmpty && almostReady.isEmpty)
            const _EmptyCard(
              icon: Icons.menu_book_outlined,
              text: 'Add a recipe to start matching meals to your pantry.',
            )
          else
            ...((readyRecipes.isNotEmpty ? readyRecipes : almostReady)
                .take(3)
                .map((recipe) {
                  final missing = store.missingFor(recipe);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        onTap: onOpenRecipes,
                        leading: Text(
                          recipe.emoji,
                          style: const TextStyle(fontSize: 28),
                        ),
                        title: Text(recipe.name),
                        subtitle: Text(
                          missing.isEmpty
                              ? 'Everything is in stock'
                              : _missingSummary(store, missing),
                        ),
                        trailing: Icon(
                          missing.isEmpty
                              ? Icons.check_circle_outline
                              : Icons.shopping_basket_outlined,
                        ),
                      ),
                    ),
                  );
                })),
          const SizedBox(height: 20),
          FilledButton.tonalIcon(
            onPressed: onOpenInventory,
            icon: const Icon(Icons.add_shopping_cart),
            label: const Text('Put away groceries'),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.value,
    required this.label,
    required this.icon,
  });
  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 210,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(child: Icon(icon)),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(label),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _InventoryPage extends StatelessWidget {
  const _InventoryPage({required this.store});
  final PantryStore store;

  @override
  Widget build(BuildContext context) => _PageShell(
    title: 'Inventory',
    subtitle:
        'Counted items stay natural; measured items convert behind the scenes.',
    action: Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        OutlinedButton.icon(
          onPressed: () => showFoodEditor(context, store),
          icon: const Icon(Icons.add_box_outlined),
          label: const Text('Define food'),
        ),
        OutlinedButton.icon(
          onPressed: () => _showAddLot(context, store),
          icon: const Icon(Icons.add),
          label: const Text('Add one lot'),
        ),
        FilledButton.icon(
          onPressed: () => showGroceryImportDialog(context, store),
          icon: const Icon(Icons.playlist_add),
          label: const Text('Import groceries'),
        ),
      ],
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 900
            ? (constraints.maxWidth - 24) / 3
            : constraints.maxWidth >= 560
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: store.foods
              .map(
                (food) => SizedBox(
                  width: width,
                  child: _FoodCard(store: store, food: food),
                ),
              )
              .toList(),
        );
      },
    ),
  );
}

class _FoodCard extends StatelessWidget {
  const _FoodCard({required this.store, required this.food});
  final PantryStore store;
  final FoodDefinition food;

  @override
  Widget build(BuildContext context) {
    final amount = store.totalFor(food.id);
    final lots = store
        .lotsFor(food.id)
        .where((lot) => lot.quantityBase > 0)
        .length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(food.emoji, style: const TextStyle(fontSize: 34)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        food.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        food.mode == QuantityMode.counted
                            ? 'Counted'
                            : 'Measured',
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Edit food definition',
                  onPressed: () =>
                      showFoodEditor(context, store, existing: food),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              store.units.bestInventoryLabel(food, amount),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              '$lots ${lots == 1 ? 'lot' : 'lots'} · ${food.defaultLocation.label}',
            ),
            if (food.nutrition != null) ...[
              const SizedBox(height: 8),
              Text(
                _nutritionLabel(food.nutrition!.totals),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                '${food.nutrition!.estimated ? 'Estimated' : 'Label data'} per serving',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: amount <= 0
                    ? null
                    : () => _showConsume(context, store, food),
                icon: const Icon(Icons.remove_circle_outline),
                label: Text(
                  food.mode == QuantityMode.counted ? 'Use one' : 'Use some',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecipesPage extends StatelessWidget {
  const _RecipesPage({required this.store});
  final PantryStore store;

  @override
  Widget build(BuildContext context) {
    final ready = <Recipe>[];
    final quickRun = <Recipe>[];
    final planning = <Recipe>[];
    for (final recipe in store.recipes) {
      final missingCount = store.missingFor(recipe).length;
      if (missingCount == 0) {
        ready.add(recipe);
      } else if (missingCount <= 2) {
        quickRun.add(recipe);
      } else {
        planning.add(recipe);
      }
    }
    for (final recipes in [ready, quickRun, planning]) {
      recipes.sort((a, b) => a.name.compareTo(b.name));
    }
    return _PageShell(
      title: 'Recipes',
      subtitle: 'Start with what is ready, or see exactly what to pick up.',
      action: FilledButton.icon(
        onPressed: () => showRecipeEditor(context, store),
        icon: const Icon(Icons.add),
        label: const Text('New recipe'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RecipeSection(
            title: 'Ready to cook',
            subtitle: 'Every tracked ingredient is in stock.',
            recipes: ready,
            store: store,
            emptyText: 'No complete matches yet.',
          ),
          const SizedBox(height: 28),
          _RecipeSection(
            title: 'Quick grocery run',
            subtitle: 'Missing only one or two ingredients.',
            recipes: quickRun,
            store: store,
            emptyText: 'Nothing is one or two items away right now.',
          ),
          if (planning.isNotEmpty) ...[
            const SizedBox(height: 28),
            _RecipeSection(
              title: 'Needs more planning',
              subtitle: 'Useful ideas for a future shopping trip.',
              recipes: planning,
              store: store,
              emptyText: '',
            ),
          ],
        ],
      ),
    );
  }
}

class _RecipeSection extends StatelessWidget {
  const _RecipeSection({
    required this.title,
    required this.subtitle,
    required this.recipes,
    required this.store,
    required this.emptyText,
  });

  final String title;
  final String subtitle;
  final List<Recipe> recipes;
  final PantryStore store;
  final String emptyText;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 4),
      Text(
        subtitle,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      const SizedBox(height: 12),
      if (recipes.isEmpty)
        _EmptyCard(icon: Icons.restaurant_menu, text: emptyText)
      else
        ...recipes.map(
          (recipe) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _RecipeCard(store: store, recipe: recipe),
          ),
        ),
    ],
  );
}

class _RecipeCard extends StatelessWidget {
  const _RecipeCard({required this.store, required this.recipe});
  final PantryStore store;
  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    final missing = store.missingFor(recipe);
    final recipeNutrition = store.nutritionForRecipe(recipe);
    final compact = MediaQuery.sizeOf(context).width < 600;
    final availabilityChip = Chip(
      avatar: Icon(
        missing.isEmpty ? Icons.check_circle : Icons.shopping_basket_outlined,
        size: 18,
      ),
      label: Text(missing.isEmpty ? 'Ready' : 'Missing ${missing.length}'),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(recipe.emoji, style: const TextStyle(fontSize: 36)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recipe.name,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${store.units.formatAmount(recipe.servings)} ${recipe.servings == 1 ? 'serving' : 'servings'}',
                      ),
                      if (compact) ...[
                        const SizedBox(height: 8),
                        availabilityChip,
                      ],
                    ],
                  ),
                ),
                if (!compact) availabilityChip,
                PopupMenuButton<String>(
                  tooltip: 'Recipe actions',
                  onSelected: (value) {
                    if (value == 'edit') {
                      showRecipeEditor(context, store, existing: recipe);
                    } else if (value == 'delete') {
                      _confirmDeleteRecipe(context, store, recipe);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Edit'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(Icons.delete_outline),
                        title: Text('Delete'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 28),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: recipe.ingredients.map((ingredient) {
                final food = store.food(ingredient.foodId);
                return Chip(
                  label: Text(store.units.ingredientLabel(food, ingredient)),
                );
              }).toList(),
            ),
            if (missing.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.secondaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pick up',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(_missingSummary(store, missing)),
                  ],
                ),
              ),
            ],
            if (recipeNutrition != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.monitor_heart_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Approx. ${_nutritionLabel(recipeNutrition.scale(1 / recipe.servings))} per serving · based on ingredient profiles',
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: missing.isEmpty
                    ? () => _cook(context, store, recipe)
                    : null,
                icon: const Icon(Icons.soup_kitchen),
                label: const Text('Cook recipe'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FoodLogPage extends StatefulWidget {
  const _FoodLogPage({required this.store});
  final PantryStore store;

  @override
  State<_FoodLogPage> createState() => _FoodLogPageState();
}

class _FoodLogPageState extends State<_FoodLogPage> {
  DateTime selectedDay = DateTime.now();

  void _moveDay(int days) => setState(
    () => selectedDay = DateTime(
      selectedDay.year,
      selectedDay.month,
      selectedDay.day + days,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final events = store.eventsForDay(selectedDay);
    final nutrition = store.nutritionForDay(selectedDay);
    final today = DateTime.now();
    final isToday = DateUtils.isSameDay(selectedDay, today);
    return _PageShell(
      title: 'Food log',
      subtitle:
          'Calories and nutrients from recipes, pantry items, and food away from home.',
      action: FilledButton.icon(
        onPressed: () => _showExternalMeal(context, store, selectedDay),
        icon: const Icon(Icons.add),
        label: const Text('Log food'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Previous day',
                onPressed: () => _moveDay(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  isToday ? 'Today' : _calendarDate(selectedDay),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Next day',
                onPressed: isToday ? null : () => _moveDay(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _NutritionSummary(nutrition: nutrition),
          const SizedBox(height: 20),
          Text(
            'Meals and snacks',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          if (events.isEmpty)
            const _EmptyCard(
              icon: Icons.restaurant_outlined,
              text: 'Nothing logged for this day yet.',
            )
          else
            ...events.map(
              (event) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Icon(_eventIcon(event.kind))),
                    title: Text(event.label),
                    subtitle: Text(
                      '${_eventSource(event)}${event.nutrition == null ? '' : ' · ${_nutritionLabel(event.nutrition!)}'}${event.note.isEmpty ? '' : '\n${event.note}'}',
                    ),
                    isThreeLine: event.note.isNotEmpty,
                    trailing: TextButton(
                      onPressed: () => store.undo(event.id),
                      child: Text(
                        event.kind == ConsumptionKind.external
                            ? 'Remove'
                            : 'Undo',
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NutritionSummary extends StatelessWidget {
  const _NutritionSummary({required this.nutrition});
  final NutritionTotals nutrition;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Daily nutrition',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _NutrientTile(
                label: 'Calories',
                value: nutrition.calories,
                unit: 'cal',
              ),
              _NutrientTile(
                label: 'Protein',
                value: nutrition.proteinG,
                unit: 'g',
              ),
              _NutrientTile(label: 'Carbs', value: nutrition.carbsG, unit: 'g'),
              _NutrientTile(label: 'Fat', value: nutrition.fatG, unit: 'g'),
              _NutrientTile(label: 'Fiber', value: nutrition.fiberG, unit: 'g'),
              _NutrientTile(label: 'Sugar', value: nutrition.sugarG, unit: 'g'),
              _NutrientTile(
                label: 'Sodium',
                value: nutrition.sodiumMg,
                unit: 'mg',
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _NutrientTile extends StatelessWidget {
  const _NutrientTile({
    required this.label,
    required this.value,
    required this.unit,
  });
  final String label;
  final double value;
  final String unit;

  @override
  Widget build(BuildContext context) => Container(
    width: 132,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 3),
        Text(
          '${_compactNumber(value)} $unit',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    ),
  );
}

Future<void> _showExternalMeal(
  BuildContext context,
  PantryStore store,
  DateTime day,
) async {
  final name = TextEditingController();
  final note = TextEditingController();
  final calories = TextEditingController();
  final protein = TextEditingController();
  final carbs = TextEditingController();
  final fat = TextEditingController();
  final fiber = TextEditingController();
  final sugar = TextEditingController();
  final sodium = TextEditingController();
  final nutrientFields = <(String, TextEditingController, String)>[
    ('Calories', calories, 'cal'),
    ('Protein', protein, 'g'),
    ('Carbs', carbs, 'g'),
    ('Fat', fat, 'g'),
    ('Fiber', fiber, 'g'),
    ('Sugar', sugar, 'g'),
    ('Sodium', sodium, 'mg'),
  ];
  var estimated = true;
  String? error;
  double number(TextEditingController controller) =>
      double.tryParse(controller.text.trim()) ?? 0;

  final submitted = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Log food away from home'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Meal or snack',
                    hintText: 'Cheeseburger, coffee, granola bar…',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(
                    labelText: 'Restaurant, brand, or note',
                    hintText: 'Optional',
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Nutrition for what you ate',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: nutrientFields
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
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Nutrition is estimated'),
                  subtitle: const Text(
                    'Useful for restaurant meals or approximate portions.',
                  ),
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
              final values = nutrientFields.map((field) => number(field.$2));
              if (name.text.trim().isEmpty) {
                setDialogState(() => error = 'Enter a meal or snack name.');
              } else if (values.any((value) => value < 0) ||
                  !values.any((value) => value > 0)) {
                setDialogState(
                  () => error = 'Enter at least one positive nutrition value.',
                );
              } else {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Add to log'),
          ),
        ],
      ),
    ),
  );

  if (submitted == true && context.mounted) {
    final today = DateTime.now();
    final timestamp = DateUtils.isSameDay(day, today)
        ? today
        : DateTime(day.year, day.month, day.day, 12);
    final event = store.logExternalMeal(
      label: name.text,
      note: note.text,
      estimated: estimated,
      timestamp: timestamp,
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${event.label} added to the food log.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => store.undo(event.id),
        ),
      ),
    );
  }
  for (final controller in [
    name,
    note,
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

IconData _eventIcon(ConsumptionKind kind) => switch (kind) {
  ConsumptionKind.recipe => Icons.soup_kitchen,
  ConsumptionKind.inventory => Icons.kitchen_outlined,
  ConsumptionKind.external => Icons.storefront_outlined,
};

String _eventSource(ConsumptionEvent event) => switch (event.kind) {
  ConsumptionKind.recipe => 'Recipe · inventory deducted',
  ConsumptionKind.inventory => 'Pantry item · inventory deducted',
  ConsumptionKind.external =>
    event.nutritionEstimated
        ? 'Outside food · estimated'
        : 'Outside food · label data',
};

String _calendarDate(DateTime date) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

Future<void> _showAddLot(BuildContext context, PantryStore store) async {
  var food = store.foods.first;
  var unit = food.conversions.first.unit;
  var location = food.defaultLocation;
  final amountController = TextEditingController(text: '1');
  final daysController = TextEditingController();
  final submitted = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Put away groceries'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<FoodDefinition>(
                initialValue: food,
                decoration: const InputDecoration(labelText: 'Food'),
                items: store.foods
                    .map(
                      (item) => DropdownMenuItem(
                        value: item,
                        child: Text('${item.emoji}  ${item.name}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setDialogState(() {
                  food = value!;
                  unit = food.conversions.first.unit;
                  location = food.defaultLocation;
                }),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Amount'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: unit,
                      decoration: const InputDecoration(labelText: 'Unit'),
                      items: food.conversions
                          .map(
                            (item) => DropdownMenuItem(
                              value: item.unit,
                              child: Text(item.symbol),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setDialogState(() => unit = value!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<StorageLocation>(
                initialValue: location,
                decoration: const InputDecoration(labelText: 'Location'),
                items: StorageLocation.values
                    .map(
                      (item) => DropdownMenuItem(
                        value: item,
                        child: Text(item.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setDialogState(() => location = value!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: daysController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Best by (days from now)',
                  hintText: 'Optional',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add lot'),
          ),
        ],
      ),
    ),
  );
  if (submitted == true) {
    final amount = double.tryParse(amountController.text);
    final days = int.tryParse(daysController.text);
    if (amount == null || amount <= 0) return;
    store.addLot(
      food: food,
      amount: amount,
      unit: unit,
      location: location,
      bestBy: days == null ? null : DateTime.now().add(Duration(days: days)),
    );
  }
}

Future<void> _showConsume(
  BuildContext context,
  PantryStore store,
  FoodDefinition food,
) async {
  var unit = food.conversions.first.unit;
  final amountController = TextEditingController(
    text: food.mode == QuantityMode.counted ? '1' : '1',
  );
  final submitted = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text('Use ${food.name.toLowerCase()}'),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 150,
              child: TextField(
                controller: amountController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Amount'),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<String>(
                initialValue: unit,
                decoration: const InputDecoration(labelText: 'Unit'),
                items: food.conversions
                    .map(
                      (item) => DropdownMenuItem(
                        value: item.unit,
                        child: Text(item.symbol),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setDialogState(() => unit = value!),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Use it'),
          ),
        ],
      ),
    ),
  );
  if (submitted != true || !context.mounted) return;
  final amount = double.tryParse(amountController.text);
  if (amount == null || amount <= 0) return;
  try {
    store.consume(food, amount, unit);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Used ${store.units.formatAmount(amount)} ${food.conversionFor(unit).symbol} ${food.name.toLowerCase()}',
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => store.undo(store.history.first.id),
        ),
      ),
    );
  } on InsufficientInventoryException {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('There is not enough in inventory.')),
    );
  }
}

void _cook(BuildContext context, PantryStore store, Recipe recipe) {
  // Revalidate at tap time. The button may still be visible for a frame after
  // another cook has changed inventory (for example, during a double-click).
  final missing = store.missingFor(recipe);
  if (missing.isNotEmpty) {
    _showMissingInventory(context, store, missing);
    return;
  }

  try {
    final event = store.cook(recipe);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${recipe.name} deducted from inventory.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => store.undo(event.id),
        ),
      ),
    );
  } on InsufficientInventoryException catch (exception) {
    // The store remains the final authority if inventory changes between the
    // preflight check and its atomic deduction plan.
    _showMissingInventory(context, store, exception.missing);
  }
}

void _showMissingInventory(
  BuildContext context,
  PantryStore store,
  Map<String, double> missing,
) {
  final details = missing.entries
      .map((entry) {
        final food = store.food(entry.key);
        final unit = food.conversionFor(food.baseUnit).symbol;
        return '${food.name} (${store.units.formatAmount(entry.value)} $unit short)';
      })
      .join(', ');
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('Not enough inventory: $details.')));
}

String _missingSummary(
  PantryStore store,
  Map<String, double> missing,
) => missing.entries
    .map((entry) {
      final food = store.food(entry.key);
      return '${food.name} — ${store.units.bestInventoryLabel(food, entry.value)}';
    })
    .join(' · ');

Future<void> _confirmDeleteRecipe(
  BuildContext context,
  PantryStore store,
  Recipe recipe,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete ${recipe.name}?'),
      content: const Text(
        'Past cooking history will remain, but the recipe itself will be removed.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed == true) store.deleteRecipe(recipe.id);
}

String _dayPart() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'morning';
  if (hour < 18) return 'afternoon';
  return 'evening';
}

String _relativeDate(DateTime now, DateTime date) {
  final days = DateTime(
    date.year,
    date.month,
    date.day,
  ).difference(DateTime(now.year, now.month, now.day)).inDays;
  if (days < 0) return '${-days}d overdue';
  if (days == 0) return 'Today';
  if (days == 1) return 'Tomorrow';
  return 'In $days days';
}

String _nutritionLabel(NutritionTotals nutrition) =>
    '${nutrition.calories.round()} cal · ${_compactNumber(nutrition.proteinG)}g protein · ${_compactNumber(nutrition.carbsG)}g carbs · ${_compactNumber(nutrition.fatG)}g fat';

String _compactNumber(double value) {
  if ((value - value.round()).abs() < 0.05) return '${value.round()}';
  return value.toStringAsFixed(1);
}
