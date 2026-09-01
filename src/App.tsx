import { useEffect, useMemo, useRef, useState } from 'react';
import {
  Archive,
  BarChart3,
  CalendarDays,
  Check,
  ChevronRight,
  ClipboardList,
  CookingPot,
  Download,
  History as HistoryIcon,
  House,
  ListChecks,
  NotebookTabs,
  PackageOpen,
  Plus,
  RefreshCw,
  ScanLine,
  Search,
  Settings2,
  ShoppingBasket,
  Store,
  Target,
  Trash2,
  TrendingUp,
  Utensils,
  X,
  type LucideIcon,
} from 'lucide-react';
import {
  NAV_ITEMS,
  PAGE_META,
  type PageId,
  type PanelKind,
  type Recipe,
} from './data';
import { usePantryData, type InventoryFood } from './pantry-data';

const PAGE_ICONS: Record<PageId, LucideIcon> = {
  today: House,
  inventory: Archive,
  recipes: CookingPot,
  products: Store,
  'food-log': NotebookTabs,
  history: HistoryIcon,
  trends: BarChart3,
  week: CalendarDays,
  grocery: ListChecks,
};

const PANEL_FOR_PAGE: Record<PageId, PanelKind> = {
  today: 'lot',
  inventory: 'lot',
  recipes: 'recipe',
  products: 'external',
  'food-log': 'log',
  history: 'export',
  trends: 'targets',
  week: 'meal',
  grocery: 'item',
};

interface PanelState {
  kind: PanelKind;
  recipe?: Recipe;
  values?: Record<string, string>;
  inventoryFood?: InventoryFood;
}

const cx = (...values: Array<string | false | null | undefined>) => values.filter(Boolean).join(' ');

export function greetingFor(date: Date, timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone) {
  let hour = date.getHours();
  try { hour = Number(new Intl.DateTimeFormat('en-US', { hour: 'numeric', hourCycle: 'h23', timeZone }).format(date)); } catch { /* Fall back to the device time zone for invalid legacy values. */ }
  return hour < 12 ? 'morning' : hour < 17 ? 'afternoon' : 'evening';
}

function localDateLabel(date: Date, timeZone: string) {
  try { return date.toLocaleDateString([], { weekday: 'short', month: 'short', day: 'numeric', timeZone }).toUpperCase(); }
  catch { return date.toLocaleDateString([], { weekday: 'short', month: 'short', day: 'numeric' }).toUpperCase(); }
}

function calendarDateKey(date: Date) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}

const servingLabel = (count: number) => `${count} serving${count === 1 ? '' : 's'}`;

