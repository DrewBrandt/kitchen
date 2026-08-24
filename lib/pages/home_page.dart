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
const _sky = Color(0xFF70C7E8);
const _violet = Color(0xFFB89BEA);

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

  static const mobileDestinations = [
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
    NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
  ];

  int get _mobileIndex => switch (selectedIndex) {
    0 || 1 || 2 => selectedIndex,
    4 => 3,
    _ => 4,
  };

  Future<void> _openMobileMore(BuildContext context) async {
    final value = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('More'),
              subtitle: Text('Dining, meal history, and longer-term trends'),
            ),
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: const Text('Eating out'),
              onTap: () => Navigator.pop(context, 3),
            ),
            ListTile(
              leading: const Icon(Icons.history_outlined),
              title: const Text('History'),
              onTap: () => Navigator.pop(context, 5),
            ),
            ListTile(
              leading: const Icon(Icons.show_chart_outlined),
              title: const Text('Trends'),
              onTap: () => Navigator.pop(context, 6),
            ),
          ],
        ),
      ),
    );
    if (value != null && mounted) setState(() => selectedIndex = value);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _Dashboard(
        store: widget.store,
        onOpenInventory: () => setState(() => selectedIndex = 1),
        onOpenRecipes: () => setState(() => selectedIndex = 2),
        onOpenFoodLog: () => setState(() => selectedIndex = 4),
      ),
      _InventoryPage(store: widget.store),
      _RecipesPage(store: widget.store),
      _EatingOutPage(store: widget.store),
      _FoodLogPage(store: widget.store),
      _HistoryPage(store: widget.store),
      _TrendsPage(store: widget.store),
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
              labelBehavior:
                  NavigationDestinationLabelBehavior.onlyShowSelected,
              selectedIndex: _mobileIndex,
              destinations: mobileDestinations,
              onDestinationSelected: (value) {
                if (value <= 2) {
                  setState(() => selectedIndex = value);
                } else if (value == 3) {
                  setState(() => selectedIndex = 4);
                } else {
                  _openMobileMore(context);
                }
              },
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
                externalFoodCount: widget.store.externalFoods.length,
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
    required this.externalFoodCount,
    required this.onSelected,
    required this.onSignOut,
  });

  final int selectedIndex;
  final int inventoryCount;
  final int recipeCount;
  final int externalFoodCount;
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
            _SidebarDestination(
              label: 'Eating out',
              badge: '$externalFoodCount',
              selected: selectedIndex == 3,
              onTap: () => onSelected(3),
            ),
            const SizedBox(height: 24),
            const _NavGroupLabel('Eating'),
            _SidebarDestination(
              label: 'Food log',
              selected: selectedIndex == 4,
              onTap: () => onSelected(4),
            ),
            _SidebarDestination(
              label: 'History',
              selected: selectedIndex == 5,
              onTap: () => onSelected(5),
            ),
            _SidebarDestination(
              label: 'Trends',
              selected: selectedIndex == 6,
              onTap: () => onSelected(6),
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
                  height: 340,
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
            const Spacer(),
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
            final cardHeight = constraints.maxWidth < 480 ? 560.0 : 450.0;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: recipes
                  .map(
                    (recipe) => SizedBox(
                      width: width,
                      height: cardHeight,
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
            const Spacer(),
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

class _EatingOutPage extends StatelessWidget {
  const _EatingOutPage({required this.store});

  final PantryStore store;

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<ExternalFood>>{};
    for (final food in store.externalFoods) {
      final place = food.brand.trim().isEmpty ? 'Other' : food.brand.trim();
      grouped.putIfAbsent(place, () => []).add(food);
    }
    final places = grouped.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    for (final place in places) {
      place.value.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    }

    return _PageShell(
      eyebrow:
          '${store.externalFoods.length} saved items · ${places.length} ${places.length == 1 ? 'place' : 'places'}',
      title: 'Eating out',
      subtitle:
          'Restaurant and packaged foods that never touch inventory — saved once, logged in a tap.',
      action: FilledButton.icon(
        onPressed: () => showExternalFoodEditor(context, store),
        icon: const Icon(Icons.add),
        label: const Text('Save food'),
      ),
      child: places.isEmpty
          ? const _EmptyCard(
              icon: Icons.storefront_outlined,
              text:
                  'Save a restaurant order or packaged food, then it will appear here under its place or brand.',
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth >= 760
                    ? (constraints.maxWidth - 14) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: places
                      .map(
                        (place) => SizedBox(
                          width: width,
                          child: _EatingOutPlaceCard(
                            store: store,
                            name: place.key,
                            foods: place.value,
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
    );
  }
}

class _EatingOutPlaceCard extends StatelessWidget {
  const _EatingOutPlaceCard({
    required this.store,
    required this.name,
    required this.foods,
  });

  final PantryStore store;
  final String name;
  final List<ExternalFood> foods;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _raised,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _initials(name),
                  style: const TextStyle(
                    color: _muted,
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${foods.length} saved ${foods.length == 1 ? 'item' : 'items'}',
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...foods.map(
            (food) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
                decoration: BoxDecoration(
                  color: _raised,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Text(food.emoji, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(food.name, style: const TextStyle(fontSize: 13)),
                          const SizedBox(height: 4),
                          Text(
                            '${food.servingLabel} · ${_nutritionLabel(food.nutrition)}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _faint,
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Edit ${food.name}',
                      onPressed: () => showExternalFoodEditor(
                        context,
                        store,
                        existing: food,
                      ),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      color: _faint,
                      visualDensity: VisualDensity.compact,
                    ),
                    OutlinedButton(
                      onPressed: () => _showLogKnownFood(
                        context,
                        store,
                        food,
                        DateTime.now(),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        minimumSize: const Size(0, 32),
                      ),
                      child: const Text('Log'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _HistoryPage extends StatefulWidget {
  const _HistoryPage({required this.store});
  final PantryStore store;

  @override
  State<_HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<_HistoryPage> {
  int rangeDays = 14;

  @override
  Widget build(BuildContext context) {
    final events = _eventsInRange(widget.store, rangeDays);
    final groups = _groupEventsByDay(events);
    final repeats = _mealFrequencies(events);
    final repeatedCount = repeats.where((item) => item.count >= 3).length;
    final range = _rangeLabel(rangeDays);
    final subtitle = events.isEmpty
        ? 'No meals logged in this range yet.'
        : '${events.length} meals · ${repeats.length} distinct foods · '
              '$repeatedCount repeated three times or more';
    return _PageShell(
      eyebrow: range,
      title: 'History',
      subtitle: subtitle,
      action: _RangePicker(
        values: const [7, 14, 30],
        labels: const ['1 week', '2 weeks', '30 days'],
        selected: rangeDays,
        onSelected: (value) => setState(() => rangeDays = value),
      ),
      child: events.isEmpty
          ? const _EmptyCard(
              icon: Icons.history_outlined,
              text: 'Your meals will appear here as you cook or log food.',
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final timeline = _HistoryTimeline(
                  groups: groups,
                  frequencies: {
                    for (final item in repeats) item.key: item.count,
                  },
                );
                final repeated = _RepeatedMealsCard(items: repeats);
                if (constraints.maxWidth < 820) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [timeline, const SizedBox(height: 18), repeated],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: timeline),
                    const SizedBox(width: 20),
                    Expanded(child: repeated),
                  ],
                );
              },
            ),
    );
  }
}

class _HistoryTimeline extends StatelessWidget {
  const _HistoryTimeline({required this.groups, required this.frequencies});
  final List<_DayEvents> groups;
  final Map<String, int> frequencies;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Day by day',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          for (final (index, group) in groups.indexed) ...[
            _HistoryDayRow(group: group, frequencies: frequencies),
            if (index != groups.length - 1)
              const Divider(height: 30, color: _border),
          ],
        ],
      ),
    ),
  );
}

class _HistoryDayRow extends StatelessWidget {
  const _HistoryDayRow({required this.group, required this.frequencies});
  final _DayEvents group;
  final Map<String, int> frequencies;

  @override
  Widget build(BuildContext context) {
    final total = group.events.fold(
      const NutritionTotals(),
      (sum, event) => sum + (event.nutrition ?? const NutritionTotals()),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final date = SizedBox(
          width: constraints.maxWidth < 520 ? 82 : 92,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _weekdayLabel(group.day),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _monthDay(group.day),
                style: const TextStyle(
                  color: _faint,
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ],
          ),
        );
        final meals = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: group.events.map((event) {
            final repeats = frequencies[_mealKey(event.label)] ?? 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Wrap(
                spacing: 8,
                runSpacing: 5,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Icon(_eventIcon(event.kind), size: 16, color: _muted),
                  Text(event.label, style: const TextStyle(fontSize: 13)),
                  if (repeats > 1)
                    _SmallBadge(
                      label: '$repeats× in range',
                      color: repeats >= 3 ? _amber : _faint,
                    ),
                ],
              ),
            );
          }).toList(),
        );
        final nutrition = Text(
          '${total.calories.round()} cal\n${_compactNumber(total.proteinG)}g protein',
          textAlign: TextAlign.right,
          style: const TextStyle(
            color: _muted,
            fontFamily: 'monospace',
            fontSize: 11,
            height: 1.55,
          ),
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            date,
            const SizedBox(width: 10),
            Expanded(child: meals),
            if (constraints.maxWidth >= 450) ...[
              const SizedBox(width: 12),
              nutrition,
            ],
          ],
        );
      },
    );
  }
}

