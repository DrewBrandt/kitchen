import 'package:flutter/material.dart';

import '../data/pantry_store.dart';
import '../models/pantry_models.dart';
import '../widgets/food_editor_dialog.dart';
import '../widgets/external_food_editor_dialog.dart';
import '../widgets/grocery_import_dialog.dart';
import '../widgets/calendar_sync_card.dart';
import '../widgets/barcode_scanner_dialog.dart';
import '../widgets/product_editor_dialog.dart';
import '../widgets/recipe_editor_dialog.dart';
import '../widgets/recipe_detail_dialog.dart';
import '../widgets/recipe_feedback_dialog.dart';
import '../widgets/recipe_portion_dialog.dart';

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
      icon: Icon(Icons.shopping_cart_outlined),
      selectedIcon: Icon(Icons.shopping_cart),
      label: 'Grocery',
    ),
    NavigationDestination(
      icon: Icon(Icons.menu_book_outlined),
      selectedIcon: Icon(Icons.menu_book),
      label: 'Recipes',
    ),
    NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
  ];

  int get _mobileIndex => switch (selectedIndex) {
    0 || 1 => selectedIndex,
    8 => 2,
    2 => 3,
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
              subtitle: Text('Planning, dining, food log, and history'),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('This week'),
              onTap: () => Navigator.pop(context, 7),
            ),
            ListTile(
              leading: const Icon(Icons.monitor_heart_outlined),
              title: const Text('Food log'),
              onTap: () => Navigator.pop(context, 4),
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
            ListTile(
              leading: const Icon(Icons.tune_outlined),
              title: const Text('Me'),
              onTap: () => Navigator.pop(context, -1),
            ),
          ],
        ),
      ),
    );
    if (value == -1 && context.mounted) {
      await _showFoodPreferences(context, widget.store);
    } else if (value != null && mounted) {
      setState(() => selectedIndex = value);
    }
  }

  @override
  Widget build(BuildContext context) {
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
              Expanded(
                child: switch (selectedIndex) {
                  0 => _Dashboard(
                    store: widget.store,
                    onOpenInventory: () => setState(() => selectedIndex = 1),
                    onOpenRecipes: () => setState(() => selectedIndex = 2),
                    onOpenFoodLog: () => setState(() => selectedIndex = 4),
                    onOpenPlan: () => setState(() => selectedIndex = 7),
                  ),
                  1 => _InventoryPage(store: widget.store),
                  2 => _RecipesPage(store: widget.store),
                  3 => _EatingOutPage(store: widget.store),
                  4 => _FoodLogPage(store: widget.store),
                  5 => _HistoryPage(store: widget.store),
                  6 => _TrendsPage(store: widget.store),
                  7 => _PlanningPage(store: widget.store),
                  _ => _GroceryListPage(store: widget.store),
                },
              ),
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
                if (value <= 1) {
                  setState(() => selectedIndex = value);
                } else if (value == 2) {
                  setState(() => selectedIndex = 8);
                } else if (value == 3) {
                  setState(() => selectedIndex = 2);
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
                planCount: _plannedMealGroupCount(widget.store.plannedMeals),
                groceryCount: widget.store.groceryItems
                    .where((item) => !item.checked)
                    .length,
                onSelected: (value) => setState(() => selectedIndex = value),
                onFoodProfile: () =>
                    _showFoodPreferences(context, widget.store),
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
    required this.planCount,
    required this.groceryCount,
    required this.onSelected,
    required this.onFoodProfile,
    required this.onSignOut,
  });

  final int selectedIndex;
  final int inventoryCount;
  final int recipeCount;
  final int externalFoodCount;
  final int planCount;
  final int groceryCount;
  final ValueChanged<int> onSelected;
  final VoidCallback onFoodProfile;
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
            const SizedBox(height: 24),
            const _NavGroupLabel('Planning'),
            _SidebarDestination(
              label: 'This week',
              badge: '$planCount',
              selected: selectedIndex == 7,
              onTap: () => onSelected(7),
            ),
            _SidebarDestination(
              label: 'Grocery list',
              badge: '$groceryCount',
              selected: selectedIndex == 8,
              onTap: () => onSelected(8),
            ),
            const Spacer(),
            const Divider(),
            const SizedBox(height: 8),
            InkWell(
              onTap: onFoodProfile,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 13,
                      backgroundColor: Color(0xFF313A35),
                      child: Icon(
                        Icons.person_outline,
                        size: 15,
                        color: _muted,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Drew', style: TextStyle(color: _muted)),
                          Text(
                            'Routine & food profile',
                            style: TextStyle(color: _faint, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.tune_outlined, size: 16, color: _faint),
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onSignOut,
                style: TextButton.styleFrom(
                  foregroundColor: _faint,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  textStyle: const TextStyle(fontSize: 11),
                ),
                child: const Text('Sign out'),
              ),
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
    required this.onOpenPlan,
  });

  final PantryStore store;
  final VoidCallback onOpenInventory;
  final VoidCallback onOpenRecipes;
  final VoidCallback onOpenFoodLog;
  final VoidCallback onOpenPlan;

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
    final today = DateTime(store.now.year, store.now.month, store.now.day);
    final upcomingMeals = store.plannedMeals
        .where((meal) => meal.completedAt == null && !meal.date.isBefore(today))
        .toList();
    final upcoming = upcomingMeals.isEmpty ? null : upcomingMeals.first;
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
              final side = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _UpcomingPlanCard(
                    store: store,
                    meal: upcoming,
                    onOpenPlan: onOpenPlan,
                  ),
                  const SizedBox(height: 18),
                  _UseSoonCard(store: store, expiring: expiring),
                ],
              );
              if (stacked) {
                return Column(
                  children: [nutrition, const SizedBox(height: 18), side],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: nutrition),
                  const SizedBox(width: 18),
                  Expanded(child: side),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          _PreparedFoodSection(store: store),
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

class _PreparedFoodSection extends StatelessWidget {
  const _PreparedFoodSection({required this.store});

  final PantryStore store;

  @override
  Widget build(BuildContext context) {
    final batches = store.activePreparedBatches;
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
                        'Ready to eat',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Leftovers and prepared food are separate from raw inventory.',
                        style: TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _showAddPreparedFood(context, store),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add leftover'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (batches.isEmpty)
              const _EmptyCard(
                icon: Icons.ramen_dining_outlined,
                text: 'Make a recipe or add a ready-made leftover.',
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth >= 760
                      ? (constraints.maxWidth - 12) / 2
                      : constraints.maxWidth;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: batches
                        .map(
                          (batch) => SizedBox(
                            width: width,
                            child: _PreparedFoodCard(
                              store: store,
                              batch: batch,
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _PreparedFoodCard extends StatelessWidget {
  const _PreparedFoodCard({required this.store, required this.batch});

  final PantryStore store;
  final PreparedBatch batch;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _raised,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(batch.emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    batch.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${store.units.formatAmount(batch.remainingServings)} of ${store.units.formatAmount(batch.totalServings)} servings · ${batch.location.label}',
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'move') {
                  store.updatePreparedBatch(
                    batch,
                    location: batch.location == StorageLocation.fridge
                        ? StorageLocation.freezer
                        : StorageLocation.fridge,
                  );
                } else if (value == 'adjust') {
                  _showAdjustPreparedFood(context, store, batch);
                } else if (value == 'discard') {
                  store.updatePreparedBatch(batch, discard: true);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'move',
                  child: Text(
                    batch.location == StorageLocation.fridge
                        ? 'Move to freezer'
                        : 'Move to fridge',
                  ),
                ),
                const PopupMenuItem(
                  value: 'adjust',
                  child: Text('Adjust servings'),
                ),
                const PopupMenuItem(
                  value: 'discard',
                  child: Text('Discard remainder'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (batch.bestBy != null)
              Expanded(
                child: Text(
                  'Best by ${_monthDay(batch.bestBy!)}',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              )
            else
              const Spacer(),
            FilledButton(
              onPressed: () => _showEatPreparedFood(context, store, batch),
              child: const Text('Eat'),
            ),
          ],
        ),
      ],
    ),
  );
}

class _UpcomingPlanCard extends StatelessWidget {
  const _UpcomingPlanCard({
    required this.store,
    required this.meal,
    required this.onOpenPlan,
  });

  final PantryStore store;
  final PlannedMeal? meal;
  final VoidCallback onOpenPlan;

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
                  meal == null
                      ? 'Nothing planned yet'
                      : DateUtils.isSameDay(meal!.date, store.now)
                      ? 'On the plan today'
                      : 'Next on the plan',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(onPressed: onOpenPlan, child: const Text('Week')),
            ],
          ),
          const SizedBox(height: 12),
          if (meal == null)
            InkWell(
              onTap: onOpenPlan,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _raised,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.add_circle_outline, color: _amber),
                    SizedBox(width: 12),
                    Expanded(child: Text('Plan a meal for this week')),
                  ],
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _raised,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Text(meal!.emoji, style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          meal!.name,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${meal!.slot.label} · ${_shortPlanDate(meal!.date)} · ${_compactNumber(meal!.servings)} servings',
                          style: const TextStyle(color: _muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () =>
                        _completePlannedMeal(context, store, meal!),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      minimumSize: const Size(0, 34),
                    ),
                    child: Text(
                      meal!.source == PlannedMealSource.recipe ||
                              meal!.source == PlannedMealSource.meal
                          ? 'Eat'
                          : 'Done',
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
        'Ingredients grouped in Waugh Chapel Safeway walking order, with meal-planning roles.',
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
          onPressed: () async {
            final product = await scanProductBarcode(context, store);
            if (product != null && context.mounted) {
              await _showAddLot(context, store, initialProduct: product);
            }
          },
          icon: const Icon(Icons.barcode_reader),
          label: const Text('Scan barcode'),
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
        final grouped = <GrocerySection, List<FoodDefinition>>{};
        for (final food in store.foods) {
          grouped.putIfAbsent(food.grocerySection, () => []).add(food);
        }
        for (final foods in grouped.values) {
          foods.sort((a, b) => a.name.compareTo(b.name));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final section in GrocerySection.values)
              if (grouped[section]?.isNotEmpty == true) ...[
                _InventorySectionHeading(
                  section: section,
                  count: grouped[section]!.length,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: grouped[section]!
                      .map(
                        (food) => SizedBox(
                          width: width,
                          height: 340,
                          child: _FoodCard(store: store, food: food),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 28),
              ],
          ],
        );
      },
    ),
  );
}

class _InventorySectionHeading extends StatelessWidget {
  const _InventorySectionHeading({required this.section, required this.count});

  final GrocerySection section;
  final int count;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(section.emoji, style: const TextStyle(fontSize: 20)),
      const SizedBox(width: 9),
      Expanded(
        child: Text(
          section.label,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      Text(
        '$count',
        style: const TextStyle(color: _faint, fontFamily: 'monospace'),
      ),
    ],
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
                PopupMenuButton<String>(
                  tooltip: 'Products for ${food.name}',
                  icon: const Icon(Icons.inventory_2_outlined, size: 20),
                  onSelected: (value) {
                    if (value == 'new') {
                      showProductEditor(context, store, initialFood: food);
                    } else {
                      showProductEditor(
                        context,
                        store,
                        existing: store.product(value),
                      );
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'new',
                      child: Text('Add product…'),
                    ),
                    ...store
                        .productsFor(food.id)
                        .map(
                          (product) => PopupMenuItem(
                            value: product.id,
                            child: Text(
                              product.brand.isEmpty
                                  ? product.name
                                  : '${product.brand} ${product.name}',
                            ),
                          ),
                        ),
                  ],
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
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 5,
              children: [
                _InventoryTag(label: food.ingredientRole.label),
                if (food.storeAisle.isNotEmpty)
                  _InventoryTag(label: food.storeAisle),
              ],
            ),
            if (activeLots.any((lot) => lot.productId != null))
              Text(
                activeLots
                    .where((lot) => lot.productId != null)
                    .map(
                      (lot) =>
                          store.productOrNull(lot.productId)?.name ??
                          'Unknown product',
                    )
                    .toSet()
                    .join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _faint, fontSize: 11),
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

class _InventoryTag extends StatelessWidget {
  const _InventoryTag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: _amber.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(label, style: const TextStyle(color: _amber, fontSize: 10)),
  );
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
      action: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          OutlinedButton.icon(
            onPressed: () => _showMealTemplateEditor(context, store),
            icon: const Icon(Icons.dinner_dining_outlined),
            label: const Text('New combined meal'),
          ),
          FilledButton.icon(
            onPressed: () => showRecipeEditor(context, store),
            icon: const Icon(Icons.add),
            label: const Text('New recipe'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MealTemplateSection(store: store),
          const SizedBox(height: 28),
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

class _MealTemplateSection extends StatelessWidget {
  const _MealTemplateSection({required this.store});

  final PantryStore store;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Combined meals',
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 4),
      const Text(
        'A dinner can combine independently prepared mains and sides.',
        style: TextStyle(color: _muted),
      ),
      const SizedBox(height: 12),
      if (store.mealTemplates.isEmpty)
        const _EmptyCard(
          icon: Icons.dinner_dining_outlined,
          text: 'Create a combined meal from two or more component recipes.',
        )
      else
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: store.mealTemplates.map((meal) {
            final labels = meal.components
                .map((component) {
                  final recipe = store.recipes.firstWhere(
                    (item) => item.id == component.recipeId,
                  );
                  return '${recipe.name} (${store.units.formatAmount(component.servings)})';
                })
                .join(' + ');
            return SizedBox(
              width: 430,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Text(
                            meal.emoji,
                            style: const TextStyle(fontSize: 30),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              meal.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Edit combined meal',
                            onPressed: () => _showMealTemplateEditor(
                              context,
                              store,
                              existing: meal,
                            ),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(labels, style: const TextStyle(color: _muted)),
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: () {
                            try {
                              store.consumeMealTemplate(meal);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${meal.name} logged from prepared portions.',
                                  ),
                                ),
                              );
                            } on StateError catch (error) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(error.message.toString()),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.restaurant_outlined),
                          label: const Text('Eat prepared meal'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
    ],
  );
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
    final averageEase = store.averageEaseForRecipe(recipe.id);
    final averageTaste = store.averageTasteForRecipe(recipe.id);
    final averageMinutes = store.averageMinutesForRecipe(recipe.id);
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
                        '${store.units.formatAmount(recipe.servings)} ${recipe.servings == 1 ? 'serving' : 'servings'}${averageMinutes == null ? '' : ' · ${averageMinutes.round()} min avg'}',
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          _CompactRating(
                            label: 'Ease',
                            value: averageEase,
                            color: _herb,
                          ),
                          const SizedBox(width: 12),
                          _CompactRating(
                            label: 'Taste',
                            value: averageTaste,
                            color: _amber,
                          ),
                        ],
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
            if (recipe.portions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Portions: ${recipe.portions.map((portion) => '${portion.name} (${store.units.formatAmount(portion.servings)} servings)').join(' · ')}',
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ],
            const Spacer(),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: () => showRecipeDetails(
                    context,
                    store,
                    recipe,
                    onMake: () => _showCookRecipe(context, store, recipe),
                  ),
                  child: const Text('View recipe'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => _showCookRecipe(context, store, recipe),
                  icon: const Icon(Icons.soup_kitchen),
                  label: const Text('Make batch'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactRating extends StatelessWidget {
  const _CompactRating({
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
      Text(label, style: const TextStyle(color: _faint, fontSize: 11)),
      const SizedBox(width: 5),
      ...List.generate(
        5,
        (index) => Padding(
          padding: const EdgeInsets.only(right: 2),
          child: Icon(
            Icons.circle,
            size: 7,
            color: index < (value?.round() ?? 0) ? color : _border,
          ),
        ),
      ),
    ],
  );
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
          'Restaurant orders and one-off foods you are not tracking in the pantry. Logging these never changes inventory.',
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

class _PlanningPage extends StatefulWidget {
  const _PlanningPage({required this.store});
  final PantryStore store;

  @override
  State<_PlanningPage> createState() => _PlanningPageState();
}

class _PlanningPageState extends State<_PlanningPage> {
  late DateTime weekStart = _startOfWeek(widget.store.now);

  void _moveWeek(int days) =>
      setState(() => weekStart = weekStart.add(Duration(days: days)));

  @override
  Widget build(BuildContext context) {
    final end = weekStart.add(const Duration(days: 6));
    final meals = widget.store.plannedMeals
        .where(
          (meal) => !meal.date.isBefore(weekStart) && !meal.date.isAfter(end),
        )
        .toList();
    final groceries = widget.store.groceryItems
        .where((item) => !item.checked)
        .length;
    final mealCount = _plannedMealGroupCount(meals);
    return _PageShell(
      eyebrow: '${_monthDay(weekStart)} – ${_monthDay(end)}',
      title: DateUtils.isSameDay(weekStart, _startOfWeek(widget.store.now))
          ? 'This week'
          : 'Week of ${_monthDay(weekStart)}',
      subtitle:
          '$mealCount ${mealCount == 1 ? 'meal' : 'meals'} planned · $groceries groceries needed',
      action: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          IconButton.outlined(
            tooltip: 'Previous week',
            onPressed: () => _moveWeek(-7),
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton.outlined(
            tooltip: 'Next week',
            onPressed: () => _moveWeek(7),
            icon: const Icon(Icons.chevron_right),
          ),
          FilledButton.icon(
            onPressed: () =>
                _showPlannedMealEditor(context, widget.store, weekStart),
            icon: const Icon(Icons.add),
            label: const Text('Add a meal'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: _WeekCalendar(store: widget.store, weekStart: weekStart),
          ),
          if (widget.store.isCloudBacked) ...[
            const SizedBox(height: 18),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: const CalendarSyncCard(),
            ),
          ],
        ],
      ),
    );
  }
}

// Kept as a reusable inline summary if Food Profile later gets its own page.
// ignore: unused_element
class _FoodPreferencesCard extends StatelessWidget {
  const _FoodPreferencesCard({required this.store});

  final PantryStore store;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) {
      final profile = store.foodPreferences;
      final groups = [
        ('ALLERGIES', profile.allergies, _berry),
        ('AVOID', profile.dislikes, _amber),
        ('FAVORITES', profile.favorites, _herb),
        ('DIETARY RULES', profile.dietaryRules, _sky),
      ];
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.tune_outlined, color: _amber),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Food profile',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'Used by meal planning, recipe suggestions, and Pantry GPT.',
                          style: TextStyle(color: _muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _showFoodPreferences(context, store),
                    icon: const Icon(Icons.edit_outlined, size: 17),
                    label: Text(profile.isEmpty ? 'Set up' : 'Edit'),
                  ),
                ],
              ),
              if (profile.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text(
                    'Add allergies, foods you dislike, favorites, dietary rules, or anything a meal planner should remember.',
                    style: TextStyle(color: _faint, fontSize: 12),
                  ),
                )
              else ...[
                const SizedBox(height: 18),
                for (final group in groups)
                  if (group.$2.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 13),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.$1,
                            style: TextStyle(
                              color: group.$3,
                              fontSize: 9,
                              letterSpacing: 1.1,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Wrap(
                            spacing: 7,
                            runSpacing: 7,
                            children: group.$2
                                .map((item) => Chip(label: Text(item)))
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                if (profile.planningNotes.isNotEmpty) ...[
                  const Text(
                    'PLANNING NOTES',
                    style: TextStyle(
                      color: _violet,
                      fontSize: 9,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    profile.planningNotes,
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _WeekCalendar extends StatelessWidget {
  const _WeekCalendar({required this.store, required this.weekStart});
  final PantryStore store;
  final DateTime weekStart;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 760 ? 2 : 1;
      final spacing = columns == 2 ? 16.0 : 12.0;
      final cardWidth = columns == 2
          ? (constraints.maxWidth - spacing) / 2
          : constraints.maxWidth;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: List.generate(7, (index) {
          final day = weekStart.add(Duration(days: index));
          return SizedBox(
            width: cardWidth,
            child: _PlanDayCard(
              store: store,
              day: day,
              meals: store.plannedForDay(day),
            ),
          );
        }),
      );
    },
  );
}

class _PlanDayCard extends StatelessWidget {
  const _PlanDayCard({
    required this.store,
    required this.day,
    required this.meals,
  });
  final PantryStore store;
  final DateTime day;
  final List<PlannedMeal> meals;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.isSameDay(day, store.now);
    final grouped = <String, List<PlannedMeal>>{};
    for (final meal in meals) {
      grouped.putIfAbsent(meal.groupId ?? meal.id, () => []).add(meal);
    }
    final dateLabel = _monthDay(day);
    return Container(
      constraints: const BoxConstraints(minHeight: 178),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: today ? const Color(0xFF20271F) : const Color(0xFF171B19),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _PlanDayLabel(
                  day: day,
                  today: today,
                  dateLabel: dateLabel,
                ),
              ),
              if (today)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _amber,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'TODAY',
                    style: TextStyle(
                      color: Color(0xFF251A08),
                      fontSize: 10,
                      letterSpacing: .8,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (grouped.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Nothing planned yet',
                style: TextStyle(
                  color: _muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            )
          else
            ...grouped.values.map(
              (group) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _PlannedMealGroupChip(store: store, meals: group),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => _showPlannedMealEditor(context, store, day),
              style: TextButton.styleFrom(
                foregroundColor: _amber,
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
              child: const Text('+ Add a meal'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanDayLabel extends StatelessWidget {
  const _PlanDayLabel({
    required this.day,
    required this.today,
    required this.dateLabel,
  });
  final DateTime day;
  final bool today;
  final String dateLabel;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Text(
        _weekdayLabel(day),
        style: TextStyle(
          color: today ? _amber : _ink,
          fontWeight: FontWeight.w800,
          fontSize: 18,
        ),
      ),
      const SizedBox(width: 8),
      Text(
        dateLabel,
        style: const TextStyle(
          color: _muted,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

class _PlannedMealGroupChip extends StatelessWidget {
  const _PlannedMealGroupChip({required this.store, required this.meals});
  final PantryStore store;
  final List<PlannedMeal> meals;

  @override
  Widget build(BuildContext context) {
    final first = meals.first;
    final groupId = first.groupId;
    final name = meals.map((meal) => meal.name).join(' + ');
    final leftover = meals.every(
      (meal) => meal.intent == PlannedMealIntent.leftover,
    );
    final recipeCount = _recipesForPlannedMeals(store, meals).length;
    return Material(
      color: const Color(0xFF272D29),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _openPlannedMealGroup(context, store, meals),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF343C36),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  meals.length == 1 ? first.emoji : '🍽️',
                  style: const TextStyle(fontSize: 20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${first.slot.label}${first.scheduledTime == null ? '' : ' · ${first.scheduledTime}'}${leftover ? ' · leftovers' : ''}'
                          .toUpperCase(),
                      style: const TextStyle(
                        color: _amber,
                        fontSize: 10,
                        letterSpacing: .8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: first.completedAt == null ? _ink : _faint,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                        decoration: first.completedAt == null
                            ? null
                            : TextDecoration.lineThrough,
                      ),
                    ),
                    if (recipeCount > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        recipeCount == 1
                            ? 'View recipe and ingredients'
                            : 'View $recipeCount recipes and ingredients',
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (first.preparationTasks.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${first.preparationTasks.length} scheduled prep ${first.preparationTasks.length == 1 ? 'task' : 'tasks'}',
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: _muted, size: 20),
              IconButton(
                tooltip: 'Remove from plan',
                onPressed: () => groupId == null
                    ? store.deletePlannedMeal(first.id)
                    : store.deletePlannedMealGroup(groupId),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 34,
                  height: 34,
                ),
                icon: const Icon(Icons.close, size: 17, color: _muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _openPlannedMealGroup(
  BuildContext context,
  PantryStore store,
  List<PlannedMeal> meals,
) async {
  final recipes = _recipesForPlannedMeals(store, meals);
  if (recipes.length == 1) {
    final recipe = recipes.single;
    await showRecipeDetails(
      context,
      store,
      recipe,
      onMake: () => _showCookRecipe(context, store, recipe),
    );
    return;
  }
  if (recipes.length > 1) {
    final selected = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${meals.first.emoji} ${meals.map((meal) => meal.name).join(' + ')}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Recipes in this meal',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: _amber,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Choose a recipe to see its ingredients and method.',
                    style: TextStyle(color: _muted, fontSize: 14),
                  ),
                ],
              ),
            ),
            for (final recipe in recipes)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 7,
                ),
                leading: Text(
                  recipe.emoji,
                  style: const TextStyle(fontSize: 24),
                ),
                title: Text(
                  recipe.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${recipe.ingredients.length} ingredients · ${_compactNumber(recipe.servings)} servings',
                ),
                trailing: const Icon(Icons.arrow_forward_rounded),
                onTap: () => Navigator.pop(context, recipe),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(context, _MealSheetAction.cook),
                icon: const Icon(Icons.restaurant_menu),
                label: const Text('Cook this meal'),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected is Recipe && context.mounted) {
      await showRecipeDetails(
        context,
        store,
        selected,
        onMake: () => _showCookRecipe(context, store, selected),
      );
    } else if (selected == _MealSheetAction.cook && context.mounted) {
      await _showCookMeal(context, store, meals);
    }
    return;
  }
  final first = meals.first;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('${first.emoji} ${first.name}'),
      content: Text(
        [
          '${first.slot.label} · ${_compactNumber(first.servings)} servings',
          if (first.note.isNotEmpty) first.note,
        ].join('\n\n'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

enum _MealSheetAction { cook }

List<Recipe> _recipesForPlannedMeals(
  PantryStore store,
  List<PlannedMeal> meals,
) => _recipePlansForPlannedMeals(
  store,
  meals,
).map((plan) => plan.recipe).toList();

List<_MealRecipePlan> _recipePlansForPlannedMeals(
  PantryStore store,
  List<PlannedMeal> meals,
) {
  final servingsByRecipe = <String, double>{};
  for (final meal in meals) {
    if (meal.source == PlannedMealSource.recipe && meal.sourceId != null) {
      servingsByRecipe.update(
        meal.sourceId!,
        (servings) => servings + meal.servings,
        ifAbsent: () => meal.servings,
      );
    } else if (meal.source == PlannedMealSource.meal && meal.sourceId != null) {
      final templates = store.mealTemplates.where(
        (template) => template.id == meal.sourceId,
      );
      if (templates.isNotEmpty) {
        final template = templates.first;
        final factor = meal.servings / template.servings;
        for (final component in template.components) {
          servingsByRecipe.update(
            component.recipeId,
            (servings) => servings + component.servings * factor,
            ifAbsent: () => component.servings * factor,
          );
        }
      }
    }
  }
  return servingsByRecipe.entries
      .map(
        (entry) => (
          entry: entry,
          matches: store.recipes.where((recipe) => recipe.id == entry.key),
        ),
      )
      .where((match) => match.matches.isNotEmpty)
      .map(
        (match) => _MealRecipePlan(
          recipe: match.matches.first,
          servings: match.entry.value,
        ),
      )
      .toList();
}

class _MealRecipePlan {
  const _MealRecipePlan({required this.recipe, required this.servings});

  final Recipe recipe;
  final double servings;
}

Future<void> _showCookMeal(
  BuildContext context,
  PantryStore store,
  List<PlannedMeal> meals,
) async {
  final preparedCount = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: const Color(0xFF101311),
    builder: (context) => _MealCookingSheet(
      store: store,
      meals: meals,
      plans: _recipePlansForPlannedMeals(store, meals),
    ),
  );
  if (preparedCount == null || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        '$preparedCount ${preparedCount == 1 ? 'recipe is' : 'recipes are'} prepared and ready in the fridge.',
      ),
    ),
  );
}

class _MealCookingSheet extends StatefulWidget {
  const _MealCookingSheet({
    required this.store,
    required this.meals,
    required this.plans,
  });

  final PantryStore store;
  final List<PlannedMeal> meals;
  final List<_MealRecipePlan> plans;

  @override
  State<_MealCookingSheet> createState() => _MealCookingSheetState();
}

class _MealCookingSheetState extends State<_MealCookingSheet> {
  late final Map<String, bool> included = {
    for (final plan in widget.plans) plan.recipe.id: true,
  };
  late final Map<String, TextEditingController> servings = {
    for (final plan in widget.plans)
      plan.recipe.id: TextEditingController(
        text: widget.store.units.formatAmount(plan.servings),
      ),
  };
  String? error;

  @override
  void dispose() {
    for (final controller in servings.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _adjust(_MealRecipePlan plan, double amount) {
    final current = double.tryParse(servings[plan.recipe.id]!.text) ?? 0;
    final next = (current + amount).clamp(.5, 999.0);
    setState(() {
      servings[plan.recipe.id]!.text = widget.store.units.formatAmount(next);
      error = null;
    });
  }

  void _finish() {
    final request = <String, double>{};
    for (final plan in widget.plans) {
      if (included[plan.recipe.id] != true) continue;
      final amount = double.tryParse(servings[plan.recipe.id]!.text.trim());
      if (amount == null || amount <= 0) {
        setState(
          () => error = 'Every included recipe needs positive servings.',
        );
        return;
      }
      request[plan.recipe.id] = amount;
    }
    if (request.isEmpty) {
      setState(() => error = 'Choose at least one recipe to prepare.');
      return;
    }
    try {
      final batches = widget.store.prepareRecipeGroup(
        request,
        note:
            'Prepared from ${widget.meals.map((meal) => meal.name).join(' + ')}',
      );
      for (final meal in widget.meals) {
        widget.store.setPlannedMealCompleted(meal.id, true);
      }
      Navigator.pop(context, batches.length);
    } on InsufficientInventoryException catch (exception) {
      final details = exception.missing.entries
          .map((entry) {
            final food = widget.store.food(entry.key);
            return '${food.name} (${widget.store.units.bestInventoryLabel(food, entry.value)} short)';
          })
          .join(', ');
      setState(() => error = 'Not enough inventory: $details.');
    } on ArgumentError catch (exception) {
      setState(() => error = exception.message.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final mealName = widget.meals.map((meal) => meal.name).join(' + ');
    final selectedCount = included.values.where((value) => value).length;
    return FractionallySizedBox(
      heightFactor: .94,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'COOKING MODE',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: _amber,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '${widget.meals.first.emoji} $mealName',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Follow every recipe here. Omit a component or change its batch size without affecting the others.',
                        style: TextStyle(color: _muted, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close cooking mode',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              itemCount: widget.plans.length,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (context, index) {
                final plan = widget.plans[index];
                return _CookingRecipeCard(
                  store: widget.store,
                  plan: plan,
                  included: included[plan.recipe.id]!,
                  controller: servings[plan.recipe.id]!,
                  initiallyExpanded: index == 0,
                  onIncludedChanged: (value) => setState(() {
                    included[plan.recipe.id] = value;
                    error = null;
                  }),
                  onDecrease: () => _adjust(plan, -.5),
                  onIncrease: () => _adjust(plan, .5),
                  onServingsChanged: (_) => setState(() => error = null),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
            decoration: const BoxDecoration(
              color: Color(0xFF171B19),
              boxShadow: [
                BoxShadow(
                  color: Color(0x55000000),
                  blurRadius: 20,
                  offset: Offset(0, -6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (error != null) ...[
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                FilledButton.icon(
                  onPressed: selectedCount == 0 ? null : _finish,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(
                    selectedCount == 1
                        ? 'Mark selected recipe cooked'
                        : 'Mark $selectedCount recipes cooked',
                  ),
                ),
                const SizedBox(height: 7),
                const Text(
                  'This deducts ingredients and saves each component as prepared food. It does not log the meal as eaten.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CookingRecipeCard extends StatelessWidget {
  const _CookingRecipeCard({
    required this.store,
    required this.plan,
    required this.included,
    required this.controller,
    required this.initiallyExpanded,
    required this.onIncludedChanged,
    required this.onDecrease,
    required this.onIncrease,
    required this.onServingsChanged,
  });

  final PantryStore store;
  final _MealRecipePlan plan;
  final bool included;
  final TextEditingController controller;
  final bool initiallyExpanded;
  final ValueChanged<bool> onIncludedChanged;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final ValueChanged<String> onServingsChanged;

  @override
  Widget build(BuildContext context) {
    final recipe = plan.recipe;
    final requested = double.tryParse(controller.text) ?? plan.servings;
    final factor = requested / recipe.servings;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: included ? 1 : .55,
      child: Material(
        color: const Color(0xFF202522),
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: initiallyExpanded,
            tilePadding: const EdgeInsets.fromLTRB(18, 8, 16, 8),
            childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
            leading: Text(recipe.emoji, style: const TextStyle(fontSize: 28)),
            title: Text(
              recipe.name,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              included
                  ? '${store.units.formatAmount(requested)} servings selected'
                  : 'Omitted from this cook',
              style: TextStyle(
                color: included ? _herb : _muted,
                fontWeight: FontWeight.w600,
              ),
            ),
            trailing: Switch(value: included, onChanged: onIncludedChanged),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'BATCH SIZE',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 11,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton.outlined(
                    tooltip: 'Decrease servings',
                    onPressed: included ? onDecrease : null,
                    icon: const Icon(Icons.remove, size: 18),
                  ),
                  SizedBox(
                    width: 82,
                    child: TextField(
                      enabled: included,
                      controller: controller,
                      onChanged: onServingsChanged,
                      textAlign: TextAlign.center,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        suffixText: 'srv',
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton.outlined(
                    tooltip: 'Increase servings',
                    onPressed: included ? onIncrease : null,
                    icon: const Icon(Icons.add, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'INGREDIENTS',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: _amber,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              for (final ingredient in recipe.ingredients)
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Row(
                    children: [
                      const Icon(Icons.circle, size: 7, color: _herb),
                      const SizedBox(width: 10),
                      Expanded(child: Text(store.food(ingredient.foodId).name)),
                      Text(
                        store.units.formatUnitAmount(
                          store.food(ingredient.foodId),
                          ingredient.amount * factor,
                          ingredient.unit,
                        ),
                        style: const TextStyle(
                          color: _muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'METHOD',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: _amber,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (recipe.instructions.isEmpty)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'No method has been added yet.',
                    style: TextStyle(color: _muted),
                  ),
                )
              else
                for (final step in recipe.instructions.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 13),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFF343C36),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${step.$1 + 1}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            step.$2,
                            style: const TextStyle(fontSize: 15, height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

// Retained for legacy single-entry plans while grouped plans use the compact chip.
// ignore: unused_element
class _PlannedMealTile extends StatelessWidget {
  const _PlannedMealTile({required this.store, required this.meal});
  final PantryStore store;
  final PlannedMeal meal;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: _raised,
      borderRadius: BorderRadius.circular(11),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                meal.slot.label.toUpperCase(),
                style: const TextStyle(
                  color: _faint,
                  letterSpacing: 1,
                  fontSize: 9,
                ),
              ),
            ),
            InkWell(
              onTap: () => store.deletePlannedMeal(meal.id),
              child: const Icon(Icons.close, size: 15, color: _faint),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(meal.emoji),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                meal.name,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.3,
                  color: meal.completedAt == null ? _ink : _faint,
                  decoration: meal.completedAt == null
                      ? null
                      : TextDecoration.lineThrough,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => meal.completedAt == null
                ? _completePlannedMeal(context, store, meal)
                : store.setPlannedMealCompleted(meal.id, false),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 26),
              visualDensity: VisualDensity.compact,
            ),
            icon: Icon(
              meal.completedAt == null
                  ? meal.source == PlannedMealSource.recipe ||
                            meal.source == PlannedMealSource.meal
                        ? Icons.restaurant_outlined
                        : Icons.check_circle_outline
                  : Icons.undo,
              size: 14,
            ),
            label: Text(
              meal.completedAt == null
                  ? meal.source == PlannedMealSource.recipe ||
                            meal.source == PlannedMealSource.meal
                        ? 'Eat prepared'
                        : 'Complete'
                  : 'Reopen',
              style: const TextStyle(fontSize: 10),
            ),
          ),
        ),
      ],
    ),
  );
}

class _GroceryListPage extends StatelessWidget {
  const _GroceryListPage({required this.store});
  final PantryStore store;

  @override
  Widget build(BuildContext context) {
    final weekStart = _startOfWeek(store.now);
    final weekEnd = weekStart.add(const Duration(days: 6));
    final done = store.groceryItems.where((item) => item.checked).length;
    return _PageShell(
      eyebrow: '${_monthDay(weekStart)} – ${_monthDay(weekEnd)}',
      title: 'Grocery list',
      subtitle:
          'Waugh Chapel Safeway walking order · shared ingredients merged · $done of ${store.groceryItems.length} checked',
      action: Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          OutlinedButton(
            onPressed: store.rebuildGroceryList,
            child: const Text('Rebuild from plan'),
          ),
          FilledButton.icon(
            onPressed: () => _showManualGroceryEditor(context, store),
            icon: const Icon(Icons.add),
            label: const Text('Add item'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ShoppingProgressCard(store: store),
          const SizedBox(height: 18),
          _GroceryListCard(store: store),
        ],
      ),
    );
  }
}

class _ShoppingProgressCard extends StatelessWidget {
  const _ShoppingProgressCard({required this.store});
  final PantryStore store;

  @override
  Widget build(BuildContext context) {
    final total = store.groceryItems.length;
    final done = store.groceryItems.where((item) => item.checked).length;
    final remaining = total - done;
    final nextSection = GrocerySection.values
        .cast<GrocerySection?>()
        .firstWhere(
          (section) => store.groceryItems.any(
            (item) => !item.checked && item.grocerySection == section,
          ),
          orElse: () => null,
        );
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _amber.withValues(alpha: .10),
        border: Border.all(color: _amber.withValues(alpha: .28)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _amber,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.storefront, color: Color(0xFF171B19)),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      remaining == 0 && total > 0
                          ? 'Shopping complete'
                          : '$remaining ${remaining == 1 ? 'item' : 'items'} left',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      nextSection == null
                          ? 'Waugh Chapel Safeway'
                          : 'Next: ${nextSection.label}',
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Text(
                '$done / $total',
                style: const TextStyle(
                  color: _amber,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          LinearProgressIndicator(
            value: total == 0 ? 0 : done / total,
            minHeight: 7,
            borderRadius: BorderRadius.circular(6),
            backgroundColor: _border,
            color: _amber,
          ),
          const SizedBox(height: 9),
          const Text(
            '2644 Chapel Lake Dr · ordered from the produce-side entrance',
            style: TextStyle(color: _faint, fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}

class _GroceryListCard extends StatelessWidget {
  const _GroceryListCard({required this.store});
  final PantryStore store;

  @override
  Widget build(BuildContext context) {
    final items = store.groceryItems;
    final requirements = store.plannedRequirementsBase;
    final alreadyHave = requirements.entries
        .where((entry) => store.totalFor(entry.key) >= entry.value)
        .map((entry) => store.food(entry.key))
        .toList();
    final grouped = <GrocerySection, List<GroceryListItem>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.grocerySection, () => []).add(item);
    }
    for (final sectionItems in grouped.values) {
      sectionItems.sort((a, b) {
        if (a.checked != b.checked) return a.checked ? 1 : -1;
        return a.name.compareTo(b.name);
      });
    }
    final sections = GrocerySection.values
        .where((section) => grouped[section]?.isNotEmpty == true)
        .toList();
    if (items.isEmpty) {
      return const _EmptyCard(
        icon: Icons.shopping_cart_outlined,
        text: 'Plan recipes or add a shopping item to start your list.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900
                ? 3
                : constraints.maxWidth >= 580
                ? 2
                : 1;
            final width = (constraints.maxWidth - (columns - 1) * 14) / columns;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final section in sections)
                  SizedBox(
                    width: width,
                    child: _GrocerySectionCard(
                      store: store,
                      section: section,
                      items: grouped[section]!,
                    ),
                  ),
              ],
            );
          },
        ),
        if (alreadyHave.isNotEmpty) ...[
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF131715),
              border: Border.all(color: const Color(0xFF232926)),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ALREADY IN THE KITCHEN — LEFT OFF THE LIST',
                  style: TextStyle(
                    color: _faint,
                    fontSize: 10,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 13),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: alreadyHave
                      .map(
                        (food) => Chip(
                          avatar: Text(food.emoji),
                          label: Text(food.name),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _GrocerySectionCard extends StatelessWidget {
  const _GrocerySectionCard({
    required this.store,
    required this.section,
    required this.items,
  });
  final PantryStore store;
  final GrocerySection section;
  final List<GroceryListItem> items;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xFF171B19),
      border: Border.all(color: _border),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(section.emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                section.label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'STOP ${section.storeOrder + 1}',
                  style: const TextStyle(
                    color: _amber,
                    fontSize: 9,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  '${items.where((item) => !item.checked).length} left',
                  style: const TextStyle(
                    color: _faint,
                    fontFamily: 'monospace',
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final item in items) _GroceryItemRow(store: store, item: item),
      ],
    ),
  );
}

class _GroceryItemRow extends StatelessWidget {
  const _GroceryItemRow({required this.store, required this.item});
  final PantryStore store;
  final GroceryListItem item;

  @override
  Widget build(BuildContext context) {
    var amount = item.quantityLabel;
    if (item.foodId != null && item.quantityBase != null) {
      amount = store.units.bestInventoryLabel(
        store.food(item.foodId!),
        item.quantityBase!,
      );
    }
    final usedBy = item.foodId == null
        ? const <String>[]
        : store.plannedMeals
              .where(
                (meal) =>
                    meal.intent == PlannedMealIntent.prepare &&
                    meal.source == PlannedMealSource.recipe &&
                    meal.sourceId != null,
              )
              .map(
                (meal) =>
                    store.recipes.where((recipe) => recipe.id == meal.sourceId),
              )
              .expand((recipes) => recipes)
              .where(
                (recipe) => recipe.ingredients.any(
                  (ingredient) => ingredient.foodId == item.foodId,
                ),
              )
              .map((recipe) => recipe.name)
              .toSet()
              .take(2)
              .toList();
    final aisle = item.foodId == null
        ? ''
        : store.food(item.foodId!).storeAisle;
    return Semantics(
      button: true,
      checked: item.checked,
      label: '${item.checked ? 'Uncheck' : 'Check off'} ${item.name}',
      child: InkWell(
        onTap: () => store.toggleGroceryItem(item.id),
        borderRadius: BorderRadius.circular(13),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 64),
          margin: const EdgeInsets.only(bottom: 7),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: item.checked ? Colors.transparent : const Color(0xFF202622),
            border: Border.all(
              color: item.checked ? _border : const Color(0xFF343D37),
            ),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: item.checked ? _herb : Colors.transparent,
                  border: Border.all(
                    color: item.checked ? _herb : _muted,
                    width: 2,
                  ),
                  shape: BoxShape.circle,
                ),
                child: item.checked
                    ? const Icon(
                        Icons.check,
                        size: 20,
                        color: Color(0xFF102016),
                      )
                    : null,
              ),
              const SizedBox(width: 11),
              Text(item.emoji),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: TextStyle(
                        color: item.checked ? _faint : _ink,
                        decoration: item.checked
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    if (aisle.isNotEmpty || usedBy.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (aisle.isNotEmpty) aisle,
                          if (usedBy.isNotEmpty) 'For ${usedBy.join(' + ')}',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _faint, fontSize: 10.5),
                      ),
                    ],
                  ],
                ),
              ),
              if (amount.isNotEmpty)
                Text(
                  amount,
                  style: const TextStyle(
                    color: _faint,
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
              if (!item.fromPlan)
                IconButton(
                  tooltip: 'Remove ${item.name}',
                  onPressed: () => store.deleteGroceryItem(item.id),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 16),
                  color: _faint,
                ),
            ],
          ),
        ),
      ),
    );
  }
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
                  Text(
                    event.displayLabel,
                    style: const TextStyle(fontSize: 13),
                  ),
                  if (repeats > event.count)
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
  final List<_CollapsedConsumption> events;
}

class _CollapsedConsumption {
  const _CollapsedConsumption(this.events);

  final List<ConsumptionEvent> events;

  ConsumptionEvent get representative => events.first;
  int get count => events.length;
  String get label => representative.label;
  String get displayLabel => count == 1 ? label : '$count× $label';
  ConsumptionKind get kind => representative.kind;

  NutritionTotals? get nutrition {
    if (!events.any((event) => event.nutrition != null)) return null;
    return events.fold<NutritionTotals>(
      const NutritionTotals(),
      (total, event) => total + (event.nutrition ?? const NutritionTotals()),
    );
  }
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
      .map(
        (entry) => _DayEvents(entry.key, _collapseSameDayEvents(entry.value)),
      )
      .toList()
    ..sort((a, b) => b.day.compareTo(a.day));
}

List<_CollapsedConsumption> _collapseSameDayEvents(
  Iterable<ConsumptionEvent> events,
) {
  final grouped = <String, List<ConsumptionEvent>>{};
  for (final event in events) {
    final key = [
      event.kind.name,
      event.recipeId ?? '',
      _mealKey(event.label),
      event.note.trim().toLowerCase(),
    ].join('|');
    grouped.putIfAbsent(key, () => []).add(event);
  }
  final result = grouped.values.map((items) {
    items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return _CollapsedConsumption(items);
  }).toList();
  result.sort(
    (a, b) => b.representative.timestamp.compareTo(a.representative.timestamp),
  );
  return result;
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
    final collapsedEvents = _collapseSameDayEvents(events);
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
            events: collapsedEvents,
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
                '${collapsedEvents.length} ${collapsedEvents.length == 1 ? 'entry' : 'entries'}',
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
            ...collapsedEvents.map(
              (event) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: _FoodLogEventCard(
                  event: event,
                  onUndo: () {
                    for (final item in event.events) {
                      store.undo(item.id);
                    }
                  },
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

  final List<_CollapsedConsumption> events;
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
                        'Each color is one food or same-day repeat group.',
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
                        event.displayLabel,
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
  final List<_CollapsedConsumption> events;
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

  final _CollapsedConsumption event;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final representative = event.representative;
    final source =
        '${_eventSource(representative)}${representative.note.isEmpty ? '' : ' · ${representative.note}'}';
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
                        event.displayLabel,
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
                event.count > 1
                    ? (event.events.any((item) => item.deductions.isNotEmpty)
                          ? 'Undo all'
                          : 'Remove all')
                    : (representative.deductions.isEmpty ? 'Remove' : 'Undo'),
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

Future<void> _showFoodPreferences(
  BuildContext context,
  PantryStore store,
) async {
  final current = store.foodPreferences;
  final allergies = TextEditingController(text: current.allergies.join('\n'));
  final dislikes = TextEditingController(text: current.dislikes.join('\n'));
  final favorites = TextEditingController(text: current.favorites.join('\n'));
  final dietaryRules = TextEditingController(
    text: current.dietaryRules.join('\n'),
  );
  final planningNotes = TextEditingController(text: current.planningNotes);
  final routine = store.personalRoutine;
  final timeZone = TextEditingController(text: routine.timeZone);
  final dinnerStart = TextEditingController(text: routine.dinnerStart);
  final dinnerEnd = TextEditingController(text: routine.dinnerEnd);
  final commuteMinutes = TextEditingController(
    text: '${routine.commuteMinutes}',
  );
  final preparationBuffer = TextEditingController(
    text: '${routine.preparationBufferMinutes}',
  );
  final thawHours = TextEditingController(text: '${routine.defaultThawHours}');
  final routineNotes = TextEditingController(text: routine.notes);
  final wakeTimes = {
    for (final day in PersonalRoutine.dayNames)
      day: TextEditingController(text: routine.days[day]!.wakeTime),
  };
  final bedTimes = {
    for (final day in PersonalRoutine.dayNames)
      day: TextEditingController(text: routine.days[day]!.bedTime),
  };
  final fields = <(String, String, TextEditingController)>[
    (
      'Allergies and intolerances',
      'One per line. These are treated as hard safety constraints.',
      allergies,
    ),
    ('Foods to avoid', 'Dislikes and ingredients you do not want.', dislikes),
    ('Favorites', 'Foods, cuisines, and meals you enjoy.', favorites),
    (
      'Dietary rules',
      'Examples: no pork, pescatarian, or limit red meat.',
      dietaryRules,
    ),
  ];
  final submitted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Me'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Your routine and food profile are stored privately with Pantry so the assistant can plan around sleep, school, work, and preferences.',
                style: TextStyle(color: _muted),
              ),
              const SizedBox(height: 18),
              Text(
                'Routine & availability',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: timeZone,
                decoration: const InputDecoration(
                  labelText: 'IANA time zone',
                  hintText: 'America/New_York',
                ),
              ),
              const SizedBox(height: 12),
              for (final day in PersonalRoutine.dayNames) ...[
                Row(
                  children: [
                    SizedBox(
                      width: 92,
                      child: Text(
                        '${day[0].toUpperCase()}${day.substring(1, 3)}',
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: wakeTimes[day],
                        decoration: const InputDecoration(
                          labelText: 'Wake',
                          hintText: '07:00',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: bedTimes[day],
                        decoration: const InputDecoration(
                          labelText: 'Bed',
                          hintText: '23:00',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: dinnerStart,
                      decoration: const InputDecoration(
                        labelText: 'Dinner window starts',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: dinnerEnd,
                      decoration: const InputDecoration(
                        labelText: 'Dinner window ends',
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
                      controller: commuteMinutes,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Travel buffer',
                        suffixText: 'min',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: preparationBuffer,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Prep buffer',
                        suffixText: 'min',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: thawHours,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Default thaw',
                        suffixText: 'hours',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: routineNotes,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Scheduling notes',
                  hintText: 'Avoid cooking after 9 PM; classes vary by week…',
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Food profile',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              for (final field in fields) ...[
                TextField(
                  controller: field.$3,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: field.$1,
                    helperText: field.$2,
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 14),
              ],
              TextField(
                controller: planningNotes,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Other planning notes',
                  hintText:
                      'Budget, effort, texture preferences, variety goals, serving habits…',
                  alignLabelWithHint: true,
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
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Save profile'),
        ),
      ],
    ),
  );
  final updated = submitted == true
      ? FoodPreferences(
          allergies: _parsePreferenceList(allergies.text),
          dislikes: _parsePreferenceList(dislikes.text),
          favorites: _parsePreferenceList(favorites.text),
          dietaryRules: _parsePreferenceList(dietaryRules.text),
          planningNotes: planningNotes.text,
        )
      : null;
  PersonalRoutine? updatedRoutine;
  if (submitted == true) {
    final clock = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
    final commute = int.tryParse(commuteMinutes.text);
    final buffer = int.tryParse(preparationBuffer.text);
    final thaw = int.tryParse(thawHours.text);
    final validTimes = [
      dinnerStart.text,
      dinnerEnd.text,
      ...wakeTimes.values.map((item) => item.text),
      ...bedTimes.values.map((item) => item.text),
    ].every(clock.hasMatch);
    if (timeZone.text.trim().isNotEmpty &&
        validTimes &&
        commute != null &&
        commute >= 0 &&
        buffer != null &&
        buffer >= 0 &&
        thaw != null &&
        thaw > 0) {
      updatedRoutine = PersonalRoutine(
        timeZone: timeZone.text.trim(),
        days: {
          for (final day in PersonalRoutine.dayNames)
            day: DailyRoutine(
              wakeTime: wakeTimes[day]!.text,
              bedTime: bedTimes[day]!.text,
            ),
        },
        dinnerStart: dinnerStart.text,
        dinnerEnd: dinnerEnd.text,
        commuteMinutes: commute,
        preparationBufferMinutes: buffer,
        defaultThawHours: thaw,
        notes: routineNotes.text.trim(),
      );
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Routine times must use 24-hour HH:mm; minute values must be non-negative.',
          ),
        ),
      );
    }
  }
  await Future<void>.delayed(kThemeAnimationDuration);
  for (final controller in [
    allergies,
    dislikes,
    favorites,
    dietaryRules,
    planningNotes,
    timeZone,
    dinnerStart,
    dinnerEnd,
    commuteMinutes,
    preparationBuffer,
    thawHours,
    routineNotes,
    ...wakeTimes.values,
    ...bedTimes.values,
  ]) {
    controller.dispose();
  }
  if (updated != null && updatedRoutine != null) {
    store.saveFoodPreferences(updated);
    store.savePersonalRoutine(updatedRoutine);
  }
}

List<String> _parsePreferenceList(String value) => value
    .split(RegExp(r'[,\n]'))
    .map((item) => item.trim())
    .where((item) => item.isNotEmpty)
    .toList();

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
  ConsumptionKind.recipe =>
    event.deductions.isEmpty
        ? 'Recipe · recorded before inventory snapshot'
        : 'Recipe · inventory deducted',
  ConsumptionKind.inventory =>
    event.deductions.isEmpty
        ? 'Pantry item · recorded before inventory snapshot'
        : 'Pantry item · inventory deducted',
  ConsumptionKind.external =>
    event.nutritionEstimated
        ? 'No inventory change · estimated'
        : 'No inventory change · label data',
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

DateTime _startOfWeek(DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

int _plannedMealGroupCount(Iterable<PlannedMeal> meals) =>
    meals.map((meal) => meal.groupId ?? meal.id).toSet().length;

String _shortPlanDate(DateTime date) {
  if (DateUtils.isSameDay(date, DateTime.now())) return 'Today';
  return _monthDay(date);
}

void _completePlannedMeal(
  BuildContext context,
  PantryStore store,
  PlannedMeal meal,
) {
  if (meal.source == PlannedMealSource.recipe) {
    final index = store.recipes.indexWhere(
      (recipe) => recipe.id == meal.sourceId,
    );
    if (index < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That recipe no longer exists.')),
      );
      return;
    }
    try {
      store.consumePreparedRecipe(store.recipes[index], meal.servings);
    } on StateError catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message.toString())));
      return;
    }
  } else if (meal.source == PlannedMealSource.meal) {
    final index = store.mealTemplates.indexWhere(
      (template) => template.id == meal.sourceId,
    );
    if (index < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That combined meal no longer exists.')),
      );
      return;
    }
    try {
      store.consumeMealTemplate(
        store.mealTemplates[index],
        servings: meal.servings,
      );
    } on StateError catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message.toString())));
      return;
    }
  }
  store.setPlannedMealCompleted(meal.id, true);
}

Future<void> _showPlannedMealEditor(
  BuildContext context,
  PantryStore store,
  DateTime day,
) async {
  final leftoverSources = <String, List<PlannedMeal>>{};
  for (final meal in store.plannedMeals.where(
    (meal) =>
        meal.groupId != null &&
        meal.intent == PlannedMealIntent.prepare &&
        meal.date.isBefore(DateTime(day.year, day.month, day.day)),
  )) {
    leftoverSources.putIfAbsent(meal.groupId!, () => []).add(meal);
  }
  var source = store.recipes.isNotEmpty
      ? PlannedMealSource.recipe
      : store.externalFoods.isNotEmpty
      ? PlannedMealSource.external
      : PlannedMealSource.custom;
  var planType = source.name;
  String? leftoverOfGroupId = leftoverSources.keys.firstOrNull;
  var slot = MealSlot.dinner;
  var intent = PlannedMealIntent.prepare;
  Recipe? recipe = store.recipes.isEmpty ? null : store.recipes.first;
  final selectedRecipes = <Recipe>{?recipe};
  MealTemplate? mealTemplate = store.mealTemplates.isEmpty
      ? null
      : store.mealTemplates.first;
  ExternalFood? external = store.externalFoods.isEmpty
      ? null
      : store.externalFoods.first;
  final name = TextEditingController();
  final emoji = TextEditingController(text: '🍽️');
  final servings = TextEditingController(
    text: recipe == null ? '1' : _compactNumber(recipe.servings),
  );
  final scheduledTime = TextEditingController();
  final note = TextEditingController();
  String? error;
  final submitted = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text('Plan ${_weekdayLabel(day)}'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<MealSlot>(
                        initialValue: slot,
                        decoration: const InputDecoration(labelText: 'Meal'),
                        items: MealSlot.values
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value.label),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setDialogState(() => slot = value!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: planType,
                        decoration: const InputDecoration(labelText: 'Type'),
                        items: [
                          const DropdownMenuItem(
                            value: 'recipe',
                            child: Text('Recipe'),
                          ),
                          const DropdownMenuItem(
                            value: 'meal',
                            child: Text('Combined meal'),
                          ),
                          const DropdownMenuItem(
                            value: 'external',
                            child: Text('Eating out'),
                          ),
                          const DropdownMenuItem(
                            value: 'custom',
                            child: Text('Simple note'),
                          ),
                          if (leftoverSources.isNotEmpty)
                            const DropdownMenuItem(
                              value: 'plannedLeftovers',
                              child: Text('Leftovers from plan'),
                            ),
                        ],
                        onChanged: (value) => setDialogState(() {
                          planType = value!;
                          if (value != 'plannedLeftovers') {
                            source = PlannedMealSource.values.byName(value);
                          } else if (leftoverOfGroupId != null) {
                            servings.text = _compactNumber(
                              leftoverSources[leftoverOfGroupId]!
                                  .first
                                  .servings,
                            );
                          }
                        }),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (planType == 'plannedLeftovers')
                  DropdownButtonFormField<String>(
                    initialValue: leftoverOfGroupId,
                    decoration: const InputDecoration(
                      labelText: 'Earlier meal',
                      helperText:
                          'References the planned meal; no new saved recipe or meal.',
                    ),
                    items: leftoverSources.entries
                        .map(
                          (entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(
                              '${_monthDay(entry.value.first.date)} · '
                              '${entry.value.map((meal) => meal.name).join(' + ')}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setDialogState(() {
                      leftoverOfGroupId = value;
                      if (value != null) {
                        servings.text = _compactNumber(
                          leftoverSources[value]!.first.servings,
                        );
                      }
                    }),
                  )
                else if (source == PlannedMealSource.recipe)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'RECIPES IN THIS MEAL',
                        style: TextStyle(
                          color: _faint,
                          fontSize: 10,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: store.recipes
                            .map(
                              (value) => FilterChip(
                                selected: selectedRecipes.contains(value),
                                avatar: Text(value.emoji),
                                label: Text(value.name),
                                onSelected: (selected) => setDialogState(() {
                                  if (selected) {
                                    selectedRecipes.add(value);
                                    recipe = value;
                                    if (selectedRecipes.length == 1) {
                                      servings.text = _compactNumber(
                                        value.servings,
                                      );
                                    }
                                  } else {
                                    selectedRecipes.remove(value);
                                    recipe = selectedRecipes.firstOrNull;
                                  }
                                }),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  )
                else if (source == PlannedMealSource.meal)
                  DropdownButtonFormField<MealTemplate>(
                    initialValue: mealTemplate,
                    decoration: const InputDecoration(
                      labelText: 'Combined meal',
                    ),
                    items: store.mealTemplates
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text('${value.emoji}  ${value.name}'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setDialogState(() {
                      mealTemplate = value;
                      if (value != null) {
                        servings.text = _compactNumber(value.servings);
                      }
                    }),
                  )
                else if (source == PlannedMealSource.external)
                  DropdownButtonFormField<ExternalFood>(
                    initialValue: external,
                    decoration: const InputDecoration(labelText: 'Saved food'),
                    items: store.externalFoods
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text('${value.emoji}  ${value.name}'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => external = value),
                  )
                else
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
                          decoration: const InputDecoration(
                            labelText: 'Meal name',
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                if (planType != 'plannedLeftovers' &&
                    (source == PlannedMealSource.recipe ||
                        source == PlannedMealSource.meal)) ...[
                  DropdownButtonFormField<PlannedMealIntent>(
                    initialValue: intent,
                    decoration: const InputDecoration(labelText: 'Plan as'),
                    items: PlannedMealIntent.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(
                              value == PlannedMealIntent.prepare
                                  ? 'Cook / prepare'
                                  : 'Eat leftovers (no groceries)',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setDialogState(() => intent = value!),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: servings,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: source == PlannedMealSource.external
                        ? 'Servings or orders'
                        : 'Servings',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: scheduledTime,
                  decoration: const InputDecoration(
                    labelText: 'Specific time (optional)',
                    hintText: '19:00',
                    helperText:
                        'Overrides the default breakfast/lunch/dinner time.',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(
                    labelText: 'Note',
                    hintText: 'Optional',
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
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
              final servingCount = double.tryParse(servings.text);
              final invalidSource =
                  (planType == 'plannedLeftovers' &&
                      leftoverOfGroupId == null) ||
                  (planType != 'plannedLeftovers' &&
                      source == PlannedMealSource.recipe &&
                      selectedRecipes.isEmpty) ||
                  (planType != 'plannedLeftovers' &&
                      source == PlannedMealSource.meal &&
                      mealTemplate == null) ||
                  (planType != 'plannedLeftovers' &&
                      source == PlannedMealSource.external &&
                      external == null) ||
                  (planType != 'plannedLeftovers' &&
                      source == PlannedMealSource.custom &&
                      name.text.trim().isEmpty);
              final time = scheduledTime.text.trim();
              final invalidTime =
                  time.isNotEmpty &&
                  !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(time);
              if (servingCount == null ||
                  servingCount <= 0 ||
                  invalidSource ||
                  invalidTime) {
                setDialogState(
                  () => error =
                      'Choose a meal, enter positive servings, and use HH:mm for a specific time.',
                );
              } else {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Add to plan'),
          ),
        ],
      ),
    ),
  );
  if (submitted == true) {
    final servingCount = double.parse(servings.text);
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final groupId = 'meal-$timestamp';
    if (planType == 'plannedLeftovers') {
      final sourceMeals = leftoverSources[leftoverOfGroupId]!;
      for (final sourceMeal in sourceMeals) {
        store.savePlannedMeal(
          PlannedMeal(
            id: 'plan-$timestamp-${sourceMeal.id}',
            groupId: groupId,
            leftoverOfGroupId: leftoverOfGroupId,
            intent: PlannedMealIntent.leftover,
            date: DateTime(day.year, day.month, day.day),
            slot: slot,
            source: sourceMeal.source,
            sourceId: sourceMeal.sourceId,
            name: sourceMeal.name,
            emoji: sourceMeal.emoji,
            servings: servingCount,
            note: note.text.trim(),
            scheduledTime: scheduledTime.text.trim().isEmpty
                ? null
                : scheduledTime.text.trim(),
          ),
        );
      }
      for (final controller in [name, emoji, servings, scheduledTime, note]) {
        controller.dispose();
      }
      return;
    }
    if (source == PlannedMealSource.recipe) {
      for (final selected in selectedRecipes) {
        store.savePlannedMeal(
          PlannedMeal(
            id: 'plan-$timestamp-${selected.id}',
            groupId: groupId,
            intent: intent,
            date: DateTime(day.year, day.month, day.day),
            slot: slot,
            source: PlannedMealSource.recipe,
            sourceId: selected.id,
            name: selected.name,
            emoji: selected.emoji,
            servings: servingCount,
            note: note.text.trim(),
            scheduledTime: scheduledTime.text.trim().isEmpty
                ? null
                : scheduledTime.text.trim(),
          ),
        );
      }
      for (final controller in [name, emoji, servings, scheduledTime, note]) {
        controller.dispose();
      }
      return;
    }
    final plannedName = switch (source) {
      PlannedMealSource.recipe => throw StateError('Handled above'),
      PlannedMealSource.meal => mealTemplate!.name,
      PlannedMealSource.external => external!.name,
      PlannedMealSource.custom => name.text.trim(),
    };
    final plannedEmoji = switch (source) {
      PlannedMealSource.recipe => throw StateError('Handled above'),
      PlannedMealSource.meal => mealTemplate!.emoji,
      PlannedMealSource.external => external!.emoji,
      PlannedMealSource.custom =>
        emoji.text.trim().isEmpty ? '🍽️' : emoji.text.trim(),
    };
    final sourceId = switch (source) {
      PlannedMealSource.recipe => throw StateError('Handled above'),
      PlannedMealSource.meal => mealTemplate!.id,
      PlannedMealSource.external => external!.id,
      PlannedMealSource.custom => null,
    };
    store.savePlannedMeal(
      PlannedMeal(
        id: 'plan-$timestamp',
        groupId: groupId,
        intent: intent,
        date: DateTime(day.year, day.month, day.day),
        slot: slot,
        source: source,
        sourceId: sourceId,
        name: plannedName,
        emoji: plannedEmoji,
        servings: servingCount,
        note: note.text.trim(),
        scheduledTime: scheduledTime.text.trim().isEmpty
            ? null
            : scheduledTime.text.trim(),
      ),
    );
  }
  for (final controller in [name, emoji, servings, scheduledTime, note]) {
    controller.dispose();
  }
}

Future<void> _showManualGroceryEditor(
  BuildContext context,
  PantryStore store,
) async {
  final name = TextEditingController();
  final quantity = TextEditingController();
  var grocerySection = GrocerySection.pantryOther;
  var sectionWasSelected = false;
  final submitted = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Add grocery item'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                onChanged: (value) {
                  if (!sectionWasSelected) {
                    setDialogState(
                      () => grocerySection = inferGrocerySection(value),
                    );
                  }
                },
                decoration: const InputDecoration(labelText: 'Item'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: quantity,
                decoration: const InputDecoration(
                  labelText: 'Quantity',
                  hintText: 'Optional, e.g. 2 bottles',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<GrocerySection>(
                key: ValueKey(grocerySection),
                initialValue: grocerySection,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Store section'),
                items: GrocerySection.values
                    .map(
                      (section) => DropdownMenuItem(
                        value: section,
                        child: Text(
                          '${section.emoji} ${section.label}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setDialogState(() {
                  grocerySection = value!;
                  sectionWasSelected = true;
                }),
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
            onPressed: () =>
                Navigator.pop(context, name.text.trim().isNotEmpty),
            child: const Text('Add item'),
          ),
        ],
      ),
    ),
  );
  if (submitted == true) {
    store.addManualGroceryItem(
      name.text,
      quantityLabel: quantity.text,
      grocerySection: grocerySection,
    );
  }
  name.dispose();
  quantity.dispose();
}

Future<void> _showAddLot(
  BuildContext context,
  PantryStore store, {
  ProductDefinition? initialProduct,
}) async {
  var product = initialProduct;
  var food = product == null ? store.foods.first : store.food(product.foodId);
  var unit =
      product?.conversions.firstOrNull?.unit ?? food.conversions.first.unit;
  var location = food.defaultLocation;
  final amountController = TextEditingController(text: '1');
  final daysController = TextEditingController();
  final submitted = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        final conversionByUnit = <String, UnitConversion>{
          for (final conversion in food.conversions)
            conversion.unit: conversion,
          for (final conversion in product?.conversions ?? const [])
            conversion.unit: conversion,
        };
        return AlertDialog(
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
                    product = null;
                    unit = food.conversions.first.unit;
                    location = food.defaultLocation;
                  }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey('product-${food.id}-${product?.id}'),
                  initialValue: product?.id,
                  decoration: const InputDecoration(
                    labelText: 'Specific product (optional)',
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      child: Text('Unspecified / generic'),
                    ),
                    ...store
                        .productsFor(food.id)
                        .map(
                          (item) => DropdownMenuItem(
                            value: item.id,
                            child: Text(
                              item.brand.isEmpty
                                  ? item.name
                                  : '${item.brand} ${item.name}',
                            ),
                          ),
                        ),
                  ],
                  onChanged: (value) => setDialogState(() {
                    product = value == null ? null : store.product(value);
                    if (product?.conversions.isNotEmpty ?? false) {
                      unit = product!.conversions.first.unit;
                    } else {
                      unit = food.conversions.first.unit;
                    }
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
                        items: conversionByUnit.values
                            .map(
                              (item) => DropdownMenuItem(
                                value: item.unit,
                                child: Text(item.symbol),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setDialogState(() => unit = value!),
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
        );
      },
    ),
  );
  if (submitted == true) {
    final amount = double.tryParse(amountController.text);
    final days = int.tryParse(daysController.text);
    if (amount == null || amount <= 0) return;
    store.addLot(
      food: food,
      product: product,
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
          'Used ${store.units.formatUnitAmount(food, amount, unit)} ${food.name.toLowerCase()}',
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

Future<void> _showAddPreparedFood(
  BuildContext context,
  PantryStore store,
) async {
  final name = TextEditingController();
  final servings = TextEditingController(text: '1');
  var location = StorageLocation.fridge;
  ExternalFood? savedFood;
  var useSavedFood = false;
  String? error;
  final submitted = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Add prepared food'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (store.externalFoods.isNotEmpty)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use a saved outside food'),
                  subtitle: const Text('Copies its serving nutrition.'),
                  value: useSavedFood,
                  onChanged: (value) => setDialogState(() {
                    useSavedFood = value;
                    savedFood ??= store.externalFoods.first;
                  }),
                ),
              if (useSavedFood)
                DropdownButtonFormField<ExternalFood>(
                  initialValue: savedFood,
                  decoration: const InputDecoration(labelText: 'Saved food'),
                  items: store.externalFoods
                      .map(
                        (food) => DropdownMenuItem(
                          value: food,
                          child: Text('${food.brand} · ${food.name}'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setDialogState(() => savedFood = value),
                )
              else
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'Orange chicken',
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: servings,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Servings remaining',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<StorageLocation>(
                      initialValue: location,
                      decoration: const InputDecoration(labelText: 'Stored in'),
                      items: const [
                        DropdownMenuItem(
                          value: StorageLocation.fridge,
                          child: Text('Fridge'),
                        ),
                        DropdownMenuItem(
                          value: StorageLocation.freezer,
                          child: Text('Freezer'),
                        ),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => location = value!),
                    ),
                  ),
                ],
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
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
              final count = double.tryParse(servings.text.trim());
              if (count == null ||
                  count <= 0 ||
                  (useSavedFood
                      ? savedFood == null
                      : name.text.trim().isEmpty)) {
                setDialogState(
                  () => error = 'Enter a food and positive serving count.',
                );
                return;
              }
              Navigator.pop(context, true);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    ),
  );
  if (submitted == true) {
    final food = useSavedFood ? savedFood : null;
    store.addPreparedBatch(
      name: food?.name ?? name.text.trim(),
      servings: double.parse(servings.text.trim()),
      emoji: food?.emoji ?? '🍽️',
      source: food == null ? PreparedSource.manual : PreparedSource.external,
      sourceId: food?.id,
      location: location,
      nutritionPerServing: food?.nutrition,
      note: food == null
          ? 'Manually added leftover'
          : '${food.brand} · ${food.servingLabel}',
    );
  }
  name.dispose();
  servings.dispose();
}

Future<void> _showEatPreparedFood(
  BuildContext context,
  PantryStore store,
  PreparedBatch batch,
) async {
  final servings = TextEditingController(text: '1');
  final submitted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Eat ${batch.name}'),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: servings,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Servings',
            helperText:
                '${store.units.formatAmount(batch.remainingServings)} remaining',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Log and subtract'),
        ),
      ],
    ),
  );
  if (submitted == true && context.mounted) {
    final amount = double.tryParse(servings.text.trim());
    try {
      if (amount == null) throw ArgumentError('Enter a number');
      final event = store.consumePreparedBatch(batch, amount);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${batch.name} logged. ${store.units.formatAmount(batch.remainingServings - amount)} servings remain.',
          ),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => store.undo(event.id),
          ),
        ),
      );
    } on Object catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
  servings.dispose();
}

Future<void> _showAdjustPreparedFood(
  BuildContext context,
  PantryStore store,
  PreparedBatch batch,
) async {
  final servings = TextEditingController(
    text: store.units.formatAmount(batch.remainingServings),
  );
  final submitted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Adjust ${batch.name}'),
      content: TextField(
        controller: servings,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: 'Servings remaining',
          helperText:
              'Maximum ${store.units.formatAmount(batch.totalServings)}',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (submitted == true) {
    final amount = double.tryParse(servings.text.trim());
    if (amount != null) {
      store.updatePreparedBatch(batch, remainingServings: amount);
    }
  }
  servings.dispose();
}

Future<void> _showMealTemplateEditor(
  BuildContext context,
  PantryStore store, {
  MealTemplate? existing,
}) async {
  final name = TextEditingController(text: existing?.name ?? '');
  final emoji = TextEditingController(text: existing?.emoji ?? '🍽️');
  final servings = TextEditingController(
    text: _compactNumber(existing?.servings ?? 1),
  );
  final selected = <String, TextEditingController>{
    for (final component in existing?.components ?? const <MealComponent>[])
      component.recipeId: TextEditingController(
        text: _compactNumber(component.servings),
      ),
  };
  String? error;
  final submitted = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(
          existing == null ? 'New combined meal' : 'Edit combined meal',
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
                      width: 80,
                      child: TextField(
                        controller: emoji,
                        decoration: const InputDecoration(labelText: 'Emoji'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: name,
                        decoration: const InputDecoration(
                          labelText: 'Meal name',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 110,
                      child: TextField(
                        controller: servings,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Meal servings',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Component recipes and servings',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 8),
                ...store.recipes.map((recipe) {
                  final checked = selected.containsKey(recipe.id);
                  return CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${recipe.emoji}  ${recipe.name}'),
                    value: checked,
                    onChanged: (value) => setDialogState(() {
                      if (value == true) {
                        selected[recipe.id] = TextEditingController(text: '1');
                      } else {
                        selected.remove(recipe.id)?.dispose();
                      }
                    }),
                    secondary: checked
                        ? SizedBox(
                            width: 90,
                            child: TextField(
                              controller: selected[recipe.id],
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Servings',
                              ),
                            ),
                          )
                        : null,
                  );
                }),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () {
                store.deleteMealTemplate(existing.id);
                Navigator.pop(context, false);
              },
              child: const Text('Delete'),
            ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final yieldCount = double.tryParse(servings.text.trim());
              final validComponents = selected.entries.every(
                (entry) => (double.tryParse(entry.value.text.trim()) ?? 0) > 0,
              );
              if (name.text.trim().isEmpty ||
                  yieldCount == null ||
                  yieldCount <= 0 ||
                  selected.length < 2 ||
                  !validComponents) {
                setDialogState(
                  () => error =
                      'Enter a name and choose at least two components with positive servings.',
                );
                return;
              }
              Navigator.pop(context, true);
            },
            child: const Text('Save meal'),
          ),
        ],
      ),
    ),
  );
  if (submitted == true) {
    store.saveMealTemplate(
      MealTemplate(
        id: existing?.id ?? store.nextId(name.text.trim()),
        name: name.text.trim(),
        servings: double.parse(servings.text.trim()),
        components: selected.entries
            .map(
              (entry) => MealComponent(
                recipeId: entry.key,
                servings: double.parse(entry.value.text.trim()),
              ),
            )
            .toList(),
        emoji: emoji.text.trim().isEmpty ? '🍽️' : emoji.text.trim(),
      ),
    );
  }
  name.dispose();
  emoji.dispose();
  servings.dispose();
  for (final controller in selected.values) {
    controller.dispose();
  }
}

Future<void> _showCookRecipe(
  BuildContext context,
  PantryStore store,
  Recipe recipe,
) async {
  final request = await showRecipePortionDialog(context, store, recipe);
  if (request == null || !context.mounted) return;
  try {
    final batch = store.prepareRecipe(
      recipe,
      servings: request.servingsPerPortion * request.count,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${store.units.formatAmount(batch.totalServings)} servings of ${recipe.name} are ready in the fridge.',
        ),
      ),
    );
    if (recipe.promptForFeedback && context.mounted) {
      final feedback = await showRecipeFeedbackDialog(context, recipe);
      if (feedback == null || !context.mounted) return;
      if (feedback.dontAskAgain) {
        store.saveRecipe(recipe.copyWith(promptForFeedback: false));
      }
      if (feedback.tasteRating != null ||
          feedback.easeRating != null ||
          feedback.actualMinutes != null) {
        final now = DateTime.now();
        store.saveRecipeMakeFeedback(
          RecipeMakeFeedback(
            id: 'feedback-${now.microsecondsSinceEpoch}',
            recipeId: recipe.id,
            preparedBatchId: batch.id,
            createdAt: now,
            tasteRating: feedback.tasteRating,
            easeRating: feedback.easeRating,
            actualMinutes: feedback.actualMinutes,
          ),
        );
      }
    }
  } on InsufficientInventoryException catch (exception) {
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
        return '${food.name} (${store.units.formatUnitAmount(food, entry.value, food.baseUnit)} short)';
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