export function App({ ownerName = 'Drew', syncStatus = 'synced', onSignOut, onToggleGrocery, onVoidFoodLog, onSaveAction, onLogExternal, onCookRecipe, onSavePrepFeedback, onCookRecipes, onConsumePrepared, onRebuildShopping, onRemovePlannedMeals, onSetPlannedMealsMade, onRemoveGrocery, onConsumeInventoryLot, onSetInventoryLotQuantity }: { ownerName?: string; syncStatus?: 'connecting' | 'synced' | 'error'; onSignOut?: () => void; onToggleGrocery?: (id: string, checked: boolean) => Promise<void>; onVoidFoodLog?: (id: string) => Promise<void>; onSaveAction?: (kind: PanelKind, form: FormData) => Promise<string>; onLogExternal?: (id: string) => Promise<void>; onCookRecipe?: (id: string) => Promise<string>; onSavePrepFeedback?: (prepId: string, ease: number, taste: number, minutes: number) => Promise<void>; onCookRecipes?: (ids: string[]) => Promise<void>; onConsumePrepared?: (id: string) => Promise<void>; onRebuildShopping?: () => Promise<number>; onRemovePlannedMeals?: (ids: string[]) => Promise<void>; onSetPlannedMealsMade?: (ids: string[], made: boolean) => Promise<void>; onRemoveGrocery?: (id: string) => Promise<void>; onConsumeInventoryLot?: (id: string, quantity: number) => Promise<void>; onSetInventoryLotQuantity?: (id: string, remaining: number, discard: boolean) => Promise<void> } = {}) {
  const pantryData = usePantryData();
  const { foodLog, grocerySections, history, inventorySections, recipes, weekDays } = pantryData;
  const [page, setPage] = useState<PageId>('today');
  const [panel, setPanel] = useState<PanelState | null>(null);
  const groceryKey = (item: { id?: string; name: string }) => item.id ?? item.name;
  const [checkedGroceries, setCheckedGroceries] = useState<Set<string>>(() => new Set(grocerySections.flatMap((section) => section.items).filter((item) => item.checked).map(groceryKey)));
  const [inventoryFilter, setInventoryFilter] = useState('All');
  const [recipeFilter, setRecipeFilter] = useState('All recipes');
  const [search, setSearch] = useState('');
  const [toast, setToast] = useState('');
  const [shoppingMode, setShoppingMode] = useState(false);
  const [activeRecipeIds, setActiveRecipeIds] = useState<Set<string>>(() => new Set(recipes.filter((recipe) => {
    try { return (JSON.parse(localStorage.getItem(`mise.recipe-progress.${recipe.id}`) ?? '[]') as string[]).length > 0; } catch { return false; }
  }).map((recipe) => recipe.id)));

  useEffect(() => {
    setCheckedGroceries(new Set(grocerySections.flatMap((section) => section.items).filter((item) => item.checked).map(groceryKey)));
  }, [grocerySections]);

  useEffect(() => {
    if (!panel) return;
    const closeOnEscape = (event: KeyboardEvent) => { if (event.key === 'Escape') setPanel(null); };
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    window.addEventListener('keydown', closeOnEscape);
    return () => { document.body.style.overflow = previousOverflow; window.removeEventListener('keydown', closeOnEscape); };
  }, [panel]);

  const inventoryFoodCount = inventorySections.reduce((total, section) => total + section.foods.length, 0);
  const inventoryLotCount = inventorySections.reduce((total, section) => total + section.foods.reduce((foodTotal, food) => foodTotal + food.lots.length, 0), 0);
  const groceryTotal = grocerySections.flatMap((section) => section.items).length;
  const groceryDone = checkedGroceries.size;
  const plannedMealCount = new Set(weekDays.flatMap((day) => day.meals.map((meal) => meal.groupId ?? meal.id ?? `${day.dateKey ?? `${day.day}-${day.date}`}-${meal.name}`))).size;
  const now = new Date();
  const dateLabel = localDateLabel(now, pantryData.settings.timeZone);
  const greeting = greetingFor(now, pantryData.settings.timeZone);
  const meta = {
    ...PAGE_META[page],
    title: page === 'today' ? `Good ${greeting}, ${ownerName}` : PAGE_META[page].title,
    eyebrow: page === 'today' || page === 'food-log'
      ? dateLabel
      : page === 'inventory'
        ? `${inventoryFoodCount} FOODS · ${inventoryLotCount} LOTS`
        : page === 'recipes'
          ? `${recipes.length} RECIPE${recipes.length === 1 ? '' : 'S'}`
          : page === 'products'
            ? `${pantryData.products.length} KNOWN PRODUCT${pantryData.products.length === 1 ? '' : 'S'}`
            : page === 'history'
              ? `${history.length} LOGGED DAY${history.length === 1 ? '' : 'S'}`
              : page === 'week'
                ? `${plannedMealCount} PLANNED MEAL${plannedMealCount === 1 ? '' : 'S'}`
                : page === 'grocery'
                  ? `${groceryTotal - groceryDone} ITEM${groceryTotal - groceryDone === 1 ? '' : 'S'} LEFT`
                  : PAGE_META[page].eyebrow,
    subtitle: page === 'today'
      ? `${foodLog.length} food log entr${foodLog.length === 1 ? 'y' : 'ies'} today · ${plannedMealCount} meal${plannedMealCount === 1 ? '' : 's'} planned this week.`
      : page === 'recipes'
        ? 'Recipes and live inventory availability.'
        : page === 'history'
          ? 'Meals and nutrition totals from your live food log.'
          : page === 'week'
            ? `${plannedMealCount} meal${plannedMealCount === 1 ? '' : 's'} planned · grocery shortages can be rebuilt from the plan.`
            : PAGE_META[page].subtitle,
  };

  function open(kind: PanelKind, recipe?: Recipe, values?: Record<string, string>) {
    setPanel({ kind, recipe, values });
  }

  function openInventory(food: InventoryFood) {
    setPanel({ kind: 'inventory-detail', inventoryFood: food });
  }

  const todayPins = weekDays.find((day) => day.today)?.meals.flatMap((meal) => recipes.filter((recipe) => recipe.id === meal.recipeId)) ?? [];
  const pinnedRecipes = [...new Map([...todayPins, ...recipes.filter((recipe) => activeRecipeIds.has(recipe.id))].map((recipe) => [recipe.id, recipe])).values()];

  function notify(message: string) {
    setToast(message);
    window.setTimeout(() => setToast(''), 2800);
  }

  function toggleGrocery(item: { id?: string; name: string }) {
    const key = groceryKey(item);
    const nextChecked = !checkedGroceries.has(key);
    setCheckedGroceries((current) => {
      const next = new Set(current);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
    if (item.id && onToggleGrocery) void onToggleGrocery(item.id, nextChecked).catch(() => {
      setCheckedGroceries((current) => { const next = new Set(current); if (nextChecked) next.delete(key); else next.add(key); return next; });
      notify('Could not update that grocery item.');
    });
  }

  function runSecondary() {
    if (page === 'today' || page === 'food-log') open('scan');
    else if (page === 'inventory') open('groceries');
    else if (page === 'week' || page === 'grocery') {
      if (!onRebuildShopping) notify('A live Supabase connection is required to rebuild groceries.');
      else void onRebuildShopping().then((count) => notify(`Grocery list rebuilt with ${count} planned shortage${count === 1 ? '' : 's'}.`)).catch((error: unknown) => notify(error instanceof Error ? error.message : 'Could not rebuild groceries.'));
    }
  }

  return (
    <div className="app-shell">
      <Sidebar
        page={page}
        ownerName={ownerName}
        syncStatus={syncStatus}
        groceryLeft={groceryTotal - groceryDone}
        badges={{ inventory: inventoryFoodCount, recipes: recipes.length, products: pantryData.products.length, week: plannedMealCount }}
        onNavigate={setPage}
        onProfile={() => open('profile')}
        pinnedRecipes={pinnedRecipes}
        onPinnedRecipe={(recipe) => open('cook', recipe)}
        onSignOut={onSignOut}
      />

      <main className="main-shell">
        <header className="page-header">
          <div className="page-header-inner">
            <div className="page-heading">
              <div className="eyebrow">{meta.eyebrow}</div>
              <h1>{meta.title}</h1>
              <p>{meta.subtitle}</p>
            </div>
            <div className="header-actions">
              {meta.secondary && (
                <button className="button secondary" onClick={runSecondary}>
                  {meta.secondary.includes('barcode') ? <ScanLine /> : <RefreshCw />}
                  <span>{meta.secondary}</span>
                </button>
              )}
              <button className="button primary" onClick={() => open(PANEL_FOR_PAGE[page])}>
                <Plus /> <span>{meta.primary}</span>
              </button>
            </div>
          </div>
        </header>

        <div className="page-content">
          {page === 'today' && <TodayPage onNavigate={setPage} onOpen={open} notify={notify} onConsumePrepared={onConsumePrepared} />}
          {page === 'inventory' && (
            <InventoryPage
              filter={inventoryFilter}
              search={search}
              onFilter={setInventoryFilter}
              onSearch={setSearch}
              onOpen={open}
              onOpenFood={openInventory}
            />
          )}
          {page === 'recipes' && <RecipesPage filter={recipeFilter} onFilter={setRecipeFilter} onOpen={open} />}
          {page === 'products' && <ProductsPage onOpen={open} notify={notify} onLog={onLogExternal} />}
          {page === 'food-log' && <FoodLogPage onOpen={open} notify={notify} onVoid={onVoidFoodLog} />}
          {page === 'history' && <HistoryPage onOpen={open} />}
          {page === 'trends' && <TrendsPage onOpen={open} />}
          {page === 'week' && <WeekPage onOpen={open} notify={notify} onRemove={onRemovePlannedMeals} onSetMade={onSetPlannedMealsMade} />}
          {page === 'grocery' && (
            <GroceryPage
              checked={checkedGroceries}
              toggle={toggleGrocery}
              shoppingMode={shoppingMode}
              onShoppingMode={setShoppingMode}
              onRemove={onRemoveGrocery}
              notify={notify}
            />
          )}
        </div>
      </main>

      <MobileNav page={page} onNavigate={setPage} onScan={() => open('scan')} />
      {panel && <ActionPanel state={panel} onClose={() => setPanel(null)} notify={notify} onSave={onSaveAction} onCookRecipe={onCookRecipe} onSavePrepFeedback={onSavePrepFeedback} onCookRecipes={onCookRecipes} onRecipeProgress={(id, active) => setActiveRecipeIds((current) => { const next = new Set(current); if (active) next.add(id); else next.delete(id); return next; })} onConsumeInventoryLot={onConsumeInventoryLot} onSetInventoryLotQuantity={onSetInventoryLotQuantity} />}
      {toast && <div className="toast" role="status"><Check />{toast}</div>}
    </div>
  );
}

function Sidebar({ page, ownerName, syncStatus, groceryLeft, badges, pinnedRecipes, onPinnedRecipe, onNavigate, onProfile, onSignOut }: { page: PageId; ownerName: string; syncStatus: 'connecting' | 'synced' | 'error'; groceryLeft: number; badges: Partial<Record<PageId, number>>; pinnedRecipes: Recipe[]; onPinnedRecipe: (recipe: Recipe) => void; onNavigate: (page: PageId) => void; onProfile: () => void; onSignOut?: () => void }) {
  const initials = ownerName.split(/\s+/).map((part) => part[0]).join('').slice(0, 2).toUpperCase();
  return (
    <aside className="sidebar">
      <button className="brand brand-button" onClick={() => onNavigate('today')} aria-label="Mise home"><span className="brand-mark">🫙</span><strong>Mise</strong><span className={cx('sync-dot', syncStatus)} title={syncStatus === 'synced' ? 'Live data connected' : syncStatus === 'connecting' ? 'Connecting to live updates' : 'Live updates disconnected'} /></button>
      {(['Kitchen', 'Eating', 'Planning'] as const).map((group) => (
        <nav className="nav-group" aria-label={group} key={group}>
          <div className="nav-label">{group}</div>
          {NAV_ITEMS.filter((item) => item.group === group).map((item) => {
            const Icon = PAGE_ICONS[item.id];
            return (
              <button aria-label={item.label} key={item.id} className={cx('nav-item', page === item.id && 'active')} onClick={() => onNavigate(item.id)}>
                <Icon /><span>{item.label}</span>
                {(item.id === 'grocery' || badges[item.id] !== undefined) && <small>{item.id === 'grocery' ? groceryLeft || '✓' : badges[item.id]}</small>}
              </button>
            );
          })}
        </nav>
      ))}
      {pinnedRecipes.length > 0 && <nav className="nav-group pinned-recipes" aria-label="Pinned cooking"><div className="nav-label">On deck</div>{pinnedRecipes.slice(0, 4).map((recipe) => <button className="nav-item" key={recipe.id} onClick={() => onPinnedRecipe(recipe)}><span className="pin-emoji">{recipe.emoji}</span><span>{recipe.name}</span><small>Open</small></button>)}</nav>}
      <div className="sidebar-spacer" />
      <button className="profile-row" aria-label={`${ownerName} — Routine & food profile`} onClick={onProfile}>
        <span className="avatar">{initials}</span><span><strong>{ownerName}</strong><small>Routine & food profile</small></span><Settings2 />
      </button>
      {onSignOut && <button className="text-button sign-out" onClick={onSignOut}>Sign out</button>}
    </aside>
  );
}

function MobileNav({ page, onNavigate, onScan }: { page: PageId; onNavigate: (page: PageId) => void; onScan: () => void }) {
  const items: Array<{ id: PageId; label: string; icon: LucideIcon }> = [
    { id: 'today', label: 'Today', icon: House },
    { id: 'week', label: 'Week', icon: CalendarDays },
    { id: 'grocery', label: 'Shop', icon: ShoppingBasket },
    { id: 'trends', label: 'Trends', icon: TrendingUp },
  ];
  return (
    <nav className="mobile-nav" aria-label="Mobile navigation">
      {items.slice(0, 2).map((item) => <MobileNavItem key={item.id} item={item} page={page} onNavigate={onNavigate} />)}
      <button className="scan-fab" onClick={onScan} aria-label="Look up barcode"><ScanLine /></button>
      {items.slice(2).map((item) => <MobileNavItem key={item.id} item={item} page={page} onNavigate={onNavigate} />)}
    </nav>
  );
}

function MobileNavItem({ item, page, onNavigate }: { item: { id: PageId; label: string; icon: LucideIcon }; page: PageId; onNavigate: (page: PageId) => void }) {
  const Icon = item.icon;
  return <button className={cx(page === item.id && 'active')} onClick={() => onNavigate(item.id)}><Icon /><span>{item.label}</span></button>;
}

function Card({ children, className }: { children: React.ReactNode; className?: string }) {
  return <section className={cx('card', className)}>{children}</section>;
}

function SectionTitle({ title, subtitle, action, onAction }: { title: string; subtitle?: string; action?: string; onAction?: () => void }) {
  return (
    <div className="section-title">
      <div><h2>{title}</h2>{subtitle && <p>{subtitle}</p>}</div>
      {action && (onAction ? <button className="text-button" onClick={onAction}>{action}</button> : <span className="section-meta">{action}</span>)}
    </div>
  );
}

function Progress({ value, color }: { value: number; color?: string }) {
  return <div className="progress"><span style={{ width: `${Math.min(value, 100)}%`, background: color }} /></div>;
}

function TodayPage({ onNavigate, onOpen, notify, onConsumePrepared }: { onNavigate: (page: PageId) => void; onOpen: (kind: PanelKind, recipe?: Recipe, values?: Record<string, string>) => void; notify: (message: string) => void; onConsumePrepared?: (id: string) => Promise<void> }) {
  const { inventorySections, nutrients, preparedLots, recipes, weekDays } = usePantryData();
  const todayIndex = weekDays.findIndex((day) => day.today);
  const relevantDays = todayIndex >= 0 ? weekDays.slice(todayIndex) : weekDays;
  const nextMeal = relevantDays.flatMap((day) => day.meals.map((meal) => ({ ...meal, day }))).find(Boolean);
  const nextRecipe = recipes.find((recipe) => recipe.id === nextMeal?.recipeId || recipe.name === nextMeal?.name);
  const useSoon = inventorySections.flatMap((section) => section.foods).filter((food) => ['warn', 'urgent'].includes(food.tone)).slice(0, 2);
  const popularRecipes = [...recipes].sort((left, right) => (right.prepCount ?? 0) - (left.prepCount ?? 0) || left.name.localeCompare(right.name)).slice(0, 4);
  return (
    <div className="stack">
      <div className="today-grid">
        <Card className="nutrition-card">
          <div className="card-kicker"><span>TODAY · NUTRITION</span><button onClick={() => onOpen('targets')}>Targets</button></div>
          <div className="calorie-total"><strong>{nutrients[0]?.value ?? '0'}</strong><span>{nutrients[0]?.target ?? ''}</span><em>{Math.max(0, 100 - (nutrients[0]?.pct ?? 0))}% left</em></div>
          <div className="macro-list">{nutrients.slice(1, 6).map((row) => <MacroRow key={row.label} {...row} />)}</div>
        </Card>
        <Card className="next-card">
          <div className="card-kicker"><span>NEXT UP</span><button onClick={() => onNavigate('week')}>Week</button></div>
          <div className="featured-meal"><span>{nextMeal?.emoji ?? '📅'}</span><div><strong>{nextMeal?.name ?? 'Nothing planned'}</strong><small>{nextMeal ? `${nextMeal.slot.toLowerCase()} · ${nextMeal.day.today ? 'today' : nextMeal.day.day}` : 'Add a meal to this week'}</small></div></div>
          <div className="split-actions"><button className="button primary" disabled={!nextRecipe} onClick={() => nextRecipe && onOpen('cook', nextRecipe)}>Cook it</button><button className="button secondary" onClick={() => onOpen('meal', undefined, nextMeal?.day.dateKey ? { plan_date: nextMeal.day.dateKey, daypart: nextMeal.slot.toLowerCase() } : undefined)}>{nextMeal ? 'Plan another' : 'Plan meal'}</button></div>
        </Card>
        <Card>
          <div className="card-kicker"><span>USE SOON</span><small>{useSoon.length}</small></div>
          {useSoon.map((food) => <div className={cx('soon-row', food.tone)} key={food.name}><div><strong>{food.name}</strong><small>{food.total} · {food.lots[0]?.split(' ').at(-1)}</small></div><em>{food.due}</em></div>)}
          {!useSoon.length && <div className="soon-row"><div><strong>Nothing urgent</strong><small>No dated lots need attention.</small></div></div>}
          <button className="text-button align-left" onClick={() => onNavigate('recipes')}>Cook something with these →</button>
        </Card>
      </div>

      <Card>
        <SectionTitle title="Ready to eat" />
        {preparedLots.map((lot) => <PreparedRow key={lot.id} emoji={lot.emoji} name={lot.name} where={lot.location} servings={lot.remaining} due={lot.due} progress={lot.progress} onEat={() => { if (onConsumePrepared) void onConsumePrepared(lot.id).then(() => notify(`One serving of ${lot.name} logged and deducted.`)).catch((error: unknown) => notify(error instanceof Error ? error.message : `Could not log ${lot.name}.`)); }} />)}
        {!preparedLots.length && <div className="empty-ready"><CookingPot /><div><strong>Nothing prepared yet</strong><small>Cook a recipe to keep ready-to-eat servings here.</small></div><button className="button secondary compact" onClick={() => onNavigate('recipes')}>Find a recipe</button></div>}
      </Card>

      <Card>
        <SectionTitle title="Popular recipes" subtitle="Your most-prepared recipes, up to four." action="All recipes" onAction={() => onNavigate('recipes')} />
        <div className="cookable-grid">
          {popularRecipes.map((recipe) => (
            <button className="cookable-row" key={recipe.id} onClick={() => onOpen('recipe-detail', recipe)}>
              <span>{recipe.emoji}</span><div><strong>{recipe.name}</strong><small>{recipe.minutes} min · {servingLabel(recipe.servings)}</small></div><ChevronRight />
            </button>
          ))}
        </div>
      </Card>
    </div>
  );
}

function MacroRow({ label, value, target, pct, color }: { label: string; value: string; target: string; pct: number; color: string }) {
  return <div className="macro-row"><div><span>{label}</span><strong>{value}</strong><small>{target}</small></div><Progress value={pct} color={color} /></div>;
}

function PreparedRow({ emoji, name, where, servings, due, progress, onEat }: { emoji: string; name: string; where: string; servings: string; due: string; progress: number; onEat: () => void }) {
  return <div className="prepared-row"><span className="row-emoji">{emoji}</span><div className="grow"><strong>{name}</strong><small>{where}</small></div><div className="servings"><Progress value={progress} /><small>{servings}</small></div><small className="due">{due}</small><button className="button compact" onClick={onEat}>Eat</button></div>;
}

function InventoryPage({ filter, search, onFilter, onSearch, onOpen, onOpenFood }: { filter: string; search: string; onFilter: (filter: string) => void; onSearch: (value: string) => void; onOpen: (kind: PanelKind, recipe?: Recipe, values?: Record<string, string>) => void; onOpenFood: (food: InventoryFood) => void }) {
  const { inventorySections } = usePantryData();
  const sections = useMemo(() => inventorySections.map((section) => ({
    ...section,
    foods: section.foods.filter((food) => food.name.toLowerCase().includes(search.toLowerCase()) && (filter === 'All' || filter === 'Use soon' && ['warn', 'urgent'].includes(food.tone) || filter === 'Fridge' && food.lots.some((lot) => lot.includes('fridge')) || filter === 'Pantry' && food.lots.some((lot) => lot.includes('pantry')))),
  })).filter((section) => section.foods.length), [filter, inventorySections, search]);

  return (
    <div>
      <div className="toolbar inventory-toolbar">
        <label className="search-box"><Search /><input value={search} onChange={(event) => onSearch(event.target.value)} placeholder="Search foods, brands, lots…" /></label>
        {['All', 'Use soon', 'Fridge', 'Pantry'].map((item) => <button key={item} className={cx('filter-chip', filter === item && 'active')} onClick={() => onFilter(item)}>{item}</button>)}
        <span className="toolbar-spacer" />
        <button className="button secondary" onClick={() => onOpen('scan')}><ScanLine />Look up barcode</button>
        <button className="button secondary" onClick={() => onOpen('food')}><PackageOpen />Define food</button>
      </div>
      {sections.map((section) => (
        <Card className="inventory-section" key={section.label}>
          <div className="inventory-section-head"><span>{section.emoji}</span><strong>{section.label}</strong><small>{section.foods.length} foods</small></div>
          {section.foods.map((food) => (
            <button className="inventory-row" key={food.name} onClick={() => onOpenFood(food)}>
              <span className="row-emoji">{food.emoji}</span><div className="inventory-name"><strong>{food.name}</strong><small>{food.sub}</small></div>
              <div className="lot-meter"><div>{food.lots.map((lot, index) => <span key={lot} className={cx('lot-bar', index === 0 && food.tone)} />)}</div><small>{food.lots.join(' · ')}</small></div>
              <strong className="inventory-total">{food.total}</strong><small className={cx('inventory-due', food.tone)}>{food.due}</small>
              <ChevronRight className="row-chevron" />
            </button>
          ))}
        </Card>
      ))}
      {!sections.length && <Card className="empty-state"><Search /><h2>No matching food</h2><p>Try a different name or location filter.</p></Card>}
    </div>
  );
}

function Rating({ label, value }: { label: string; value: number }) {
  return <div className="rating" title={value ? `${value.toFixed(1)} out of 5` : 'Not rated yet'}><small>{label}</small><span>{Array.from({ length: 5 }, (_, index) => <i className={index < Math.round(value) ? 'filled' : ''} key={index} />)}</span><em>{value ? value.toFixed(1) : '—'}</em></div>;
}

function RecipesPage({ filter, onFilter, onOpen }: { filter: string; onFilter: (value: string) => void; onOpen: (kind: PanelKind, recipe?: Recipe) => void }) {
  const { recipes } = usePantryData();
  const visibleRecipes = filter === 'Cookable now' ? recipes.filter((recipe) => recipe.cookable) : recipes;
  return (
    <div>
      <div className="toolbar"><button className={cx('filter-chip', filter === 'All recipes' && 'active')} onClick={() => onFilter('All recipes')}>All recipes <small>{recipes.length}</small></button><button className={cx('filter-chip', filter === 'Cookable now' && 'active')} onClick={() => onFilter('Cookable now')}>Cookable now <small>{recipes.filter((recipe) => recipe.cookable).length}</small></button></div>
      <div className="recipe-grid">
        {visibleRecipes.map((recipe) => (
          <Card className="recipe-card" key={recipe.id}>
            <div className="recipe-head"><span>{recipe.emoji}</span><div className="grow"><div className="title-with-badge"><h2>{recipe.name}</h2></div><small>{recipe.minutes} min · {servingLabel(recipe.servings)} · {recipe.prepCount ?? 0} preparation{recipe.prepCount === 1 ? '' : 's'}</small></div><div><Rating label="EASE" value={recipe.ease} /><Rating label="TASTE" value={recipe.taste} /></div></div>
            <div className="ingredient-chips">{recipe.ingredients.map((item) => { const short = item.stock.includes('· short'); return <span className={short ? 'short' : ''} key={item.label}>{short ? '!' : '✓'} {item.label}</span>; })}</div>
            <p className="recipe-nutrition">{recipe.nutrition}</p>
            <div className="card-actions"><button className="button primary" onClick={() => onOpen('cook', recipe)}>Make batch</button><button className="button secondary" onClick={() => onOpen('recipe-edit', recipe)}>Edit recipe</button></div>
          </Card>
        ))}
        {!visibleRecipes.length && <Card className="empty-state"><CookingPot /><h2>Nothing is fully stocked</h2><p>Add the missing ingredients, then check again.</p></Card>}
      </div>
      <div className="inline-heading"><h2>Meals</h2><p>Cook one recipe or prepare several recipes as one meal.</p><button className="button secondary" onClick={() => onOpen('combined-meal')}>Build a meal</button></div>
      <Card className="combined-meal">
        <div className="combined-summary"><span>🍽️</span><div className="grow"><strong>Build a meal</strong><small>Select one or more recipes and cook them in one inventory transaction.</small></div><button className="button primary" onClick={() => onOpen('combined-meal')}>Choose recipes</button></div>
        <div className="combined-components">{recipes.map((recipe) => <button key={recipe.id} onClick={() => onOpen('recipe-detail', recipe)}><span>{recipe.emoji}</span><div><strong>{recipe.name}</strong><small>{recipe.minutes} min · independently prepared</small></div><ChevronRight /></button>)}</div>
      </Card>
    </div>
  );
}

function GroceryPage({ checked, toggle, shoppingMode, onShoppingMode, onRemove, notify }: { checked: Set<string>; toggle: (item: { id?: string; name: string }) => void; shoppingMode: boolean; onShoppingMode: (value: boolean) => void; onRemove?: (id: string) => Promise<void>; notify: (message: string) => void }) {
  const { grocerySections, inventorySections } = usePantryData();
  const itemKey = (item: { id?: string; name: string }) => item.id ?? item.name;
  const total = grocerySections.flatMap((section) => section.items).length;
  const done = checked.size;
  const next = grocerySections.find((section) => section.items.some((item) => !checked.has(itemKey(item))));
  const alreadyInKitchen = inventorySections.flatMap((section) => section.foods).slice(0, 6);
  return (
    <div className={cx(shoppingMode && 'shopping-mode')}>
      <Card className="grocery-summary">
        <div className="grow"><div className="grocery-count"><strong>{done}<span>/{total}</span></strong><span>{total - done === 0 ? 'Shopping complete' : `${total - done} items left`}</span></div><Progress value={total ? done / total * 100 : 100} /></div>
        <div className="next-aisle"><span>{next ? 'NEXT AISLE' : 'ALL DONE'}</span><strong>{next?.label ?? 'Everything checked'}</strong><button className="button compact" onClick={() => onShoppingMode(!shoppingMode)}>{shoppingMode ? 'Exit shopping mode' : 'Start shopping mode'}</button></div>
      </Card>
      <div className="grocery-grid">
        {grocerySections.map((section) => (
          <Card className={cx('grocery-section', section.items.every((item) => checked.has(itemKey(item))) && 'complete')} key={section.label}>
            <div className="inventory-section-head"><span>{section.emoji}</span><strong>{section.label}</strong><small>{section.items.filter((item) => !checked.has(itemKey(item))).length} left</small></div>
            {section.items.map((item) => (
              <div className={cx('grocery-row', checked.has(itemKey(item)) && 'checked')} key={itemKey(item)}><button className="grocery-toggle" onClick={() => toggle(item)}><span className="check-box">{checked.has(itemKey(item)) && <Check />}</span><strong>{item.name}</strong><small>{item.quantity}</small></button>{item.id && <button className="grocery-remove" aria-label={`Remove ${item.name}`} disabled={!onRemove} onClick={() => { if (onRemove) void onRemove(item.id!).then(() => notify(`${item.name} removed from the grocery list.`)).catch(() => notify(`Could not remove ${item.name}.`)); }}><Trash2 /></button>}</div>
            ))}
          </Card>
        ))}
      </div>
      <div className="already-in"><span>ALREADY IN THE KITCHEN</span><div>{alreadyInKitchen.map((food) => <em key={food.name}>{food.emoji} {food.name}</em>)}</div></div>
    </div>
  );
}

function WeekPage({ onOpen, notify, onRemove, onSetMade }: { onOpen: (kind: PanelKind, recipe?: Recipe, values?: Record<string, string>) => void; notify: (message: string) => void; onRemove?: (ids: string[]) => Promise<void>; onSetMade?: (ids: string[], made: boolean) => Promise<void> }) {
  const { plannedMeals, recipes, settings } = usePantryData();
  const [weekOffset, setWeekOffset] = useState(0);
  const weekDays = useMemo(() => {
    const now = new Date();
    now.setHours(12, 0, 0, 0);
    const start = new Date(now);
    start.setDate(now.getDate() - ((now.getDay() + 6) % 7) + weekOffset * 7);
    return Array.from({ length: 7 }, (_, offset) => {
      const date = new Date(start);
      date.setDate(start.getDate() + offset);
      let dateKey = calendarDateKey(date);
      try {
        const parts = new Intl.DateTimeFormat('en-US', { year: 'numeric', month: '2-digit', day: '2-digit', timeZone: settings.timeZone }).formatToParts(date);
        const value = (type: Intl.DateTimeFormatPartTypes) => parts.find((part) => part.type === type)?.value ?? '';
        dateKey = `${value('year')}-${value('month')}-${value('day')}`;
      } catch { /* device date is a safe fallback */ }
      return { day: date.toLocaleDateString([], { weekday: 'short' }).toUpperCase(), date: String(date.getDate()), dateKey, today: date.toDateString() === now.toDateString(), meals: plannedMeals.filter((meal) => meal.dateKey === dateKey) };
    });
  }, [plannedMeals, settings.timeZone, weekOffset]);
  const weekLabel = `${new Date(`${weekDays[0].dateKey}T12:00:00`).toLocaleDateString([], { month: 'short', day: 'numeric' })} – ${new Date(`${weekDays[6].dateKey}T12:00:00`).toLocaleDateString([], { month: 'short', day: 'numeric', year: 'numeric' })}`;
  const todayKey = calendarDateKey(new Date());
  return (
    <Card className="week-card"><div className="week-switcher"><button className="icon-button" aria-label="Previous week" onClick={() => setWeekOffset((value) => value - 1)}>‹</button><strong>{weekLabel}</strong><button className="icon-button" aria-label="Next week" onClick={() => setWeekOffset((value) => value + 1)}>›</button></div>
      <div className="week-grid">{weekDays.map((day) => (
        <div className={cx('week-day', day.today && 'today', day.dateKey < todayKey && 'past')} key={day.dateKey}>
          <div className="week-date"><strong>{day.day}</strong><small>{day.date}</small></div>
          <div className="week-meals">{[...day.meals.reduce((groups, meal) => { const key = meal.groupId ?? meal.id ?? meal.name; groups.set(key, [...(groups.get(key) ?? []), meal]); return groups; }, new Map<string, typeof day.meals>()).entries()].map(([groupId, meals]) => { const made = meals.every((meal) => meal.status === 'made'); const ids = meals.flatMap((meal) => meal.id ? [meal.id] : []); return <div className={cx('planned-meal-group', made && 'made', meals[0].isLeftover && 'leftover')} key={groupId}><div className="planned-meal-head"><small>{meals[0].slot}{meals[0].isLeftover ? ' · LEFTOVERS' : ''}</small><span className={cx('plan-status', made ? 'made' : day.dateKey < todayKey ? 'missed' : 'planned')}>{made ? 'Made' : day.dateKey < todayKey ? 'Not made' : 'Planned'}</span></div><div className="planned-components">{meals.map((meal) => { const recipe = recipes.find((candidate) => candidate.id === meal.recipeId); return <button key={meal.id} disabled={!recipe} onClick={() => recipe && onOpen('recipe-detail', recipe)}><span>{meal.emoji}</span>{meal.name}</button>; })}</div><div className="plan-actions"><button disabled={!onSetMade || !ids.length} onClick={() => { if (onSetMade) void onSetMade(ids, !made).then(() => notify(made ? 'Meal marked as planned.' : 'Meal marked as made.')).catch(() => notify('Could not update the meal status.')); }}>{made ? 'Undo made' : 'Mark made'}</button><button aria-label={`Remove ${meals.map((meal) => meal.name).join(', ')}`} disabled={!onRemove || !ids.length} onClick={() => { if (onRemove) void onRemove(ids).then(() => notify('Meal removed from the plan.')).catch(() => notify('Could not remove the meal.')); }}><Trash2 /> Remove</button></div></div>; })}</div>
          <button className="day-add" aria-label={`Add meal on ${day.day}`} onClick={() => onOpen('meal', undefined, { plan_date: day.dateKey ?? '' })}><Plus /></button>
        </div>
      ))}</div>
    </Card>
  );
}

function FoodLogPage({ onOpen, notify, onVoid }: { onOpen: (kind: PanelKind) => void; notify: (message: string) => void; onVoid?: (id: string) => Promise<void> }) {
  const { foodLog: todayFoodLog, foodLogByDate, nutrients: todayNutrients, todayProjection } = usePantryData();
  const [selectedDate, setSelectedDate] = useState(() => {
    const date = new Date();
    date.setHours(12, 0, 0, 0);
    return date;
  });
  const today = new Date();
  today.setHours(12, 0, 0, 0);
  const selectedKey = selectedDate.toLocaleDateString('en-CA');
  const isToday = selectedDate.getTime() === today.getTime();
  const selectedDay = foodLogByDate[selectedKey];
  const foodLog = isToday ? todayFoodLog : (selectedDay?.foodLog ?? []);
  const nutrients = isToday ? todayNutrients : (selectedDay?.nutrients ?? todayNutrients.map((nutrient) => ({
    ...nutrient,
    value: nutrient.label === 'Calories' ? '0' : `0 ${nutrient.label === 'Sodium' ? 'mg' : 'g'}`,
    pct: 0,
  })));
  const dateLabel = selectedDate.toLocaleDateString([], { weekday: 'short', month: 'short', day: 'numeric' });
  const moveDay = (days: number) => setSelectedDate((current) => {
    const next = new Date(current);
    next.setDate(next.getDate() + days);
    return next;
  });
  return (
    <div className="stack">
      <div className="date-switcher"><button aria-label="Previous day" onClick={() => moveDay(-1)}>‹</button><strong>{isToday ? 'Today' : dateLabel}</strong>{isToday && <span>{dateLabel}</span>}<button aria-label="Next day" disabled={isToday} onClick={() => moveDay(1)}>›</button></div>
      <Card className="contribution-card">
        <SectionTitle title="How each food built your day" subtitle="Each color is one food or same-day repeat group. The line is your target — sodium's is a limit." action="Targets" onAction={() => onOpen('targets')} />
        <div className="legend">{foodLog.map((item) => <span key={item.id ?? item.label}><i style={{ background: item.color }} />{item.label}<small>{item.calories}</small></span>)}{isToday && Object.values(todayProjection).some(Boolean) && <span><i className="projection-swatch" />Today's plan<small>what if</small></span>}</div>
        {nutrients.map((nutrient) => {
          const label = nutrient.label as keyof typeof todayProjection;
          const target = Number(nutrient.target.replace(/[^\d.]/g, '')) || 1;
          const total = foodLog.reduce((sum, entry) => sum + Number(entry.nutrition?.[label] ?? 0), 0);
          const projection = isToday ? todayProjection[label] : 0;
          const scale = Math.max(target / 0.82, total + projection, 1);
          return <div className="contribution-row" key={nutrient.label}><strong>{nutrient.label}</strong><div className="segment-bar">{foodLog.map((entry, index) => <i key={entry.id ?? `${entry.label}-${index}`} style={{ width: `${Number(entry.nutrition?.[label] ?? 0) / scale * 100}%`, background: entry.color }} />)}{projection > 0 && <i className="projection-segment" style={{ width: `${projection / scale * 100}%` }} />}<b style={{ left: `${target / scale * 100}%` }} /></div><span>{nutrient.value} {nutrient.target}</span></div>;
        })}
      </Card>
      <Card>
        <SectionTitle title="Meals and snacks" action={`${foodLog.length} entr${foodLog.length === 1 ? 'y' : 'ies'}`} />
        {foodLog.map((entry) => <div className="log-row" key={entry.id ?? entry.label}><i style={{ background: entry.color }} /><span className="row-emoji">{entry.emoji}</span><div className="grow"><strong>{entry.label}</strong><small>{entry.serving}</small></div><span>{entry.calories}</span><span>{entry.protein}</span><small>{entry.time}</small>{entry.id && onVoid && <button onClick={() => { void onVoid(entry.id!).then(() => notify(`${entry.label} removed from the food log.`)).catch(() => notify(`Could not remove ${entry.label}.`)); }}>Remove</button>}</div>)}
      </Card>
    </div>
  );
}

function HistoryPage({ onOpen }: { onOpen: (kind: PanelKind) => void }) {
  const { history } = usePantryData();
  const repeated = [...history.reduce((counts, day) => {
    for (const meal of day.meals) counts.set(meal, (counts.get(meal) ?? 0) + 1);
    return counts;
  }, new Map<string, number>()).entries()].sort((left, right) => right[1] - left[1]).slice(0, 5);
  return (
    <div className="history-layout">
      <Card className="grow">
        <SectionTitle title="Day by day" />
        {history.map((day) => <div className="history-day" key={day.date}><div><strong>{day.day}</strong><small>{day.date}</small></div><div>{day.meals.map((meal, index) => <span key={`${meal}-${index}`}>{meal}</span>)}</div><small>{day.totals}</small></div>)}
      </Card>
      <Card className="repeats-card">
        <SectionTitle title="Most repeated" subtitle="Context for planning more variety." />
        {repeated.map(([label, count]) => <div className="repeat-row" key={label}><strong>{count}×</strong><div><span>{label}</span><small>In this displayed range</small></div></div>)}
        {!repeated.length && <div className="empty-inline">No meals logged in this range.</div>}
        <button className="button secondary full" onClick={() => onOpen('export')}><Download />Export this range</button>
      </Card>
    </div>
  );
}

function TrendsPage({ onOpen }: { onOpen: (kind: PanelKind) => void }) {
  const { nutritionHistory, settings } = usePantryData();
  const nutrientLabels = ['Calories', 'Protein', 'Carbs', 'Fat', 'Fiber', 'Sodium'] as const;
  type TrendNutrient = typeof nutrientLabels[number];
  const [nutrient, setNutrient] = useState<TrendNutrient>('Protein');
  const [driverNutrient, setDriverNutrient] = useState<TrendNutrient>('Protein');
  const [range, setRange] = useState(30);
  const spec: Record<TrendNutrient, { target: number; unit: string; color: string }> = {
    Calories: { target: settings.calories, unit: 'cal', color: '#53d7a0' }, Protein: { target: settings.proteinG, unit: 'g', color: '#53d7a0' }, Carbs: { target: settings.carbsG, unit: 'g', color: '#5eb5f5' }, Fat: { target: settings.fatG, unit: 'g', color: '#a78bfa' }, Fiber: { target: settings.fiberG, unit: 'g', color: '#f2d06b' }, Sodium: { target: settings.sodiumMg, unit: 'mg', color: '#ef7d7d' },
  };
  const cutoff = new Date();
  cutoff.setHours(12, 0, 0, 0);
  cutoff.setDate(cutoff.getDate() - (range - 1));
  const cutoffKey = `${cutoff.getFullYear()}-${String(cutoff.getMonth() + 1).padStart(2, '0')}-${String(cutoff.getDate()).padStart(2, '0')}`;
  const recent = nutritionHistory.filter((day) => day.dateKey >= cutoffKey);
  const days = Array.from({ length: range }, (_, index) => {
    const date = new Date(cutoff);
    date.setDate(cutoff.getDate() + index);
    const key = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
    return { label: String(date.getDate()), value: recent.find((day) => day.dateKey === key)?.values[nutrient] ?? 0 };
  });
  const average = days.reduce((total, day) => total + day.value, 0) / range;
  const target = spec[nutrient].target;
  const daysOnTarget = days.filter((day) => nutrient === 'Sodium' ? day.value <= target : day.value >= target).length;
  const chartMaximum = Math.max(target, ...days.map((day) => day.value), 1) * 1.1;
  const averages = nutrientLabels.map((label) => ({ label, value: recent.reduce((total, day) => total + day.values[label], 0) / range, ...spec[label] }));
  const driverTotals = new Map<string, number>();
  for (const day of recent) for (const food of day.foods) driverTotals.set(food.label, (driverTotals.get(food.label) ?? 0) + food.values[driverNutrient]);
  const driverGrandTotal = [...driverTotals.values()].reduce((total, value) => total + value, 0);
  const drivers = [...driverTotals.entries()].sort((left, right) => right[1] - left[1]).slice(0, 5).map(([label, value]) => ({ label, pct: driverGrandTotal ? Math.round(value / driverGrandTotal * 100) : 0 }));
  const driverMax = Math.max(...drivers.map((driver) => driver.pct), 1);
  return (
    <div className="stack">
      <Card className="trend-card">
        <SectionTitle title={`${nutrient}, day by day`} subtitle={`Daily average ${Math.round(average).toLocaleString()} ${spec[nutrient].unit} · target ${target.toLocaleString()} ${spec[nutrient].unit} · ${daysOnTarget} of ${range} days ${nutrient === 'Sodium' ? 'within limit' : 'on target'}`} action="Edit targets" onAction={() => onOpen('targets')} />
        <div className="trend-controls"><div className="driver-tabs">{nutrientLabels.map((label) => <button className={nutrient === label ? 'active' : ''} key={label} onClick={() => setNutrient(label)}>{label}</button>)}</div><label>Range<select value={range} onChange={(event) => setRange(Number(event.target.value))}><option value="7">7 days</option><option value="30">30 days</option><option value="90">90 days</option></select></label></div>
        <div className="bar-chart"><div className="target-line" style={{ bottom: `${target / chartMaximum * 100}%` }}><span>{target.toLocaleString()} {spec[nutrient].unit} target</span></div>{days.map((day, index) => <div className="chart-column" key={index}><i style={{ height: `${day.value / chartMaximum * 100}%`, background: spec[nutrient].color }} /><small>{index % Math.max(1, Math.floor(range / 6)) === 0 ? day.label : ''}</small></div>)}</div>
      </Card>
      <div className="two-column">
        <Card><SectionTitle title="Daily average vs target" subtitle={`Average per calendar day over ${range} days.`} />{averages.map((row) => <MacroRow key={row.label} label={row.label} value={`${Math.round(row.value).toLocaleString()} ${row.unit}`} target={`/ ${row.target.toLocaleString()} ${row.unit}`} pct={row.target ? row.value / row.target * 100 : 0} color={row.color} />)}</Card>
        <Card><SectionTitle title="What drives each nutrient" subtitle={`Share of logged nutrition over ${range} days; bars are relative to the top contributor.`} /><div className="driver-tabs">{nutrientLabels.map((label) => <button className={driverNutrient === label ? 'active' : ''} key={label} onClick={() => setDriverNutrient(label)}>{label}</button>)}</div>{drivers.map(({ label, pct }) => <div className="driver" key={label}><div><span>{label}</span><small>{pct}%</small></div><Progress value={pct / driverMax * 100} /></div>)}{!drivers.length && <div className="empty-inline">No {driverNutrient.toLowerCase()} has been logged in this period.</div>}</Card>
      </div>
    </div>
  );
}

function ProductsPage({ onOpen, notify, onLog }: { onOpen: (kind: PanelKind) => void; notify: (message: string) => void; onLog?: (id: string) => Promise<void> }) {
  const { products } = usePantryData();
  const [query, setQuery] = useState('');
  const [brandFilter, setBrandFilter] = useState('All brands');
  const [sort, setSort] = useState<'used' | 'recent' | 'name'>('used');
  const [viewing, setViewing] = useState<(typeof products)[number] | null>(null);
  const [comparison, setComparison] = useState<string[]>([]);
  const brands = [...new Set(products.map((product) => product.brand || 'Unbranded'))].sort();
  const visible = products.filter((product) =>
    `${product.label} ${product.foodName} ${product.barcode} ${product.estimatedCost ?? ''}`.toLowerCase().includes(query.toLowerCase())
    && (brandFilter === 'All brands' || (product.brand || 'Unbranded') === brandFilter)
  );
  const brandGroups = [...visible.reduce((groups, product) => {
    const brand = product.brand || 'Unbranded';
    groups.set(brand, [...(groups.get(brand) ?? []), product]);
    return groups;
  }, new Map<string, typeof products>()).entries()].sort((left, right) =>
    sort === 'name'
      ? left[0].localeCompare(right[0])
      : Math.max(...right[1].map((item) => sort === 'used' ? item.useCount : Date.parse(item.lastUsedAt) || 0))
        - Math.max(...left[1].map((item) => sort === 'used' ? item.useCount : Date.parse(item.lastUsedAt) || 0))
  );
  const compared = comparison.map((id) => products.find((product) => product.id === id)).filter(Boolean) as typeof products;

  function toggleCompare(id: string) {
    const product = products.find((candidate) => candidate.id === id);
    if (!product) return;
    setComparison((current) => {
      if (current.includes(id)) return current.filter((value) => value !== id);
      const existing = products.find((candidate) => candidate.id === current[0]);
      if (existing && existing.foodId !== product.foodId) {
        notify(`Choose another ${existing.foodName} product to compare.`);
        return current;
      }
      return [...current, id].slice(-2);
    });
  }

  return (
    <div className="stack">
      <div className="toolbar product-toolbar">
        <label className="search-box"><Search /><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search products, foods, brands, barcode, or cost…" /></label>
        <select aria-label="Filter by brand" value={brandFilter} onChange={(event) => setBrandFilter(event.target.value)}><option>All brands</option>{brands.map((brand) => <option key={brand}>{brand}</option>)}</select>
        <select aria-label="Sort products" value={sort} onChange={(event) => setSort(event.target.value as typeof sort)}><option value="used">Most used</option><option value="recent">Recently used</option><option value="name">Brand A–Z</option></select>
        <button className="button secondary" onClick={() => onOpen('scan')}><ScanLine />Scan</button>
      </div>
      {compared.length > 0 && (
        <Card className="comparison-card">
          <SectionTitle title={`Compare ${compared[0].foodName}`} subtitle="Prices are package estimates; nutrition uses each product's stored basis." action="Clear" onAction={() => setComparison([])} />
          <div className="comparison-grid">
            <span /><strong>{compared[0]?.label}</strong><strong>{compared[1]?.label ?? 'Select one more'}</strong>
            <span>Est. cost</span>{compared.map((product) => <em key={`cost-${product.id}`}>{product.estimatedCost === null ? '—' : `$${product.estimatedCost.toFixed(2)}`}</em>)}{compared.length === 1 && <em>—</em>}
            {(['Calories', 'Protein', 'Carbs', 'Fat', 'Fiber', 'Sodium'] as const).flatMap((label) => [
              <span key={`${label}-label`}>{label}</span>,
              ...compared.map((product) => <em key={`${label}-${product.id}`}>{Math.round(product.nutrition[label]).toLocaleString()}{label === 'Calories' ? ' cal' : label === 'Sodium' ? ' mg' : ' g'}</em>),
              ...(compared.length === 1 ? [<em key={`${label}-empty`}>—</em>] : []),
            ])}
          </div>
        </Card>
      )}
      {brandGroups.map(([brand, items]) => (
        <Card className="brand-group" key={brand}>
          <SectionTitle title={brand} action={`${items.length} product${items.length === 1 ? '' : 's'}`} />
          <div className="product-grid">
            {[...items].sort((left, right) => sort === 'name' ? left.name.localeCompare(right.name) : sort === 'used' ? right.useCount - left.useCount : (Date.parse(right.lastUsedAt) || 0) - (Date.parse(left.lastUsedAt) || 0)).map((product) => (
              <div className="product-card" key={product.id}>
                <div className="product-title"><span>{product.emoji}</span><div className="grow"><small>{product.foodName} · used {product.useCount}×</small><strong>{product.name}</strong><em>{product.barcode || 'No barcode'}</em></div></div>
                <div className="product-macros"><span>{product.estimatedCost === null ? 'No cost estimate' : `Est. $${product.estimatedCost.toFixed(2)}`}</span><span>{Math.round(product.nutrition.Calories)} cal</span><span>{Math.round(product.nutrition.Protein)} g protein</span><span>{Math.round(product.nutrition.Sodium)} mg sodium</span></div>
                <div className="card-actions">
                  <button className="button secondary" onClick={() => setViewing(product)}>View</button>
                  <button className={cx('button secondary', comparison.includes(product.id) && 'selected')} onClick={() => toggleCompare(product.id)}>{comparison.includes(product.id) ? 'Selected' : 'Compare'}</button>
                  {product.isExternal && <button className="button primary" disabled={!onLog} onClick={() => { if (onLog) void onLog(product.id).then(() => notify(`${product.name} logged.`)).catch(() => notify(`Could not log ${product.name}.`)); }}>Log</button>}
                </div>
              </div>
            ))}
          </div>
        </Card>
      ))}
      {!visible.length && <Card className="empty-state"><Store /><h2>No matching products</h2><p>Try another name, brand, food, barcode, or cost.</p></Card>}
      {viewing && (
        <div className="panel-layer">
          <button className="panel-scrim" aria-label="Close product details" onClick={() => setViewing(null)} />
          <aside className="action-panel product-detail" role="dialog" aria-modal="true">
            <PanelHeader eyebrow={viewing.foodName.toUpperCase()} title={`${viewing.emoji} ${viewing.label}`} subtitle={viewing.barcode ? `Barcode ${viewing.barcode}` : 'No barcode saved'} onClose={() => setViewing(null)} />
            <div className="panel-body">
              <div className="product-cost-detail"><span>Estimated package cost</span><strong>{viewing.estimatedCost === null ? 'Not estimated' : `$${viewing.estimatedCost.toFixed(2)}`}</strong>{viewing.costSource && <small>{viewing.costSource}{viewing.costAsOf ? ` · as of ${new Date(`${viewing.costAsOf}T00:00:00`).toLocaleDateString()}` : ''}</small>}</div>
              <div className="nutrition-detail">{Object.entries(viewing.nutrition).map(([label, value]) => <div key={label}><span>{label}</span><strong>{Math.round(value).toLocaleString()} {label === 'Calories' ? 'cal' : label === 'Sodium' ? 'mg' : 'g'}</strong></div>)}</div>
            </div>
          </aside>
        </div>
      )}
    </div>
  );
}

const PANEL_COPY: Record<Exclude<PanelKind, 'recipe-detail' | 'cook' | 'combined-meal' | 'inventory-detail'>, { eyebrow: string; title: string; subtitle: string; save: string }> = {
  lot: { eyebrow: 'PUT AWAY', title: 'Add a lot', subtitle: 'Track a quantity, location, and date.', save: 'Save lot' },
  groceries: { eyebrow: 'GROCERY LIST', title: 'Add several grocery items', subtitle: 'Add one manual shopping-list item per line.', save: 'Add items' },
  food: { eyebrow: 'DEFINE', title: 'Define a food', subtitle: 'Units, conversions, nutrition, and where this food normally lives.', save: 'Save food' },
  recipe: { eyebrow: 'RECIPE', title: 'New recipe', subtitle: 'Ingredients are matched against tracked foods for availability.', save: 'Save recipe' },
  'recipe-edit': { eyebrow: 'RECIPE', title: 'Edit recipe', subtitle: 'Update the recipe, ingredients, or method.', save: 'Save changes' },
  external: { eyebrow: 'PRODUCTS', title: 'Add a product', subtitle: 'Add a known restaurant item or packaged product with its nutrition.', save: 'Save product' },
  log: { eyebrow: 'FOOD LOG', title: 'Log food', subtitle: 'Enter a meal and its nutrition by hand.', save: 'Log it' },
  item: { eyebrow: 'GROCERY LIST', title: 'Add an item', subtitle: '', save: 'Add item' },
  meal: { eyebrow: 'PLANNING', title: 'Add a recipe to the plan', subtitle: 'Choose a saved recipe, date, meal, and scale.', save: 'Add to plan' },
  targets: { eyebrow: 'PROFILE', title: 'Edit targets', subtitle: 'Goals and limits used across Today, Food log, and Trends.', save: 'Save targets' },
  export: { eyebrow: 'HISTORY', title: 'Export range', subtitle: 'A CSV of every logged meal in the selected range.', save: 'Download CSV' },
  scan: { eyebrow: 'BARCODE', title: 'Look up a barcode', subtitle: 'Enter a saved UPC or EAN to identify its product.', save: 'Look up' },
  profile: { eyebrow: 'ME', title: 'Routine & food profile', subtitle: 'Hard constraints, preferences, and planning availability.', save: 'Save profile' },
  calendar: { eyebrow: 'CALENDAR', title: 'Mise Planner', subtitle: 'Schedule-aware grocery and preparation reminders.', save: 'Sync now' },
};

function ActionPanel({ state, onClose, notify, onSave, onCookRecipe, onSavePrepFeedback, onCookRecipes, onRecipeProgress, onConsumeInventoryLot, onSetInventoryLotQuantity }: { state: PanelState; onClose: () => void; notify: (message: string) => void; onSave?: (kind: PanelKind, form: FormData) => Promise<string>; onCookRecipe?: (id: string) => Promise<string>; onSavePrepFeedback?: (prepId: string, ease: number, taste: number, minutes: number) => Promise<void>; onCookRecipes?: (ids: string[]) => Promise<void>; onRecipeProgress: (id: string, active: boolean) => void; onConsumeInventoryLot?: (id: string, quantity: number) => Promise<void>; onSetInventoryLotQuantity?: (id: string, remaining: number, discard: boolean) => Promise<void> }) {
  const { history, recipes } = usePantryData();
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  if (state.kind === 'recipe-detail' || state.kind === 'cook') return <RecipePanel recipe={state.recipe ?? recipes[0]} cooking={state.kind === 'cook'} onClose={onClose} notify={notify} onCook={onCookRecipe} onFeedback={onSavePrepFeedback} onProgressChange={onRecipeProgress} />;
  if (state.kind === 'combined-meal') return <CombinedMealPanel onClose={onClose} notify={notify} onCook={onCookRecipes} />;
  if (state.kind === 'inventory-detail') return state.inventoryFood ? <InventoryLotsPanel food={state.inventoryFood} onClose={onClose} notify={notify} onConsume={onConsumeInventoryLot} onSetQuantity={onSetInventoryLotQuantity} /> : null;
  const copy = PANEL_COPY[state.kind];
  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (state.kind === 'export') {
      const form = new FormData(event.currentTarget);
      const from = String(form.get('date_from') ?? '');
      const through = String(form.get('date_to') ?? '');
      const selectedHistory = history.filter((day) => (!from || !day.dateKey || day.dateKey >= from) && (!through || !day.dateKey || day.dateKey <= through));
      const rows = [['date', 'day', 'foods', 'totals'], ...selectedHistory.map((day) => [day.dateKey ?? day.date, day.day, day.meals.join(' | '), day.totals.replace('\n', ' | ')])];
      const csv = rows.map((row) => row.map((cell) => `"${cell.replaceAll('"', '""')}"`).join(',')).join('\n');
      const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }));
      const link = document.createElement('a');
      link.href = url;
      link.download = `mise-history-${new Date().toLocaleDateString('en-CA')}.csv`;
      link.click();
      URL.revokeObjectURL(url);
      onClose();
      notify('History CSV downloaded.');
      return;
    }
    if (!onSave) { setError('This form needs a live Supabase connection.'); return; }
    setSaving(true);
    setError('');
    try {
      const message = await onSave(state.kind, new FormData(event.currentTarget));
      onClose();
      notify(message);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Could not save this change.');
    } finally {
      setSaving(false);
    }
  }
  return (
    <div className="panel-layer">
      <button className="panel-scrim" aria-label="Close panel" onClick={onClose} />
      <aside className="action-panel" role="dialog" aria-modal="true" aria-labelledby="panel-title">
        <PanelHeader eyebrow={copy.eyebrow} title={copy.title} subtitle={copy.subtitle} onClose={onClose} />
        <form id="panel-action-form" onSubmit={(event) => void submit(event)}>
          <div className="panel-body"><PanelFields kind={state.kind} values={state.values} recipe={state.recipe} />{error && <div className="auth-error" role="alert">{error}</div>}</div>
        </form>
        <div className="panel-footer"><button className="button secondary" onClick={onClose}>Cancel</button><button className="button primary" type="submit" form="panel-action-form" disabled={saving}>{saving ? 'Saving…' : copy.save}</button></div>
      </aside>
    </div>
  );
}