class _RepeatedMealsCard extends StatelessWidget {
  const _RepeatedMealsCard({required this.items});
  final List<_MealFrequency> items;

  @override
  Widget build(BuildContext context) {
    final visible = items.take(6).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Most repeated',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 5),
            const Text(
              'Useful context when planning for more variety.',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            for (final (index, item) in visible.indexed) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _raised,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      '${item.count}×',
                      style: const TextStyle(
                        color: _amber,
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.label, style: const TextStyle(fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(
                          'Last had ${_relativeMealDate(item.lastEaten)}',
                          style: const TextStyle(color: _faint, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (index != visible.length - 1)
                const Divider(height: 24, color: _border),
            ],
          ],
        ),
      ),
    );
  }
}

class _TrendsPage extends StatefulWidget {
  const _TrendsPage({required this.store});
  final PantryStore store;

  @override
  State<_TrendsPage> createState() => _TrendsPageState();
}

class _TrendsPageState extends State<_TrendsPage> {
  int rangeDays = 30;
  _DriverMetric driver = _DriverMetric.protein;

  @override
  Widget build(BuildContext context) {
    final events = _eventsInRange(widget.store, rangeDays);
    final days = _dailyNutrition(events, rangeDays);
    final totals = days.fold(
      const NutritionTotals(),
      (sum, item) => sum + item.nutrition,
    );
    final average = totals.scale(1 / rangeDays);
    return _PageShell(
      eyebrow: _rangeLabel(rangeDays),
      title: 'Trends',
      subtitle:
          'Daily nutrition, target comparisons, and the foods driving each nutrient.',
      action: _RangePicker(
        values: const [7, 30, 90],
        labels: const ['7 days', '30 days', '90 days'],
        selected: rangeDays,
        onSelected: (value) => setState(() => rangeDays = value),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProteinTrendCard(
            days: days,
            target: widget.store.nutritionTargets.proteinG,
            average: average.proteinG,
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final averages = _AverageTargetsCard(
                average: average,
                targets: widget.store.nutritionTargets,
              );
              final drivers = _NutrientDriversCard(
                events: events,
                selected: driver,
                onSelected: (value) => setState(() => driver = value),
              );
              if (constraints.maxWidth < 820) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [averages, const SizedBox(height: 20), drivers],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: averages),
                  const SizedBox(width: 20),
                  Expanded(child: drivers),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ProteinTrendCard extends StatelessWidget {
  const _ProteinTrendCard({
    required this.days,
    required this.target,
    required this.average,
  });
  final List<_DailyNutrition> days;
  final double target;
  final double average;

  @override
  Widget build(BuildContext context) {
    final peak = days.fold(target, (value, day) {
      return day.nutrition.proteinG > value ? day.nutrition.proteinG : value;
    });
    final chartMax = peak <= 0 ? 1.0 : peak * 1.2;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Protein, day by day',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Average ${_compactNumber(average)}g per day',
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                _SmallBadge(
                  label: 'Target ${_compactNumber(target)}g',
                  color: _herb,
                ),
              ],
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 190,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final chartWidth = days.length > 31
                      ? days.length * 13.0
                      : constraints.maxWidth;
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: days.length > 31,
                    child: SizedBox(
                      width: chartWidth,
                      child: Stack(
                        children: [
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 28 + 138 * target / chartMax,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Container(height: 1, color: _herb),
                                ),
                              ],
                            ),
                          ),
                          Positioned.fill(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: days.map((day) {
                                final height =
                                    138 * day.nutrition.proteinG / chartMax;
                                return Expanded(
                                  child: Tooltip(
                                    message:
                                        '${_monthDay(day.day)} · ${_compactNumber(day.nutrition.proteinG)}g protein',
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 2,
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          Container(
                                            height: height,
                                            decoration: BoxDecoration(
                                              color:
                                                  day.nutrition.proteinG >=
                                                      target
                                                  ? _herb
                                                  : _sky,
                                              borderRadius:
                                                  const BorderRadius.vertical(
                                                    top: Radius.circular(4),
                                                  ),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            day.day.day == 1 ||
                                                    days.length <= 14 ||
                                                    day == days.last
                                                ? '${day.day.month}/${day.day.day}'
                                                : '',
                                            style: const TextStyle(
                                              color: _faint,
                                              fontFamily: 'monospace',
                                              fontSize: 9,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AverageTargetsCard extends StatelessWidget {
  const _AverageTargetsCard({required this.average, required this.targets});
  final NutritionTotals average;
  final NutritionTargets targets;

  @override
  Widget build(BuildContext context) {
    final rows = [
      _TargetComparison('Calories', average.calories, targets.calories, 'cal'),
      _TargetComparison('Protein', average.proteinG, targets.proteinG, 'g'),
      _TargetComparison('Carbs', average.carbsG, targets.carbsG, 'g'),
      _TargetComparison('Fat', average.fatG, targets.fatG, 'g'),
      _TargetComparison('Fiber', average.fiberG, targets.fiberG, 'g'),
      _TargetComparison(
        'Sodium',
        average.sodiumMg,
        targets.sodiumMg,
        'mg',
        isLimit: true,
      ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Daily average vs. target',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 5),
            const Text(
              'Average across every calendar day in the selected range.',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 20),
            for (final row in rows) _TargetComparisonRow(item: row),
          ],
        ),
      ),
    );
  }
}

class _TargetComparisonRow extends StatelessWidget {
  const _TargetComparisonRow({required this.item});
  final _TargetComparison item;

  @override
  Widget build(BuildContext context) {
    final ratio = item.target <= 0 ? 0.0 : item.value / item.target;
    final caution = item.isLimit && ratio > 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text(item.label)),
              Text(
                '${_compactNumber(item.value)} / ${_compactNumber(item.target)} ${item.unit}',
                style: TextStyle(
                  color: caution ? _berry : _muted,
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio.clamp(0, 1),
              minHeight: 7,
              backgroundColor: _raised,
              color: caution ? _berry : _amber,
            ),
          ),
        ],
      ),
    );
  }
}

class _NutrientDriversCard extends StatelessWidget {
  const _NutrientDriversCard({
    required this.events,
    required this.selected,
    required this.onSelected,
  });
  final List<ConsumptionEvent> events;
  final _DriverMetric selected;
  final ValueChanged<_DriverMetric> onSelected;

  @override
  Widget build(BuildContext context) {
    final contributors = _nutrientContributors(events, selected);
    final max = contributors.isEmpty ? 1.0 : contributors.first.value;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'What drives each nutrient',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: _DriverMetric.values.map((metric) {
                return ChoiceChip(
                  label: Text(metric.label),
                  selected: selected == metric,
                  onSelected: (_) => onSelected(metric),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            if (contributors.isEmpty)
              const Text(
                'No nutrition data in this range.',
                style: TextStyle(color: _muted),
              )
            else
              for (final item in contributors.take(6))
                Padding(
                  padding: const EdgeInsets.only(bottom: 15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          Text(
                            '${_compactNumber(item.value)}${selected.unit}',
                            style: const TextStyle(
                              color: _muted,
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: max <= 0 ? 0 : item.value / max,
                        child: Container(
                          height: 7,
                          decoration: BoxDecoration(
                            color: selected.color,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _RangePicker extends StatelessWidget {
  const _RangePicker({
    required this.values,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });
  final List<int> values;
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 7,
    runSpacing: 7,
    children: values.indexed.map((entry) {
      final (index, value) = entry;
      return ChoiceChip(
        label: Text(labels[index]),
        selected: selected == value,
        onSelected: (_) => onSelected(value),
      );
    }).toList(),
  );
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontFamily: 'monospace', fontSize: 10),
    ),
  );
}

class _DayEvents {
  const _DayEvents(this.day, this.events);
  final DateTime day;
  final List<ConsumptionEvent> events;
}

class _MealFrequency {
  const _MealFrequency({
    required this.key,
    required this.label,
    required this.count,
    required this.lastEaten,
  });
  final String key;
  final String label;
  final int count;
  final DateTime lastEaten;
}

class _DailyNutrition {
  const _DailyNutrition(this.day, this.nutrition);
  final DateTime day;
  final NutritionTotals nutrition;
}

class _TargetComparison {
  const _TargetComparison(
    this.label,
    this.value,
    this.target,
    this.unit, {
    this.isLimit = false,
  });
  final String label;
  final double value;
  final double target;
  final String unit;
  final bool isLimit;
}

enum _DriverMetric {
  protein('Protein', 'g', _herb),
  sodium('Sodium', 'mg', _berry),
  fiber('Fiber', 'g', _amber),
  sugar('Sugar', 'g', _violet);

  const _DriverMetric(this.label, this.unit, this.color);
  final String label;
  final String unit;
  final Color color;

  double value(NutritionTotals nutrition) => switch (this) {
    _DriverMetric.protein => nutrition.proteinG,
    _DriverMetric.sodium => nutrition.sodiumMg,
    _DriverMetric.fiber => nutrition.fiberG,
    _DriverMetric.sugar => nutrition.sugarG,
  };
}

class _NutrientContributor {
  const _NutrientContributor(this.label, this.value);
  final String label;
  final double value;
}

List<ConsumptionEvent> _eventsInRange(PantryStore store, int days) {
  final now = DateTime.now();
  final cutoff = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(Duration(days: days - 1));
  return store.history
      .where(
        (event) => event.undoneAt == null && !event.timestamp.isBefore(cutoff),
      )
      .toList()
    ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
}

List<_DayEvents> _groupEventsByDay(List<ConsumptionEvent> events) {
  final grouped = <DateTime, List<ConsumptionEvent>>{};
  for (final event in events) {
    final day = DateTime(
      event.timestamp.year,
      event.timestamp.month,
      event.timestamp.day,
    );
    grouped.putIfAbsent(day, () => []).add(event);
  }
  return grouped.entries
      .map((entry) => _DayEvents(entry.key, entry.value))
      .toList()
    ..sort((a, b) => b.day.compareTo(a.day));
}

List<_MealFrequency> _mealFrequencies(List<ConsumptionEvent> events) {
  final grouped = <String, List<ConsumptionEvent>>{};
  for (final event in events) {
    grouped.putIfAbsent(_mealKey(event.label), () => []).add(event);
  }
  final result = grouped.entries.map((entry) {
    entry.value.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return _MealFrequency(
      key: entry.key,
      label: entry.value.first.label,
      count: entry.value.length,
      lastEaten: entry.value.first.timestamp,
    );
  }).toList();
  result.sort((a, b) {
    final count = b.count.compareTo(a.count);
    return count != 0 ? count : b.lastEaten.compareTo(a.lastEaten);
  });
  return result;
}

List<_DailyNutrition> _dailyNutrition(List<ConsumptionEvent> events, int days) {
  final now = DateTime.now();
  final first = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(Duration(days: days - 1));
  final totals = <DateTime, NutritionTotals>{};
  for (final event in events) {
    final day = DateTime(
      event.timestamp.year,
      event.timestamp.month,
      event.timestamp.day,
    );
    totals[day] =
        (totals[day] ?? const NutritionTotals()) +
        (event.nutrition ?? const NutritionTotals());
  }
  return List.generate(days, (index) {
    final day = first.add(Duration(days: index));
    return _DailyNutrition(day, totals[day] ?? const NutritionTotals());
  });
}

List<_NutrientContributor> _nutrientContributors(
  List<ConsumptionEvent> events,
  _DriverMetric metric,
) {
  final labels = <String, String>{};
  final totals = <String, double>{};
  for (final event in events) {
    final key = _mealKey(event.label);
    labels[key] = event.label;
    totals[key] =
        (totals[key] ?? 0) +
        metric.value(event.nutrition ?? const NutritionTotals());
  }
  final result = totals.entries
      .where((entry) => entry.value > 0)
      .map((entry) => _NutrientContributor(labels[entry.key]!, entry.value))
      .toList();
  result.sort((a, b) => b.value.compareTo(a.value));
  return result;
}

String _mealKey(String label) => label.trim().toLowerCase();

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
          _MealContributionChart(
            events: events,
            nutrition: nutrition,
            targets: store.nutritionTargets,
            onEdit: () => _showNutritionTargets(context, store),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Meals and snacks',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Text(
                '${events.length} ${events.length == 1 ? 'entry' : 'entries'}',
                style: const TextStyle(
                  color: _faint,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ],
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
                padding: const EdgeInsets.only(bottom: 9),
                child: _FoodLogEventCard(
                  event: event,
                  onUndo: () => store.undo(event.id),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MealContributionChart extends StatelessWidget {
  const _MealContributionChart({
    required this.events,
    required this.nutrition,
    required this.targets,
    required this.onEdit,
  });

  final List<ConsumptionEvent> events;
  final NutritionTotals nutrition;
  final NutritionTargets targets;
  final VoidCallback onEdit;

  static const colors = [_amber, _herb, _sky, _berry, _violet];

  @override
  Widget build(BuildContext context) {
    final rows = <_ContributionMetric>[
      _ContributionMetric(
        label: 'Calories',
        unit: 'cal',
        target: targets.calories,
        total: nutrition.calories,
        value: (n) => n.calories,
      ),
      _ContributionMetric(
        label: 'Protein',
        unit: 'g',
        target: targets.proteinG,
        total: nutrition.proteinG,
        value: (n) => n.proteinG,
      ),
      _ContributionMetric(
        label: 'Carbs',
        unit: 'g',
        target: targets.carbsG,
        total: nutrition.carbsG,
        value: (n) => n.carbsG,
      ),
      _ContributionMetric(
        label: 'Fat',
        unit: 'g',
        target: targets.fatG,
        total: nutrition.fatG,
        value: (n) => n.fatG,
      ),
      _ContributionMetric(
        label: 'Fiber',
        unit: 'g',
        target: targets.fiberG,
        total: nutrition.fiberG,
        value: (n) => n.fiberG,
      ),
      _ContributionMetric(
        label: 'Sodium',
        unit: 'mg',
        target: targets.sodiumMg,
        total: nutrition.sodiumMg,
        value: (n) => n.sodiumMg,
        isLimit: true,
      ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'How each food built your day',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Each color is one logged food or meal.',
                        style: TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                TextButton(onPressed: onEdit, child: const Text('Targets')),
              ],
            ),
            const SizedBox(height: 18),
            if (events.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Log something to see where today’s nutrients came from.',
                  style: TextStyle(color: _muted),
                ),
              )
            else ...[
              Wrap(
                spacing: 16,
                runSpacing: 10,
                children: events.indexed.map((entry) {
                  final (index, event) = entry;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: colors[index % colors.length],
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        event.label,
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  );
                }).toList(),
              ),
              const SizedBox(height: 22),
              ...rows.map(
                (metric) => _ContributionRow(
                  metric: metric,
                  events: events,
                  colors: colors,
                ),
              ),
              const SizedBox(height: 4),
              const Row(
                children: [
                  SizedBox(
                    width: 2,
                    height: 12,
                    child: ColoredBox(color: _ink),
                  ),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'The white mark is your daily target; sodium’s is a limit.',
                      style: TextStyle(color: _faint, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ContributionMetric {
  const _ContributionMetric({
    required this.label,
    required this.unit,
    required this.target,
    required this.total,
    required this.value,
    this.isLimit = false,
  });

  final String label;
  final String unit;
  final double target;
  final double total;
  final double Function(NutritionTotals) value;
  final bool isLimit;
}

class _ContributionRow extends StatelessWidget {
  const _ContributionRow({
    required this.metric,
    required this.events,
    required this.colors,
  });

  final _ContributionMetric metric;
  final List<ConsumptionEvent> events;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 15),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final bar = _ContributionBar(
          values: events
              .map(
                (event) =>
                    metric.value(event.nutrition ?? const NutritionTotals()),
              )
              .toList(),
          colors: colors,
          target: metric.target,
          total: metric.total,
          isLimit: metric.isLimit,
        );
        final value = Text(
          '${_compactNumber(metric.total)} of ${_compactNumber(metric.target)} ${metric.unit}',
          textAlign: TextAlign.right,
          style: TextStyle(
            color: metric.isLimit && metric.total > metric.target
                ? _berry
                : _muted,
            fontFamily: 'monospace',
            fontSize: 12,
          ),
        );
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      metric.label,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  value,
                ],
              ),
              const SizedBox(height: 7),
              bar,
            ],
          );
        }
        return Row(
          children: [
            SizedBox(
              width: 74,
              child: Text(metric.label, style: const TextStyle(fontSize: 13)),
            ),
            Expanded(child: bar),
            const SizedBox(width: 14),
            SizedBox(width: 136, child: value),
          ],
        );
      },
    ),
  );
}

class _ContributionBar extends StatelessWidget {
  const _ContributionBar({
    required this.values,
    required this.colors,
    required this.target,
    required this.total,
    required this.isLimit,
  });

  final List<double> values;
  final List<Color> colors;
  final double target;
  final double total;
  final bool isLimit;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 22,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final max = target * 1.25;
        final scale = total > max && total > 0 ? max / total : 1.0;
        final segments = <Widget>[];
        var left = 0.0;
        for (final (index, rawValue) in values.indexed) {
          final width = max == 0
              ? 0.0
              : constraints.maxWidth * rawValue * scale / max;
          if (width > 0) {
            segments.add(
              Positioned(
                left: left,
                top: 0,
                bottom: 0,
                width: width,
                child: ColoredBox(color: colors[index % colors.length]),
              ),
            );
          }
          left += width;
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: _raised)),
              ...segments,
              if (isLimit && total > target)
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: constraints.maxWidth * .8,
                  right: 0,
                  child: ColoredBox(color: _berry.withValues(alpha: .12)),
                ),
              Positioned(
                top: 0,
                bottom: 0,
                left: constraints.maxWidth * .8,
                child: const SizedBox(width: 2, child: ColoredBox(color: _ink)),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _FoodLogEventCard extends StatelessWidget {
  const _FoodLogEventCard({required this.event, required this.onUndo});

  final ConsumptionEvent event;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final source =
        '${_eventSource(event)}${event.note.isEmpty ? '' : ' · ${event.note}'}';
    final nutrition = event.nutrition == null
        ? 'No nutrition data'
        : _nutritionLabel(event.nutrition!);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: _border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final identity = Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _raised,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(_eventIcon(event.kind), size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.label,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        source,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            );
            final action = TextButton(
              onPressed: onUndo,
              style: TextButton.styleFrom(
                foregroundColor: _faint,
                minimumSize: const Size(64, 36),
              ),
              child: Text(
                event.kind == ConsumptionKind.external ? 'Remove' : 'Undo',
              ),
            );
            if (constraints.maxWidth < 620) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  identity,
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          nutrition,
                          style: const TextStyle(
                            color: _muted,
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ),
                      action,
                    ],
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: identity),
                const SizedBox(width: 18),
                Text(
                  nutrition,
                  style: const TextStyle(
                    color: _muted,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 12),
                action,
              ],
            );
          },
        ),
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

String _rangeLabel(int days) {
  final end = DateTime.now();
  final start = DateTime(
    end.year,
    end.month,
    end.day,
  ).subtract(Duration(days: days - 1));
  return '${_monthDay(start)} – ${_monthDay(end)}';
}

String _monthDay(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}';
}

String _weekdayLabel(DateTime date) {
  const days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  final today = DateTime.now();
  if (DateUtils.isSameDay(date, today)) return 'Today';
  if (DateUtils.isSameDay(date, today.subtract(const Duration(days: 1)))) {
    return 'Yesterday';
  }
  return days[date.weekday - 1];
}

String _relativeMealDate(DateTime date) {
  final now = DateTime.now();
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(date.year, date.month, date.day)).inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  return '$days days ago';
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

String _initials(String value) {
  final words = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) return '—';
  if (words.length == 1) {
    final word = words.first;
    return word.substring(0, word.length >= 2 ? 2 : 1).toUpperCase();
  }
  return '${words.first[0]}${words.last[0]}'.toUpperCase();
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
