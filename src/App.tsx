import { useEffect, useMemo, useState } from 'react';
import {
  Archive,
  BarChart3,
  CalendarDays,
  Camera,
  Check,
  ChevronRight,
  ClipboardList,
  CookingPot,
  Download,
  History as HistoryIcon,
  House,
  ListChecks,
  MoreHorizontal,
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
import { usePantryData } from './pantry-data';

const PAGE_ICONS: Record<PageId, LucideIcon> = {
  today: House,
  inventory: Archive,
  recipes: CookingPot,
  'eating-out': Store,
  'food-log': NotebookTabs,
  history: HistoryIcon,
  trends: BarChart3,
  week: CalendarDays,
  grocery: ListChecks,
};

const PANEL_FOR_PAGE: Record<PageId, PanelKind> = {
  today: 'groceries',
  inventory: 'lot',
  recipes: 'recipe',
  'eating-out': 'external',
  'food-log': 'log',
  history: 'export',
  trends: 'targets',
  week: 'meal',
  grocery: 'item',
};

interface PanelState {
  kind: PanelKind;
  recipe?: Recipe;
}

const cx = (...values: Array<string | false | null | undefined>) => values.filter(Boolean).join(' ');

export function App({ onSignOut, onToggleGrocery, onVoidFoodLog, onSaveAction, onLogExternal, onCookRecipe, onCookRecipes, onConsumePrepared, onRebuildShopping }: { onSignOut?: () => void; onToggleGrocery?: (id: string, checked: boolean) => Promise<void>; onVoidFoodLog?: (id: string) => Promise<void>; onSaveAction?: (kind: PanelKind, form: FormData) => Promise<string>; onLogExternal?: (id: string) => Promise<void>; onCookRecipe?: (id: string) => Promise<void>; onCookRecipes?: (ids: string[]) => Promise<void>; onConsumePrepared?: (id: string) => Promise<void>; onRebuildShopping?: () => Promise<number> } = {}) {
  const pantryData = usePantryData();
  const { externalProducts, foodLog, grocerySections, history, inventorySections, recipes, weekDays } = pantryData;
  const [page, setPage] = useState<PageId>('today');
  const [panel, setPanel] = useState<PanelState | null>(null);
  const [checkedGroceries, setCheckedGroceries] = useState<Set<string>>(() => new Set(grocerySections.flatMap((section) => section.items).filter((item) => item.checked).map((item) => item.name)));
  const [inventoryFilter, setInventoryFilter] = useState('All');
  const [recipeFilter, setRecipeFilter] = useState('All recipes');
  const [search, setSearch] = useState('');
  const [toast, setToast] = useState('');
  const [shoppingMode, setShoppingMode] = useState(false);

  useEffect(() => {
    setCheckedGroceries(new Set(grocerySections.flatMap((section) => section.items).filter((item) => item.checked).map((item) => item.name)));
  }, [grocerySections]);

  const inventoryFoodCount = inventorySections.reduce((total, section) => total + section.foods.length, 0);
  const inventoryLotCount = inventorySections.reduce((total, section) => total + section.foods.reduce((foodTotal, food) => foodTotal + food.lots.length, 0), 0);
  const groceryTotal = grocerySections.flatMap((section) => section.items).length;
  const groceryDone = checkedGroceries.size;
  const plannedMealCount = weekDays.reduce((total, day) => total + day.meals.length, 0);
  const dateLabel = new Date().toLocaleDateString([], { weekday: 'short', month: 'short', day: 'numeric' }).toUpperCase();
  const meta = {
    ...PAGE_META[page],
    eyebrow: page === 'today' || page === 'food-log'
      ? dateLabel
      : page === 'inventory'
        ? `${inventoryFoodCount} FOODS · ${inventoryLotCount} LOTS`
        : page === 'recipes'
          ? `${recipes.length} SAVED RECIPE${recipes.length === 1 ? '' : 'S'}`
          : page === 'eating-out'
            ? `${externalProducts.length} SAVED ITEM${externalProducts.length === 1 ? '' : 'S'}`
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
        ? 'Saved recipes and batch cooking. Automatic cookability scoring is coming soon.'
        : page === 'history'
          ? 'Meals and nutrition totals from your live food log.'
          : page === 'week'
            ? `${plannedMealCount} meal${plannedMealCount === 1 ? '' : 's'} planned · grocery shortages can be rebuilt from the plan.`
            : PAGE_META[page].subtitle,
  };

  function open(kind: PanelKind, recipe?: Recipe) {
    setPanel({ kind, recipe });
  }

  function notify(message: string) {
    setToast(message);
    window.setTimeout(() => setToast(''), 2800);
  }

  function toggleGrocery(name: string) {
    const item = grocerySections.flatMap((section) => section.items).find((candidate) => candidate.name === name);
    const nextChecked = !checkedGroceries.has(name);
    setCheckedGroceries((current) => {
      const next = new Set(current);
      if (next.has(name)) next.delete(name);
      else next.add(name);
      return next;
    });
    if (item?.id && onToggleGrocery) void onToggleGrocery(item.id, nextChecked).catch(() => notify('Could not update that grocery item.'));
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
        groceryLeft={groceryTotal - groceryDone}
        badges={{ inventory: inventoryFoodCount, recipes: recipes.length, 'eating-out': externalProducts.length, week: plannedMealCount }}
        onNavigate={setPage}
        onProfile={() => open('profile')}
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
                  {meta.secondary.includes('Scan') ? <ScanLine /> : <RefreshCw />}
                  <span>{meta.secondary}</span>
                </button>
              )}
              <button className="button primary" onClick={() => open(PANEL_FOR_PAGE[page])}>
                <Plus /> <span>{meta.primary}</span>
              </button>
              <button className="icon-button" aria-label="More actions"><MoreHorizontal /></button>
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
            />
          )}
          {page === 'recipes' && <RecipesPage filter={recipeFilter} onFilter={setRecipeFilter} onOpen={open} />}
          {page === 'eating-out' && <EatingOutPage onOpen={open} notify={notify} onLog={onLogExternal} />}
          {page === 'food-log' && <FoodLogPage onOpen={open} notify={notify} onVoid={onVoidFoodLog} />}
          {page === 'history' && <HistoryPage onOpen={open} />}
          {page === 'trends' && <TrendsPage onOpen={open} />}
          {page === 'week' && <WeekPage onOpen={open} />}
          {page === 'grocery' && (
            <GroceryPage
              checked={checkedGroceries}
              toggle={toggleGrocery}
              shoppingMode={shoppingMode}
              onShoppingMode={setShoppingMode}
            />
          )}
        </div>
      </main>

      <MobileNav page={page} onNavigate={setPage} onScan={() => open('scan')} />
      {panel && <ActionPanel state={panel} onClose={() => setPanel(null)} notify={notify} onSave={onSaveAction} onCookRecipe={onCookRecipe} onCookRecipes={onCookRecipes} />}
      {toast && <div className="toast" role="status"><Check />{toast}</div>}
    </div>
  );
}