function PanelHeader({ eyebrow, title, subtitle, onClose }: { eyebrow: string; title: string; subtitle: string; onClose: () => void }) {
  return <div className="panel-header"><div className="grow"><div className="eyebrow">{eyebrow}</div><h2 id="panel-title">{title}</h2><p>{subtitle}</p></div><button className="icon-button" onClick={onClose} aria-label="Close"><X /></button></div>;
}

function PanelFields({ kind, values = {}, recipe }: { kind: Exclude<PanelKind, 'recipe-detail' | 'cook' | 'combined-meal' | 'inventory-detail'>; values?: Record<string, string>; recipe?: Recipe }) {
  const { categories, locations, plannedMeals, products, recipes, settings, units } = usePantryData();
  const today = new Date().toLocaleDateString('en-CA');
  const defaultUnit = units.find((unit) => unit.shortName === 'ct')?.id ?? units[0]?.id ?? '';

  if (kind === 'scan') return <BarcodeScanner />;

  if (kind === 'targets') return <div className="form-grid two">
    <Field name="nutrition_calories" label="Calories (kcal)" type="number" defaultValue={String(settings.calories)} required />
    <Field name="nutrition_protein_g" label="Protein (g)" type="number" defaultValue={String(settings.proteinG)} required />
    <Field name="nutrition_carbs_g" label="Carbs (g)" type="number" defaultValue={String(settings.carbsG)} required />
    <Field name="nutrition_fat_g" label="Fat (g)" type="number" defaultValue={String(settings.fatG)} required />
    <Field name="nutrition_fiber_g" label="Fiber (g)" type="number" defaultValue={String(settings.fiberG)} required />
    <Field name="nutrition_sodium_mg" label="Sodium limit (mg)" type="number" defaultValue={String(settings.sodiumMg)} required />
  </div>;

  if (kind === 'profile') return <div className="profile-form"><h3>Food constraints</h3>
    <Field name="allergies" label="Allergies and intolerances" defaultValue={settings.allergies.join(', ')} placeholder="Comma-separated" />
    <Field name="dietary_rules" label="Dietary requirements" defaultValue={settings.dietaryRules.join(', ')} placeholder="Vegetarian, halal…" />
    <Field name="dislikes" label="Foods to avoid" defaultValue={settings.dislikes.join(', ')} placeholder="Dislikes and avoidances" />
    <Field name="favorites" label="Favorites" defaultValue={settings.favorites.join(', ')} placeholder="Soft preferences" />
    <h3>Routine & availability</h3><Field name="time_zone" label="Time zone" defaultValue={settings.timeZone} required />
    <label className="field"><span>Planning notes</span><textarea name="planning_notes" rows={4} defaultValue={settings.planningNotes} placeholder="Work schedule, cooking constraints, or planning preferences" /></label>
    <div className="calendar-card"><CalendarDays /><div className="grow"><strong>Google Calendar</strong><small>Calendar sync is not connected in this version.</small></div></div>
  </div>;

  if (kind === 'groceries') return <><label className="field"><span>Paste or type groceries</span><textarea name="groceries" required rows={8} placeholder={'2 onions\n1 bag spinach\n1 dozen eggs'} /></label><div className="notice"><ClipboardList /><span>Each non-empty line becomes a manual grocery item. You can refine quantities after import.</span></div></>;

  if (kind === 'export') return <div className="form-grid"><div className="form-grid two"><Field name="date_from" label="From" type="date" required /><Field name="date_to" label="Through" type="date" defaultValue={today} required /></div><label className="field"><span>Format</span><select name="format"><option value="csv">CSV</option></select></label></div>;

  if (kind === 'meal') return <div className="form-grid">
    <SelectField name="intent" label="Plan type" defaultValue="prepare" options={[{ value: 'prepare', label: 'Prepare a meal' }, { value: 'leftover', label: 'Eat leftovers from a planned meal' }]} required />
    <SelectField name="recipe" label="Recipe (for a newly prepared meal)" defaultValue={values.recipe} options={recipes.map((recipe) => ({ value: recipe.id, label: `${recipe.emoji} ${recipe.name}` }))} />
    <SelectField name="source_group_id" label="Original meal (for leftovers)" options={[...plannedMeals.reduce((groups, meal) => { const group = groups.get(meal.groupId) ?? { value: meal.groupId, label: `${meal.dateKey} · ${meal.name}` }; if (!group.label.includes(meal.name)) group.label += ` + ${meal.name}`; groups.set(meal.groupId, group); return groups; }, new Map<string, { value: string; label: string }>()).values()]} />
    <div className="form-grid two"><Field name="plan_date" label="Date" type="date" defaultValue={values.plan_date || today} required /><SelectField name="daypart" label="Meal" defaultValue={values.daypart || 'dinner'} options={['breakfast', 'brunch', 'lunch', 'dinner', 'snack', 'dessert'].map((value) => ({ value, label: value[0].toUpperCase() + value.slice(1) }))} required /></div>
    <Field name="scale_factor" label="Recipe scale" type="number" defaultValue="1" step="0.25" min="0.25" required />
    <Field name="note" label="Notes" placeholder="Optional planning note" />
  </div>;

  if (kind === 'recipe' || kind === 'recipe-edit') return <div className="form-grid">
    {recipe && <input type="hidden" name="recipe_id" value={recipe.id} />}
    <div className="form-grid two"><Field name="name" label="Recipe name" defaultValue={recipe?.name} placeholder="Recipe name" required /><Field name="emoji" label="Emoji" defaultValue={recipe?.emoji} placeholder="🍳" /></div>
    <div className="form-grid two"><Field name="servings" label="Servings" type="number" defaultValue={String(recipe?.servings ?? 4)} min="0.25" step="0.25" required /><Field name="source_url" label="Source URL" type="url" defaultValue={recipe?.sourceUrl} placeholder="https://…" /></div>
    <label className="field"><span>Ingredients</span><textarea name="ingredients" required rows={7} defaultValue={recipe?.ingredientText} placeholder={'1.5 cup All-purpose flour\n2 ct Egg'} /></label>
    <small>Use: quantity, unit abbreviation, then the exact tracked food name.</small>
    <label className="field"><span>Method</span><textarea name="instructions" rows={7} defaultValue={recipe?.instructionText} placeholder="One step per line" /></label>
    <label className="toggle-row"><input name="prompt_for_feedback" type="checkbox" defaultChecked={recipe?.promptForFeedback ?? true} /><span><strong>Ask how it went after making</strong></span></label>
  </div>;

  if (kind === 'lot') return <div className="form-grid">
    <SelectField name="product" label="Product" defaultValue={values.product} options={products.filter((product) => !product.isExternal).map((product) => ({ value: product.id, label: product.label }))} required />
    <div className="form-grid two"><Field name="initial_qty" label="Stock quantity in product base units" type="number" min="0.001" step="any" required /><Field name="total_cost" label="Total cost (USD)" type="number" min="0" step="0.01" defaultValue="0" /></div>
    <div className="form-grid two"><SelectField name="location" label="Location" options={locations.map((location) => ({ value: location, label: location }))} /><Field name="use_by" label="Best by" type="date" /></div>
    <Field name="note" label="Note" placeholder="Optional lot note" />
    <label className="toggle-row"><input name="cost_is_estimated" type="checkbox" /><span><strong>Cost is estimated</strong></span></label>
  </div>;

  if (kind === 'item') return <div className="form-grid"><Field name="name" label="Item" placeholder="Grocery item" required /><Field name="quantity_label" label="Quantity" placeholder="2 bags" /><Field name="note" label="Note" placeholder="Optional" /></div>;

  if (kind === 'log') return <div className="form-grid">
    <Field name="label" label="Food" placeholder="What did you eat?" required />
    <div className="form-grid two"><Field name="servings" label="Servings" type="number" defaultValue="1" min="0.01" step="any" required /><Field name="occurred_at" label="Time" type="datetime-local" /></div>
    <div className="form-grid two"><Field name="kcal" label="Calories" type="number" min="0" defaultValue="0" /><Field name="protein_g" label="Protein (g)" type="number" min="0" defaultValue="0" /></div>
    <div className="form-grid two"><Field name="carbs_g" label="Carbs (g)" type="number" min="0" defaultValue="0" /><Field name="fat_g" label="Fat (g)" type="number" min="0" defaultValue="0" /></div>
    <div className="form-grid two"><Field name="fiber_g" label="Fiber (g)" type="number" min="0" defaultValue="0" /><Field name="sodium_mg" label="Sodium (mg)" type="number" min="0" defaultValue="0" /></div>
    <Field name="note" label="Note" placeholder="Optional" />
    <label className="toggle-row"><input name="nutrition_is_estimated" type="checkbox" defaultChecked /><span><strong>Nutrition is estimated</strong><small>Keep the confidence visible in the log.</small></span></label>
  </div>;

  if (kind === 'external') return <div className="form-grid">
    <input type="hidden" name="measure_style" value="discrete" /><input type="hidden" name="unit" value={defaultUnit} />
    <input type="hidden" name="package_qty_base" value="1" /><input type="hidden" name="serving_qty_base" value="1" /><input type="hidden" name="nutrition_basis_qty" value="1" />
    <div className="form-grid two"><Field name="name" label="Menu item" placeholder="Exact item or order" required /><Field name="brand" label="Restaurant or brand" placeholder="Where is it from?" required /></div>
    <div className="form-grid two"><Field name="emoji" label="Emoji" placeholder="🥡" /><Field name="barcode" label="Barcode" placeholder="Optional UPC/EAN" /></div>
    <p className="form-help">Nutrition per serving</p>
    <div className="form-grid two"><Field name="kcal" label="Calories" type="number" min="0" defaultValue="0" /><Field name="protein_g" label="Protein (g)" type="number" min="0" defaultValue="0" /></div>
    <div className="form-grid two"><Field name="carbs_g" label="Carbs (g)" type="number" min="0" defaultValue="0" /><Field name="fat_g" label="Fat (g)" type="number" min="0" defaultValue="0" /></div>
    <div className="form-grid two"><Field name="fiber_g" label="Fiber (g)" type="number" min="0" defaultValue="0" /><Field name="sodium_mg" label="Sodium (mg)" type="number" min="0" defaultValue="0" /></div>
    <label className="toggle-row"><input name="nutrition_is_estimated" type="checkbox" /><span><strong>Nutrition is estimated</strong></span></label>
  </div>;

  if (kind === 'food') return <div className="form-grid">
    <div className="form-grid two"><Field name="name" label="Food and product name" placeholder="Name" required /><Field name="brand" label="Brand" placeholder="Optional" /></div>
    <div className="form-grid two"><Field name="emoji" label="Emoji" placeholder="🍽️" /><Field name="barcode" label="Barcode" placeholder="Optional UPC/EAN" /></div>
    <div className="form-grid two"><SelectField name="measure_style" label="Stock style" options={['discrete', 'weight', 'volume'].map((value) => ({ value, label: value }))} required /><SelectField name="unit" label="Stock unit" defaultValue={defaultUnit} options={units.map((unit) => ({ value: unit.id, label: unit.label }))} required /></div>
    <div className="form-grid two"><Field name="package_qty_base" label="Package quantity" type="number" defaultValue="1" min="0.001" step="any" required /><Field name="serving_qty_base" label="Serving quantity" type="number" defaultValue="1" min="0.001" step="any" /></div>
    <SelectField name="grocery_category" label="Grocery category" options={categories.map((category) => ({ value: category, label: category }))} />
    <Field name="ingredient_role" label="Ingredient role" placeholder="Main, supporting, staple…" />
    <Field name="nutrition_basis_qty" label="Nutrition basis quantity" type="number" defaultValue="100" min="0.001" step="any" required />
    <div className="form-grid two"><Field name="kcal" label="Calories" type="number" min="0" defaultValue="0" /><Field name="protein_g" label="Protein (g)" type="number" min="0" defaultValue="0" /></div>
    <div className="form-grid two"><Field name="carbs_g" label="Carbs (g)" type="number" min="0" defaultValue="0" /><Field name="fat_g" label="Fat (g)" type="number" min="0" defaultValue="0" /></div>
    <div className="form-grid two"><Field name="fiber_g" label="Fiber (g)" type="number" min="0" defaultValue="0" /><Field name="sodium_mg" label="Sodium (mg)" type="number" min="0" defaultValue="0" /></div>
    <label className="toggle-row"><input name="nutrition_is_estimated" type="checkbox" /><span><strong>Nutrition is estimated</strong></span></label>
  </div>;

  return <div className="notice"><ClipboardList /><span>This action is not available yet.</span></div>;
}

