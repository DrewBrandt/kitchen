import { useMemo, useState } from 'react';
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
  FOOD_LOG,
  GROCERY_SECTIONS,
  HISTORY,
  INVENTORY_SECTIONS,
  NAV_ITEMS,
  NUTRIENTS,
  PAGE_META,
  RECIPES,
  TREND_VALUES,
  WEEK_DAYS,
  type PageId,
  type PanelKind,
  type Recipe,
} from './data';

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

export function App() {
  const [page, setPage] = useState<PageId>('today');
  const [panel, setPanel] = useState<PanelState | null>(null);
  const [checkedGroceries, setCheckedGroceries] = useState<Set<string>>(() => new Set(['Eggs']));
  const [inventoryFilter, setInventoryFilter] = useState('All');
  const [recipeFilter, setRecipeFilter] = useState('Cookable now');
  const [search, setSearch] = useState('');
  const [toast, setToast] = useState('');
  const [shoppingMode, setShoppingMode] = useState(false);

  const meta = PAGE_META[page];
  const groceryTotal = GROCERY_SECTIONS.flatMap((section) => section.items).length;
  const groceryDone = checkedGroceries.size;

  function open(kind: PanelKind, recipe?: Recipe) {
    setPanel({ kind, recipe });
  }

  function notify(message: string) {
    setToast(message);
    window.setTimeout(() => setToast(''), 2800);
  }

  function toggleGrocery(name: string) {
    setCheckedGroceries((current) => {
      const next = new Set(current);
      if (next.has(name)) next.delete(name);
      else next.add(name);
      return next;
    });
  }

  function runSecondary() {
    if (page === 'today' || page === 'food-log') open('scan');
    else if (page === 'inventory') open('groceries');
    else if (page === 'week' || page === 'grocery') notify('Grocery list rebuilt from the current plan.');
  }

  return (
    <div className="app-shell">
      <Sidebar
        page={page}
        groceryLeft={groceryTotal - groceryDone}
        onNavigate={setPage}
        onProfile={() => open('profile')}
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
          {page === 'today' && <TodayPage onNavigate={setPage} onOpen={open} notify={notify} />}
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
          {page === 'eating-out' && <EatingOutPage onOpen={open} notify={notify} />}
          {page === 'food-log' && <FoodLogPage onOpen={open} notify={notify} />}
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
      {panel && <ActionPanel state={panel} onClose={() => setPanel(null)} notify={notify} />}
      {toast && <div className="toast" role="status"><Check />{toast}</div>}
    </div>
  );
}

function Sidebar({ page, groceryLeft, onNavigate, onProfile }: { page: PageId; groceryLeft: number; onNavigate: (page: PageId) => void; onProfile: () => void }) {
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
                {(item.id === 'grocery' ? groceryLeft > 0 ? groceryLeft : '✓' : item.badge) && <small>{item.id === 'grocery' ? groceryLeft || '✓' : item.badge}</small>}
              </button>
            );
          })}
        </nav>
      ))}
      <div className="sidebar-spacer" />
      <button className="profile-row" aria-label="Drew — Routine & food profile" onClick={onProfile}>
        <span className="avatar">DB</span><span><strong>Drew</strong><small>Routine & food profile</small></span><Settings2 />
      </button>
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