function Sidebar({ page, groceryLeft, badges, onNavigate, onProfile, onSignOut }: { page: PageId; groceryLeft: number; badges: Partial<Record<PageId, number>>; onNavigate: (page: PageId) => void; onProfile: () => void; onSignOut?: () => void }) {
  return (
    <aside className="sidebar">
      <div className="brand"><span className="brand-mark">🫙</span><strong>Pantry</strong><span className="sync-dot" title="Synced" /></div>
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
      <div className="sidebar-spacer" />
      <button className="profile-row" aria-label="Drew — Routine & food profile" onClick={onProfile}>
        <span className="avatar">DB</span><span><strong>Drew</strong><small>Routine & food profile</small></span><Settings2 />
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
      <button className="scan-fab" onClick={onScan} aria-label="Scan food"><ScanLine /></button>
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
      {action && <button className="text-button" onClick={onAction}>{action}</button>}
    </div>
  );
}

function Progress({ value, color }: { value: number; color?: string }) {
  return <div className="progress"><span style={{ width: `${Math.min(value, 100)}%`, background: color }} /></div>;
}

function TodayPage({ onNavigate, onOpen, notify, onConsumePrepared }: { onNavigate: (page: PageId) => void; onOpen: (kind: PanelKind, recipe?: Recipe) => void; notify: (message: string) => void; onConsumePrepared?: (id: string) => Promise<void> }) {
  const { inventorySections, nutrients, preparedLots, recipes, weekDays } = usePantryData();
  const nextMeal = weekDays.flatMap((day) => day.meals.map((meal) => ({ ...meal, day }))).find(Boolean);
  const useSoon = inventorySections.flatMap((section) => section.foods).filter((food) => ['warn', 'urgent'].includes(food.tone)).slice(0, 2);
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
          <div className="split-actions"><button className="button primary" disabled={!nextMeal} onClick={() => onOpen('cook', recipes.find((recipe) => recipe.name === nextMeal?.name))}>Cook it</button><button className="button secondary" onClick={() => onOpen('meal')}>{nextMeal ? 'Swap' : 'Plan meal'}</button></div>
        </Card>
        <Card>
          <div className="card-kicker"><span>USE SOON</span><small>{useSoon.length}</small></div>
          {useSoon.map((food) => <div className={cx('soon-row', food.tone)} key={food.name}><div><strong>{food.name}</strong><small>{food.total} · {food.lots[0]?.split(' ').at(-1)}</small></div><em>{food.due}</em></div>)}
          {!useSoon.length && <div className="soon-row"><div><strong>Nothing urgent</strong><small>No dated lots need attention.</small></div></div>}
          <button className="text-button align-left" onClick={() => onNavigate('recipes')}>Cook something with these →</button>
        </Card>
      </div>

      <Card>
        <SectionTitle title="Ready to eat" subtitle="Leftovers and prepared batches, separate from raw inventory." action="Add leftover" onAction={() => onOpen('food')} />
        {preparedLots.map((lot) => <PreparedRow key={lot.id} emoji={lot.emoji} name={lot.name} where={lot.location} servings={lot.remaining} due={lot.due} onEat={() => { if (onConsumePrepared) void onConsumePrepared(lot.id).then(() => notify(`One unit of ${lot.name} logged and deducted.`)).catch((error: unknown) => notify(error instanceof Error ? error.message : `Could not log ${lot.name}.`)); }} />)}
        {!preparedLots.length && <div className="empty-inline">No prepared batches are currently in inventory.</div>}
      </Card>

      <Card>
        <SectionTitle title="Saved recipes" subtitle="Inventory is checked atomically when you start cooking." action="All recipes" onAction={() => onNavigate('recipes')} />
        <div className="cookable-grid">
          {recipes.map((recipe) => (
            <button className="cookable-row" key={recipe.id} onClick={() => onOpen('recipe-detail', recipe)}>
              <span>{recipe.emoji}</span><div><strong>{recipe.name}</strong><small>{recipe.minutes} min · {recipe.servings} servings</small></div><ChevronRight />
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

function PreparedRow({ emoji, name, where, servings, due, onEat }: { emoji: string; name: string; where: string; servings: string; due: string; onEat: () => void }) {
  return <div className="prepared-row"><span className="row-emoji">{emoji}</span><div className="grow"><strong>{name}</strong><small>{where}</small></div><div className="servings"><Progress value={55} /><small>{servings}</small></div><small className="due">{due}</small><button className="button compact" onClick={onEat}>Eat</button></div>;
}

function InventoryPage({ filter, search, onFilter, onSearch, onOpen }: { filter: string; search: string; onFilter: (filter: string) => void; onSearch: (value: string) => void; onOpen: (kind: PanelKind) => void }) {
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
        <button className="button secondary" onClick={() => onOpen('scan')}><ScanLine />Scan barcode</button>
        <button className="button secondary" onClick={() => onOpen('food')}><PackageOpen />Define food</button>
      </div>
      {sections.map((section) => (
        <Card className="inventory-section" key={section.label}>
          <div className="inventory-section-head"><span>{section.emoji}</span><strong>{section.label}</strong><small>{section.foods.length} foods</small></div>
          {section.foods.map((food) => (
            <button className="inventory-row" key={food.name} onClick={() => onOpen('lot')}>
              <span className="row-emoji">{food.emoji}</span><div className="inventory-name"><strong>{food.name}</strong><small>{food.sub}</small></div>
              <div className="lot-meter"><div>{food.lots.map((lot, index) => <span key={lot} className={cx('lot-bar', index === 0 && food.tone)} />)}</div><small>{food.lots.join(' · ')}</small></div>
              <strong className="inventory-total">{food.total}</strong><small className={cx('inventory-due', food.tone)}>{food.due}</small>
              <div className="row-actions"><span>+</span><span>−</span><span>···</span></div>
            </button>
          ))}
        </Card>
      ))}
      {!sections.length && <Card className="empty-state"><Search /><h2>No matching food</h2><p>Try a different name or location filter.</p></Card>}
    </div>
  );
}

function Rating({ label, value }: { label: string; value: number }) {
  return <div className="rating"><small>{label}</small><span>{Array.from({ length: 5 }, (_, index) => <i className={index < value ? 'filled' : ''} key={index} />)}</span></div>;
}

function RecipesPage({ filter, onFilter, onOpen }: { filter: string; onFilter: (value: string) => void; onOpen: (kind: PanelKind, recipe?: Recipe) => void }) {
  const { recipes } = usePantryData();
  return (
    <div>
      <div className="toolbar"><button className={cx('filter-chip', filter === 'All recipes' && 'active')} onClick={() => onFilter('All recipes')}>All recipes <small>{recipes.length}</small></button><button className="filter-chip" disabled title="Automatic ingredient availability is planned">Cookable now <small>Coming soon</small></button><button className="filter-chip" disabled title="Grocery-run scoring is planned">Quick grocery run <small>Coming soon</small></button></div>
      <div className="recipe-grid">
        {recipes.map((recipe) => (
          <Card className="recipe-card" key={recipe.id}>
            <div className="recipe-head"><span>{recipe.emoji}</span><div className="grow"><div className="title-with-badge"><h2>{recipe.name}</h2><em>SAVED</em></div><small>{recipe.minutes} min · {recipe.servings} servings</small></div><div><Rating label="EASE" value={recipe.ease} /><Rating label="TASTE" value={recipe.taste} /></div></div>
            <div className="ingredient-chips">{recipe.ingredients.map((item) => <span key={item.label}>✓ {item.label.replace(/^\S+\s/, '')}</span>)}</div>
            <p className="recipe-nutrition">{recipe.nutrition}</p>
            <div className="card-actions"><button className="button primary" onClick={() => onOpen('cook', recipe)}>Make batch</button><button className="button secondary" onClick={() => onOpen('recipe-detail', recipe)}>View recipe</button><span /><button className="icon-button"><MoreHorizontal /></button></div>
          </Card>
        ))}
      </div>
      <div className="inline-heading"><h2>Meals</h2><p>Cook one recipe or prepare several recipes as one meal.</p><button className="button secondary" onClick={() => onOpen('combined-meal')}>Build a meal</button></div>
      <Card className="combined-meal">
        <div className="combined-summary"><span>🍽️</span><div className="grow"><strong>Build a meal</strong><small>Select one or more recipes and cook them in one inventory transaction.</small></div><button className="button primary" onClick={() => onOpen('combined-meal')}>Choose recipes</button></div>
        <div className="combined-components">{recipes.map((recipe) => <button key={recipe.id} onClick={() => onOpen('recipe-detail', recipe)}><span>{recipe.emoji}</span><div><strong>{recipe.name}</strong><small>{recipe.minutes} min · independently prepared</small></div><ChevronRight /></button>)}</div>
      </Card>
    </div>
  );
}

function GroceryPage({ checked, toggle, shoppingMode, onShoppingMode }: { checked: Set<string>; toggle: (name: string) => void; shoppingMode: boolean; onShoppingMode: (value: boolean) => void }) {
  const { grocerySections, inventorySections } = usePantryData();
  const total = grocerySections.flatMap((section) => section.items).length;
  const done = checked.size;
  const next = grocerySections.find((section) => section.items.some((item) => !checked.has(item.name)));
  const alreadyInKitchen = inventorySections.flatMap((section) => section.foods).slice(0, 6);
  return (
    <div className={cx(shoppingMode && 'shopping-mode')}>
      <Card className="grocery-summary">
        <div className="grow"><div className="grocery-count"><strong>{done}<span>/{total}</span></strong><span>{total - done === 0 ? 'Shopping complete' : `${total - done} items left`}</span></div><Progress value={total ? done / total * 100 : 100} /><small>Waugh Chapel Safeway · 2644 Chapel Lake Dr · walking order from the produce-side entrance</small></div>
        <div className="next-aisle"><span>{next ? 'NEXT AISLE' : 'ALL DONE'}</span><strong>{next?.label ?? 'Everything checked'}</strong><button className="button compact" onClick={() => onShoppingMode(!shoppingMode)}>{shoppingMode ? 'Exit shopping mode' : 'Start shopping mode'}</button></div>
      </Card>
      <div className="grocery-grid">
        {grocerySections.map((section) => (
          <Card className={cx('grocery-section', section.items.every((item) => checked.has(item.name)) && 'complete')} key={section.label}>
            <div className="inventory-section-head"><span>{section.emoji}</span><strong>{section.label}</strong><small>{section.items.filter((item) => !checked.has(item.name)).length} left</small></div>
            {section.items.map((item) => (
              <button className={cx('grocery-row', checked.has(item.name) && 'checked')} onClick={() => toggle(item.name)} key={item.name}>
                <span className="check-box">{checked.has(item.name) && <Check />}</span><strong>{item.name}</strong><small>{item.quantity}</small>
              </button>
            ))}
          </Card>
        ))}
      </div>
      <div className="already-in"><span>ALREADY IN THE KITCHEN</span><div>{alreadyInKitchen.map((food) => <em key={food.name}>{food.emoji} {food.name}</em>)}</div></div>
    </div>
  );
}

function WeekPage({ onOpen }: { onOpen: (kind: PanelKind, recipe?: Recipe) => void }) {
  const { weekDays, recipes } = usePantryData();
  return (
    <Card className="week-card">
      <div className="week-grid">{weekDays.map((day) => (
        <div className={cx('week-day', day.today && 'today')} key={day.day}>
          <div className="week-date"><strong>{day.day}</strong><small>{day.date}</small></div>
          <div className="week-meals">{day.meals.map((meal) => <button key={`${meal.slot}-${meal.name}`} onClick={() => onOpen('recipe-detail', recipes.find((recipe) => recipe.name === meal.name))}><small>{meal.slot}</small><span>{meal.emoji} {meal.name}</span></button>)}</div>
          <button className="day-add" onClick={() => onOpen('meal')}><Plus /></button>
        </div>
      ))}</div>
    </Card>
  );
}

function FoodLogPage({ onOpen, notify, onVoid }: { onOpen: (kind: PanelKind) => void; notify: (message: string) => void; onVoid?: (id: string) => Promise<void> }) {
  const { foodLog, nutrients } = usePantryData();
  const segments = [26, 24, 50];
  const today = new Date().toLocaleDateString([], { weekday: 'short', month: 'short', day: 'numeric' });
  return (
    <div className="stack">
      <div className="date-switcher"><button disabled title="Past-day navigation is coming soon">‹</button><strong>Today</strong><span>{today}</span><button disabled>›</button></div>
      <Card className="contribution-card">
        <SectionTitle title="How each food built your day" subtitle="Each color is one food or same-day repeat group. The line is your target — sodium's is a limit." action="Targets" onAction={() => onOpen('targets')} />
        <div className="legend">{foodLog.map((item) => <span key={item.id ?? item.label}><i style={{ background: item.color }} />{item.label}<small>{item.calories}</small></span>)}</div>
        {nutrients.map((nutrient, rowIndex) => (
          <div className="contribution-row" key={nutrient.label}><strong>{nutrient.label}</strong><div className="segment-bar">{segments.slice(0, foodLog.length).map((width, index) => <i key={index} style={{ width: `${width * (0.65 + rowIndex * 0.04)}%`, background: foodLog[index]?.color }} />)}<b style={{ left: `${Math.min(92, 72 + rowIndex * 3)}%` }} /></div><span>{nutrient.value} {nutrient.target}</span></div>
        ))}
      </Card>
      <Card>
        <SectionTitle title="Meals and snacks" action="3 entries" />
        {foodLog.map((entry) => <div className="log-row" key={entry.id ?? entry.label}><i style={{ background: entry.color }} /><span className="row-emoji">{entry.emoji}</span><div className="grow"><strong>{entry.label}</strong><small>{entry.serving}</small></div><span>{entry.calories}</span><span>{entry.protein}</span><small>{entry.time}</small><button onClick={() => { if (entry.id && onVoid) void onVoid(entry.id).then(() => notify(`${entry.label} removed. Undo is available.`)); else notify(`${entry.label} removed. Undo is available.`); }}>Remove</button></div>)}
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
  const { nutrientDrivers, nutrients, proteinTrend, settings } = usePantryData();
  const [driverNutrient, setDriverNutrient] = useState<'Protein' | 'Calories' | 'Sodium'>('Protein');
  const average = proteinTrend.reduce((total, day) => total + day.value, 0) / Math.max(proteinTrend.length, 1);
  const daysOnTarget = proteinTrend.filter((day) => day.value >= settings.proteinG).length;
  const chartMaximum = Math.max(settings.proteinG, ...proteinTrend.map((day) => day.value), 1) * 1.1;
  return (
    <div className="stack">
      <Card className="trend-card">
        <SectionTitle title="Protein, day by day" subtitle={`Average ${Math.round(average)}g · target ${settings.proteinG}g · ${daysOnTarget} of 30 days on target`} action="Edit targets" onAction={() => onOpen('targets')} />
        <div className="bar-chart"><div className="target-line" style={{ bottom: `${settings.proteinG / chartMaximum * 100}%` }}><span>{settings.proteinG}g target</span></div>{proteinTrend.map((day, index) => <div className="chart-column" key={index}><i style={{ height: `${day.value / chartMaximum * 100}%` }} /><small>{index % 5 === 0 ? day.date : ''}</small></div>)}</div>
      </Card>
      <div className="two-column">
        <Card><SectionTitle title="Today vs target" />{nutrients.slice(1).map((row) => <MacroRow key={row.label} {...row} />)}</Card>
        <Card><SectionTitle title="What drives each nutrient" subtitle="Share of logged nutrition over the last 30 days." /><div className="driver-tabs">{(['Protein', 'Calories', 'Sodium'] as const).map((label) => <button className={driverNutrient === label ? 'active' : ''} key={label} onClick={() => setDriverNutrient(label)}>{label}</button>)}</div>{nutrientDrivers[driverNutrient].map(({ label, pct }) => <div className="driver" key={label}><div><span>{label}</span><small>{pct}%</small></div><Progress value={pct} /></div>)}{!nutrientDrivers[driverNutrient].length && <div className="empty-inline">No {driverNutrient.toLowerCase()} has been logged in this period.</div>}</Card>
      </div>
    </div>
  );
}

function EatingOutPage({ onOpen, notify, onLog }: { onOpen: (kind: PanelKind) => void; notify: (message: string) => void; onLog?: (id: string) => Promise<void> }) {
  const { externalProducts } = usePantryData();
  const places = [...new Set(externalProducts.map((product) => product.place))];
  return <div className="grocery-grid">{places.map((place) => { const foods = externalProducts.filter((product) => product.place === place); return <Card className="place-card" key={place}><div className="place-head"><span>{place.slice(0, 2).toUpperCase()}</span><div><strong>{place}</strong><small>{foods.length} saved item{foods.length > 1 ? 's' : ''}</small></div><MoreHorizontal /></div>{foods.map((food) => <div className="place-food" key={food.id}><span>{food.emoji}</span><div className="grow"><strong>{food.name}</strong><small>{food.nutrition}</small></div><button className="button compact" disabled={!onLog} onClick={() => { if (onLog) void onLog(food.id).then(() => notify(`${food.name} added to today's food log.`)).catch(() => notify(`Could not log ${food.name}.`)); }}>Log</button></div>)}<button className="text-button place-add" onClick={() => onOpen('external')}>+ Add another saved food</button></Card>; })}{!places.length && <Card className="empty-state"><Store /><h2>No eating-out foods yet</h2><button className="button primary" onClick={() => onOpen('external')}>Save one</button></Card>}</div>;
}

const PANEL_COPY: Record<Exclude<PanelKind, 'recipe-detail' | 'cook' | 'combined-meal'>, { eyebrow: string; title: string; subtitle: string; save: string }> = {
  lot: { eyebrow: 'PUT AWAY', title: 'Add a lot', subtitle: 'One purchase, one expiry date. Lots deduct earliest-first.', save: 'Save lot' },
  groceries: { eyebrow: 'PUT AWAY', title: 'Put away groceries', subtitle: 'Review a grocery haul, then file every item into a lot.', save: 'Put away' },
  food: { eyebrow: 'DEFINE', title: 'Define a food', subtitle: 'Units, conversions, nutrition, and where this food normally lives.', save: 'Save food' },
  recipe: { eyebrow: 'RECIPE', title: 'New recipe', subtitle: 'Ingredients are matched against tracked foods for availability.', save: 'Save recipe' },
  external: { eyebrow: 'EATING OUT', title: 'Save a food', subtitle: 'A restaurant order or packaged food kept out of inventory.', save: 'Save food' },
  log: { eyebrow: 'FOOD LOG', title: 'Log food', subtitle: 'Pick a saved food or enter nutrition by hand.', save: 'Log it' },
  item: { eyebrow: 'GROCERY LIST', title: 'Add an item', subtitle: 'Placed in the aisle it belongs to in the Safeway walking order.', save: 'Add item' },
  meal: { eyebrow: 'PLANNING', title: 'Add a meal', subtitle: 'A recipe, several recipes, leftovers, or a night eating out.', save: 'Add to plan' },
  targets: { eyebrow: 'PROFILE', title: 'Edit targets', subtitle: 'Goals and limits used across Today, Food log, and Trends.', save: 'Save targets' },
  export: { eyebrow: 'HISTORY', title: 'Export range', subtitle: 'A CSV of every logged meal in the selected range.', save: 'Download CSV' },
  scan: { eyebrow: 'BARCODE', title: 'Scan food', subtitle: 'Use the camera or enter a UPC/EAN manually. Suggestions are always reviewed.', save: 'Enter barcode' },
  profile: { eyebrow: 'ME', title: 'Routine & food profile', subtitle: 'Hard constraints, preferences, and planning availability.', save: 'Save profile' },
  calendar: { eyebrow: 'CALENDAR', title: 'Pantry Planner', subtitle: 'Schedule-aware grocery and preparation reminders.', save: 'Sync now' },
};

function ActionPanel({ state, onClose, notify, onSave, onCookRecipe, onCookRecipes }: { state: PanelState; onClose: () => void; notify: (message: string) => void; onSave?: (kind: PanelKind, form: FormData) => Promise<string>; onCookRecipe?: (id: string) => Promise<void>; onCookRecipes?: (ids: string[]) => Promise<void> }) {
  const { history, recipes } = usePantryData();
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  if (state.kind === 'recipe-detail' || state.kind === 'cook') return <RecipePanel recipe={state.recipe ?? recipes[0]} cooking={state.kind === 'cook'} onClose={onClose} notify={notify} onCook={onCookRecipe} />;
  if (state.kind === 'combined-meal') return <CombinedMealPanel onClose={onClose} notify={notify} onCook={onCookRecipes} />;
  const copy = PANEL_COPY[state.kind];
  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (state.kind === 'export') {
      const rows = [['date', 'day', 'foods', 'totals'], ...history.map((day) => [day.date, day.day, day.meals.join(' | '), day.totals.replace('\n', ' | ')])];
      const csv = rows.map((row) => row.map((cell) => `"${cell.replaceAll('"', '""')}"`).join(',')).join('\n');
      const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }));
      const link = document.createElement('a');
      link.href = url;
      link.download = `pantry-history-${new Date().toLocaleDateString('en-CA')}.csv`;
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
          <div className="panel-body"><PanelFields kind={state.kind} openCalendar={() => notify('Calendar sync will move to a Supabase Edge Function.')} />{error && <div className="auth-error" role="alert">{error}</div>}</div>
        </form>
        <div className="panel-footer"><button className="button secondary" onClick={onClose}>Cancel</button><button className="button primary" type="submit" form="panel-action-form" disabled={saving}>{saving ? 'Saving…' : copy.save}</button></div>
      </aside>
    </div>
  );
}

function PanelHeader({ eyebrow, title, subtitle, onClose }: { eyebrow: string; title: string; subtitle: string; onClose: () => void }) {
  return <div className="panel-header"><div className="grow"><div className="eyebrow">{eyebrow}</div><h2 id="panel-title">{title}</h2><p>{subtitle}</p></div><button className="icon-button" onClick={onClose} aria-label="Close"><X /></button></div>;
}

function PanelFields({ kind, openCalendar }: { kind: Exclude<PanelKind, 'recipe-detail' | 'cook' | 'combined-meal'>; openCalendar: () => void }) {
  const { categories, locations, products, recipes, settings, units } = usePantryData();
  const today = new Date().toLocaleDateString('en-CA');
  const defaultUnit = units.find((unit) => unit.shortName === 'ct')?.id ?? units[0]?.id ?? '';

  if (kind === 'scan') return <div className="scan-box"><div className="scanner-frame"><ScanLine /><span>Camera scanning is not enabled yet</span><i /><i /><i /><i /></div><button className="button secondary full" type="button" disabled><Camera />Camera coming after core CRUD</button><div className="divider"><span>or</span></div><Field name="barcode" label="UPC / EAN" placeholder="Enter barcode" required /></div>;

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
    <label className="field"><span>Planning notes</span><textarea name="planning_notes" rows={4} placeholder="Work schedule, cooking constraints, or planning preferences" /></label>
    <div className="calendar-card"><CalendarDays /><div className="grow"><strong>Google Calendar</strong><small>Calendar sync is paused until its Firebase Function is replaced.</small></div><button className="button compact" type="button" onClick={openCalendar}>Details</button></div>
  </div>;

  if (kind === 'groceries') return <><label className="field"><span>Paste or type groceries</span><textarea name="groceries" required rows={8} placeholder={'2 onions\n1 bag spinach\n1 dozen eggs'} /></label><div className="notice"><ClipboardList /><span>Each non-empty line becomes a manual grocery item. You can refine quantities after import.</span></div></>;

  if (kind === 'export') return <div className="form-grid"><div className="form-grid two"><Field name="date_from" label="From" type="date" required /><Field name="date_to" label="Through" type="date" defaultValue={today} required /></div><label className="field"><span>Format</span><select name="format"><option value="csv">CSV</option></select></label></div>;

  if (kind === 'meal') return <div className="form-grid">
    <SelectField name="recipe" label="Recipe" options={recipes.map((recipe) => ({ value: recipe.id, label: `${recipe.emoji} ${recipe.name}` }))} required />
    <div className="form-grid two"><Field name="plan_date" label="Date" type="date" defaultValue={today} required /><SelectField name="daypart" label="Meal" options={['breakfast', 'brunch', 'lunch', 'dinner', 'snack', 'dessert'].map((value) => ({ value, label: value[0].toUpperCase() + value.slice(1) }))} required /></div>
    <Field name="scale_factor" label="Recipe scale" type="number" defaultValue="1" step="0.25" min="0.25" required />
    <Field name="note" label="Notes" placeholder="Optional planning note" />
  </div>;

  if (kind === 'recipe') return <div className="form-grid">
    <div className="form-grid two"><Field name="name" label="Recipe name" placeholder="Recipe name" required /><Field name="emoji" label="Emoji" placeholder="🍳" /></div>
    <div className="form-grid two"><Field name="servings" label="Servings" type="number" defaultValue="4" min="0.25" step="0.25" required /><Field name="source_url" label="Source URL" type="url" placeholder="https://…" /></div>
    <label className="field"><span>Ingredients</span><textarea name="ingredients" required rows={7} placeholder={'1.5 cup All-purpose flour\n2 ct Egg'} /></label>
    <small>Use: quantity, unit abbreviation, then the exact tracked food name.</small>
    <label className="field"><span>Method</span><textarea name="instructions" rows={7} placeholder="One step per line" /></label>
    <label className="toggle-row"><input name="prompt_for_feedback" type="checkbox" defaultChecked /><span><strong>Ask how it went after making</strong><small>Collect taste, ease, and actual cooking time.</small></span></label>
  </div>;

  if (kind === 'lot') return <div className="form-grid">
    <SelectField name="product" label="Product" options={products.filter((product) => !product.isExternal).map((product) => ({ value: product.id, label: product.label }))} required />
    <div className="form-grid two"><Field name="initial_qty" label="Stock quantity in product base units" type="number" min="0.001" step="any" required /><Field name="total_cost" label="Total cost (USD)" type="number" min="0" step="0.01" required /></div>
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

  if (kind === 'food' || kind === 'external') return <div className="form-grid">
    <div className="form-grid two"><Field name="name" label={kind === 'external' ? 'Menu item' : 'Food and product name'} placeholder="Name" required /><Field name="brand" label={kind === 'external' ? 'Restaurant' : 'Brand'} placeholder="Optional" /></div>
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

function RecipePanel({ recipe, cooking, onClose, notify, onCook }: { recipe: Recipe; cooking: boolean; onClose: () => void; notify: (message: string) => void; onCook?: (id: string) => Promise<void> }) {
  const [checks, setChecks] = useState<Set<string>>(new Set());
  const [saving, setSaving] = useState(false);
  const total = recipe.ingredients.length + recipe.steps.length;
  function toggle(key: string) { setChecks((current) => { const next = new Set(current); if (next.has(key)) next.delete(key); else next.add(key); return next; }); }
  return <div className="panel-layer"><button className="panel-scrim" onClick={onClose} aria-label="Close panel" /><aside className="action-panel recipe-panel" role="dialog" aria-modal="true"><PanelHeader eyebrow={cooking ? 'COOKING MODE' : 'RECIPE'} title={`${recipe.emoji} ${recipe.name}`} subtitle={`${recipe.servings} servings · ${recipe.minutes} minutes · ${recipe.nutrition}`} onClose={onClose} /><div className="panel-body"><div className="cooking-progress"><span>{checks.size} of {total} complete</span><Progress value={checks.size / total * 100} /></div><h3>INGREDIENTS</h3>{recipe.ingredients.map((item, index) => <CheckRow key={item.label} checked={checks.has(`i${index}`)} onClick={() => toggle(`i${index}`)} title={item.label} meta={item.stock} />)}<h3>METHOD</h3>{recipe.steps.map((step, index) => <CheckRow key={step} checked={checks.has(`s${index}`)} onClick={() => toggle(`s${index}`)} title={`${index + 1}. ${step}`} />)}<div className="deduction-preview"><strong>Inventory transaction</strong><small>Mark cooked deducts earliest-expiring ingredient lots atomically. A prepared lot is created when the recipe defines an output food.</small></div></div><div className="panel-footer"><button className="button secondary" onClick={onClose}>Close</button><button className="button primary" disabled={!onCook || saving} onClick={() => { if (!onCook) return; setSaving(true); void onCook(recipe.id).then(() => { onClose(); notify(`${recipe.name} cooked and inventory deducted.`); }).catch((error: unknown) => notify(error instanceof Error ? error.message : `Could not cook ${recipe.name}.`)).finally(() => setSaving(false)); }}>{saving ? 'Saving…' : cooking ? 'Mark cooked' : 'Cook and deduct'}</button></div></aside></div>;
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