function Field({ name, label, placeholder, defaultValue, type = 'text', min, step, required }: { name: string; label: string; placeholder?: string; defaultValue?: string; type?: string; min?: string; step?: string; required?: boolean }) {
  return <label className="field"><span>{label}</span><input name={name} type={type} min={min} step={step} required={required} placeholder={placeholder} defaultValue={defaultValue} /></label>;
}

function SelectField({ name, label, options, defaultValue, required }: { name: string; label: string; options: Array<{ value: string; label: string }>; defaultValue?: string; required?: boolean }) {
  return <label className="field"><span>{label}</span><select name={name} defaultValue={defaultValue} required={required}><option value="">Choose…</option>{options.map((option) => <option value={option.value} key={option.value}>{option.label}</option>)}</select></label>;
}

function RecipePanel({ recipe, cooking, onClose, notify, onCook, onFeedback, onProgressChange }: { recipe: Recipe; cooking: boolean; onClose: () => void; notify: (message: string) => void; onCook?: (id: string) => Promise<string>; onFeedback?: (prepId: string, ease: number, taste: number, minutes: number) => Promise<void>; onProgressChange: (id: string, active: boolean) => void }) {
  const storageKey = `mise.recipe-progress.${recipe.id}`;
  const [checks, setChecks] = useState<Set<string>>(() => {
    try { return new Set(JSON.parse(localStorage.getItem(storageKey) ?? '[]') as string[]); } catch { return new Set(); }
  });
  const [saving, setSaving] = useState(false);
  const [prepId, setPrepId] = useState('');
  const [ease, setEase] = useState(0);
  const [taste, setTaste] = useState(0);
  const [minutes, setMinutes] = useState(0);
  const total = recipe.ingredients.length + recipe.steps.length;
  useEffect(() => { localStorage.setItem(storageKey, JSON.stringify([...checks])); onProgressChange(recipe.id, checks.size > 0); }, [checks, recipe.id, storageKey]);
  function toggle(key: string) { setChecks((current) => { const next = new Set(current); if (next.has(key)) next.delete(key); else next.add(key); return next; }); }
  const clearProgress = () => { setChecks(new Set()); localStorage.removeItem(storageKey); };
  if (prepId) return <div className="panel-layer"><button className="panel-scrim" onClick={onClose} aria-label="Close feedback" /><aside className="action-panel recipe-panel" role="dialog" aria-modal="true"><PanelHeader eyebrow="PREPARATION SAVED" title={`How was ${recipe.name}?`} subtitle="This feedback belongs to this preparation and updates the recipe's averages." onClose={onClose} /><div className="panel-body feedback-form"><RatingInput label="Ease" value={ease} onChange={setEase} /><RatingInput label="Taste" value={taste} onChange={setTaste} /><label className="field"><span>Actual time (minutes)</span><input type="number" min="0" value={minutes} onChange={(event) => setMinutes(Number(event.target.value))} /></label><small>Ratings default to 0, which means “not rated” and is excluded from the average.</small></div><div className="panel-footer"><button className="button secondary" onClick={() => { clearProgress(); onClose(); }}>Skip</button><button className="button primary" disabled={saving || !onFeedback} onClick={() => { if (!onFeedback) return; setSaving(true); void onFeedback(prepId, ease, taste, minutes).then(() => { clearProgress(); onClose(); notify('Preparation feedback saved.'); }).catch((error: unknown) => notify(error instanceof Error ? error.message : 'Could not save feedback.')).finally(() => setSaving(false)); }}>{saving ? 'Saving…' : 'Save feedback'}</button></div></aside></div>;
  return <div className="panel-layer"><button className="panel-scrim" onClick={onClose} aria-label="Close panel" /><aside className="action-panel recipe-panel" role="dialog" aria-modal="true"><PanelHeader eyebrow={cooking ? 'COOKING MODE' : 'RECIPE'} title={`${recipe.emoji} ${recipe.name}`} subtitle={`${servingLabel(recipe.servings)} · ${recipe.minutes} minutes · ${recipe.nutrition}`} onClose={onClose} /><div className="panel-body"><div className="cooking-progress"><span>{checks.size} of {total} complete</span><Progress value={total ? checks.size / total * 100 : 0} />{checks.size > 0 && <button className="text-button" onClick={clearProgress}>Reset</button>}</div><h3>INGREDIENTS</h3>{recipe.ingredients.map((item, index) => <CheckRow key={item.label} checked={checks.has(`i${index}`)} onClick={() => toggle(`i${index}`)} title={item.label} meta={item.stock} />)}<h3>METHOD</h3>{recipe.steps.map((step, index) => <CheckRow key={step} checked={checks.has(`s${index}`)} onClick={() => toggle(`s${index}`)} title={`${index + 1}. ${step}`} />)}</div><div className="panel-footer"><button className="button secondary" onClick={onClose}>Close</button><button className="button primary" disabled={!onCook || saving} onClick={() => { if (!onCook) return; setSaving(true); void onCook(recipe.id).then((id) => { setPrepId(id); notify(`${recipe.name} cooked and inventory deducted.`); }).catch((error: unknown) => notify(error instanceof Error ? error.message : `Could not cook ${recipe.name}.`)).finally(() => setSaving(false)); }}>{saving ? 'Saving…' : cooking ? 'Mark cooked' : 'Cook and deduct'}</button></div></aside></div>;
}

