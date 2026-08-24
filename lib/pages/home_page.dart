import 'package:flutter/material.dart';

import '../data/pantry_store.dart';
import '../models/pantry_models.dart';
import '../widgets/food_editor_dialog.dart';
import '../widgets/external_food_editor_dialog.dart';
import '../widgets/grocery_import_dialog.dart';
import '../widgets/recipe_editor_dialog.dart';

const _ink = Color(0xFFECF1EE);
const _muted = Color(0xFF97A29B);
const _faint = Color(0xFF6E7A73);
const _raised = Color(0xFF1E2321);
const _border = Color(0xFF29302C);
const _amber = Color(0xFFF0B85A);
const _herb = Color(0xFF7DD89A);
const _berry = Color(0xFFE77986);

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
        onOpenFoodLog: () => setState(() => selectedIndex = 3),
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
              titleSpacing: 18,
              title: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _amber,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Text('🫙', style: TextStyle(fontSize: 16)),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Pantry',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontFamily: 'serif',
                      fontSize: 24,
                    ),
                  ),
                ],
              ),
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
              backgroundColor: const Color(0xFF101311),
              indicatorColor: _raised,
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
              _PantrySidebar(
                selectedIndex: selectedIndex,
                inventoryCount: widget.store.foods.length,
                recipeCount: widget.store.recipes.length,
                onSelected: (value) => setState(() => selectedIndex = value),
                onSignOut: widget.onSignOut,
              ),
              Expanded(child: content),
            ],
          ),
        );
      },
    );
  }
}

class _PantrySidebar extends StatelessWidget {
  const _PantrySidebar({
    required this.selectedIndex,
    required this.inventoryCount,
    required this.recipeCount,
    required this.onSelected,
    required this.onSignOut,
  });

  final int selectedIndex;
  final int inventoryCount;
  final int recipeCount;
  final ValueChanged<int> onSelected;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) => Container(
    width: 236,
    decoration: const BoxDecoration(
      color: Color(0xFF101311),
      border: Border(right: BorderSide(color: _border)),
    ),
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 22, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _amber,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Text('🫙', style: TextStyle(fontSize: 16)),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Pantry',
                    style: TextStyle(
                      color: _ink,
                      fontFamily: 'serif',
                      fontSize: 24,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            const _NavGroupLabel('Kitchen'),
            _SidebarDestination(
              label: 'Today',
              selected: selectedIndex == 0,
              onTap: () => onSelected(0),
            ),
            _SidebarDestination(
              label: 'Inventory',
              badge: '$inventoryCount',
              selected: selectedIndex == 1,
              onTap: () => onSelected(1),
            ),
            _SidebarDestination(
              label: 'Recipes',
              badge: '$recipeCount',
              selected: selectedIndex == 2,
              onTap: () => onSelected(2),
            ),
            const SizedBox(height: 24),
            const _NavGroupLabel('Eating'),
            _SidebarDestination(
              label: 'Food log',
              selected: selectedIndex == 3,
              onTap: () => onSelected(3),
            ),
            const Spacer(),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: [
                const CircleAvatar(
                  radius: 13,
                  backgroundColor: Color(0xFF313A35),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Drew', style: TextStyle(color: _muted)),
                ),
                TextButton(
                  onPressed: onSignOut,
                  style: TextButton.styleFrom(
                    foregroundColor: _faint,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _NavGroupLabel extends StatelessWidget {
  const _NavGroupLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
    child: Text(
      label.toUpperCase(),
      style: const TextStyle(color: _faint, fontSize: 11, letterSpacing: 1.3),
    ),
  );
}

class _SidebarDestination extends StatelessWidget {
  const _SidebarDestination({
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = '',
  });

  final String label;
  final String badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(9),
    child: Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: selected ? _raised : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: selected ? _amber : const Color(0xFF333B36),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? _ink : _muted,
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ),
          Text(
            badge,
            style: const TextStyle(
              color: _faint,
              fontFamily: 'monospace',
              fontSize: 11,
            ),
          ),
        ],
      ),
    ),
  );
}