function TodayPage({ onNavigate, onOpen, notify }: { onNavigate: (page: PageId) => void; onOpen: (kind: PanelKind, recipe?: Recipe) => void; notify: (message: string) => void }) {
  return (
    <div className="stack">
      <div className="today-grid">
        <Card className="nutrition-card">
          <div className="card-kicker"><span>TODAY · NUTRITION</span><button onClick={() => onOpen('targets')}>Targets</button></div>
          <div className="calorie-total"><strong>1,180</strong><span>/ 2,300 cal</span><em>1,120 left</em></div>
          <div className="macro-list">{NUTRIENTS.slice(1, 6).map((row) => <MacroRow key={row.label} {...row} />)}</div>
        </Card>
        <Card className="next-card">
          <div className="card-kicker"><span>NEXT UP</span><button onClick={() => onNavigate('week')}>Week</button></div>
          <div className="featured-meal"><span>🥞</span><div><strong>Simple Pancakes</strong><small>Dinner · today · 4 servings</small></div></div>
          <div className="split-actions"><button className="button primary" onClick={() => onOpen('cook', RECIPES[0])}>Cook it</button><button className="button secondary" onClick={() => onOpen('meal')}>Swap</button></div>
        </Card>
        <Card>
          <div className="card-kicker"><span>USE SOON</span><small>2</small></div>
          <div className="soon-row urgent"><div><strong>Spinach</strong><small>8 oz · fridge</small></div><em>2 days</em></div>
          <div className="soon-row warn"><div><strong>Whole milk</strong><small>1.4 L · fridge</small></div><em>3 days</em></div>
          <button className="text-button align-left" onClick={() => onNavigate('recipes')}>Cook something with these →</button>
        </Card>
      </div>

      <Card>
        <SectionTitle title="Ready to eat" subtitle="Leftovers and prepared batches, separate from raw inventory." action="Add leftover" onAction={() => onOpen('food')} />
        <PreparedRow emoji="🥘" name="Chicken & rice" where="Fridge · made Tuesday" servings="2 of 4 servings" due="Best by tomorrow" onEat={() => notify('One serving logged and removed from the batch.')} />
        <PreparedRow emoji="🥣" name="Tomato soup" where="Freezer · made Aug 18" servings="3 of 6 servings" due="Best by Sep 18" onEat={() => notify('One serving logged and removed from the batch.')} />
      </Card>

      <Card>
        <SectionTitle title="Cookable right now" subtitle="Recipes with every required ingredient available." action="All recipes" onAction={() => onNavigate('recipes')} />
        <div className="cookable-grid">
          {RECIPES.map((recipe) => (
            <button className="cookable-row" key={recipe.id} onClick={() => onOpen('recipe-detail', recipe)}>
              <span>{recipe.emoji}</span><div><strong>{recipe.name}</strong><small>{recipe.minutes} min · {recipe.servings} servings · everything in stock</small></div><ChevronRight />
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
  const sections = useMemo(() => INVENTORY_SECTIONS.map((section) => ({
    ...section,
    foods: section.foods.filter((food) => food.name.toLowerCase().includes(search.toLowerCase()) && (filter === 'All' || filter === 'Use soon' && ['warn', 'urgent'].includes(food.tone) || filter === 'Fridge' && food.lots.some((lot) => lot.includes('fridge')) || filter === 'Pantry' && food.lots.some((lot) => lot.includes('pantry')))),
  })).filter((section) => section.foods.length), [filter, search]);

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
  return (
    <div>
      <div className="toolbar">{[['Cookable now', 2], ['Quick grocery run', 0], ['All recipes', 2]].map(([label, count]) => <button className={cx('filter-chip', filter === label && 'active')} key={label} onClick={() => onFilter(String(label))}>{label} <small>{count}</small></button>)}</div>
      <div className="recipe-grid">
        {RECIPES.map((recipe) => (
          <Card className="recipe-card" key={recipe.id}>
            <div className="recipe-head"><span>{recipe.emoji}</span><div className="grow"><div className="title-with-badge"><h2>{recipe.name}</h2><em>READY</em></div><small>{recipe.minutes} min · {recipe.servings} servings</small></div><div><Rating label="EASE" value={recipe.ease} /><Rating label="TASTE" value={recipe.taste} /></div></div>
            <div className="ingredient-chips">{recipe.ingredients.map((item) => <span key={item.label}>✓ {item.label.replace(/^\S+\s/, '')}</span>)}</div>
            <p className="recipe-nutrition">{recipe.nutrition}</p>
            <div className="card-actions"><button className="button primary" onClick={() => onOpen('cook', recipe)}>Make batch</button><button className="button secondary" onClick={() => onOpen('recipe-detail', recipe)}>View recipe</button><span /><button className="icon-button"><MoreHorizontal /></button></div>
          </Card>
        ))}
      </div>
      <div className="inline-heading"><h2>Combined meals</h2><p>A dinner can combine independently prepared mains and sides.</p><button className="button secondary" onClick={() => onOpen('combined-meal')}>New combined meal</button></div>
      <Card className="combined-meal">
        <div className="combined-summary"><span>🍽️</span><div className="grow"><strong>Weekend brunch</strong><small>2 component recipes · serves 2 · cooked 4× this month</small></div><button className="button primary" onClick={() => onOpen('combined-meal')}>Cook this meal</button><button className="button secondary" onClick={() => onOpen('combined-meal')}>Open</button></div>
        <div className="combined-components">{RECIPES.map((recipe) => <button key={recipe.id} onClick={() => onOpen('recipe-detail', recipe)}><span>{recipe.emoji}</span><div><strong>{recipe.name}</strong><small>{recipe.minutes} min · independently prepared</small></div><ChevronRight /></button>)}</div>
      </Card>
    </div>
  );
}

function GroceryPage({ checked, toggle, shoppingMode, onShoppingMode }: { checked: Set<string>; toggle: (name: string) => void; shoppingMode: boolean; onShoppingMode: (value: boolean) => void }) {
  const total = GROCERY_SECTIONS.flatMap((section) => section.items).length;
  const done = checked.size;
  const next = GROCERY_SECTIONS.find((section) => section.items.some((item) => !checked.has(item.name)));
  return (
    <div className={cx(shoppingMode && 'shopping-mode')}>
      <Card className="grocery-summary">
        <div className="grow"><div className="grocery-count"><strong>{done}<span>/{total}</span></strong><span>{total - done === 0 ? 'Shopping complete' : `${total - done} items left`}</span></div><Progress value={done / total * 100} /><small>Waugh Chapel Safeway · 2644 Chapel Lake Dr · walking order from the produce-side entrance</small></div>
        <div className="next-aisle"><span>{next ? 'NEXT AISLE' : 'ALL DONE'}</span><strong>{next?.label ?? 'Everything checked'}</strong><button className="button compact" onClick={() => onShoppingMode(!shoppingMode)}>{shoppingMode ? 'Exit shopping mode' : 'Start shopping mode'}</button></div>
      </Card>
      <div className="grocery-grid">
        {GROCERY_SECTIONS.map((section) => (
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
      <div className="already-in"><span>ALREADY IN THE KITCHEN</span><div><em>🧂 Salt</em><em>🌾 All-purpose flour</em></div></div>
    </div>
  );
}

function WeekPage({ onOpen }: { onOpen: (kind: PanelKind, recipe?: Recipe) => void }) {
  return (
    <Card className="week-card">
      <div className="week-grid">{WEEK_DAYS.map((day) => (
        <div className={cx('week-day', day.today && 'today')} key={day.day}>
          <div className="week-date"><strong>{day.day}</strong><small>{day.date}</small></div>
          <div className="week-meals">{day.meals.map((meal) => <button key={meal.name} onClick={() => onOpen('recipe-detail', RECIPES.find((recipe) => recipe.name === meal.name))}><small>{meal.slot}</small><span>{meal.emoji} {meal.name}</span></button>)}</div>
          <button className="day-add" onClick={() => onOpen('meal')}><Plus /></button>
        </div>
      ))}</div>
    </Card>
  );
}

function FoodLogPage({ onOpen, notify }: { onOpen: (kind: PanelKind) => void; notify: (message: string) => void }) {
  const segments = [26, 24, 50];
  return (
    <div className="stack">
      <div className="date-switcher"><button>‹</button><strong>Today</strong><span>Thu · Aug 27</span><button disabled>›</button></div>
      <Card className="contribution-card">
        <SectionTitle title="How each food built your day" subtitle="Each color is one food or same-day repeat group. The line is your target — sodium's is a limit." action="Targets" onAction={() => onOpen('targets')} />
        <div className="legend">{FOOD_LOG.map((item) => <span key={item.label}><i style={{ background: item.color }} />{item.label}<small>{item.calories}</small></span>)}</div>
        {NUTRIENTS.map((nutrient, rowIndex) => (
          <div className="contribution-row" key={nutrient.label}><strong>{nutrient.label}</strong><div className="segment-bar">{segments.map((width, index) => <i key={index} style={{ width: `${width * (0.65 + rowIndex * 0.04)}%`, background: FOOD_LOG[index].color }} />)}<b style={{ left: `${Math.min(92, 72 + rowIndex * 3)}%` }} /></div><span>{nutrient.value} {nutrient.target}</span></div>
        ))}
      </Card>
      <Card>
        <SectionTitle title="Meals and snacks" action="3 entries" />
        {FOOD_LOG.map((entry) => <div className="log-row" key={entry.label}><i style={{ background: entry.color }} /><span className="row-emoji">{entry.emoji}</span><div className="grow"><strong>{entry.label}</strong><small>{entry.serving}</small></div><span>{entry.calories}</span><span>{entry.protein}</span><small>{entry.time}</small><button onClick={() => notify(`${entry.label} removed. Undo is available.`)}>Undo</button></div>)}
      </Card>
    </div>
  );
}

function HistoryPage({ onOpen }: { onOpen: (kind: PanelKind) => void }) {
  return (
    <div className="history-layout">
      <Card className="grow">
        <SectionTitle title="Day by day" />
        {HISTORY.map((day) => <div className="history-day" key={day.date}><div><strong>{day.day}</strong><small>{day.date}</small></div><div>{day.meals.map((meal) => <span key={meal}>{meal}{meal.includes('Chicken') && <em>3×</em>}</span>)}</div><small>{day.totals}</small></div>)}
      </Card>
      <Card className="repeats-card">
        <SectionTitle title="Most repeated" subtitle="Context for planning more variety." />
        {[['3×', 'Chicken sandwich', 'Last eaten today'], ['2×', 'Greek yogurt', 'Last eaten today'], ['2×', 'Simple Pancakes', 'Last eaten today']].map(([count, label, last]) => <div className="repeat-row" key={label}><strong>{count}</strong><div><span>{label}</span><small>{last}</small></div></div>)}
        <button className="button secondary full" onClick={() => onOpen('export')}><Download />Export this range</button>
      </Card>
    </div>
  );
}

function TrendsPage({ onOpen }: { onOpen: (kind: PanelKind) => void }) {
  return (
    <div className="stack">
      <Card className="trend-card">
        <SectionTitle title="Protein, day by day" subtitle="Average 96g · target 130g · 11 of 30 days on target" action="Edit targets" onAction={() => onOpen('targets')} />
        <div className="bar-chart"><div className="target-line"><span>130g target</span></div>{TREND_VALUES.map((value, index) => <div className="chart-column" key={index}><i style={{ height: `${value / 1.55}%` }} /><small>{index % 5 === 0 ? index + 1 : ''}</small></div>)}</div>
      </Card>
      <div className="two-column">
        <Card><SectionTitle title="Average vs target" />{NUTRIENTS.slice(1).map((row) => <MacroRow key={row.label} {...row} />)}</Card>
        <Card><SectionTitle title="What drives each nutrient" /><div className="driver-tabs"><button className="active">Protein</button><button>Calories</button><button>Sodium</button></div>{[['Chicken sandwich', 38], ['Greek yogurt', 27], ['Soft Scrambled Eggs', 21], ['Simple Pancakes', 14]].map(([label, pct]) => <div className="driver" key={label}><div><span>{label}</span><small>{pct}%</small></div><Progress value={Number(pct)} /></div>)}</Card>
      </div>
    </div>
  );
}

function EatingOutPage({ onOpen, notify }: { onOpen: (kind: PanelKind) => void; notify: (message: string) => void }) {
  const places = [
    { initials: 'CF', name: 'Chick-fil-A', foods: [{ emoji: '🥪', name: 'Chicken sandwich', meta: '1 sandwich · 420 cal · 29 g protein' }, { emoji: '🍟', name: 'Medium waffle fries', meta: '1 order · 420 cal' }] },
    { initials: 'CK', name: 'Convenience kitchen', foods: [{ emoji: '🥤', name: 'Protein shake', meta: '1 bottle · 190 cal · 30 g protein' }] },
  ];
  return <div className="grocery-grid">{places.map((place) => <Card className="place-card" key={place.name}><div className="place-head"><span>{place.initials}</span><div><strong>{place.name}</strong><small>{place.foods.length} saved item{place.foods.length > 1 ? 's' : ''}</small></div><MoreHorizontal /></div>{place.foods.map((food) => <div className="place-food" key={food.name}><span>{food.emoji}</span><div className="grow"><strong>{food.name}</strong><small>{food.meta}</small></div><button className="button compact" onClick={() => notify(`${food.name} added to today's food log.`)}>Log</button></div>)}<button className="text-button place-add" onClick={() => onOpen('external')}>+ Add another saved food</button></Card>)}</div>;
}

const PANEL_COPY: Record<Exclude<PanelKind, 'recipe-detail' | 'cook' | 'combined-meal'>, { eyebrow: string; title: string; subtitle: string; save: string }> = {
  lot: { eyebrow: 'PUT AWAY', title: 'Add a lot', subtitle: 'One purchase, one expiry date. Lots deduct earliest-first.', save: 'Save lot' },
  groceries: { eyebrow: 'PUT AWAY', title: 'Put away groceries', subtitle: 'Review a grocery haul, then file every item into a lot.', save: 'Put away' },
  food: { eyebrow: 'DEFINE', title: 'Define a food', subtitle: 'Units, conversions, nutrition, and where this food normally lives.', save: 'Save food' },
  recipe: { eyebrow: 'RECIPE', title: 'New recipe', subtitle: 'Ingredients are matched against tracked foods for availability.', save: 'Save recipe' },
  external: { eyebrow: 'EATING OUT', title: 'Save a food', subtitle: 'A restaurant order or packaged food kept out of inventory.', save: 'Save food' },
  log: { eyebrow: 'FOOD LOG', title: 'Log food', subtitle: 'Pick a saved food or enter nutrition by hand.', save: 'Log it' },
  item: { eyebrow: 'GROCERY LIST', title: 'Add an item', subtitle: 'Placed in the aisle it belongs to in the Safeway walking order.', save: 'Add item' },
  meal: { eyebrow: 'PLANNING', title: 'Add a meal', subtitle: 'A recipe, a combined meal, leftovers, or a night eating out.', save: 'Add to plan' },
  targets: { eyebrow: 'PROFILE', title: 'Edit targets', subtitle: 'Goals and limits used across Today, Food log, and Trends.', save: 'Save targets' },
  export: { eyebrow: 'HISTORY', title: 'Export range', subtitle: 'A CSV of every logged meal in the selected range.', save: 'Download CSV' },
  scan: { eyebrow: 'BARCODE', title: 'Scan food', subtitle: 'Use the camera or enter a UPC/EAN manually. Suggestions are always reviewed.', save: 'Enter barcode' },
  profile: { eyebrow: 'ME', title: 'Routine & food profile', subtitle: 'Hard constraints, preferences, and planning availability.', save: 'Save profile' },
  calendar: { eyebrow: 'CALENDAR', title: 'Pantry Planner', subtitle: 'Schedule-aware grocery and preparation reminders.', save: 'Sync now' },
};

function ActionPanel({ state, onClose, notify }: { state: PanelState; onClose: () => void; notify: (message: string) => void }) {
  if (state.kind === 'recipe-detail' || state.kind === 'cook') return <RecipePanel recipe={state.recipe ?? RECIPES[0]} cooking={state.kind === 'cook'} onClose={onClose} notify={notify} />;
  if (state.kind === 'combined-meal') return <CombinedMealPanel onClose={onClose} notify={notify} />;
  const copy = PANEL_COPY[state.kind];
  return (
    <div className="panel-layer">
      <button className="panel-scrim" aria-label="Close panel" onClick={onClose} />
      <aside className="action-panel" role="dialog" aria-modal="true" aria-labelledby="panel-title">
        <PanelHeader eyebrow={copy.eyebrow} title={copy.title} subtitle={copy.subtitle} onClose={onClose} />
        <div className="panel-body"><PanelFields kind={state.kind} openCalendar={() => notify('Calendar settings are ready from the profile menu.')} /></div>
        <div className="panel-footer"><button className="button secondary" onClick={onClose}>Cancel</button><button className="button primary" onClick={() => { onClose(); notify(`${copy.save} complete in the local UI preview.`); }}>{copy.save}</button></div>
      </aside>
    </div>
  );
}

function PanelHeader({ eyebrow, title, subtitle, onClose }: { eyebrow: string; title: string; subtitle: string; onClose: () => void }) {
  return <div className="panel-header"><div className="grow"><div className="eyebrow">{eyebrow}</div><h2 id="panel-title">{title}</h2><p>{subtitle}</p></div><button className="icon-button" onClick={onClose} aria-label="Close"><X /></button></div>;
}

function PanelFields({ kind, openCalendar }: { kind: Exclude<PanelKind, 'recipe-detail' | 'cook' | 'combined-meal'>; openCalendar: () => void }) {
  if (kind === 'scan') return <div className="scan-box"><div className="scanner-frame"><ScanLine /><span>Camera preview</span><i /><i /><i /><i /></div><button className="button secondary full"><Camera />Enable camera</button><div className="divider"><span>or</span></div><Field label="UPC / EAN" placeholder="Enter barcode" /></div>;
  if (kind === 'targets') return <div className="form-grid two">{['Calories (kcal)', 'Protein (g)', 'Carbs (g)', 'Fat (g)', 'Fiber (g)', 'Sodium limit (mg)'].map((label, index) => <Field key={label} label={label} defaultValue={['2300', '130', '260', '75', '30', '2300'][index]} />)}</div>;
  if (kind === 'profile') return <div className="profile-form"><h3>Food constraints</h3><Field label="Allergies and intolerances" placeholder="Comma-separated" /><Field label="Dietary requirements" placeholder="Vegetarian, halal…" /><Field label="Foods to avoid" placeholder="Dislikes and avoidances" /><Field label="Favorites" placeholder="Soft preferences" /><h3>Routine & availability</h3><div className="form-grid two"><Field label="Time zone" defaultValue="America/New_York" /><Field label="Dinner window" defaultValue="6:30 PM – 8:00 PM" /><Field label="Wake time" defaultValue="7:00 AM" /><Field label="Sleep time" defaultValue="11:30 PM" /></div><div className="calendar-card"><CalendarDays /><div className="grow"><strong>Google Calendar</strong><small>Connected · Pantry Planner reminders enabled</small></div><button className="button compact" onClick={openCalendar}>Manage</button></div></div>;
  if (kind === 'groceries') return <><label className="field"><span>Paste or type groceries</span><textarea rows={8} placeholder={'2 onions\n1 bag spinach\n1 dozen eggs'} /></label><div className="notice"><ClipboardList /><span>Rows will be reviewed together. Nothing is applied until every quantity and food match is valid.</span></div></>;
  if (kind === 'export') return <div className="form-grid"><Field label="Date range" defaultValue="Aug 14 – Aug 27" /><label className="field"><span>Format</span><select><option>CSV</option><option>JSON</option></select></label><label className="toggle-row"><input type="checkbox" defaultChecked /><span><strong>Include nutrition details</strong><small>Calories, macros, fiber, sugar, and sodium</small></span></label></div>;
  if (kind === 'meal') return <div className="form-grid"><label className="field"><span>Meal type</span><select><option>Saved recipe</option><option>Combined meal</option><option>Eating out</option><option>Leftovers</option><option>Simple note</option></select></label><Field label="Meal" placeholder="Choose a recipe or meal" /><div className="form-grid two"><Field label="Date" defaultValue="Aug 28, 2026" /><Field label="Slot" defaultValue="Dinner" /></div><Field label="Servings" defaultValue="4" /><Field label="Notes" placeholder="Optional planning note" /></div>;
  if (kind === 'recipe') return <div className="form-grid"><div className="form-grid two"><Field label="Recipe name" placeholder="Recipe name" /><Field label="Yield" defaultValue="4 servings" /></div><Field label="Source URL" placeholder="https://…" /><label className="field"><span>Ingredients</span><textarea rows={6} placeholder={'1 cup ingredient\n2 tbsp ingredient'} /></label><label className="field"><span>Method</span><textarea rows={6} placeholder="One step per line" /></label><label className="toggle-row"><input type="checkbox" defaultChecked /><span><strong>Ask how it went after making</strong><small>Collect taste, ease, and actual cooking time.</small></span></label></div>;
  return <div className="form-grid"><Field label={kind === 'item' ? 'Item' : kind === 'external' || kind === 'log' ? 'Food' : 'Food or product'} placeholder="Start typing…" /><div className="form-grid two"><Field label="Quantity" placeholder="1" /><Field label="Unit" placeholder="each" /></div>{kind !== 'external' && kind !== 'log' && kind !== 'item' && <><label className="field"><span>Location</span><select><option>Fridge</option><option>Pantry</option><option>Freezer</option></select></label><Field label="Best by" placeholder="Unknown" /></>}{(kind === 'external' || kind === 'log') && <><div className="form-grid two"><Field label="Calories" placeholder="0" /><Field label="Protein (g)" placeholder="0" /></div><label className="toggle-row"><input type="checkbox" defaultChecked /><span><strong>Nutrition is estimated</strong><small>Keep the confidence visible in the log.</small></span></label></>}</div>;
}

function Field({ label, placeholder, defaultValue }: { label: string; placeholder?: string; defaultValue?: string }) {
  return <label className="field"><span>{label}</span><input placeholder={placeholder} defaultValue={defaultValue} /></label>;
}

function RecipePanel({ recipe, cooking, onClose, notify }: { recipe: Recipe; cooking: boolean; onClose: () => void; notify: (message: string) => void }) {
  const [checks, setChecks] = useState<Set<string>>(new Set());
  const total = recipe.ingredients.length + recipe.steps.length;
  function toggle(key: string) { setChecks((current) => { const next = new Set(current); if (next.has(key)) next.delete(key); else next.add(key); return next; }); }
  return <div className="panel-layer"><button className="panel-scrim" onClick={onClose} aria-label="Close panel" /><aside className="action-panel recipe-panel" role="dialog" aria-modal="true"><PanelHeader eyebrow={cooking ? 'COOKING MODE' : 'RECIPE'} title={`${recipe.emoji} ${recipe.name}`} subtitle={`${recipe.servings} servings · ${recipe.minutes} minutes · ${recipe.nutrition}`} onClose={onClose} /><div className="panel-body"><div className="cooking-progress"><span>{checks.size} of {total} complete</span><Progress value={checks.size / total * 100} /></div><h3>INGREDIENTS</h3>{recipe.ingredients.map((item, index) => <CheckRow key={item.label} checked={checks.has(`i${index}`)} onClick={() => toggle(`i${index}`)} title={item.label} meta={item.stock} />)}<h3>METHOD</h3>{recipe.steps.map((step, index) => <CheckRow key={step} checked={checks.has(`s${index}`)} onClick={() => toggle(`s${index}`)} title={`${index + 1}. ${step}`} />)}<div className="deduction-preview"><strong>Inventory preview</strong><small>All ingredients are available. Earliest-expiring lots will be used first.</small></div></div><div className="panel-footer"><button className="button secondary" onClick={onClose}>Close</button><button className="button primary" onClick={() => { onClose(); notify(`${recipe.name} cooked · leftovers saved.`); }}>{cooking ? 'Mark cooked' : 'Start cooking'}</button></div></aside></div>;
}

function CheckRow({ checked, onClick, title, meta }: { checked: boolean; onClick: () => void; title: string; meta?: string }) {
  return <button className={cx('check-row', checked && 'checked')} onClick={onClick}><span className="check-box">{checked && <Check />}</span><div><strong>{title}</strong>{meta && <small>{meta}</small>}</div></button>;
}

function CombinedMealPanel({ onClose, notify }: { onClose: () => void; notify: (message: string) => void }) {
  const [selected, setSelected] = useState(new Set(RECIPES.map((recipe) => recipe.id)));
  return <div className="panel-layer"><button className="panel-scrim" onClick={onClose} aria-label="Close panel" /><aside className="action-panel" role="dialog" aria-modal="true"><PanelHeader eyebrow="COMBINED MEAL" title="🍽️ Weekend brunch" subtitle="Prepare independent recipes as one meal without merging their identity." onClose={onClose} /><div className="panel-body"><h3>RECIPES IN THIS MEAL</h3>{RECIPES.map((recipe) => <CheckRow key={recipe.id} checked={selected.has(recipe.id)} onClick={() => setSelected((current) => { const next = new Set(current); if (next.has(recipe.id)) next.delete(recipe.id); else next.add(recipe.id); return next; })} title={`${recipe.emoji} ${recipe.name}`} meta={`${recipe.servings} servings · ${recipe.minutes} min`} />)}<div className="notice"><Utensils /><span>Pancakes first, eggs last so they stay soft. Each selected recipe creates its own prepared batch.</span></div></div><div className="panel-footer"><button className="button secondary" onClick={onClose}>Cancel</button><button className="button primary" disabled={!selected.size} onClick={() => { onClose(); notify(`${selected.size} recipes cooked · meal marked complete.`); }}>Mark {selected.size} recipes cooked</button></div></aside></div>;
}