function InventoryLotsPanel({ food, onClose, notify, onConsume, onSetQuantity }: { food: InventoryFood; onClose: () => void; notify: (message: string) => void; onConsume?: (id: string, quantity: number) => Promise<void>; onSetQuantity?: (id: string, remaining: number, discard: boolean) => Promise<void> }) {
  const [busy, setBusy] = useState('');
  const run = (id: string, action: () => Promise<void>, message: string) => {
    setBusy(id);
    void action().then(() => { notify(message); onClose(); }).catch((error: unknown) => notify(error instanceof Error ? error.message : 'Could not update this lot.')).finally(() => setBusy(''));
  };
  return <div className="panel-layer"><button className="panel-scrim" onClick={onClose} aria-label="Close lot details" /><aside className="action-panel lot-detail-panel" role="dialog" aria-modal="true"><PanelHeader eyebrow="INVENTORY LOTS" title={`${food.emoji} ${food.name}`} subtitle={`${food.total} across ${food.lotDetails?.length ?? 0} lot${food.lotDetails?.length === 1 ? '' : 's'}`} onClose={onClose} /><div className="panel-body lot-detail-list">{food.lotDetails?.map((lot) => <form className="lot-detail-card" key={lot.id} onSubmit={(event) => event.preventDefault()}><div className="lot-detail-head"><strong>{lot.quantity}</strong><span>{lot.location}</span><em className={lot.tone}>{lot.dateLabel}</em></div><div className="lot-actions"><label><span>Consume</span><input name="consume" type="number" min="0.001" max={lot.remainingBase} step="any" defaultValue={Math.min(1, lot.remainingBase)} /></label><button className="button secondary" disabled={!onConsume || busy === lot.id} onClick={(event) => { const form = event.currentTarget.form!; const quantity = Number(new FormData(form).get('consume')); if (onConsume) run(lot.id, () => onConsume(lot.id, quantity), `${quantity} consumed and logged.`); }}>Consume</button></div><div className="lot-actions"><label><span>Set remaining</span><input name="remaining" type="number" min="0" step="any" defaultValue={lot.remainingBase} /></label><button className="button secondary" disabled={!onSetQuantity || busy === lot.id} onClick={(event) => { const form = event.currentTarget.form!; const remaining = Number(new FormData(form).get('remaining')); if (onSetQuantity) run(lot.id, () => onSetQuantity(lot.id, remaining, false), 'Lot quantity adjusted.'); }}>Adjust</button><button className="button danger" disabled={!onSetQuantity || busy === lot.id} onClick={() => { if (onSetQuantity && window.confirm(`Discard all remaining ${food.name} in this lot as waste?`)) run(lot.id, () => onSetQuantity(lot.id, 0, true), 'Lot discarded as waste.'); }}><Trash2 /> Discard all</button></div></form>)}{!food.lotDetails?.length && <div className="empty-inline">No available lots.</div>}</div><div className="panel-footer"><button className="button secondary" onClick={onClose}>Close</button></div></aside></div>;
}