class _PageShell extends StatelessWidget {
  const _PageShell({
    required this.title,
    required this.subtitle,
    required this.child,
    this.action,
    this.eyebrow,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? action;
  final String? eyebrow;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        MediaQuery.sizeOf(context).width < 600 ? 18 : 44,
        MediaQuery.sizeOf(context).width < 600 ? 24 : 40,
        MediaQuery.sizeOf(context).width < 600 ? 18 : 44,
        64,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 640;
                  final heading = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (eyebrow != null) ...[
                        Text(
                          eyebrow!.toUpperCase(),
                          style: const TextStyle(
                            color: _faint,
                            fontSize: 12,
                            letterSpacing: 1.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      Text(
                        title,
                        style: Theme.of(context).textTheme.displaySmall
                            ?.copyWith(
                              fontFamily: 'serif',
                              fontSize: compact ? 38 : 44,
                              height: 1.05,
                              fontWeight: FontWeight.w400,
                            ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: _muted, height: 1.45),
                        ),
                      ],
                    ],
                  );
                  if (compact && action != null) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        heading,
                        const SizedBox(height: 20),
                        Align(alignment: Alignment.centerLeft, child: action),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(child: heading),
                      ?action,
                    ],
                  );
                },
              ),
              const SizedBox(height: 28),
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
    required this.onOpenFoodLog,
  });

  final PantryStore store;
  final VoidCallback onOpenInventory;
  final VoidCallback onOpenRecipes;
  final VoidCallback onOpenFoodLog;

  @override
  Widget build(BuildContext context) {
    final expiring = store.lots.where((lot) {
      final date = lot.bestBy;
      return date != null &&
          lot.quantityBase > 0 &&
          date.difference(store.now).inDays <= 7;
    }).toList()..sort((a, b) => a.bestBy!.compareTo(b.bestBy!));
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
    final suggestions = (readyRecipes.isNotEmpty ? readyRecipes : almostReady)
        .take(4)
        .toList();
    return _PageShell(
      eyebrow: _calendarDate(store.now),
      title: 'Good ${_dayPart()}, Drew.',
      subtitle: expiring.isEmpty
          ? 'Your kitchen is in good shape. Here is what you can make today.'
          : '${expiring.length} ${expiring.length == 1 ? 'lot wants' : 'lots want'} using this week.',
      action: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          OutlinedButton(
            onPressed: onOpenFoodLog,
            child: const Text('Log food'),
          ),
          FilledButton(
            onPressed: () => showGroceryImportDialog(context, store),
            child: const Text('Put away groceries'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 760;
              final nutrition = _NutritionSummary(
                nutrition: store.nutritionForDay(store.now),
                targets: store.nutritionTargets,
                onEdit: () => _showNutritionTargets(context, store),
              );
              final useSoon = _UseSoonCard(store: store, expiring: expiring);
              if (stacked) {
                return Column(
                  children: [nutrition, const SizedBox(height: 18), useSoon],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: nutrition),
                  const SizedBox(width: 18),
                  Expanded(child: useSoon),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          readyRecipes.isEmpty
                              ? 'Closest to cookable'
                              : 'Cookable right now',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton(
                        onPressed: onOpenRecipes,
                        child: const Text('All recipes'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (suggestions.isEmpty)
                    const _EmptyCard(
                      icon: Icons.menu_book_outlined,
                      text:
                          'Add a recipe to start matching meals to your pantry.',
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 800 ? 4 : 2;
                        final width =
                            (constraints.maxWidth - (columns - 1) * 12) /
                            columns;
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: suggestions.map((recipe) {
                            final missing = store.missingFor(recipe);
                            return SizedBox(
                              width: width,
                              child: InkWell(
                                onTap: onOpenRecipes,
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: _raised,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        recipe.emoji,
                                        style: const TextStyle(fontSize: 26),
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        recipe.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 7),
                                      Text(
                                        missing.isEmpty
                                            ? '${store.units.formatAmount(recipe.servings)} servings · in stock'
                                            : 'Missing ${missing.length}',
                                        style: const TextStyle(
                                          color: _muted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onOpenInventory,
              icon: const Icon(Icons.inventory_2_outlined, size: 18),
              label: Text('${store.foods.length} foods in inventory'),
            ),
          ),
        ],
      ),
    );
  }
}

class _UseSoonCard extends StatelessWidget {
  const _UseSoonCard({required this.store, required this.expiring});
  final PantryStore store;
  final List<InventoryLot> expiring;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Use soon',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${expiring.length} ${expiring.length == 1 ? 'lot' : 'lots'}',
                style: const TextStyle(
                  color: _faint,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (expiring.isEmpty)
            const Text(
              'Nothing expires in the next week.',
              style: TextStyle(color: _muted),
            )
          else
            ...expiring.take(4).map((lot) {
              final food = store.food(lot.foodId);
              final urgent = lot.bestBy!.difference(store.now).inDays <= 3;
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    Text(food.emoji, style: const TextStyle(fontSize: 24)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(food.name, style: const TextStyle(fontSize: 14)),
                          Text(
                            '${store.units.bestInventoryLabel(food, lot.quantityBase)} · ${lot.location.label}',
                            style: const TextStyle(color: _muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: (urgent ? _berry : _amber).withValues(
                          alpha: .14,
                        ),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Text(
                        _relativeDate(store.now, lot.bestBy!),
                        style: TextStyle(
                          color: urgent ? _berry : _amber,
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    ),
  );
}

class _InventoryPage extends StatelessWidget {
  const _InventoryPage({required this.store});
  final PantryStore store;

  @override
  Widget build(BuildContext context) => _PageShell(
    eyebrow:
        '${store.foods.length} foods · ${store.lots.where((lot) => lot.quantityBase > 0).length} lots',
    title: 'Inventory',
    subtitle:
        'Counted and measured ingredients, organized by storage location.',
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
    final activeLots = store
        .lotsFor(food.id)
        .where((lot) => lot.quantityBase > 0)
        .toList();
    final lots = activeLots.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
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
                TextButton(
                  onPressed: () =>
                      showFoodEditor(context, store, existing: food),
                  style: TextButton.styleFrom(
                    foregroundColor: _faint,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: const Text('Edit'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              store.units.bestInventoryLabel(food, amount),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 26,
                fontWeight: FontWeight.w400,
              ),
            ),
            if (activeLots.isNotEmpty) ...[
              const SizedBox(height: 14),
              Row(
                children: activeLots.map((lot) {
                  final days = lot.bestBy?.difference(store.now).inDays;
                  final color = days == null
                      ? _herb
                      : days <= 3
                      ? _berry
                      : days <= 7
                      ? _amber
                      : _herb;
                  return Expanded(
                    flex: (lot.quantityBase * 100).round().clamp(1, 1000000),
                    child: Container(
                      height: 6,
                      margin: const EdgeInsets.only(right: 5),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 14),
            Text(
              '$lots ${lots == 1 ? 'lot' : 'lots'} · ${food.defaultLocation.label}',
              style: const TextStyle(color: _muted, fontSize: 12),
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
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: amount <= 0
                    ? null
                    : () => _showConsume(context, store, food),
                child: Text(
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
      eyebrow: '${store.recipes.length} recipes · ${ready.length} cookable now',
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
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
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
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 720
                ? (constraints.maxWidth - 14) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: recipes
                  .map(
                    (recipe) => SizedBox(
                      width: width,
                      child: _RecipeCard(store: store, recipe: recipe),
                    ),
                  )
                  .toList(),
            );
          },
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
      backgroundColor: (missing.isEmpty ? _herb : _amber).withValues(
        alpha: .14,
      ),
      side: BorderSide.none,
      label: Text(
        missing.isEmpty ? 'Ready' : 'Missing ${missing.length}',
        style: TextStyle(
          color: missing.isEmpty ? _herb : _amber,
          fontFamily: 'monospace',
          fontSize: 11,
        ),
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
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
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
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
                  backgroundColor: missing.containsKey(food.id)
                      ? _berry.withValues(alpha: .13)
                      : _raised,
                  label: Text(
                    store.units.ingredientLabel(food, ingredient),
                    style: TextStyle(
                      color: missing.containsKey(food.id) ? _berry : _muted,
                      fontSize: 12,
                    ),
                  ),
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
                  ).colorScheme.error.withValues(alpha: 0.10),
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
      eyebrow: isToday
          ? 'Today · ${_calendarDate(selectedDay)}'
          : _calendarDate(selectedDay),
      title: 'Food log',
      subtitle:
          'Calories and nutrients from recipes, pantry items, and food away from home.',
      action: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: () => showExternalFoodEditor(context, store),
            icon: const Icon(Icons.bookmark_add_outlined),
            label: const Text('Save food'),
          ),
          FilledButton.icon(
            onPressed: () => _showExternalMeal(context, store, selectedDay),
            icon: const Icon(Icons.add),
            label: const Text('Log food'),
          ),
        ],
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
          _NutritionSummary(
            nutrition: nutrition,
            targets: store.nutritionTargets,
            onEdit: () => _showNutritionTargets(context, store),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Known outside foods',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Text(
                'Reusable · never touches inventory',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (store.externalFoods.isEmpty)
            const _EmptyCard(
              icon: Icons.bookmarks_outlined,
              text:
                  'Save a restaurant order or packaged snack to log it again without another lookup.',
            )
          else
            ...store.externalFoods.map(
              (food) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Text(food.emoji)),
                    title: Text(food.name),
                    subtitle: Text(
                      '${food.brand.isEmpty ? food.servingLabel : '${food.brand} · ${food.servingLabel}'} · ${_nutritionLabel(food.nutrition)}',
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: 'Edit saved food',
                          onPressed: () => showExternalFoodEditor(
                            context,
                            store,
                            existing: food,
                          ),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        FilledButton(
                          onPressed: () => _showLogKnownFood(
                            context,
                            store,
                            food,
                            selectedDay,
                          ),
                          child: const Text('Log'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
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
  const _NutritionSummary({
    required this.nutrition,
    required this.targets,
    required this.onEdit,
  });
  final NutritionTotals nutrition;
  final NutritionTargets targets;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final caloriesLeft = (targets.calories - nutrition.calories)
        .clamp(0, double.infinity)
        .toDouble();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    "Today's nutrition",
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(onPressed: onEdit, child: const Text('Targets')),
              ],
            ),
            if (targets.label.isNotEmpty)
              Text(
                targets.label,
                style: const TextStyle(color: _faint, fontSize: 12),
              ),
            const SizedBox(height: 18),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 14,
              runSpacing: 6,
              children: [
                Text(
                  _compactNumber(nutrition.calories),
                  style: const TextStyle(
                    color: _amber,
                    fontFamily: 'monospace',
                    fontSize: 40,
                    height: 1,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'of ${_compactNumber(targets.calories)} cal · ${_compactNumber(caloriesLeft)} left',
                    style: const TextStyle(color: _muted, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _NutritionRow(
              label: 'Protein',
              value: nutrition.proteinG,
              target: targets.proteinG,
              unit: 'g',
              color: _herb,
            ),
            _NutritionRow(
              label: 'Carbs',
              value: nutrition.carbsG,
              target: targets.carbsG,
              unit: 'g',
              color: _amber,
            ),
            _NutritionRow(
              label: 'Fat',
              value: nutrition.fatG,
              target: targets.fatG,
              unit: 'g',
              color: _amber,
            ),
            _NutritionRow(
              label: 'Fiber',
              value: nutrition.fiberG,
              target: targets.fiberG,
              unit: 'g',
              color: _herb,
            ),
            _NutritionRow(
              label: 'Sodium',
              value: nutrition.sodiumMg,
              target: targets.sodiumMg,
              unit: 'mg',
              color: _amber,
              isLimit: true,
              bottomPadding: 0,
            ),
          ],
        ),
      ),
    );
  }
}

class _NutritionRow extends StatelessWidget {
  const _NutritionRow({
    required this.label,
    required this.value,
    required this.target,
    required this.unit,
    required this.color,
    this.isLimit = false,
    this.bottomPadding = 16,
  });

  final String label;
  final double value;
  final double target;
  final String unit;
  final Color color;
  final bool isLimit;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final percent = value / target;
    final over = isLimit && percent > 1;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 13)),
              ),
              Text(
                '${_compactNumber(value)} $unit',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              Text(
                ' / ${_compactNumber(target)} $unit',
                style: const TextStyle(
                  color: _faint,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          LinearProgressIndicator(
            value: percent.clamp(0, 1),
            minHeight: 8,
            color: over ? _berry : color,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    );
  }
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

Future<void> _showLogKnownFood(
  BuildContext context,
  PantryStore store,
  ExternalFood food,
  DateTime day,
) async {
  final servings = TextEditingController(text: '1');
  final note = TextEditingController();
  String? error;
  final submitted = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text('Log ${food.name}'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${food.servingLabel} · ${_nutritionLabel(food.nutrition)}'),
              const SizedBox(height: 14),
              TextField(
                controller: servings,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Servings eaten'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: note,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  hintText: 'Optional customizations',
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final amount = double.tryParse(servings.text.trim());
              if (amount == null || amount <= 0) {
                setDialogState(
                  () => error = 'Enter a positive serving amount.',
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
    final event = store.logExternalFood(
      food,
      servings: double.parse(servings.text.trim()),
      timestamp: DateUtils.isSameDay(day, today)
          ? today
          : DateTime(day.year, day.month, day.day, 12),
      note: note.text,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${event.label} added without changing inventory.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => store.undo(event.id),
        ),
      ),
    );
  }
  servings.dispose();
  note.dispose();
}

Future<void> _showNutritionTargets(
  BuildContext context,
  PantryStore store,
) async {
  final current = store.nutritionTargets;
  final calories = TextEditingController(
    text: _compactNumber(current.calories),
  );
  final protein = TextEditingController(text: _compactNumber(current.proteinG));
  final carbs = TextEditingController(text: _compactNumber(current.carbsG));
  final fat = TextEditingController(text: _compactNumber(current.fatG));
  final fiber = TextEditingController(text: _compactNumber(current.fiberG));
  final sodium = TextEditingController(text: _compactNumber(current.sodiumMg));
  final fields = <(String, TextEditingController, String)>[
    ('Calories', calories, 'cal'),
    ('Protein', protein, 'g'),
    ('Carbs', carbs, 'g'),
    ('Fat', fat, 'g'),
    ('Fiber', fiber, 'g'),
    ('Sodium limit', sodium, 'mg'),
  ];
  String? error;
  double? number(TextEditingController controller) =>
      double.tryParse(controller.text.trim());
  final submitted = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Daily nutrition targets'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                current.label,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
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
              const SizedBox(height: 12),
              const Text(
                'Sugar has no percentage because the log contains total sugar, while dietary guidance limits added sugar.',
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (fields.any(
                (field) => number(field.$2) == null || number(field.$2)! <= 0,
              )) {
                setDialogState(() => error = 'Every target must be positive.');
              } else {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Save targets'),
          ),
        ],
      ),
    ),
  );
  if (submitted == true) {
    store.saveNutritionTargets(
      NutritionTargets(
        calories: number(calories)!,
        proteinG: number(protein)!,
        carbsG: number(carbs)!,
        fatG: number(fat)!,
        fiberG: number(fiber)!,
        sodiumMg: number(sodium)!,
        label: current.label,
      ),
    );
  }
  for (final controller in [calories, protein, carbs, fat, fiber, sodium]) {
    controller.dispose();
  }
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