function BarcodeScanner() {
  const videoRef = useRef<HTMLVideoElement>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const frameRef = useRef<number>(0);
  const [barcode, setBarcode] = useState('');
  const [scanning, setScanning] = useState(false);
  const [message, setMessage] = useState('Use your phone camera or enter the UPC / EAN.');
  const stop = () => {
    cancelAnimationFrame(frameRef.current);
    streamRef.current?.getTracks().forEach((track) => track.stop());
    streamRef.current = null;
    setScanning(false);
  };
  useEffect(() => stop, []);
  async function start() {
    const Detector = (window as unknown as { BarcodeDetector?: new (options: { formats: string[] }) => { detect: (source: HTMLVideoElement) => Promise<Array<{ rawValue: string }>> } }).BarcodeDetector;
    if (!Detector) { setMessage('This browser does not support live barcode detection. Enter the number below.'); return; }
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: { ideal: 'environment' } }, audio: false });
      streamRef.current = stream;
      if (!videoRef.current) return;
      videoRef.current.srcObject = stream;
      await videoRef.current.play();
      setScanning(true);
      setMessage('Point the camera at the barcode.');
      const detector = new Detector({ formats: ['upc_a', 'upc_e', 'ean_8', 'ean_13', 'code_128'] });
      const detect = async () => {
        if (!videoRef.current || !streamRef.current) return;
        try {
          const found = await detector.detect(videoRef.current);
          if (found[0]?.rawValue) { setBarcode(found[0].rawValue); setMessage(`Found ${found[0].rawValue}`); stop(); return; }
        } catch { /* keep scanning through transient camera frames */ }
        frameRef.current = requestAnimationFrame(() => void detect());
      };
      void detect();
    } catch (cause) {
      setMessage(cause instanceof Error ? cause.message : 'Camera access was not available.');
      stop();
    }
  }
  return <div className="scan-box"><div className={cx('scanner-frame', scanning && 'live')}><video ref={videoRef} muted playsInline /><ScanLine /><span>{message}</span><i /><i /><i /><i /></div><button className="button secondary full" type="button" onClick={() => scanning ? stop() : void start()}>{scanning ? 'Stop camera' : 'Scan with camera'}</button><label className="field"><span>UPC / EAN</span><input name="barcode" inputMode="numeric" autoComplete="off" value={barcode} onChange={(event) => setBarcode(event.target.value)} placeholder="Enter barcode" required /></label></div>;
}

function RatingInput({ label, value, onChange }: { label: string; value: number; onChange: (value: number) => void }) {
  return <div className="rating-input"><span>{label}</span><div>{Array.from({ length: 5 }, (_, index) => <button type="button" className={index < value ? 'selected' : ''} aria-label={`${label} ${index + 1} out of 5`} key={index} onClick={() => onChange(value === index + 1 ? 0 : index + 1)}>★</button>)}</div><small>{value ? `${value}/5` : 'Not rated'}</small></div>;
}

function CheckRow({ checked, onClick, title, meta }: { checked: boolean; onClick: () => void; title: string; meta?: string }) {
  return <button className={cx('check-row', checked && 'checked')} onClick={onClick}><span className="check-box">{checked && <Check />}</span><div><strong>{title}</strong>{meta && <small>{meta}</small>}</div></button>;
}

function CombinedMealPanel({ onClose, notify, onCook }: { onClose: () => void; notify: (message: string) => void; onCook?: (ids: string[]) => Promise<void> }) {
  const { recipes } = usePantryData();
  const [selected, setSelected] = useState(new Set(recipes.map((recipe) => recipe.id)));
  const [saving, setSaving] = useState(false);
  return <div className="panel-layer"><button className="panel-scrim" onClick={onClose} aria-label="Close panel" /><aside className="action-panel" role="dialog" aria-modal="true"><PanelHeader eyebrow="MEAL" title="🍽️ Build a meal" subtitle="Prepare one or more recipes in one atomic inventory transaction." onClose={onClose} /><div className="panel-body"><h3>RECIPES IN THIS MEAL</h3>{recipes.map((recipe) => <CheckRow key={recipe.id} checked={selected.has(recipe.id)} onClick={() => setSelected((current) => { const next = new Set(current); if (next.has(recipe.id)) next.delete(recipe.id); else next.add(recipe.id); return next; })} title={`${recipe.emoji} ${recipe.name}`} meta={`${recipe.servings} servings · ${recipe.minutes} min`} />)}<div className="notice"><Utensils /><span>Every selected recipe keeps its own identity and prepared output. If any ingredient is short, nothing is deducted.</span></div></div><div className="panel-footer"><button className="button secondary" onClick={onClose}>Cancel</button><button className="button primary" disabled={!selected.size || !onCook || saving} onClick={() => { if (!onCook) return; setSaving(true); void onCook([...selected]).then(() => { onClose(); notify(`${selected.size} recipes cooked and inventory deducted.`); }).catch((error: unknown) => notify(error instanceof Error ? error.message : 'Could not cook the meal.')).finally(() => setSaving(false)); }}>{saving ? 'Saving…' : `Cook ${selected.size} recipes`}</button></div></aside></div>;
}
