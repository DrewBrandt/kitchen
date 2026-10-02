import { RecipePieceControl } from './RecipePieceControl';
import { pieceWeight, hasPieceNutritionConflict } from './lib/recipe-pieces';
import { isCookablePlan, cookingAttemptIdentity, type StagedDish, type CookingDraft } from './lib/cooking-stage';
import { CombinedMealPanel } from './CombinedMealPanel';
import { planDisplayStatus } from './lib/plan-display-status';
import { RecipeIngredientEditor } from './RecipeIngredientEditor';
import { DurableUndo, ShoppingReceiptEditor } from './ShoppingReceiptEditor';
import { addCalendarDays, formatPlanningRange, planningWeek, type PlanningRange } from './lib/planning-week';
import { QuantityCorrectionEditor } from './QuantityCorrectionEditor';
import type { Json } from './database.types';
import { ManualConsumptionEditor } from './ManualConsumptionEditor';
import { completeFormAttempt, createFormAttempt, isDefiniteMutationFailure, mutationError, pendingMutationPayload } from './lib/mutation-feedback';
import { useEffect, useMemo, useRef, useState } from 'react';
import { AccountAvatar } from './AccountAvatar';
import { MobileAccount } from './MobileAccount';
import type { IScannerControls } from '@zxing/browser';
import {
  Archive,
  BarChart3,
  CalendarDays,
  Check,
  ChevronRight,
  ClipboardList,
  Columns2,
  CookingPot,
  Download,
  GripVertical,
  Grid2X2,
  History as HistoryIcon,
  House,
  Info,
  LayoutList,
  Pencil,
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
import { usePantryData, type ShoppingReceipt, type GroceryItem, type FoodLogEntry, type InventoryFood, type PantryData, type PlannedMealConsumption, type PlannedMealView, type PieceInput, type PreparationOptions, type PreparationResult, type ProductView } from './pantry-data';
import { completeCost, dailyFoodBudget, perServingCost, usd, inventoryValueLabel } from './lib/cost';
import { formatPreparedAt, formatAmount, formatNutritionAmount, formatServings } from './lib/format';
import { DayPlanFields, NutritionSandbox } from './PlanComposer';

const PAGE_ICONS: Record<PageId, LucideIcon> = {
  today: House,
  inventory: Archive,
  'on-deck': LayoutList,
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
  'on-deck': 'recipe',
  recipes: 'recipe',
  products: 'product',
  'food-log': 'manual-log',
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
  consumptionEvent?: FoodLogEntry;
}

type ToastState = { message: string; undo?: () => Promise<void> };
type Notify = (message: string, undo?: () => Promise<void>) => void;
type Reversals = {
  correctQuantity?: (id: string, expected: number, quantity: number) => Promise<string>;
  updateFoodLog?: (id: string, patch: Json) => Promise<void>;
  voidFoodLog?: (id: string) => Promise<void>;
  restoreFoodLog?: (id: string) => Promise<void>;
  undoInventoryAdjustment?: (eventId: string) => Promise<void>;
  undoPrep?: (prepId: string) => Promise<void>;
};

const cx = (...values: Array<string | false | null | undefined>) => values.filter(Boolean).join(' ');
const costLabel = (value: number | null | undefined, estimated = false) => value === null || value === undefined ? 'Price unavailable' : `${estimated ? '~' : ''}$${value.toFixed(2)}`;

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

function dateKeyInTimeZone(date: Date, timeZone: string) {
  try {
    const parts = new Intl.DateTimeFormat('en-US', { year: 'numeric', month: '2-digit', day: '2-digit', timeZone }).formatToParts(date);
    const value = (type: Intl.DateTimeFormatPartTypes) => parts.find((part) => part.type === type)?.value ?? '';
    return `${value('year')}-${value('month')}-${value('day')}`;
  } catch {
    return calendarDateKey(date);
  }
}

const servingLabel = formatServings;

interface AppProps {
  onReceiveShopping?: (id: string, receipt: ShoppingReceipt) => Promise<void>;
  onUndoReceipt?: (lotId: string) => Promise<void>;
  ownerName?: string;
  ownerEmail?: string;
  ownerAvatarUrl?: string;
  syncStatus?: 'connecting' | 'synced' | 'error';
  onSignOut?: () => void;
  onToggleGrocery?: (id: string, checked: boolean) => Promise<void>;
  onCorrectQuantity?: (id: string, expected: number, quantity: number) => Promise<string>;
  onUpdateFoodLog?: (id: string, patch: Json) => Promise<void>;
  onVoidFoodLog?: (id: string) => Promise<void>;
  onSaveAction?: (kind: PanelKind, form: FormData) => Promise<string>;
  onCookRecipe?: (id: string, options?: PreparationOptions) => Promise<PreparationResult>;
  onSavePrepFeedback?: (prepId: string, ease: number, taste: number, minutes: number) => Promise<void>;
  onCookRecipes?: (ids: string[]) => Promise<void>;
  onConsumePrepared?: (id: string, quantity: number) => Promise<string | null>;
  onConsumePlannedMeals?: (consumptions: PlannedMealConsumption[]) => Promise<string[]>;
  onRebuildShopping?: (range: PlanningRange) => Promise<number>;
  onRemovePlannedMeals?: (ids: string[]) => Promise<void>;
  onSetPlannedConsumptionServings?: (id: string, servings: number) => Promise<void>;
  onRemoveGrocery?: (id: string) => Promise<void>;
  onConsumeInventoryLot?: (id: string, quantity: number) => Promise<string | null>;
  onSetInventoryLotQuantity?: (id: string, remaining: number, discard: boolean, reason?: string) => Promise<string | null>;
  onRestoreFoodLog?: (id: string) => Promise<void>;
  onUndoInventoryAdjustment?: (eventId: string) => Promise<void>;
  onUndoPrep?: (prepId: string) => Promise<void>;
}

export function App({ onReceiveShopping, onUndoReceipt, ownerName = 'Drew', ownerEmail, ownerAvatarUrl, syncStatus = 'synced', onSignOut, onToggleGrocery, onCorrectQuantity, onUpdateFoodLog, onVoidFoodLog, onSaveAction, onCookRecipe, onSavePrepFeedback, onCookRecipes, onConsumePrepared, onConsumePlannedMeals, onRebuildShopping, onRemovePlannedMeals, onSetPlannedConsumptionServings, onRemoveGrocery, onConsumeInventoryLot, onSetInventoryLotQuantity, onRestoreFoodLog, onUndoInventoryAdjustment, onUndoPrep }: AppProps = {}) {
  const pantryData = usePantryData();
  const { foodLog, grocerySections, history, inventorySections, recipes, weekDays } = pantryData;
  const [page, setPage] = useState<PageId>('today');
  const [weekOffset, setWeekOffset] = useState(0);
  const [rebuildingShopping, setRebuildingShopping] = useState(false);
  const [panel, setPanel] = useState<PanelState | null>(null);
  const groceryKey = (item: { id?: string; name: string }) => item.id ?? item.name;
  const [checkedGroceries, setCheckedGroceries] = useState<Set<string>>(() => new Set(grocerySections.flatMap((section) => section.items).filter((item) => item.checked).map(groceryKey)));
  const [inventoryFilter, setInventoryFilter] = useState('All');
  const [recipeFilter, setRecipeFilter] = useState('All recipes');
  const [search, setSearch] = useState('');
  const [toast, setToast] = useState<ToastState | null>(null);
  const toastTimer = useRef<number | undefined>(undefined);
  const [shoppingMode, setShoppingMode] = useState(false);
  const [activeRecipeIds, setActiveRecipeIds] = useState<Set<string>>(() => new Set(recipes.filter((recipe) => {
    try { return (JSON.parse(localStorage.getItem(`mise.recipe-progress.${recipe.id}`) ?? '[]') as string[]).length > 0; } catch { return false; }
  }).map((recipe) => recipe.id)));
  const [cookingDrafts, setCookingDrafts] = useState<CookingDraft[]>(() => {
    try {
      const saved = JSON.parse(localStorage.getItem('mise.on-deck-drafts') ?? 'null');
      if (Array.isArray(saved)) return saved.filter((draft) => typeof draft?.id === 'string' && typeof draft.recipeId === 'string' && Number.isFinite(draft.servingsMade) && draft.servingsMade > 0 && Number.isFinite(draft.servingsEaten) && draft.servingsEaten >= 0 && draft.servingsEaten <= draft.servingsMade);
      const legacy = new Set(JSON.parse(localStorage.getItem('mise.on-deck-recipes') ?? '[]') as string[]);
      return recipes.filter((recipe) => legacy.has(recipe.id)).map((recipe) => ({ id: recipe.id, recipeId: recipe.id, servingsMade: recipe.servings, servingsEaten: 0 }));
    } catch { return []; }
  });
  const [manualDeckPlanIds, setManualDeckPlanIds] = useState<Set<string>>(() => {
    try { const saved = JSON.parse(localStorage.getItem('mise.on-deck-plans') ?? '[]'); return new Set(Array.isArray(saved) ? saved : Object.values(saved)); } catch { return new Set(); }
  });
  const [deckPlanFocus, setDeckPlanFocus] = useState<string[] | null>(() => {
    try { const saved = JSON.parse(localStorage.getItem('mise.on-deck-plan-focus') ?? 'null'); return Array.isArray(saved) && saved.every((id) => typeof id === 'string') ? saved : null; } catch { return null; }
  });
  const [dismissedDeckRecipeIds, setDismissedDeckRecipeIds] = useState<Set<string>>(new Set());

  useEffect(() => {
    setCheckedGroceries(new Set(grocerySections.flatMap((section) => section.items).filter((item) => item.checked).map(groceryKey)));
  }, [grocerySections]);

  useEffect(() => () => window.clearTimeout(toastTimer.current), []);

  useEffect(() => { localStorage.setItem('mise.on-deck-drafts', JSON.stringify(cookingDrafts)); }, [cookingDrafts]);
  useEffect(() => { localStorage.setItem('mise.on-deck-plans', JSON.stringify([...manualDeckPlanIds])); }, [manualDeckPlanIds]);

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
  const selectedWeek = planningWeek(dateKeyInTimeZone(now, pantryData.settings.timeZone), weekOffset);
  const changeWeek = (delta: number) => setWeekOffset((current) => current + delta);
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
                ? `${plannedMealCount} PLANNED ITEM${plannedMealCount === 1 ? '' : 'S'}`
                : page === 'grocery'
                  ? `${groceryTotal - groceryDone} ITEM${groceryTotal - groceryDone === 1 ? '' : 'S'} LEFT`
                  : PAGE_META[page].eyebrow,
    subtitle: page === 'today'
      ? `${foodLog.length} food log entr${foodLog.length === 1 ? 'y' : 'ies'} today · ${plannedMealCount} item${plannedMealCount === 1 ? '' : 's'} planned this week.`
      : page === 'recipes'
        ? ''
        : page === 'history'
          ? ''
          : page === 'week'
            ? ''
            : PAGE_META[page].subtitle,
  };

  useEffect(() => { localStorage.setItem('mise.on-deck-plan-focus', JSON.stringify(deckPlanFocus)); }, [deckPlanFocus]);
  function stagePlans(ids: string[]) {
    const unfinished = pantryData.plannedMeals.filter((plan) => ids.includes(plan.id) && isCookablePlan(plan)).map((plan) => plan.id);
    setManualDeckPlanIds((current) => new Set([...current, ...unfinished]));
    setDeckPlanFocus(unfinished);
    setDismissedDeckRecipeIds((current) => { const next = new Set(current); unfinished.forEach((id) => next.delete(id)); return next; });
    setPanel(null); setPage('on-deck');
  }
  function open(kind: PanelKind, recipe?: Recipe, values?: Record<string, string>) {
    if (kind === 'cook' && recipe) {
      if (values?.meal_plan_id) { stagePlans([values.meal_plan_id]); return; }
      setDeckPlanFocus(null);
      setCookingDrafts((current) => current.some((draft) => draft.id === recipe.id) ? current : [...current, { id: recipe.id, recipeId: recipe.id, servingsMade: recipe.servings, servingsEaten: 0 }]);

      setDismissedDeckRecipeIds((current) => { const next = new Set(current); next.delete(recipe.id); return next; });
      setPanel(null);
      setPage('on-deck');
      return;
    }
    setPanel({ kind, recipe, values });
  }

  function openInventory(food: InventoryFood) {
    setPanel({ kind: 'inventory-detail', inventoryFood: food });
  }

  function openConsumption(consumptionEvent: FoodLogEntry) {
    setPanel({ kind: 'consumption-detail', consumptionEvent });
  }

  const todayKey = dateKeyInTimeZone(new Date(), pantryData.settings.timeZone);
  const plannedEntries: DeckEntry[] = pantryData.plannedMeals.filter((plan) => isCookablePlan(plan) && (deckPlanFocus !== null ? deckPlanFocus.includes(plan.id) : plan.dateKey === todayKey || manualDeckPlanIds.has(plan.id))).flatMap((plan) => {
    const recipe = recipes.find((item) => item.id === plan.recipeId); return recipe ? [{ id: plan.id, recipe, plan }] : [];
  });
  const unplannedEntries: DeckEntry[] = cookingDrafts.flatMap((draft) => {
    const recipe = recipes.find((item) => item.id === draft.recipeId); return recipe ? [{ id: draft.id, recipe, draft }] : [];
  });
  for (const recipe of recipes) if (activeRecipeIds.has(recipe.id) && !unplannedEntries.some((entry) => entry.id === recipe.id)) unplannedEntries.push({ id: recipe.id, recipe });
  const deckEntries = [...plannedEntries, ...(deckPlanFocus === null ? unplannedEntries : [])].filter((entry) => !dismissedDeckRecipeIds.has(entry.id));
  const pinnedRecipes = [...new Map(deckEntries.map((entry) => [entry.recipe.id, entry.recipe])).values()];
  const stageRecipes = (dishes: StagedDish[]) => {
    const drafts = dishes.map((dish) => ({ ...dish, id: 'dish:' + JSON.stringify([dish.recipeId, dish.servingsMade, dish.servingsEaten]) }));
    setDeckPlanFocus(null);
    setCookingDrafts((current) => [...current, ...drafts.filter((draft) => !current.some((entry) => entry.id === draft.id))]);
    setDismissedDeckRecipeIds((current) => { const next = new Set(current); drafts.forEach((draft) => next.delete(draft.id)); return next; });
    setPanel(null); setPage('on-deck');
  };
  const removeFromDeck = (id: string) => {
    setCookingDrafts((current) => current.filter((draft) => draft.id !== id));
    setManualDeckPlanIds((current) => { const next = new Set(current); next.delete(id); return next; });
    setDismissedDeckRecipeIds((current) => new Set(current).add(id));
  };

  // Reversible actions get a toast with Undo; everything else just says what happened.
  function notify(message: string, undo?: () => Promise<void>) {
    window.clearTimeout(toastTimer.current);
    setToast({ message, undo });
    toastTimer.current = window.setTimeout(() => setToast(null), undo ? 7000 : 2800);
  }

  function dismissToast() {
    window.clearTimeout(toastTimer.current);
    setToast(null);
  }

  function runUndo() {
    const pending = toast?.undo;
    if (!pending) return;
    dismissToast();
    void pending()
      .then(() => notify('Undone.'))
      .catch((error: unknown) => notify(error instanceof Error ? error.message : 'Could not undo that.'));
  }

  const reversals: Reversals = { correctQuantity: onCorrectQuantity, updateFoodLog: onUpdateFoodLog, voidFoodLog: onVoidFoodLog, restoreFoodLog: onRestoreFoodLog, undoInventoryAdjustment: onUndoInventoryAdjustment, undoPrep: onUndoPrep };

  function toggleGrocery(item: { id?: string; name: string }) {
    const key = groceryKey(item);
    const nextChecked = !checkedGroceries.has(key);
    setCheckedGroceries((current) => {
      const next = new Set(current);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
    if (item.id && onToggleGrocery) void onToggleGrocery(item.id, nextChecked).then(() => {
      if (nextChecked) notify(`${item.name} picked up.`, async () => { await onToggleGrocery(item.id!, false); });
    }).catch(() => {
      setCheckedGroceries((current) => { const next = new Set(current); if (nextChecked) next.delete(key); else next.add(key); return next; });
      notify('Could not update that grocery item.');
    });
  }

  function runSecondary() {
    if (page === 'today' || page === 'food-log') open('scan');
    else if (page === 'inventory') open('groceries');
    else if (page === 'week' || page === 'grocery') {
      if (!onRebuildShopping) notify('A live Supabase connection is required to rebuild groceries.');
      else if (!rebuildingShopping) {
        const range = selectedWeek;
        setRebuildingShopping(true);
        void onRebuildShopping(range).then((count) => notify(`${formatPlanningRange(range)}: ${count} planned shortage${count === 1 ? '' : 's'}.`))
          .catch((error: unknown) => notify(error instanceof Error ? error.message : 'Could not rebuild groceries.'))
          .finally(() => setRebuildingShopping(false));
      }
    }
  }

  return (
    <div className="app-shell">
      <Sidebar
        page={page}
        ownerName={ownerName}
        ownerEmail={ownerEmail}
        ownerAvatarUrl={ownerAvatarUrl}
        syncStatus={syncStatus}
        groceryLeft={groceryTotal - groceryDone}
        badges={{ inventory: inventoryFoodCount, 'on-deck': deckEntries.length, recipes: recipes.length, products: pantryData.products.length, week: plannedMealCount }}
        onNavigate={setPage}
        onProfile={() => open('profile')}
        pinnedRecipes={pinnedRecipes}
        onPinnedRecipe={() => { setDeckPlanFocus(null); setPage('on-deck'); }}
        onSignOut={onSignOut}
      />

      <main className={cx('main-shell', page === 'on-deck' && 'on-deck-shell')}>
        <header className="page-header">
          <div className="page-header-inner">
            <div className="page-heading">
              <div className="eyebrow">{meta.eyebrow}</div>
              <h1>{meta.title}</h1>
              {meta.subtitle && <p>{meta.subtitle}</p>}
            </div>
            <div className="header-actions">
              {meta.secondary && (
                <button className="button secondary" onClick={runSecondary} disabled={(page === 'week' || page === 'grocery') && rebuildingShopping} aria-label={page === 'week' || page === 'grocery' ? `${meta.secondary} for ${formatPlanningRange(selectedWeek)}` : undefined}>
                  {meta.secondary.includes('barcode') ? <ScanLine /> : <RefreshCw />}
                  <span>{meta.secondary}</span>
                </button>
              )}
              <button className="button primary" onClick={() => page === 'on-deck' ? setPage('recipes') : open(PANEL_FOR_PAGE[page])}>
                <Plus /> <span>{meta.primary}</span>
              </button>
              <MobileAccount name={ownerName} email={ownerEmail} photo={ownerAvatarUrl} onProfile={() => open('profile')} onSignOut={onSignOut} />
            </div>
          </div>
        </header>

        <div className={cx('page-content', page === 'on-deck' && 'on-deck-page-content')}>
          {page === 'today' && <TodayPage onNavigate={setPage} onOpen={open} onOpenFood={openInventory} notify={notify} onConsumePrepared={onConsumePrepared} onSetInventoryLotQuantity={onSetInventoryLotQuantity} undo={reversals} />}
          {page === 'on-deck' && <OnDeckPage onShowAll={deckPlanFocus !== null ? () => setDeckPlanFocus(null) : undefined} entries={deckEntries} locations={pantryData.locations} onAddRecipe={() => setPage('recipes')} onRemoveRecipe={removeFromDeck} notify={notify} onCook={onCookRecipe} onProgressChange={(id, active) => setActiveRecipeIds((current) => { const next = new Set(current); if (active) next.add(id); else next.delete(id); return next; })} undo={reversals} />}
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
          {page === 'products' && <ProductsPage onOpen={open} notify={notify} />}
          {page === 'food-log' && <FoodLogPage onOpen={open} onOpenConsumption={openConsumption} notify={notify} onVoid={onVoidFoodLog} onPlan={onSaveAction ? (form) => onSaveAction('meal', form) : undefined} onConsumeLot={onConsumeInventoryLot} undo={reversals} />}
          {page === 'history' && <HistoryPage onOpen={open} onOpenConsumption={openConsumption} onUndoPrep={onUndoPrep} onUndoReceipt={onUndoReceipt} onUndoDiscard={onUndoInventoryAdjustment} />}
          {page === 'trends' && <TrendsPage onOpen={open} />}
          {page === 'week' && <WeekPage range={selectedWeek} onChangeWeek={changeWeek} onCookMeal={stagePlans} onOpen={open} notify={notify} onRemove={onRemovePlannedMeals} onConsume={onConsumePlannedMeals} onSetServings={onSetPlannedConsumptionServings} />}
          {page === 'grocery' && (
            <GroceryPage
              range={selectedWeek}
              onChangeWeek={changeWeek}
              onReceive={onReceiveShopping}
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

      <MobileNav page={page} onNavigate={setPage} onScan={() => open('bulk-import')} />
      {panel && <ActionPanel onStageRecipes={stageRecipes} onStartCooking={(recipe) => open('cook', recipe)} state={panel} onClose={() => setPanel(null)} notify={notify} onSave={onSaveAction} onCookRecipe={onCookRecipe} onSavePrepFeedback={onSavePrepFeedback} onCookRecipes={onCookRecipes} onRecipeProgress={(id, active) => setActiveRecipeIds((current) => { const next = new Set(current); if (active) next.add(id); else next.delete(id); return next; })} onConsumeInventoryLot={onConsumeInventoryLot} onSetInventoryLotQuantity={onSetInventoryLotQuantity} undo={reversals} />}
      {toast && <div className="toast" role="status"><Check /><span className="grow">{toast.message}</span>{toast.undo && <button className="toast-undo" onClick={runUndo}>Undo</button>}<button className="toast-dismiss" aria-label="Dismiss" onClick={dismissToast}><X /></button></div>}
    </div>
  );
}

function Sidebar({ page, ownerName, ownerEmail, ownerAvatarUrl, syncStatus, groceryLeft, badges, pinnedRecipes, onPinnedRecipe, onNavigate, onProfile, onSignOut }: { page: PageId; ownerName: string; ownerEmail?: string; ownerAvatarUrl?: string; syncStatus: 'connecting' | 'synced' | 'error'; groceryLeft: number; badges: Partial<Record<PageId, number>>; pinnedRecipes: Recipe[]; onPinnedRecipe: (recipe: Recipe) => void; onNavigate: (page: PageId) => void; onProfile: () => void; onSignOut?: () => void }) {
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
      {pinnedRecipes.length > 0 && <nav className="nav-group pinned-recipes" aria-label="Pinned cooking"><div className="nav-label">On deck</div>{pinnedRecipes.slice(0, 4).map((recipe) => <button className="nav-item" key={recipe.id} title={recipe.name} onClick={() => onPinnedRecipe(recipe)}><span className="pin-emoji">{recipe.emoji}</span><span className="nav-item-label">{recipe.name}</span><small>Open</small></button>)}</nav>}
      <div className="sidebar-spacer" />
      <button className="profile-row" aria-label={`${ownerName}${ownerEmail ? ` (${ownerEmail})` : ''} — Routine & food profile`} title={ownerEmail ? `Signed in as ${ownerEmail}` : undefined} onClick={onProfile}>
        <AccountAvatar name={ownerName} url={ownerAvatarUrl} /><span><strong>{ownerName}</strong>{ownerEmail && <small className="account-email">{ownerEmail}</small>}<small>Routine & food profile</small></span><Settings2 />
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
    { id: 'on-deck', label: 'Deck', icon: LayoutList },
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

function Progress({ value, projected = 0, color, over = false }: { value: number; projected?: number; color?: string; over?: boolean }) {
  const actual = Math.min(Math.max(value, 0), 100);
  const plan = Math.min(Math.max(projected, 0), Math.max(0, 100 - actual));
  return <div className={cx('progress', over && 'over-budget')} data-value={actual}><span style={{ width: `${actual}%`, background: color }} />{plan > 0 && <i className="projection-segment" style={{ width: `${plan}%` }} />}</div>;
}

function TodayPage({ onNavigate, onOpen, onOpenFood, notify, onConsumePrepared, onSetInventoryLotQuantity, undo }: { onNavigate: (page: PageId) => void; onOpen: (kind: PanelKind, recipe?: Recipe, values?: Record<string, string>) => void; onOpenFood: (food: InventoryFood) => void; notify: Notify; onConsumePrepared?: (id: string, quantity: number) => Promise<string | null>; onSetInventoryLotQuantity?: AppProps['onSetInventoryLotQuantity']; undo: Reversals }) {
  const { foodLog: todayFoodLog, foodLogByDate, inventorySections, nutrients: todayNutrients, plannedMeals, preparedLots, recipes, settings, todayProjection } = usePantryData();
  const todayKey = dateKeyInTimeZone(new Date(), settings.timeZone);
  const [selectedKey, setSelectedKey] = useState(todayKey);
  const selectedDate = new Date(`${selectedKey}T12:00:00`);
  const isToday = selectedKey === todayKey;
  const selectedDay = foodLogByDate[selectedKey];
  const foodLog = isToday ? todayFoodLog : (selectedDay?.foodLog ?? []);
  const nutrients = isToday ? todayNutrients : (selectedDay?.nutrients ?? todayNutrients.map((nutrient) => ({ ...nutrient, value: nutrient.label === 'Calories' ? '0' : `0 ${nutrient.label === 'Sodium' ? 'mg' : 'g'}`, pct: 0 })));
  const projection = isToday ? todayProjection : { Calories: 0, Protein: 0, Carbs: 0, Fat: 0, Fiber: 0, Sodium: 0 };
  const dayPlans = plannedMeals.filter((meal) => meal.dateKey === selectedKey);
  const moveDay = (days: number) => setSelectedKey((current) => { const next = new Date(`${current}T12:00:00`); next.setDate(next.getDate() + days); return calendarDateKey(next); });
  const dayLabel = selectedDate.toLocaleDateString([], { weekday: 'long', month: 'short', day: 'numeric' });
  const useSoon = inventorySections.flatMap((section) => section.foods).filter((food) => ['warn', 'urgent'].includes(food.tone));
  // Money at risk is only honest when every expiring lot has a price.
  const atRisk = useSoon.every((food) => food.cost !== null && food.cost !== undefined) ? useSoon.reduce((total, food) => total + Number(food.cost), 0) : null;
  const dailyBudget = dailyFoodBudget(settings.weeklyFoodBudget);
  const spentToday = foodLog.reduce((total, entry) => total + (entry.cost ?? 0), 0);
  const plannedCostToday = dayPlans.filter((plan) => plan.consumptionStatus === 'planned').reduce((total, plan) => total + (plan.cost ?? 0), 0);
  const budgetPct = dailyBudget > 0 ? Math.min(100, spentToday / dailyBudget * 100) : 0;
  const missingPaidCosts = foodLog.filter((entry) => entry.cost == null).length;
  const amountOver = Math.max(0, spentToday - dailyBudget);
  const popularRecipes = [...recipes].sort((left, right) => (right.prepCount ?? 0) - (left.prepCount ?? 0) || left.name.localeCompare(right.name)).slice(0, 4);
  return (
    <div className="stack">
      <div className="date-switcher today-date-switcher"><button aria-label="Previous day" onClick={() => moveDay(-1)}>‹</button><strong>{isToday ? 'Today' : dayLabel}</strong>{isToday && <span>{dayLabel}</span>}<button aria-label="Next day" disabled={isToday} onClick={() => moveDay(1)}>›</button></div>
      <div className="today-grid">
        <Card className="nutrition-card">
          <div className="card-kicker"><span>{isToday ? 'TODAY' : selectedDate.toLocaleDateString([], { weekday: 'short' }).toUpperCase()} · NUTRITION</span><button onClick={() => onOpen('targets')}>Targets</button></div>
          <div className="headline-metrics">
            <div className="headline-metric">
              <div className="metric-total"><strong>{nutrients[0]?.value ?? '0'}</strong><span>{nutrients[0]?.target ?? ''}</span></div>
              <Progress value={nutrients[0]?.pct ?? 0} projected={projection.Calories / Math.max(settings.calories, 1) * 100} />
              <em>{Math.max(0, 100 - (nutrients[0]?.pct ?? 0))}% LEFT</em>
            </div>
            <div className="headline-metric spend-metric">
              <span>Food cost</span><div className="metric-total"><strong>{usd(spentToday)}{missingPaidCosts ? " + unknown" : ""}</strong><span>/ {usd(dailyBudget)} a day</span></div>
              <Progress value={budgetPct} color="var(--spend)" over={amountOver > 0} />
              <em>{missingPaidCosts ? 'Paid amounts missing' : amountOver > 0 ? `${usd(amountOver)} OVER` : `${usd(dailyBudget - spentToday)} LEFT`}</em>
            </div>
          </div>
          {Object.values(projection).some(Boolean) && <div className="plan-projection-key"><i className="projection-swatch" /> Includes items planned for today{plannedCostToday ? ` · ${usd(plannedCostToday)} estimated food value` : ''}</div>}
          <div className="macro-list">{nutrients.slice(1, 6).map((row) => <MacroRow key={row.label} {...row} projected={projection[row.label as keyof typeof projection] / Math.max(Number(row.target.replace(/[^\d.]/g, '')), 1) * 100} />)}</div>
        </Card>
        <Card className="next-card">
          <div className="card-kicker"><span>{isToday ? "TODAY'S PLAN" : 'PLANNED'}</span><button onClick={() => onNavigate('week')}>Week</button></div>
          <div className="today-plan-list">
            {dayPlans.map((meal) => {
              const recipe = recipes.find((candidate) => candidate.id === meal.recipeId || candidate.name === meal.name);
              const sourceLabel = meal.consumeFromInventory === false ? 'outside pantry' : meal.sourceKind === 'lot' ? 'exact lot' : '';
              return <button className="today-plan-row" key={meal.id} onClick={() => recipe ? onOpen('recipe-detail', recipe) : onNavigate('week')}><span>{meal.emoji}</span><div><strong>{meal.name}</strong><small>{meal.slot.toLowerCase()} · {sourceLabel ? `${sourceLabel} · ` : ''}{costLabel(meal.cost, meal.costIsEstimated)} planned portion</small></div><ChevronRight /></button>;
            })}
            {!dayPlans.length && <div className="featured-meal"><span>📅</span><div><strong>Nothing planned</strong><small>Add a recipe or pantry item for this day</small></div></div>}
          </div>
          <div className="split-actions"><button className="button primary" onClick={() => onOpen('meal', undefined, { plan_date: selectedKey })}>{dayPlans.length ? 'Plan another' : 'Add to day'}</button></div>
        </Card>
        <Card>
          <div className="card-kicker"><span>Check dates</span><small className="spend">{atRisk === null ? `${useSoon.length}` : `${usd(atRisk)} at risk`}</small></div>
          {useSoon.map((food) => <button className={cx('soon-row', food.tone)} key={food.name} onClick={() => onOpenFood(food)}><div><strong>{food.name}</strong><small>{food.total} · {food.lots[0]?.split(' ').at(-1)}</small></div><div className="soon-value"><em>{food.due}</em><small className="spend">{costLabel(food.cost, food.costIsEstimated)}</small></div></button>)}
          {!useSoon.length && <div className="soon-row"><div><strong>No dates flagged</strong></div></div>}
          <button className="text-button align-left" onClick={() => onNavigate('inventory')}>Review inventory →</button>
        </Card>
      </div>

      <Card>
        <SectionTitle title="Ready to eat" />
        {preparedLots.map((lot) => <PreparedRow key={lot.id} preparedAt={lot.preparedAt} timeZone={settings.timeZone} emoji={lot.emoji} name={lot.name} where={lot.location} servings={lot.remaining} servingsLeft={lot.servingsLeft} due={lot.due} progress={lot.progress} costPerServing={lot.costPerServing} costIsEstimated={lot.costIsEstimated} onDiscard={onSetInventoryLotQuantity ? async (quantity, reason) => {
          try {
            const eventId = await onSetInventoryLotQuantity(lot.id, lot.servingsLeft - quantity, true, reason);
            notify(`${formatServings(quantity)} of ${lot.name} discarded.`, eventId && undo.undoInventoryAdjustment ? async () => { await undo.undoInventoryAdjustment!(eventId); } : undefined);
          } catch (error) { notify(error instanceof Error ? error.message : 'Could not discard food.'); }
        } : undefined} onEat={(quantity) => { if (onConsumePrepared) void onConsumePrepared(lot.id, quantity).then((logId) => notify(`${formatServings(quantity)} of ${lot.name} logged as eaten.`, logId && undo.voidFoodLog ? async () => { await undo.voidFoodLog!(logId); } : undefined)).catch((error: unknown) => notify(error instanceof Error ? error.message : `Could not log ${lot.name}.`)); }} />)}
        {!preparedLots.length && <div className="empty-ready"><CookingPot /><div><strong>Nothing prepared yet</strong><small>Cook a recipe to keep ready-to-eat servings here.</small></div><button className="button secondary compact" onClick={() => onNavigate('recipes')}>Find a recipe</button></div>}
      </Card>

      <Card>
        <SectionTitle title="Most made" action="All recipes" onAction={() => onNavigate('recipes')} />
        <div className="cookable-grid">
          {popularRecipes.map((recipe) => (
            <button className="cookable-row" key={recipe.id} onClick={() => onOpen('recipe-detail', recipe)}>
              <span>{recipe.emoji}</span><div><strong>{recipe.name}</strong><small>{recipe.minutes} min · {servingLabel(recipe.servings)} · {costLabel(recipe.estimatedCost, recipe.costIsEstimated)} per batch</small></div><ChevronRight />
            </button>
          ))}
        </div>
      </Card>
    </div>
  );
}

function MacroRow({ label, value, target, pct, projected, color }: { label: string; value: string; target: string; pct: number; projected?: number; color: string }) {
  return <div className="macro-row"><div><span>{label}</span><strong>{value}</strong><small>{target}</small></div><Progress value={pct} projected={projected} color={color} /></div>;
}

function PreparedRow({ preparedAt, timeZone, emoji, name, where, servings, servingsLeft, due, progress, costPerServing, costIsEstimated, onEat, onDiscard }: { preparedAt?: string; timeZone: string; emoji: string; name: string; where: string; servings: string; servingsLeft: number; due: string; progress: number; costPerServing: number | null; costIsEstimated: boolean; onEat: (quantity: number) => void; onDiscard?: (quantity: number, reason: string) => Promise<void> }) {
  const preparedLabel = preparedAt ? `Prepared ${formatPreparedAt(preparedAt, timeZone)}` : undefined;
  const perServing = costPerServing === null ? 'price unavailable' : `${costIsEstimated ? '~' : ''}$${costPerServing.toFixed(2)} value per serving`;
  const [quantity, setQuantity] = useState(Math.min(1, servingsLeft));
  const [discarding, setDiscarding] = useState(false);
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  useEffect(() => setQuantity(Math.min(1, servingsLeft)), [servingsLeft]);
  return <div className="prepared-row" role="group" aria-label={`${name}${preparedLabel ? ` — ${preparedLabel}` : ''}`}><span className="row-emoji">{emoji}</span><div className="grow"><strong>{name}</strong>{preparedLabel && <small>{preparedLabel}</small>}<small>{where} · <span className="spend">{perServing}</span></small></div><div className="servings"><Progress value={progress} /><small>{servings}</small></div><small className="due">{due}</small><label className="prepared-eat-quantity"><span>Servings</span><input aria-label={`Servings of ${name} eaten`} type="number" min="0.25" max={servingsLeft} step="0.25" value={quantity} onChange={(event) => setQuantity(Number(event.target.value))} /></label><button className="button compact" disabled={busy || !Number.isFinite(quantity) || quantity <= 0 || quantity > servingsLeft} onClick={() => onEat(quantity)}>Log eaten</button><button className="button compact secondary" disabled={!onDiscard || busy} onClick={() => setDiscarding(!discarding)}>Discard</button>{discarding && <form className="prepared-discard" onSubmit={async (event) => { event.preventDefault(); if (!onDiscard || busy || !Number.isFinite(quantity) || quantity <= 0 || quantity > servingsLeft) return; setBusy(true); try { await onDiscard(quantity, reason.trim()); setDiscarding(false); } finally { setBusy(false); } }}><label className="field"><span>Reason (optional)</span><input value={reason} onChange={(event) => setReason(event.target.value)} /></label><button className="button danger compact" disabled={busy || !Number.isFinite(quantity) || quantity <= 0 || quantity > servingsLeft}>Discard {formatServings(quantity)}</button><button type="button" className="button compact secondary" disabled={busy} onClick={() => setDiscarding(false)}>Cancel</button></form>}</div>;
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
        <button className="button secondary" onClick={() => onOpen('product')}><PackageOpen />Define product</button>
      </div>
      {sections.map((section) => (
        <Card className="inventory-section" key={section.label}>
          <div className="inventory-section-head"><span>{section.emoji}</span><strong>{section.label}</strong><small>{section.foods.length} foods</small></div>
          {section.foods.map((food) => (
            <button className="inventory-row" key={food.name} onClick={() => onOpenFood(food)}>
              <span className="row-emoji">{food.emoji}</span><div className="inventory-name"><strong>{food.name}</strong><small>{food.sub}</small></div>
              <div className="lot-meter"><div>{food.lots.map((lot, index) => <span key={lot} className={cx('lot-bar', index === 0 && food.tone)} />)}</div><small>{food.lots.join(' · ')}</small></div>
              <strong className="inventory-total">{food.total}<small className="cost-inline" aria-label={inventoryValueLabel(food.cost, food.costIsEstimated)}>{inventoryValueLabel(food.cost, food.costIsEstimated, true)}</small></strong><small className={cx('inventory-due', food.tone)}>{food.due}</small>
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
  const [query, setQuery] = useState('');
  const [sort, setSort] = useState<'made' | 'added' | 'quickest' | 'cheapest' | 'stocked' | 'name'>('made');

  const matches = (recipe: Recipe) => {
    const haystack = `${recipe.name} ${recipe.ingredients.map((item) => item.label).join(' ')}`.toLowerCase();
    return haystack.includes(query.trim().toLowerCase());
  };
  const perServing = (recipe: Recipe) => perServingCost(recipe.estimatedCost, recipe.servings);
  const usesExpiring = (recipe: Recipe) => recipe.ingredients.some((item) => /expires in|short/i.test(item.stock));

  const FILTERS: Array<{ label: string; test: (recipe: Recipe) => boolean }> = [
    { label: 'All recipes', test: () => true },
    { label: 'Cookable now', test: (recipe) => Boolean(recipe.cookable) },
    { label: 'Under 15 min', test: (recipe) => recipe.minutes < 15 },
    { label: 'Under $2 a serving', test: (recipe) => { const value = perServing(recipe); return value !== null && value < 2; } },
    { label: 'Uses expiring food', test: usesExpiring },
    { label: 'Never made', test: (recipe) => !(recipe.prepCount ?? 0) },
  ];
  const active = FILTERS.find((option) => option.label === filter) ?? FILTERS[0];
  const visibleRecipes = recipes.filter((recipe) => matches(recipe) && active.test(recipe)).sort((left, right) => {
    if (sort === 'added') return left.name.localeCompare(right.name);
    if (sort === 'quickest') return left.minutes - right.minutes;
    if (sort === 'cheapest') return (perServing(left) ?? Infinity) - (perServing(right) ?? Infinity);
    if (sort === 'stocked') return Number(right.cookable ?? false) - Number(left.cookable ?? false);
    if (sort === 'name') return left.name.localeCompare(right.name);
    return (right.prepCount ?? 0) - (left.prepCount ?? 0) || left.name.localeCompare(right.name);
  });

  return (
    <div>
      <div className="find-bar">
        <label className="search-box"><Search /><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search names, ingredients, or tags…" /></label>
        <label className="find-sort">Sort<select value={sort} onChange={(event) => setSort(event.target.value as typeof sort)}>
          <option value="made">Most made</option>
          <option value="added">Recently added</option>
          <option value="quickest">Quickest first</option>
          <option value="cheapest">Cheapest per serving</option>
          <option value="stocked">Best stocked</option>
          <option value="name">A–Z</option>
        </select></label>
        <small className="find-count">{visibleRecipes.length} of {recipes.length}</small>
      </div>
      <div className="toolbar">{FILTERS.map((option) => <button className={cx('filter-chip', filter === option.label && 'active')} key={option.label} onClick={() => onFilter(option.label)}>{option.label} <small>{recipes.filter((recipe) => matches(recipe) && option.test(recipe)).length}</small></button>)}</div>
      <div className="recipe-grid">
        {visibleRecipes.map((recipe) => (
          <Card className="recipe-card" key={recipe.id}>
            <div className="recipe-head"><span>{recipe.emoji}</span><div className="grow"><div className="title-with-badge"><h2>{recipe.name}</h2></div><small>{recipe.minutes} min · {servingLabel(recipe.servings)} · {recipe.prepCount ?? 0} preparation{recipe.prepCount === 1 ? '' : 's'}</small></div><div><Rating label="EASE" value={recipe.ease} /><Rating label="TASTE" value={recipe.taste} /></div></div>
            <div className="ingredient-chips">{recipe.ingredients.map((item) => { const short = item.stock.includes('· short'); return <span className={short ? 'short' : ''} key={item.label}>{short ? '!' : '✓'} {item.label}</span>; })}</div>
            <p className="recipe-nutrition">{recipe.nutrition} · <span className="spend">{costLabel(perServing(recipe), recipe.costIsEstimated)}/serving</span></p>
            <div className="card-actions"><button className="button primary" onClick={() => onOpen('cook', recipe)}>Make batch</button><button className="button secondary" onClick={() => onOpen('recipe-edit', recipe)}>Edit recipe</button></div>
          </Card>
        ))}
        {!visibleRecipes.length && <Card className="empty-state"><CookingPot /><h2>Nothing matches</h2><p>Try a different search or filter.</p></Card>}
      </div>
      <div className="inline-heading"><h2>Meals</h2></div>
      <Card className="combined-meal">
        <div className="combined-summary"><span>🍽️</span><div className="grow"><strong>Build a meal</strong></div><button className="button primary" onClick={() => onOpen('combined-meal')}>Choose recipes</button></div>
        <div className="combined-components">{recipes.map((recipe) => <button key={recipe.id} onClick={() => onOpen('recipe-detail', recipe)}><span>{recipe.emoji}</span><div><strong>{recipe.name}</strong><small>{recipe.minutes} min · {costLabel(recipe.estimatedCost, recipe.costIsEstimated)} per batch</small></div><ChevronRight /></button>)}</div>
      </Card>
    </div>
  );
}

interface WeekSelectionProps { range: PlanningRange; onChangeWeek: (delta: number) => void }

function WeekSelector({ range, onChangeWeek }: WeekSelectionProps) {
  return <div className="week-switcher" role="group" aria-label="Planning week"><button className="icon-button" aria-label="Previous week" onClick={() => onChangeWeek(-1)}>‹</button><strong>{formatPlanningRange(range)}</strong><button className="icon-button" aria-label="Next week" onClick={() => onChangeWeek(1)}>›</button></div>;
}

function GroceryPage({ range, onChangeWeek, onReceive, checked, toggle, shoppingMode, onShoppingMode, onRemove, notify }: WeekSelectionProps & { onReceive?: (id: string, receipt: ShoppingReceipt) => Promise<void>; checked: Set<string>; toggle: (item: { id?: string; name: string }) => void; shoppingMode: boolean; onShoppingMode: (value: boolean) => void; onRemove?: (id: string) => Promise<void>; notify: Notify }) {
  const { grocerySections, groceryGeneration, inventorySections, settings } = usePantryData();
  const [receiving, setReceiving] = useState<GroceryItem | null>(null);
  const weekly = settings.weeklyFoodBudget;
  const itemKey = (item: { id?: string; name: string }) => item.id ?? item.name;
  const total = grocerySections.flatMap((section) => section.items).length;
  const groceryCost = grocerySections.flatMap((section) => section.items).reduce((sum, item) => sum + Number(item.cost ?? 0), 0);
  const done = checked.size;
  const demandChanges = grocerySections.flatMap((section) => section.items).filter((item) => item.demandNotice).length;
  const next = grocerySections.find((section) => section.items.some((item) => !checked.has(itemKey(item)) || item.demandNotice));
  const pickedUp = grocerySections.flatMap((section) => section.items).filter((item) => checked.has(itemKey(item))).reduce((sum, item) => sum + Number(item.cost ?? 0), 0);
  const alreadyInKitchen = inventorySections.flatMap((section) => section.foods).slice(0, 6);
  return (
    <div className={cx(shoppingMode && 'shopping-mode')}>
      <div className="grocery-range">
        <WeekSelector range={range} onChangeWeek={onChangeWeek} />
        <small aria-label="Saved grocery ranges">{groceryGeneration.ranges.length ? `Generated for: ${groceryGeneration.ranges.map(formatPlanningRange).join('; ')}${groceryGeneration.unknownRange ? '; some ranges unavailable' : ''}` : groceryGeneration.unknownRange ? 'Generated range unavailable' : 'No saved generated range'}</small>
      </div>
      <Card className="grocery-summary">
        <div className="grow"><div className="grocery-count"><strong>{done}<span>/{total}</span></strong><span>{demandChanges ? `${demandChanges} changed demand${demandChanges === 1 ? '' : 's'} to review` : total - done === 0 ? 'All items checked' : `${total - done} items left`}</span></div><Progress value={total ? done / total * 100 : 100} /></div>
        <div className="budget-panel">
          <strong className="spend">{usd(groceryCost)}</strong>
          <span>of {usd(weekly)} weekly food budget</span>
          <Progress value={weekly ? Math.min(100, groceryCost / weekly * 100) : 0} color="var(--spend)" />
          <small>{usd(pickedUp)} checked on the list</small>
        </div>
        <div className="next-aisle"><span>{next ? 'NEXT AISLE' : 'ALL CHECKED'}</span><strong>{next?.label ?? 'Everything checked'}</strong><button className="button compact" onClick={() => onShoppingMode(!shoppingMode)}>{shoppingMode ? 'Exit shopping mode' : 'Start shopping mode'}</button></div>
      </Card>
      {receiving && onReceive && <ShoppingReceiptEditor key={receiving.id} item={receiving} onSave={onReceive} onClose={() => setReceiving(null)} />}
      <div className="grocery-grid">
        {grocerySections.map((section) => (
          <Card className={cx('grocery-section', section.items.every((item) => checked.has(itemKey(item)) && !item.demandNotice) && 'complete')} key={section.label}>
            <div className="inventory-section-head"><span>{section.emoji}</span><strong>{section.label}</strong><small>{section.items.filter((item) => !checked.has(itemKey(item))).length} left</small></div>
            {section.items.map((item) => (
              <div className={cx('grocery-row', checked.has(itemKey(item)) && 'checked')} key={itemKey(item)}><button className="grocery-toggle" onClick={() => toggle(item)}><span className="check-box">{checked.has(itemKey(item)) && <Check />}</span><strong>{item.name}</strong><span className="grocery-quantity"><small>{item.quantity} · <span className="spend">{costLabel(item.cost, true)}</span></small></span></button>{item.requiredProductName && <small>For plan: {item.requiredProductName}</small>}{item.savedQuantityLabel !== undefined && <details><summary>Details</summary><small>Saved label: {item.savedQuantityLabel}</small></details>}{item.demandNotice && <small role="status">{item.demandNotice}</small>}{item.id && !item.receiptLotId && <button className="button compact" disabled={!onReceive} onClick={() => setReceiving(item)}>Receive</button>}{item.receiptLotId && <small>Received</small>}{item.id && !item.receiptLotId && <button className="grocery-remove" aria-label={`Remove ${item.name}`} disabled={!onRemove} onClick={() => { if (onRemove) void onRemove(item.id!).then(() => notify(`${item.name} removed from the grocery list.`)).catch(() => notify(`Could not remove ${item.name}.`)); }}><Trash2 /></button>}</div>
            ))}
          </Card>
        ))}
      </div>
      <div className="already-in"><span>ALREADY IN THE KITCHEN</span><div>{alreadyInKitchen.map((food) => <em key={food.name}>{food.emoji} {food.name}</em>)}</div></div>
    </div>
  );
}

function PlannedServingEditor({ meal, notify, onSave }: { meal: { id?: string; name: string; plannedServings?: number; actualServings?: number; consumptionStatus?: string }; notify: Notify; onSave?: (id: string, servings: number) => Promise<void> }) {
  const editable = (value: number | undefined) => String(Number(Number(value ?? 1).toFixed(3)));
  const [value, setValue] = useState(editable(meal.plannedServings));
  useEffect(() => setValue(editable(meal.plannedServings)), [meal.plannedServings]);
  const servings = Number(value);
  const changed = Number.isFinite(servings) && servings > 0 && servings !== (meal.plannedServings ?? 1);
  const eaten = meal.consumptionStatus === 'fulfilled';
  return <span className="planned-portion"><input aria-label={`Planned servings for ${meal.name}`} type="number" min="0.01" step="any" value={value} disabled={eaten} onChange={(event) => setValue(event.target.value)} /><span>{formatServings(servings)} planned</span>{eaten && meal.actualServings !== undefined ? <strong>{formatServings(meal.actualServings)} eaten</strong> : null}{changed && meal.id && onSave && !eaten ? <button type="button" onClick={() => void onSave(meal.id!, servings).then(() => notify(`Planned portion updated to ${formatServings(servings)}.`)).catch((error: unknown) => notify(error instanceof Error ? error.message : 'Could not update the planned portion.'))}>Save</button> : null}</span>;
}

function PlannedMealEatEditor({ meals, notify, onConsume }: { meals: Array<{ id?: string; name: string; plannedServings?: number; preparedServingsAvailable?: number; sourceServingsAvailable?: number }>; notify: Notify; onConsume?: (consumptions: PlannedMealConsumption[]) => Promise<string[]> }) {
  const defaultsKey = meals.map((meal) => `${meal.id ?? meal.name}:${meal.plannedServings ?? 1}`).join('|');
  const buildDefaults = () => Object.fromEntries(meals.map((meal) => [meal.id ?? meal.name, String(Number(Number(meal.plannedServings ?? 1).toFixed(3)))]));
  const [values, setValues] = useState<Record<string, string>>(buildDefaults);
  const [saving, setSaving] = useState(false);
  useEffect(() => setValues(buildDefaults()), [defaultsKey]);
  const consumptions = meals.flatMap((meal) => {
    const servings = Number(values[meal.id ?? meal.name]);
    return meal.id && Number.isFinite(servings) && servings > 0 && ((meal.sourceServingsAvailable ?? meal.preparedServingsAvailable) === undefined || servings <= (meal.sourceServingsAvailable ?? meal.preparedServingsAvailable)!) ? [{ mealPlanId: meal.id, servings }] : [];
  });
  const valid = consumptions.length === meals.length;
  const total = consumptions.reduce((sum, consumption) => sum + consumption.servings, 0);
  return <div className="meal-eat-control"><div className="meal-eat-fields">{meals.map((meal) => { const key = meal.id ?? meal.name; const amount = Number(values[key]); return <label key={key}><span>{meals.length === 1 ? 'Eating now' : meal.name}</span><span className="meal-eat-input"><input aria-label={`Servings of ${meal.name} eaten now`} type="number" min="0.01" max={meal.sourceServingsAvailable ?? meal.preparedServingsAvailable} step="any" value={values[key] ?? ''} onChange={(event) => setValues((current) => ({ ...current, [key]: event.target.value }))} /><em>serving{amount === 1 ? '' : 's'}</em></span><small>{formatServings(meal.plannedServings ?? 1)} planned{(meal.sourceServingsAvailable ?? meal.preparedServingsAvailable) !== undefined ? ` · ${formatServings((meal.sourceServingsAvailable ?? meal.preparedServingsAvailable)!)} available` : ''}</small></label>; })}</div><button className="button primary compact meal-eat-button" disabled={!onConsume || !valid || saving} onClick={() => { if (!onConsume || !valid) return; setSaving(true); void onConsume(consumptions).then(() => notify(`${formatServings(total)} logged as eaten.`)).catch((error: unknown) => notify(error instanceof Error ? error.message : 'Could not log the planned item as eaten.')).finally(() => setSaving(false)); }}><Utensils />{saving ? 'Logging…' : 'Log eaten'}</button></div>;
}

function WeekPage({ range, onChangeWeek, onCookMeal, onOpen, notify, onRemove, onConsume, onSetServings }: WeekSelectionProps & { onOpen: (kind: PanelKind, recipe?: Recipe, values?: Record<string, string>) => void; notify: Notify; onRemove?: (ids: string[]) => Promise<void>; onConsume?: (consumptions: PlannedMealConsumption[]) => Promise<string[]>; onSetServings?: (id: string, servings: number) => Promise<void>; onCookMeal: (ids: string[]) => void }) {
  const { plannedMeals, recipes, settings } = usePantryData();
  const todayKey = dateKeyInTimeZone(new Date(), settings.timeZone);
  const weekDays = useMemo(() => Array.from({ length: 7 }, (_, offset) => {
    const dateKey = addCalendarDays(range.from, offset);
    const date = new Date(`${dateKey}T12:00:00Z`);
    return { day: date.toLocaleDateString([], { weekday: 'short', timeZone: 'UTC' }).toUpperCase(), date: String(date.getUTCDate()), dateKey, today: dateKey === todayKey, meals: plannedMeals.filter((meal) => meal.dateKey === dateKey).map((meal) => ({ ...meal, slot: `${meal.slot} · ${costLabel(meal.cost, meal.costIsEstimated)}` })) };
  }), [plannedMeals, range.from, todayKey]);
  const weekly = settings.weeklyFoodBudget;
  const weekMeals = weekDays.flatMap((day) => day.meals);
  const weekMealCount = new Set(weekMeals.map((meal) => meal.groupId ?? meal.id ?? meal.name)).size;
  const committed = weekMeals.reduce((total, meal) => total + (meal.cost ?? 0), 0);
  const unavailableMealPrices = new Set(weekMeals.filter((meal) => meal.cost === null || meal.cost === undefined).map((meal) => meal.groupId ?? meal.id ?? meal.name)).size;
  const unspent = Math.max(0, weekly - committed);
  const committedPct = weekly > 0 ? Math.min(100, committed / weekly * 100) : 0;

  return (
    <Card className="week-card">
      <div className="week-header">
        <WeekSelector range={range} onChangeWeek={onChangeWeek} />
        <p>{weekMealCount} item{weekMealCount === 1 ? '' : 's'} planned · {unavailableMealPrices ? <><span className="spend">{usd(committed)}</span> known · {unavailableMealPrices} price{unavailableMealPrices === 1 ? '' : 's'} unavailable</> : <><span className="spend">{usd(unspent)}</span> of the week's budget still unspent</>}</p>
        <div className="week-budget-bar"><Progress value={committedPct} color="var(--spend)" /><small>{usd(committed)} known of {usd(weekly)}{unavailableMealPrices ? ' · incomplete' : ''}</small></div>
      </div>
      <div className="week-list">{weekDays.map((day) => {
        const dayCost = completeCost(day.meals.map((meal) => meal.cost));
        const groups = [...day.meals.reduce((map, meal) => { const key = meal.groupId ?? meal.id ?? meal.name; map.set(key, [...(map.get(key) ?? []), meal]); return map; }, new Map<string, typeof day.meals>()).entries()];
        return (
          <div className={cx('week-row', day.today && 'today', day.dateKey < todayKey && 'past')} key={day.dateKey}>
            <div className="week-row-date">
              <strong>{day.day}</strong>
              <small>{day.date}</small>
              <em className="spend">{day.meals.length ? usd(dayCost) : '—'}</em>
              <small>{groups.length} item{groups.length === 1 ? '' : 's'}</small>
            </div>
            <div className="week-row-meals">
              {groups.map(([groupId, meals]) => {
                const displayStatus = planDisplayStatus(meals, day.dateKey < todayKey);
                const { made, eaten } = displayStatus;
                const ids = meals.flatMap((meal) => meal.id ? [meal.id] : []);
                const mealsLeftToEat = meals.filter((meal) => meal.consumptionStatus !== 'fulfilled');
                const groupCost = completeCost(meals.map((meal) => meal.cost));
                const nextMeal = meals.find(isCookablePlan);
                const recipe = recipes.find((candidate) => candidate.id === (nextMeal?.recipeId ?? meals[0].recipeId));
                const waitingMeals = mealsLeftToEat.filter((meal) => meal.isLeftover && !(Number(meal.preparedServingsAvailable) > 0));
                const canEat = !eaten && mealsLeftToEat.every((meal) => meal.isLeftover
                  ? Number(meal.preparedServingsAvailable) > 0
                  : meal.status === 'made' || meal.sourceKind === 'product' || meal.sourceKind === 'lot');
                return (
                  <div className={cx('week-meal-card', made && 'made', eaten && 'eaten', canEat && 'ready-to-eat', meals[0].isLeftover && 'leftover')} key={groupId}>
                    <span className="row-emoji">{meals[0].emoji}</span>
                    <div className="grow">
                      {recipe ? <button className="week-meal-detail" onClick={() => onOpen('recipe-detail', recipe)} aria-label={`View ${meals.map((meal) => meal.name).join(', ')} details`}>
                        <strong>{meals.map((meal) => meal.name).join(' + ')}</strong>
                        <small>{meals[0].slot.split(' · ')[0]}{meals[0].isLeftover ? ' · leftovers' : ''}</small>
                      </button> : <div className="week-meal-detail"><strong>{meals.map((meal) => meal.name).join(' + ')}</strong><small>{meals[0].slot.split(' · ')[0]} · {meals[0].consumeFromInventory === false ? 'outside pantry' : meals[0].sourceKind === 'lot' ? 'exact lot' : 'pantry item'}</small></div>}
                      <div className="planned-portions">{meals.map((meal) => <PlannedServingEditor key={meal.id ?? meal.name} meal={meal} notify={notify} onSave={onSetServings} />)}</div>
                    </div>
                    <span className={cx('plan-status', displayStatus.tone)}>{displayStatus.label}</span>
                    <strong className="week-meal-cost spend">{costLabel(groupCost, meals.some((meal) => meal.costIsEstimated))}<small>planned portions</small></strong>
                    <div className="week-meal-actions">
                      {recipe && nextMeal ? <button className="button compact" onClick={() => onCookMeal(meals.filter(isCookablePlan).flatMap((meal) => meal.id ? [meal.id] : []))}><CookingPot />Cook {meals.length > 1 ? 'meal' : recipe.name}</button> : null}
                      <button className="row-icon-button" aria-label={`Remove ${meals.map((meal) => meal.name).join(', ')}`} disabled={!onRemove || !ids.length} onClick={() => { if (onRemove) void onRemove(ids).then(() => notify('Item removed from the plan.')).catch(() => notify('Could not remove the planned item.')); }}><Trash2 /></button>
                    </div>
                    {mealsLeftToEat.some((meal) => meal.sourceShortfall) && <p role="status">Selected lot is short for this week. Adjust portions or remove a plan.</p>}
                    {waitingMeals.length > 0 && <p className="meal-waiting" role="status">{waitingMeals.map((meal) => `${meal.name}: ${meal.waitingForPreparation !== false ? 'not cooked yet' : 'no servings left'}`).join(' · ')}</p>}
                    {canEat ? <PlannedMealEatEditor meals={mealsLeftToEat} notify={notify} onConsume={onConsume} /> : null}
                  </div>
                );
              })}
              <button className="week-add" onClick={() => onOpen('meal', undefined, { plan_date: day.dateKey ?? '' })}><Plus />Add to this day</button>
            </div>
          </div>
        );
      })}</div>
    </Card>
  );
}

function FoodLogPage({ onOpen, onOpenConsumption, notify, onVoid, onPlan, onConsumeLot, undo }: { onOpen: (kind: PanelKind) => void; onOpenConsumption: (entry: FoodLogEntry) => void; notify: Notify; onVoid?: (id: string) => Promise<void>; onPlan?: (form: FormData) => Promise<string>; onConsumeLot?: (id: string, quantity: number) => Promise<string | null>; undo: Reversals }) {
  const { foodLog: todayFoodLog, foodLogByDate, nutrients: todayNutrients, nutritionIncompleteEntries: todayIncompleteEntries, plannedMeals, settings, todayProjection } = usePantryData();
  const dailyBudget = dailyFoodBudget(settings.weeklyFoodBudget);
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
  const incompleteEntries = isToday ? todayIncompleteEntries : (selectedDay?.nutritionIncompleteEntries ?? 0);
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
      {isToday && <NutritionSandbox onPlan={onPlan} onConsumeLot={onConsumeLot} notify={notify} />}
      <Card className="contribution-card">
        <SectionTitle title="How each food built your day" action="Targets" onAction={() => onOpen('targets')} />
        {incompleteEntries > 0 && <div className="notice"><Info /><span>Known nutrition is shown as a minimum. {incompleteEntries} entr{incompleteEntries === 1 ? 'y has' : 'ies have'} partial or unknown nutrition.</span></div>}
        <div className="legend">{foodLog.map((item) => <span key={item.id ?? item.label}><i style={{ background: item.color }} />{item.label}<small>{item.calories}</small></span>)}{isToday && Object.values(todayProjection).some(Boolean) && <span><i className="projection-swatch" />Planned for today<small>not eaten yet</small></span>}</div>
        {nutrients.map((nutrient) => {
          const label = nutrient.label as keyof typeof todayProjection;
          const target = Number(nutrient.target.replace(/[^\d.]/g, '')) || 1;
          const total = foodLog.reduce((sum, entry) => sum + Number(entry.nutrition?.[label] ?? 0), 0);
          const projection = isToday ? todayProjection[label] : 0;
          const scale = Math.max(target / 0.82, total + projection, 1);
          return <div className="contribution-row" key={nutrient.label}><strong>{nutrient.label}</strong><div className="segment-bar">{foodLog.map((entry, index) => <i key={entry.id ?? `${entry.label}-${index}`} style={{ width: `${Number(entry.nutrition?.[label] ?? 0) / scale * 100}%`, maxWidth: 'none', background: entry.color }} />)}{projection > 0 && <i className="projection-segment" style={{ width: `${projection / scale * 100}%`, maxWidth: 'none' }} />}<b style={{ left: `${target / scale * 100}%` }} /></div><span>{nutrient.value} {nutrient.target}</span></div>;
        })}
        {(() => {
          // Cost reads exactly like a nutrient: same segments, same target marker,
          // with the line at the day's share of the one weekly budget.
          const spent = foodLog.reduce((sum, entry) => sum + (entry.cost ?? 0), 0);
          const plannedCost = isToday ? plannedMeals.filter((plan) => plan.dateKey === selectedKey && plan.consumptionStatus === 'planned').reduce((sum, plan) => sum + (plan.cost ?? 0), 0) : 0;
          const scale = Math.max(dailyBudget / 0.82, spent + plannedCost, 0.01);
          return <div className="contribution-row" key="Cost"><strong>Cost</strong><div className="segment-bar">{foodLog.map((entry, index) => <i key={entry.id ?? `${entry.label}-${index}`} style={{ width: `${(entry.cost ?? 0) / scale * 100}%`, maxWidth: 'none', background: entry.color }} />)}{plannedCost > 0 && <i className="projection-segment" style={{ width: `${plannedCost / scale * 100}%`, maxWidth: 'none' }} />}<b style={{ left: `${dailyBudget / scale * 100}%` }} /></div><span>{usd(spent)}{plannedCost ? ` + ${usd(plannedCost)} planned` : ''} / {usd(dailyBudget)}</span></div>;
        })()}
      </Card>
      <Card>
        <SectionTitle title="Food and drinks" action={`${foodLog.length} entr${foodLog.length === 1 ? 'y' : 'ies'} · ${costLabel(foodLog.every((entry) => entry.cost !== null && entry.cost !== undefined) ? foodLog.reduce((sum, entry) => sum + Number(entry.cost), 0) : null, foodLog.some((entry) => entry.costIsEstimated))}`} />
        {foodLog.map((entry) => <div className="log-row" key={entry.id ?? entry.label}><i style={{ background: entry.color }} /><button className="log-event-button" onClick={() => onOpenConsumption(entry)} aria-label={`View ${entry.label} consumption event`}><span className="row-emoji">{entry.emoji}</span><div className="grow"><strong>{entry.label}</strong><small>{entry.serving}</small></div><strong className="log-cost">{costLabel(entry.cost, entry.costIsEstimated)}</strong><span>{entry.calories}</span><span>{entry.protein}</span><small>{entry.time}</small></button><div className="log-row-actions">{entry.id && onVoid && <button className="row-icon-button" aria-label={entry.eventIds && entry.eventIds.length > 1 ? `Choose ${entry.label} event to remove` : `Remove ${entry.label}`} onClick={() => { if ((entry.eventIds?.length ?? 0) > 1) { onOpenConsumption(entry); return; } void onVoid(entry.id!).then(() => notify(`${entry.label} removed from the food log.`, undo.restoreFoodLog ? async () => { await undo.restoreFoodLog!(entry.id!); } : undefined)).catch((cause) => notify(mutationError(cause, `Could not remove ${entry.label}.`))); }}><Trash2 /></button>}</div></div>)}
        {!foodLog.length && <div className="empty-inline">Nothing logged for this day.</div>}
      </Card>
    </div>
  );
}

function HistoryPage({ onUndoPrep, onUndoReceipt, onUndoDiscard, onOpen, onOpenConsumption }: { onUndoPrep?: (id: string) => Promise<void>; onUndoReceipt?: (id: string) => Promise<void>; onUndoDiscard?: (id: string) => Promise<void>; onOpen: (kind: PanelKind) => void; onOpenConsumption: (entry: FoodLogEntry) => void }) {
  const { foodLogByDate, history, preparationHistory, receiptHistory = [], discardHistory = [], settings } = usePantryData();
  const [range, setRange] = useState(30);

  const cutoff = new Date();
  cutoff.setHours(12, 0, 0, 0);
  cutoff.setDate(cutoff.getDate() - (range - 1));
  const cutoffKey = cutoff.toLocaleDateString('en-CA');
  const days = history.filter((day) => !day.dateKey || day.dateKey >= cutoffKey);
  const preparations = preparationHistory.filter((prep) => prep.dateKey >= cutoffKey);
  const discards = discardHistory.filter((entry) => entry.dateKey >= cutoffKey);

  const proteinTarget = settings.proteinG || 1;
  const dailyBudget = dailyFoodBudget(settings.weeklyFoodBudget);
  const logged = days.length;
  const completeDays = days.filter((day) => !day.nutritionIncompleteEntries);
  const avgCalories = completeDays.length ? completeDays.reduce((total, day) => total + (day.calories ?? 0), 0) / completeDays.length : 0;
  const avgProtein = completeDays.length ? completeDays.reduce((total, day) => total + (day.protein ?? 0), 0) / completeDays.length : 0;
  const pricedDays = days.filter((day) => day.cost !== null && day.cost !== undefined);
  const totalSpend = pricedDays.reduce((total, day) => total + Number(day.cost), 0);
  const targetHits = completeDays.filter((day) => (day.protein ?? 0) >= proteinTarget).length;

  // The strip is the real calendar: one cell per day in range, coloured only where
  // a day was actually logged. Nothing here is synthesized to fill a gap.
  const byKey = new Map(days.flatMap((day) => day.dateKey ? [[day.dateKey, day] as const] : []));
  const cells = Array.from({ length: range }, (_, index) => {
    const date = new Date(cutoff);
    date.setDate(date.getDate() + index);
    const key = date.toLocaleDateString('en-CA');
    const day = byKey.get(key);
    const share = day && !day.nutritionIncompleteEntries ? (day.protein ?? 0) / proteinTarget : null;
    return { key, label: date.toLocaleDateString([], { month: 'short', day: 'numeric' }), day, share };
  });
  const heatColor = (share: number | null) => {
    if (share === null) return '#1a201e';
    if (share >= 0.9) return '#5fe0a0';
    if (share >= 0.7) return '#3f9e72';
    if (share >= 0.5) return '#2f5c44';
    return '#26483a';
  };

  const repeated = [...days.reduce((counts, day) => {
    for (const meal of day.mealDetails ?? day.meals.map((label) => ({ label, cost: null as number | null, costIsEstimated: true, emoji: '🍽️' }))) {
      const current = counts.get(meal.label) ?? { count: 0, spend: 0, priced: true, emoji: meal.emoji };
      counts.set(meal.label, { count: current.count + 1, spend: current.spend + (meal.cost ?? 0), priced: current.priced && meal.cost !== null, emoji: current.emoji });
    }
    return counts;
  }, new Map<string, { count: number; spend: number; priced: boolean; emoji: string }>()).entries()]
    .sort((left, right) => right[1].count - left[1].count).slice(0, 5);

  // Longest run of consecutive logged days inside the range.
  let streak = 0;
  let run = 0;
  for (const cell of cells) { run = cell.day ? run + 1 : 0; streak = Math.max(streak, run); }
  const missingCost = days.reduce((total, day) => total + (day.mealsMissingCost ?? 0), 0);

  return (
    <div className="stack">
      <div className="range-bar">
        <div className="range-chips">{[7, 30, 90].map((option) => <button key={option} className={cx('filter-chip', range === option && 'active')} onClick={() => setRange(option)}>{option} days</button>)}</div>
        <button className="button secondary" onClick={() => onOpen('export')}><Download />Export</button>
      </div>

      <Card>
        <div className="stat-strip">
          <div><span>Days logged</span><strong>{logged} of {range}</strong></div>
          <div><span>Avg calories</span><strong>{Math.round(avgCalories).toLocaleString()}</strong></div>
          <div><span>Avg protein</span><strong>{Math.round(avgProtein)} g</strong></div>
          <div><span>Food cost</span><strong className="spend">{usd(totalSpend)}{missingCost ? " + unknown" : ""}</strong><small>avg {usd(pricedDays.length ? totalSpend / pricedDays.length : null)} on logged days</small></div>
          <div><span>Protein target hit</span><strong>{targetHits} of {completeDays.length}</strong></div>
        </div>
        <div className="heat-strip">{cells.map((cell) => <i key={cell.key} style={{ background: heatColor(cell.share) }} title={cell.day ? `${cell.label} · ${Math.round(cell.day.protein ?? 0)} g protein · ${usd(cell.day.cost)}` : `${cell.label} · not logged`} />)}</div>
      </Card>

      <Card>
        <SectionTitle title="What I made" action={`${preparations.length} batch${preparations.length === 1 ? '' : 'es'}`} />
        {preparations.map((prep) => <div className="prep-history-row" key={prep.id}><span className="row-emoji">{prep.emoji}</span><div className="grow"><strong>{prep.name}</strong><small>{formatPreparedAt(prep.preparedAt, settings.timeZone)}</small></div><div><span>Made</span><strong>{formatServings(prep.servingsMade)}</strong></div><div><span>Stored</span><strong>{prep.location}</strong></div><div><span>Remaining</span><strong>{formatAmount(prep.servingsRemaining)}</strong></div><DurableUndo label={`Undo prep ${prep.name}`} action={onUndoPrep ? () => onUndoPrep(prep.id) : undefined} /></div>)}
        {!preparations.length && <div className="empty-inline">No recipes prepared in the last {range} days.</div>}
      </Card>

      <Card>
        <SectionTitle title="Discarded food" />
        {discards.map((entry) => <div className="prep-history-row" key={entry.eventId}><div className="grow"><strong>{entry.name}</strong><small>{formatPreparedAt(entry.occurredAt, settings.timeZone)} · {entry.quantity} · {costLabel(entry.cost)} wasted</small>{entry.reason && <small>{entry.reason}</small>}</div><DurableUndo label={`Undo discard ${entry.name}`} action={onUndoDiscard ? () => onUndoDiscard(entry.eventId) : undefined} /></div>)}
        {!discards.length && <div className="empty-inline">Nothing discarded in the last {range} days.</div>}
      </Card>
      <Card>
        <SectionTitle title="Shopping receipts" />
        {receiptHistory.map((receipt) => <div className="prep-history-row" key={receipt.lotId}><div className="grow"><strong>{receipt.name}</strong><small>{formatPreparedAt(receipt.acquiredAt, settings.timeZone)} · {receipt.quantity} · {costLabel(receipt.cost)}</small></div><DurableUndo label={`Undo receipt ${receipt.name}`} action={onUndoReceipt ? () => onUndoReceipt(receipt.lotId) : undefined} /></div>)}
        {!receiptHistory.length && <p>No shopping receipts yet.</p>}
      </Card>
      <Card>
        <SectionTitle title="Day by day" action={`${logged} logged day${logged === 1 ? '' : 's'}`} />
        {days.map((day) => (
          <div className="history-row" key={day.dateKey ?? day.date}>
            <div className="history-when"><strong>{day.day}</strong><small>{day.date}</small></div>
            <div className="history-meals">{(day.mealDetails ?? day.meals.map((label) => ({ id: undefined, label, emoji: '🍽️', cost: null as number | null, costIsEstimated: true }))).map((meal, index) => (
              <button className="meal-chip" key={`${meal.label}-${index}`} onClick={() => {
                const entry = day.dateKey ? foodLogByDate[day.dateKey]?.foodLog.find((candidate) => meal.id ? candidate.id === meal.id : candidate.label === meal.label) : undefined;
                onOpenConsumption(entry ?? { id: meal.id, emoji: meal.emoji, label: meal.label, serving: 'Serving details unavailable', calories: `${Math.round(day.calories ?? 0).toLocaleString()} cal for the day`, protein: `${Math.round(day.protein ?? 0)} g protein for the day`, time: day.date, color: 'var(--spend)', cost: meal.cost, costIsEstimated: meal.costIsEstimated });
              }}><span>{meal.emoji}</span>{meal.label}<em className="spend">{costLabel(meal.cost, meal.costIsEstimated)}</em></button>
            ))}</div>
            <span className="history-figure">{Math.round(day.calories ?? 0).toLocaleString()}{day.nutritionIncompleteEntries ? '+' : ''} cal</span>
            <span className="history-figure">{Math.round(day.protein ?? 0)}{day.nutritionIncompleteEntries ? '+' : ''} g</span>
            <span className="history-figure spend">{costLabel(day.cost, true)}</span>
            <div className="history-actions"><button className="button secondary compact" onClick={() => onOpen('meal')}>Plan again</button></div>
          </div>
        ))}
        {!days.length && <div className="empty-inline">Nothing logged in the last {range} days.</div>}
      </Card>

      <div className="history-layout">
        <Card className="grow">
          <SectionTitle title="Most repeated" />
          {repeated.map(([label, meal]) => <div className="repeat-row" key={label}><strong>{meal.count}×</strong><div><span>{meal.emoji} {label}</span><small className="spend">{meal.priced ? `${usd(meal.spend)} across the range` : 'Price unavailable'}</small></div><button className="button secondary compact" onClick={() => onOpen('meal')}>Plan</button></div>)}
          {!repeated.length && <div className="empty-inline">No meals logged in this range.</div>}
        </Card>
        <Card className="repeats-card">
          <SectionTitle title="Gaps and misses" />
          <div className="gap-row"><span>Unlogged days</span><strong>{range - logged}</strong></div>
          <div className="gap-row"><span>Meals missing a cost</span><strong>{missingCost}</strong></div>
          <div className="gap-row"><span>Longest streak</span><strong>{streak} day{streak === 1 ? '' : 's'}</strong></div>
          <div className="gap-row"><span>Incomplete nutrition days</span><strong>{logged - completeDays.length}</strong></div>
          <div className="gap-row"><span>Protein target missed</span><strong>{completeDays.length - targetHits} of {completeDays.length}</strong></div>
          <div className="gap-row"><span>Days over budget</span><strong>{pricedDays.filter((day) => Number(day.cost) > dailyBudget).length}</strong></div>
        </Card>
      </div>
    </div>
  );
}

function TrendsPage({ onOpen }: { onOpen: (kind: PanelKind) => void }) {
  const { nutritionHistory, settings, spendHistory, wasteCauses } = usePantryData();
  const [view, setView] = useState<'nutrition' | 'spend'>('nutrition');
  const nutrientLabels = ['Calories', 'Protein', 'Carbs', 'Fat', 'Fiber', 'Sodium'] as const;
  type TrendNutrient = typeof nutrientLabels[number];
  const [nutrient, setNutrient] = useState<TrendNutrient>('Protein');
  const [driverNutrient, setDriverNutrient] = useState<TrendNutrient>('Protein');
  const [range, setRange] = useState(30);
  const spec: Record<TrendNutrient, { target: number; unit: string; color: string }> = {
    Calories: { target: settings.calories, unit: 'cal', color: '#5fe0a0' }, Protein: { target: settings.proteinG, unit: 'g', color: '#5fe0a0' }, Carbs: { target: settings.carbsG, unit: 'g', color: '#57a8f2' }, Fat: { target: settings.fatG, unit: 'g', color: '#a184f5' }, Fiber: { target: settings.fiberG, unit: 'g', color: '#f0b13f' }, Sodium: { target: settings.sodiumMg, unit: 'mg', color: '#f2637a' },
  };
  const cutoff = new Date();
  cutoff.setHours(12, 0, 0, 0);
  cutoff.setDate(cutoff.getDate() - (range - 1));
  const cutoffKey = `${cutoff.getFullYear()}-${String(cutoff.getMonth() + 1).padStart(2, '0')}-${String(cutoff.getDate()).padStart(2, '0')}`;
  const recent = nutritionHistory.filter((day) => day.dateKey >= cutoffKey);
  const incompleteEntries = recent.reduce((total, day) => total + day.nutritionIncompleteEntries, 0);
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

  // Spend is a top-level view, not a seventh macro.
  const weekly = settings.weeklyFoodBudget;
  const dailyBudget = dailyFoodBudget(weekly);
  const spendDays = Array.from({ length: range }, (_, index) => {
    const date = new Date(cutoff);
    date.setDate(cutoff.getDate() + index);
    const key = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
    const row = spendHistory.find((entry) => entry.dateKey === key);
    return { label: String(date.getDate()), spend: row?.spend ?? 0, waste: row?.waste ?? 0, away: row?.away ?? 0, missing: row?.spendMissingCost ?? 0, wasteMissing: row?.wasteMissingCost ?? 0, awayMissing: row?.awayMissingCost ?? 0, estimated: row?.costIsEstimated ?? false };
  });
  const missingCosts = spendDays.reduce((total, day) => total + day.missing, 0);
  const wasteMissingCosts = spendDays.reduce((total, day) => total + day.wasteMissing, 0);
  const awayMissingCosts = spendDays.reduce((total, day) => total + day.awayMissing, 0);
  const estimatedCosts = spendDays.some((day) => day.estimated);
  const lastSevenMissing = spendDays.slice(-7).some((day) => day.missing > 0);
  const spendTotal = spendDays.reduce((total, day) => total + day.spend, 0);
  const lastSeven = spendDays.slice(-7).reduce((total, day) => total + day.spend, 0);
  const caloriesTotal = recent.reduce((total, day) => total + day.values.Calories, 0);
  const per1000Cal = caloriesTotal > 0 && missingCosts === 0 && incompleteEntries === 0 ? spendTotal / caloriesTotal * 1000 : null;
  const spendMaximum = Math.max(dailyBudget, ...spendDays.map((day) => day.spend), 0.01) * 1.1;

  const wasteTotal = spendDays.reduce((total, day) => total + day.waste, 0);
  const awayTotal = spendDays.reduce((total, day) => total + day.away, 0);
  const wasteDays = spendDays.filter((day) => day.waste > 0 || day.wasteMissing > 0).length;
  const worstDay = spendDays.reduce((worst, day) => day.waste > worst.waste ? day : worst, { label: '—', waste: 0, spend: 0, away: 0 });
  const causeMax = Math.max(...wasteCauses.map((cause) => cause.amount), 0.01);
  return (
    <div className="stack">
      <div className="segmented">
        <button className={cx(view === 'nutrition' && 'active')} onClick={() => setView('nutrition')}>Nutrition</button>
        <button className={cx(view === 'spend' && 'active')} onClick={() => setView('spend')}>Spend</button>
      </div>

      {view === 'nutrition' ? (
        <Card className="trend-card">
          <SectionTitle title={`${nutrient}, day by day`} subtitle={`Daily average ${Math.round(average).toLocaleString()} ${spec[nutrient].unit} · target ${target.toLocaleString()} ${spec[nutrient].unit} · ${daysOnTarget} of ${range} days ${nutrient === 'Sodium' ? 'within limit' : 'on target'}`} action="Edit targets" onAction={() => onOpen('targets')} />
          {incompleteEntries > 0 && <div className="notice"><Info /><span>Trend totals include known values only; {incompleteEntries} entr{incompleteEntries === 1 ? 'y is' : 'ies are'} incomplete in this range.</span></div>}
          <div className="trend-controls"><div className="driver-tabs">{nutrientLabels.map((label) => <button className={nutrient === label ? 'active' : ''} key={label} onClick={() => setNutrient(label)}>{label}</button>)}</div><label>Range<select value={range} onChange={(event) => setRange(Number(event.target.value))}><option value="7">7 days</option><option value="30">30 days</option><option value="90">90 days</option></select></label></div>
          <div className="bar-chart"><div className="target-line" style={{ bottom: `${target / chartMaximum * 100}%` }}><span>{target.toLocaleString()} {spec[nutrient].unit} target</span></div>{days.map((day, index) => <div className="chart-column" key={index}><i style={{ height: `${day.value / chartMaximum * 100}%`, background: spec[nutrient].color }} /><small>{index % Math.max(1, Math.floor(range / 6)) === 0 ? day.label : ''}</small></div>)}</div>
        </Card>
      ) : (
        <Card className="trend-card">
          <SectionTitle title="Food cost, day by day" subtitle="What you paid for the portions eaten" action="Edit budget" onAction={() => onOpen('targets')} />
          {missingCosts > 0 && <div className="notice"><Info /><span>{missingCosts} consumption entries have unknown paid amounts. Amounts below are known subtotals, not complete food costs.</span></div>}
          <div className="spend-figures">
            <div><span>Last 7 days</span><strong className="spend">{usd(lastSeven, estimatedCosts)}{lastSevenMissing ? ' + unknown' : ''}</strong></div>
            <div><span>Weekly budget</span><strong>{usd(weekly)}</strong></div>
            <div><span>{range}-day total</span><strong className="spend">{usd(spendTotal, estimatedCosts)}{missingCosts ? ' + unknown' : ''}</strong></div>
            <div><span>Per 1,000 cal</span><strong>{per1000Cal === null ? '—' : usd(per1000Cal, estimatedCosts)}</strong></div>
          </div>
          <div className="trend-controls">
            <div className="chart-legend"><span><i style={{ background: 'var(--spend)' }} />Paid cost of food eaten</span></div>
            <label>Range<select value={range} onChange={(event) => setRange(Number(event.target.value))}><option value="7">7 days</option><option value="30">30 days</option><option value="90">90 days</option></select></label>
          </div>
          <div className="bar-chart">
            <div className="target-line" style={{ bottom: `${dailyBudget / spendMaximum * 100}%` }}><span>{usd(dailyBudget)} a day</span></div>
            {spendDays.map((day, index) => (
              <div className="chart-column" key={index}>
                <i style={{ height: `${day.spend / spendMaximum * 100}%`, background: 'var(--spend)' }} />
                <small>{index % Math.max(1, Math.floor(range / 6)) === 0 ? day.label : ''}</small>
              </div>
            ))}
          </div>
        </Card>
      )}

      {view === 'spend' && (
        <Card>
          {wasteMissingCosts > 0 && <div className="notice"><Info /><span>{wasteMissingCosts} discarded items have unknown prices. Waste amounts and categories show known subtotals only.</span></div>}
          <SectionTitle title="Lost to waste" action="Food value, separate from paid cost" />
          <div className="stat-strip four">
            <div><span>{range} days</span><strong className="waste">{usd(wasteTotal)}{wasteMissingCosts ? ' + unknown' : ''}</strong></div>
            <div><span>Per week</span><strong className="waste">{usd(wasteTotal / (range / 7))}{wasteMissingCosts ? ' + unknown' : ''}</strong></div>
            <div><span>Days with waste</span><strong>{wasteDays} of {range}</strong></div>
            <div><span>Worst day</span><strong className="waste">{wasteMissingCosts ? 'Unknown' : usd(worstDay.waste)}</strong><small>{wasteMissingCosts ? 'Some prices missing' : `day ${worstDay.label}`}</small></div>
          </div>
          <div className="waste-causes">
            {wasteCauses.map((cause) => (
              <div className="driver" key={cause.label}>
                <div><span>{cause.label}<small className="cause-note"> · {cause.note}</small></span><small className="waste">{usd(cause.amount)}</small></div>
                <Progress value={cause.amount / causeMax * 100} color="var(--urgent)" />
              </div>
            ))}
          </div>
          {wasteTotal === 0 && wasteMissingCosts === 0 && <div className="empty-inline">Nothing discarded in the last {range} days.</div>}
        </Card>
      )}

      <div className="two-column">
        <Card>
          <SectionTitle title={view === 'spend' ? 'Averages' : 'Daily average vs target'} subtitle={view === 'spend' ? undefined : `Average per calendar day over ${range} days.`} />
          {view === 'spend' ? (
            <>
              <div className="gap-row"><span>Per day</span><strong className="spend">{usd(spendTotal / range, estimatedCosts)}{missingCosts ? ' + unknown' : ''}</strong></div>
              <div className="gap-row"><span>Per week</span><strong className="spend">{usd(spendTotal / (range / 7), estimatedCosts)}{missingCosts ? ' + unknown' : ''}</strong></div>
              <div className="gap-row"><span>Food from inventory</span><strong className="spend">{usd(Math.max(0, spendTotal - awayTotal), estimatedCosts)}{missingCosts || awayMissingCosts ? ' + unknown' : ''}</strong></div>
              <div className="gap-row"><span>Food away from home</span><strong className="spend">{usd(awayTotal, estimatedCosts)}{awayMissingCosts ? ' + unknown' : ''}</strong></div>
              <div className="gap-row"><span>Wasted</span><strong className="waste">{usd(wasteTotal)}{wasteMissingCosts ? ' + unknown' : ''}</strong></div>
            </>
          ) : averages.map((row) => <MacroRow key={row.label} label={row.label} value={`${Math.round(row.value).toLocaleString()} ${row.unit}`} target={`/ ${row.target.toLocaleString()} ${row.unit}`} pct={row.target ? row.value / row.target * 100 : 0} color={row.color} />)}
        </Card>
        <Card><SectionTitle title="What drives each nutrient" subtitle={`Share of logged nutrition over ${range} days; bars are relative to the top contributor.`} /><div className="driver-tabs">{nutrientLabels.map((label) => <button className={driverNutrient === label ? 'active' : ''} key={label} onClick={() => setDriverNutrient(label)}>{label}</button>)}</div>{drivers.map(({ label, pct }) => <div className="driver" key={label}><div><span>{label}</span><small>{pct}%</small></div><Progress value={pct / driverMax * 100} /></div>)}{!drivers.length && <div className="empty-inline">No {driverNutrient.toLowerCase()} has been logged in this period.</div>}</Card>
      </div>
    </div>
  );
}

const COMPARE_ROWS: Array<{ label: string; higherIsBetter: boolean; read: (product: ProductView) => number | null; format: (value: number | null) => string }> = [
  { label: 'Est. package cost', higherIsBetter: false, read: (product) => product.estimatedCost, format: (value) => value === null ? '—' : `$${value.toFixed(2)}` },
  { label: 'Calories / serving', higherIsBetter: false, read: (product) => product.nutritionPerServing.Calories, format: (value) => value === null ? '—' : `${Math.round(value).toLocaleString()} cal` },
  { label: 'Protein / serving', higherIsBetter: true, read: (product) => product.nutritionPerServing.Protein, format: (value) => value === null ? '—' : `${Math.round(value)} g` },
  { label: 'Carbs / serving', higherIsBetter: false, read: (product) => product.nutritionPerServing.Carbs, format: (value) => value === null ? '—' : `${Math.round(value)} g` },
  { label: 'Fat / serving', higherIsBetter: false, read: (product) => product.nutritionPerServing.Fat, format: (value) => value === null ? '—' : `${Math.round(value)} g` },
  { label: 'Fiber / serving', higherIsBetter: true, read: (product) => product.nutritionPerServing.Fiber, format: (value) => value === null ? '—' : `${Math.round(value)} g` },
  { label: 'Sodium / serving', higherIsBetter: false, read: (product) => product.nutritionPerServing.Sodium, format: (value) => value === null ? '—' : `${Math.round(value).toLocaleString()} mg` },
];

const costPer100Cal = (cost: number | null, calories: number) =>
  cost === null || !calories ? '—' : `$${(cost / calories * 100).toFixed(2)}`;

function ProductsPage({ onOpen, notify }: { onOpen: (kind: PanelKind, recipe?: Recipe, values?: Record<string, string>) => void; notify: Notify }) {
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
  const sorted = [...visible].sort((left, right) =>
    sort === 'name'
      ? (left.brand || 'Unbranded').localeCompare(right.brand || 'Unbranded') || left.name.localeCompare(right.name)
      : sort === 'used'
        ? right.servingsConsumed - left.servingsConsumed
        : (Date.parse(right.lastUsedAt) || 0) - (Date.parse(left.lastUsedAt) || 0)
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
        <select aria-label="Sort products" value={sort} onChange={(event) => setSort(event.target.value as typeof sort)}><option value="used">Most consumed</option><option value="recent">Recently consumed</option><option value="name">Brand A–Z</option></select>
        <button className="button secondary" onClick={() => onOpen('scan')}><ScanLine />Scan</button>
      </div>
      {compared.length > 0 && (
        <Card className="comparison-card">
          <SectionTitle title={`Compare ${compared[0].foodName}`} action="Clear" onAction={() => setComparison([])} />
          <div className="comparison-grid">
            <span /><strong>{compared[0]?.label}</strong><strong>{compared[1]?.label ?? 'Select one more'}</strong>
            {COMPARE_ROWS.map((row) => {
              const values = compared.map((product) => row.read(product));
              // "Better" is row-specific: cheaper, more protein, less sodium.
              const best = values.length === 2 && values[0] !== null && values[1] !== null && values[0] !== values[1]
                ? (row.higherIsBetter ? (Number(values[0]) > Number(values[1]) ? 0 : 1) : (Number(values[0]) < Number(values[1]) ? 0 : 1))
                : -1;
              return [
                <span key={`${row.label}-label`}>{row.label}</span>,
                ...compared.map((product, index) => <em className={cx(index === best && 'better')} key={`${row.label}-${product.id}`}>{row.format(values[index])}</em>),
                ...(compared.length === 1 ? [<em key={`${row.label}-empty`}>—</em>] : []),
              ];
            })}
          </div>
        </Card>
      )}
      <Card>
        <SectionTitle title="Products" action={`${visible.length} product${visible.length === 1 ? '' : 's'}`} />
        <div className="product-table">
          <div className="product-table-head">
            <span className="product-cell-name">Product</span>
            <span>Package</span><span>Cal / serving</span><span>Protein</span><span>Sodium</span><span>Consumed</span>
            <span className="product-cell-actions" />
          </div>
          {sorted.map((product) => (
            <div className={cx('product-row', comparison.includes(product.id) && 'comparing')} key={product.id}>
              <div className="product-cell-name">
                <span className="row-emoji">{product.emoji}</span>
                <div className="grow"><strong>{product.name}</strong><small>{[product.brand || 'Unbranded', product.foodName, product.barcode || 'no barcode'].join(' · ')}</small></div>
              </div>
              <span className="spend">{product.estimatedCost === null ? '—' : `$${product.estimatedCost.toFixed(2)}`}</span>
              <span>{Math.round(product.nutritionPerServing.Calories).toLocaleString()}</span>
              <span>{Math.round(product.nutritionPerServing.Protein)} g</span>
              <span>{Math.round(product.nutritionPerServing.Sodium).toLocaleString()}</span>
              <span>{formatAmount(product.servingsConsumed)}</span>
              <div className="product-cell-actions">
                <button className={cx('button secondary compact', comparison.includes(product.id) && 'selected')} onClick={() => toggleCompare(product.id)}>{comparison.includes(product.id) ? 'Selected' : 'Compare'}</button>
                <button className="button secondary compact" onClick={() => setViewing(product)}>Open</button>
                <button className="button compact" onClick={() => onOpen('log', undefined, { product: product.id })}>Consume</button>
              </div>
            </div>
          ))}
          {!sorted.length && <div className="empty-inline">No products match that search.</div>}
        </div>
      </Card>
      {viewing && (
        <div className="panel-layer">
          <button className="panel-scrim" aria-label="Close product details" onClick={() => setViewing(null)} />
          <aside className="action-panel product-detail" role="dialog" aria-modal="true">
            <PanelHeader title={`${viewing.emoji} ${viewing.label}`} subtitle={viewing.barcode ? `Barcode ${viewing.barcode}` : 'No barcode saved'} onClose={() => setViewing(null)} />
            <div className="panel-body">
              <div className="product-headline-stats">
                <div><span>Estimated cost</span><strong className="spend">{viewing.estimatedCost === null ? 'Not estimated' : `$${viewing.estimatedCost.toFixed(2)}`}</strong>{viewing.costSource && <small>{viewing.costSource}{viewing.costAsOf ? ` · as of ${new Date(`${viewing.costAsOf}T00:00:00`).toLocaleDateString()}` : ''}</small>}</div>
                <div><span>Servings consumed</span><strong>{formatAmount(viewing.servingsConsumed)}</strong>{viewing.lastUsedAt && <small>last {new Date(viewing.lastUsedAt).toLocaleDateString()}</small>}</div>
                <div><span>Cost per 100 cal</span><strong className="spend">{costPer100Cal(viewing.costPerServing, viewing.nutritionPerServing.Calories)}</strong><small>{viewing.servingLabel}</small></div>
              </div>
              <PanelSection title={`Per serving · ${viewing.servingLabel}`}><div className="nutrition-detail">{Object.entries(viewing.nutritionPerServing).map(([label, value]) => <div key={label}><span>{label}</span><strong>{formatNutritionAmount(value, label)} {label === 'Calories' ? 'cal' : label === 'Sodium' ? 'mg' : 'g'}</strong></div>)}</div></PanelSection>
            </div>
          </aside>
        </div>
      )}
    </div>
  );
}

const PANEL_COPY: Record<Exclude<PanelKind, 'recipe-detail' | 'cook' | 'combined-meal' | 'inventory-detail' | 'consumption-detail'>, { title: string; subtitle?: string; save: string; destructive?: string }> = {
  lot: { title: 'Add a lot', save: 'Save lot' },
  groceries: { title: 'Add several items', save: 'Add items' },
  product: { title: 'Add a product', save: 'Save product' },
  recipe: { title: 'New recipe', save: 'Save recipe' },
  'recipe-edit': { title: 'Edit recipe', save: 'Save changes' },
  log: { title: 'Consume a product', save: 'Acquire & consume' },
  'manual-log': { title: 'Log a meal or snack', save: 'Log food' },
  item: { title: 'Add an item', save: 'Add item' },
  meal: { title: 'Add to day', save: 'Add to day' },
  targets: { title: 'Targets & budget', save: 'Save targets' },
  export: { title: 'Export range', save: 'Download CSV' },
  scan: { title: 'Look up a barcode', save: 'Look up' },
  'bulk-import': { title: 'Bulk inventory scan', save: 'Add inventory' },
  profile: { title: 'Routine & food profile', save: 'Save profile' },
  calendar: { title: 'Mise Planner', subtitle: 'Schedule-aware grocery and preparation reminders.', save: 'Sync now' },
};


function ActionPanel({ onStageRecipes, onStartCooking, state, onClose, notify, onSave, onCookRecipe, onSavePrepFeedback, onCookRecipes, onRecipeProgress, onConsumeInventoryLot, onSetInventoryLotQuantity, undo }: { onStageRecipes: (dishes: StagedDish[]) => void; onStartCooking: (recipe: Recipe) => void; state: PanelState; onClose: () => void; notify: Notify; onSave?: (kind: PanelKind, form: FormData) => Promise<string>; onCookRecipe?: (id: string, options?: PreparationOptions) => Promise<PreparationResult>; onSavePrepFeedback?: (prepId: string, ease: number, taste: number, minutes: number) => Promise<void>; onCookRecipes?: (ids: string[]) => Promise<void>; onRecipeProgress: (id: string, active: boolean) => void; onConsumeInventoryLot?: (id: string, quantity: number) => Promise<string | null>; onSetInventoryLotQuantity?: (id: string, remaining: number, discard: boolean, reason?: string) => Promise<string | null>; undo: Reversals }) {
  const { foodLog, grocerySections, history, nutrients, recipes, settings } = usePantryData();
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [formValid, setFormValid] = useState(state.kind !== 'meal');
  const [formAttempt] = useState(createFormAttempt);
  if (state.kind === 'cook') return <RecipePanel onStartCooking={onStartCooking} recipe={state.recipe ?? recipes[0]} cooking onClose={onClose} notify={notify} onCook={onCookRecipe} onFeedback={onSavePrepFeedback} onProgressChange={onRecipeProgress} undo={undo} />;
  if (state.kind === 'recipe-detail') return <RecipePanel onStartCooking={onStartCooking} recipe={state.recipe ?? recipes[0]} cooking={false} onClose={onClose} notify={notify} onCook={onCookRecipe} onFeedback={onSavePrepFeedback} onProgressChange={onRecipeProgress} undo={undo} />;
  if (state.kind === 'combined-meal') return <CombinedMealPanel onClose={onClose} onStage={onStageRecipes} onSave={onSave} notify={notify} />;
  if (state.kind === 'inventory-detail') return state.inventoryFood ? <InventoryLotsPanel food={state.inventoryFood} onClose={onClose} notify={notify} onConsume={onConsumeInventoryLot} onSetQuantity={onSetInventoryLotQuantity} undo={undo} /> : null;
  if (state.kind === 'consumption-detail') return state.consumptionEvent ? <ConsumptionDetailPanel entry={state.consumptionEvent} onClose={onClose} undo={undo} notify={notify} /> : null;
  if (state.kind === 'bulk-import') return <BulkInventoryPanel onClose={onClose} notify={notify} onSave={onSave} />;
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
      const form = new FormData(event.currentTarget);
      form.set('owner_time_zone', settings.timeZone);
      form.set('action_kind', state.kind);
      const attempt = ['manual-log', 'log', 'lot', 'recipe', 'meal'].includes(state.kind) ? await formAttempt(form) : form;
      const message = await onSave(state.kind, attempt);
      if (attempt.has('request_id')) completeFormAttempt(attempt);
      onClose();
      notify(message);
    } catch (cause) {
      setError(mutationError(cause));
    } finally {
      setSaving(false);
    }
  }
  const context = panelContext(state, { nutrients, foodLog, grocerySections, settings });
  return (
    <div className="panel-layer">
      <button className="panel-scrim" aria-label="Close panel" onClick={onClose} />
      <aside className={cx('action-panel', state.kind === 'meal' && 'plan-panel')} role="dialog" aria-modal="true" aria-labelledby="panel-title">
        <PanelHeader title={copy.title} subtitle={copy.subtitle} onClose={onClose} />
        <form id="panel-action-form" onSubmit={(event) => void submit(event)}>
          <div className="panel-body">
            {context ? <PanelContext>{context}</PanelContext> : null}
            <PanelFields kind={state.kind} values={state.values} recipe={state.recipe} onValidityChange={state.kind === 'meal' ? setFormValid : undefined} />
            {error && <div className="auth-error" role="alert">{error}</div>}
          </div>
        </form>
        <div className="panel-footer">
          {copy.destructive ? <button className="button danger" type="button" onClick={onClose}><Trash2 />{copy.destructive}</button> : null}
          <span className="panel-footer-spacer" />
          <button className="button primary" type="submit" form="panel-action-form" disabled={saving || !formValid}>{saving ? 'Saving…' : copy.save}</button>
        </div>
      </aside>
    </div>
  );
}

// Every string here is a number the user can check against a screen, never a hint.
function panelContext(state: PanelState, data: Pick<PantryData, 'nutrients' | 'foodLog' | 'grocerySections' | 'settings'>): string | null {
  const { nutrients, foodLog, grocerySections, settings } = data;
  const weekly = settings.weeklyFoodBudget;
  const daily = dailyFoodBudget(weekly);
  const sumCosts = (costs: Array<number | null | undefined>) => costs.reduce((total: number, value) => total + (value ?? 0), 0);

  if (state.kind === 'log' || state.kind === 'manual-log') {
    const calories = nutrients.find((row) => row.label === 'Calories');
    return `Today so far: ${calories?.value ?? '0'} cal · ${usd(sumCosts(foodLog.map((entry) => entry.cost)))} of ${usd(daily)}.`;
  }
  if (state.kind === 'item') {
    return `List total so far: ${usd(sumCosts(grocerySections.flatMap((section) => section.items.map((item) => item.cost))))} of ${usd(weekly)} for the week.`;
  }
  if (state.kind === 'meal') return null;
  if (state.kind === 'targets') {
    return `One food budget: ${usd(weekly)} a week works out to ${usd(daily)} a day.`;
  }
  if (state.kind === 'recipe-edit' && state.recipe) {
    const recipe = state.recipe;
    const perServing = perServingCost(recipe.estimatedCost, recipe.servings);
    const made = recipe.prepCount ?? 0;
    return `${recipe.emoji} ${recipe.name} · made ${made} time${made === 1 ? '' : 's'} · ${usd(recipe.estimatedCost, recipe.costIsEstimated)} a batch, ${usd(perServing, recipe.costIsEstimated)} a serving`;
  }
  return null;
}

function PanelHeader({ title, subtitle, onClose }: { title: string; subtitle?: string; onClose: () => void }) {
  return <div className="panel-header"><div className="grow"><h2 id="panel-title">{title}</h2>{subtitle ? <p>{subtitle}</p> : null}</div><button className="icon-button" type="button" onClick={onClose} aria-label="Close"><X /></button></div>;
}

// Live numbers, never instructions.
function PanelContext({ children }: { children: React.ReactNode }) {
  return <div className="panel-context"><Info aria-hidden /><span>{children}</span></div>;
}

function PanelSection({ title, children }: { title: string; children: React.ReactNode }) {
  return <section className="panel-section">{title ? <div className="panel-section-head"><span>{title}</span><i /></div> : null}{children}</section>;
}

function PanelFields({ kind, values = {}, recipe, onValidityChange }: { kind: Exclude<PanelKind, 'recipe-detail' | 'cook' | 'combined-meal' | 'inventory-detail' | 'consumption-detail'>; values?: Record<string, string>; recipe?: Recipe; onValidityChange?: (valid: boolean) => void }) {
  const { categories, locations, products, recipes, settings, units } = usePantryData();
  const today = new Date().toLocaleDateString('en-CA');
  const defaultUnit = units.find((unit) => unit.shortName === 'ct')?.id ?? units[0]?.id ?? '';

  if (kind === 'scan') return <BarcodeScanner />;

  if (kind === 'targets') return <div className="form-grid">
    <PanelSection title="Energy"><div className="form-grid"><Field name="nutrition_calories" label="Calories (kcal)" type="number" defaultValue={String(settings.calories)} required /></div></PanelSection>
    <PanelSection title="Macros"><div className="form-grid two">
      <Field name="nutrition_protein_g" label="Protein (g)" type="number" defaultValue={String(settings.proteinG)} required />
      <Field name="nutrition_carbs_g" label="Carbs (g)" type="number" defaultValue={String(settings.carbsG)} required />
      <Field name="nutrition_fat_g" label="Fat (g)" type="number" defaultValue={String(settings.fatG)} required />
      <Field name="nutrition_fiber_g" label="Fiber (g)" type="number" defaultValue={String(settings.fiberG)} required />
    </div></PanelSection>
    <PanelSection title="Limits"><div className="form-grid"><Field name="nutrition_sodium_mg" label="Sodium limit (mg)" type="number" defaultValue={String(settings.sodiumMg)} required /></div></PanelSection>
    <PanelSection title="Food budget"><WeeklyBudgetFields weeklyFoodBudget={settings.weeklyFoodBudget} /></PanelSection>
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

  if (kind === 'meal') return <DayPlanFields values={values} onValidityChange={onValidityChange} />;

  if (kind === 'recipe' || kind === 'recipe-edit') return <div className="form-grid">
    {recipe && <input type="hidden" name="recipe_id" value={recipe.id} />}
    <div className="form-grid two"><Field name="name" label="Recipe name" defaultValue={recipe?.name} placeholder="Recipe name" required /><Field name="emoji" label="Emoji" defaultValue={recipe?.emoji} placeholder="🍳" /></div>
    <div className="form-grid two"><Field name="servings" label="Servings" type="number" defaultValue={String(recipe?.servings ?? 4)} min="0.25" step="0.25" required /><Field name="source_url" label="Source URL" type="url" defaultValue={recipe?.sourceUrl} placeholder="https://…" /></div>
    <>{recipe ? <RecipeIngredientEditor key={recipe.id} recipe={recipe} /> : <label className="field"><span>Ingredients</span><textarea name="ingredients" required rows={7} placeholder={'1.5 cup All-purpose flour\n2 ct Egg'} /></label>}</>
    <small>Use: quantity, unit abbreviation, then the exact tracked food name.</small>
    <label className="field"><span>Method</span><textarea name="instructions" rows={7} defaultValue={recipe?.instructionText} placeholder="One step per line" /></label>
    <label className="toggle-row"><input name="prompt_for_feedback" type="checkbox" defaultChecked={recipe?.promptForFeedback ?? true} /><span><strong>Ask how it went after making</strong></span></label>
  </div>;

  if (kind === 'lot') return <div className="form-grid">
    <SelectField name="product" label="Product" defaultValue={values.product} options={products.map((product) => ({ value: product.id, label: product.label }))} required />
    <div className="form-grid two"><Field name="initial_qty" label="Stock quantity" type="number" min="0.001" step="any" required /><Field name="quantity_unit" label="Quantity unit" defaultValue="ct" placeholder="ct, oz, g, fl oz…" required /></div>
    <div className="form-grid two"><Field name="acquired_at" label="Acquired at" type="datetime-local" /><SelectField name="time_precision" label="Time precision" defaultValue="exact" options={[{ value: 'exact', label: 'Exact' }, { value: 'estimated', label: 'Estimated' }, { value: 'dateOnly', label: 'Date only' }]} required /></div>
    <div className="form-grid two"><SelectField name="location" label="Location" options={locations.map((location) => ({ value: location, label: location }))} /><Field name="use_by" label="Best by" type="date" /></div>
    <div className="form-grid two"><Field name="total_cost" label="Full price (USD)" type="number" min="0" step="0.01" required /><Field name="out_of_pocket_cost" label="You paid (USD)" type="number" min="0" step="0.01" required /></div>
    <div className="form-grid two"><Field name="paid_by" label="Paid by" defaultValue="self" required /><Field name="price_as_of" label="Price as of" type="date" defaultValue={today} required /></div>
    <Field name="cost_source" label="Price source" placeholder="Receipt, store listing, estimate…" required />
    <Field name="note" label="Note" placeholder="Optional lot note" />
    <label className="toggle-row"><input name="cost_is_estimated" type="checkbox" /><span><strong>Cost is estimated</strong></span></label>
  </div>;

  if (kind === 'item') return <div className="form-grid"><Field name="name" label="Item" placeholder="Grocery item" required /><Field name="quantity_label" label="Quantity" placeholder="2 bags" /><Field name="note" label="Note" placeholder="Optional" /></div>;

  if (kind === 'log') return <div className="form-grid">
    <SelectField name="product" label="Product" defaultValue={values.product} options={products.map((product) => ({ value: product.id, label: product.label }))} required />
    <div className="form-grid two"><Field name="purchased_quantity" label="Quantity purchased" type="number" defaultValue="1" min="0.001" step="any" required /><Field name="consumed_quantity" label="Quantity consumed now" type="number" defaultValue="1" min="0" step="any" required /></div>
    <Field name="quantity_unit" label="Shared quantity unit" defaultValue="ct" placeholder="ct, oz, g, fl oz…" required />
    <div className="form-grid two"><SelectField name="acquisition_type" label="Acquisition type" defaultValue="grocery" options={['grocery', 'restaurant', 'takeout', 'office', 'gift', 'home', 'other'].map((value) => ({ value, label: value }))} required /><SelectField name="location" label="Remaining item location" options={locations.map((location) => ({ value: location, label: location }))} /></div>
    <div className="form-grid two"><Field name="occurred_at" label="Time" type="datetime-local" /><SelectField name="time_precision" label="Time precision" defaultValue="exact" options={[{ value: 'exact', label: 'Exact' }, { value: 'estimated', label: 'Estimated' }, { value: 'dateOnly', label: 'Date only' }]} required /></div>
    <div className="form-grid two"><Field name="total_cost" label="Full price (USD)" type="number" min="0" step="0.01" required /><Field name="out_of_pocket_cost" label="You paid (USD)" type="number" min="0" step="0.01" required /></div>
    <div className="form-grid two"><Field name="paid_by" label="Paid by" defaultValue="self" required /><Field name="price_as_of" label="Price as of" type="date" defaultValue={today} required /></div>
    <Field name="cost_source" label="Cost source" placeholder="Receipt, menu, estimate…" required />
    <Field name="label" label="Log label override" placeholder="Optional; defaults to brand and product" />
    <Field name="note" label="Note" placeholder="Optional" />
    <label className="toggle-row"><input name="cost_is_estimated" type="checkbox" /><span><strong>Cost is estimated</strong></span></label>
  </div>;

  if (kind === 'manual-log') return <div className="form-grid">
    <PanelSection title="What you ate"><div className="form-grid">
      <Field name="label" label="Meal or food" placeholder="Spaghetti at Mom's" required />
      <div className="form-grid two"><Field name="portion_label" label="Portion" placeholder="1 large plate" /><Field name="occurred_at" label="Time" type="datetime-local" /></div>
      <SelectField name="time_precision" label="Time precision" defaultValue="exact" options={[{ value: 'exact', label: 'Exact' }, { value: 'estimated', label: 'Estimated' }, { value: 'dateOnly', label: 'Date only' }]} required />
      <label className="field"><span>Components (one per line)</span><textarea name="components" rows={4} placeholder={'Spaghetti\n3 beef meatballs\nTomato sauce'} /></label>
    </div></PanelSection>
    <PanelSection title="Nutrition (optional)"><div className="form-grid">
      <div className="form-grid two"><Field name="kcal" label="Calories" type="number" min="0" step="any" /><Field name="protein_g" label="Protein (g)" type="number" min="0" step="any" /></div>
      <div className="form-grid two"><Field name="carbs_g" label="Carbs (g)" type="number" min="0" step="any" /><Field name="fat_g" label="Fat (g)" type="number" min="0" step="any" /></div>
      <div className="form-grid two"><Field name="fiber_g" label="Fiber (g)" type="number" min="0" step="any" /><Field name="sugar_g" label="Sugar (g)" type="number" min="0" step="any" /></div>
      <Field name="sodium_mg" label="Sodium (mg)" type="number" min="0" step="any" />
      <Field name="nutrition_source" label="Nutrition source" placeholder="Rough portion estimate, recipe from Mom…" />
      <div className="form-grid two"><SelectField name="nutrition_confidence" label="Estimate confidence" defaultValue="medium" options={[{ value: 'low', label: 'Low' }, { value: 'medium', label: 'Medium' }, { value: 'high', label: 'High' }]} /><Field name="nutrition_rationale" label="Estimate rationale" placeholder="Label math, visual estimate…" /></div>
      <label className="toggle-row"><input name="nutrition_is_estimated" type="checkbox" /><span><strong>Nutrition is estimated</strong><small>Blank = unknown</small></span></label>
    </div></PanelSection>
    <PanelSection title="Acquisition and cost"><div className="form-grid">
      <SelectField name="acquisition_type" label="Acquisition type" defaultValue="home" options={['grocery', 'restaurant', 'takeout', 'office', 'gift', 'home', 'other'].map((value) => ({ value, label: value }))} required />
      <div className="form-grid two"><Field name="total_price" label="Full price/value (USD)" type="number" min="0" step="0.01" /><Field name="out_of_pocket_cost" label="You paid (USD)" type="number" min="0" step="0.01" placeholder="0 if free to you" required /></div>
      <div className="form-grid two"><Field name="paid_by" label="Paid by" defaultValue="self" required /><Field name="price_as_of" label="Price as of" type="date" defaultValue={today} /></div>
      <Field name="cost_source" label="Cost source" defaultValue="User-entered in app; full value may be unknown" placeholder="Receipt, menu, retailer estimate, free meal…" required />
      <label className="toggle-row"><input name="cost_is_estimated" type="checkbox" /><span><strong>Cost is estimated</strong></span></label>
    </div></PanelSection>
    <Field name="note" label="Note" placeholder="Optional context" />
  </div>;

  if (kind === 'product') return <div className="form-grid">
    <div className="notice"><Info /><span>Use the selected stock unit for package, serving, and nutrition quantities. For a 2 lb package with a 4 oz serving, choose ounces and enter 32, 4, and 4 if the nutrition label is per serving. Prices are per whole package; leave unknown prices blank.</span></div>
    <div className="form-grid two"><Field name="name" label="Food and product name" placeholder="Name" required /><Field name="brand" label="Brand" placeholder="Optional" /></div>
    <div className="form-grid two"><Field name="emoji" label="Emoji" placeholder="🍽️" /><Field name="barcode" label="Barcode" placeholder="Optional UPC/EAN" /></div>
    <div className="form-grid two"><SelectField name="measure_style" label="Stock style" options={['discrete', 'weight', 'volume'].map((value) => ({ value, label: value }))} required /><SelectField name="unit" label="Stock unit" defaultValue={defaultUnit} options={units.map((unit) => ({ value: unit.id, label: unit.label }))} required /></div>
    <div className="form-grid two"><Field name="package_qty_base" label="Quantity in one package (stock unit)" type="number" defaultValue="1" min="0.001" step="any" required /><Field name="serving_qty_base" label="Quantity in one serving (stock unit)" type="number" defaultValue="1" min="0.001" step="any" /></div>
    <SelectField name="grocery_category" label="Grocery category" options={categories.map((category) => ({ value: category, label: category }))} />
    <Field name="ingredient_role" label="Ingredient role" placeholder="Main, supporting, staple…" />
    <label className="toggle-row"><input name="always_available" type="checkbox" /><span><strong>Always available</strong><small>No stock tracking</small></span></label>
    <Field name="nutrition_basis_qty" label="Nutrition values below are per (stock unit)" type="number" defaultValue="100" min="0.001" step="any" required />
    <div className="form-grid two"><Field name="kcal" label="Calories" type="number" min="0" defaultValue="0" /><Field name="protein_g" label="Protein (g)" type="number" min="0" defaultValue="0" /></div>
    <div className="form-grid two"><Field name="carbs_g" label="Carbs (g)" type="number" min="0" defaultValue="0" /><Field name="fat_g" label="Fat (g)" type="number" min="0" defaultValue="0" /></div>
    <div className="form-grid two"><Field name="fiber_g" label="Fiber (g)" type="number" min="0" defaultValue="0" /><Field name="sodium_mg" label="Sodium (mg)" type="number" min="0" defaultValue="0" /></div>
    <div className="form-grid two"><Field name="estimated_cost" label="Estimated package cost" type="number" min="0" step="0.01" /><Field name="cost_source" label="Cost source" placeholder="Store, menu, receipt…" /></div>
    <Field name="cost_as_of" label="Cost as of" type="date" />
    <label className="toggle-row"><input name="nutrition_is_estimated" type="checkbox" /><span><strong>Nutrition is estimated</strong></span></label>
  </div>;

  return <div className="notice"><ClipboardList /><span>This action is not available yet.</span></div>;
}

function WeeklyBudgetFields({ weeklyFoodBudget }: { weeklyFoodBudget: number }) {
  const [weekly, setWeekly] = useState(String(weeklyFoodBudget));
  const parsed = Number(weekly);
  const daily = Number.isFinite(parsed) && parsed > 0 ? usd(dailyFoodBudget(parsed)) : '—';
  return <div className="form-grid two">
    <label className="field"><span>Weekly food budget (USD)</span><input name="weekly_food_budget" type="number" min="0.01" step="0.01" required value={weekly} onChange={(event) => setWeekly(event.target.value)} /></label>
    <label className="field"><span>Works out to (per day)</span><input type="text" value={daily} readOnly tabIndex={-1} /></label>
  </div>;
}

function Field({ name, label, placeholder, defaultValue, type = 'text', min, step, required }: { name: string; label: string; placeholder?: string; defaultValue?: string; type?: string; min?: string; step?: string; required?: boolean }) {
  return <label className="field"><span>{label}</span><input name={name} type={type} min={min} step={step} required={required} placeholder={placeholder} defaultValue={defaultValue} /></label>;
}

function SelectField({ name, label, options, defaultValue, required }: { name: string; label: string; options: Array<{ value: string; label: string }>; defaultValue?: string; required?: boolean }) {
  return <label className="field"><span>{label}</span><select name={name} defaultValue={defaultValue} required={required}><option value="">Choose…</option>{options.map((option) => <option value={option.value} key={option.value}>{option.label}</option>)}</select></label>;
}

function ConsumptionDetailPanel({ entry, onClose, undo, notify }: { entry: FoodLogEntry; onClose: () => void; undo: Reversals; notify: Notify }) {
  const [editingId, setEditingId] = useState('');
  const [busyId, setBusyId] = useState('');
  const [removed, setRemoved] = useState<string[]>([]);
  const [error, setError] = useState('');
  async function removeEvent(id: string) {
    if (!undo.voidFoodLog || busyId) return;
    setBusyId(id); setError('');
    try {
      await undo.voidFoodLog(id);
      setRemoved((current) => [...current, id]);
      notify('One consumption event removed. Inventory was restored where applicable.', undo.restoreFoodLog ? async () => { await undo.restoreFoodLog!(id); setRemoved((current) => current.filter((value) => value !== id)); } : undefined);
    } catch (cause) { setError(mutationError(cause, 'Could not remove this consumption event.')); }
    finally { setBusyId(''); }
  }
  const nutrition = entry.nutrition ? Object.entries(entry.nutrition) : [];
  const eventIds = entry.eventIds?.length ? entry.eventIds : entry.id ? [entry.id] : [];
  return <div className="panel-layer"><button className="panel-scrim" onClick={onClose} aria-label="Close consumption event" /><aside className="action-panel consumption-detail-panel" role="dialog" aria-modal="true"><PanelHeader title={`${entry.emoji} ${entry.label}`} subtitle={eventIds.length > 1 ? `${eventIds.length} consumption events` : 'Consumption event'} onClose={onClose} /><div className="panel-body"><div className="consumption-summary"><div><span>Portion</span><strong>{entry.serving}</strong></div><div><span>Logged</span><strong>{entry.time}</strong></div><div><span>Food cost · you paid</span><strong className="spend">{costLabel(entry.cost, entry.costIsEstimated)}</strong></div>{entry.foodValue !== undefined && <div><span>Full food value</span><strong>{costLabel(entry.foodValue, entry.foodValueIsEstimated)}</strong></div>}</div><PanelSection title="Nutrition"><div className="consumption-nutrition">{nutrition.length ? nutrition.map(([label, value]) => <div key={label}><span>{label}</span><strong>{value === null ? 'Unknown' : `${Math.round(value).toLocaleString()}${label === 'Calories' ? ' cal' : label === 'Sodium' ? ' mg' : ' g'}`}</strong></div>) : <div className="empty-inline">Detailed nutrition was not recorded for this event.</div>}</div></PanelSection>{error && <div role="alert">{error}</div>}<PanelSection title="Individual events">{eventIds.map((eventId, index) => { const detail = entry.events?.find((event) => event.id === eventId); return <div className="event-reference" key={eventId}><span>{detail ? `${detail.portion} · ${detail.time} · ${costLabel(detail.cost, detail.costIsEstimated)}` : `Consumption ${index + 1}`}</span>{!removed.includes(eventId) && detail?.quantityCorrection && undo.correctQuantity && (editingId === eventId ? <QuantityCorrectionEditor id={eventId} label={detail.label} snapshot={detail.quantityCorrection} save={async (id, expected, quantity) => { const replacement = await undo.correctQuantity!(id, expected, quantity); notify('Quantity corrected.'); onClose(); return replacement; }} close={() => setEditingId('')} /> : <button type="button" className="button" disabled={Boolean(busyId)} onClick={() => setEditingId(eventId)} aria-label={`Correct quantity for consumption ${index + 1}`}>Correct quantity</button>)}{detail?.quantityCorrectionUnavailable && <p>{detail.quantityCorrectionUnavailable}</p>}{!removed.includes(eventId) && detail?.manual && undo.updateFoodLog && (editingId === eventId ? <ManualConsumptionEditor id={eventId} original={detail.manual} save={async (id, patch) => { await undo.updateFoodLog!(id, patch); notify('Consumption corrected.'); onClose(); }} close={() => setEditingId('')} /> : <button type="button" className="button" disabled={Boolean(busyId)} onClick={() => setEditingId(eventId)} aria-label={`Edit consumption ${index + 1}`}>Edit this event</button>)}{removed.includes(eventId) ? <span>Removed</span> : undo.voidFoodLog && <button type="button" className="button" disabled={Boolean(busyId) || Boolean(editingId)} onClick={() => void removeEvent(eventId)} aria-label={`Remove consumption ${index + 1}`}>{busyId === eventId ? 'Removing…' : 'Remove this event'}</button>}</div>; })}</PanelSection></div></aside></div>;
}

type RecipePanelProps = { onStartCooking?: (recipe: Recipe) => void; recipe: Recipe; cooking: boolean; onClose: () => void; notify: Notify; onCook?: (id: string, options?: PreparationOptions) => Promise<PreparationResult>; onFeedback?: (prepId: string, ease: number, taste: number, minutes: number) => Promise<void>; onProgressChange: (id: string, active: boolean) => void; undo: Reversals };

function scaledIngredient(item: Recipe['ingredients'][number], scale: number) {
  if (item.pieceBasis) return `${formatAmount(item.pieceBasis.count * scale)} ${item.pieceBasis.label} (~${formatAmount(item.pieceBasis.grams * scale)} g estimated)`;
  if (scale === 1) return item.label;
  if (item.quantity !== undefined && item.name) return `${formatAmount(item.quantity * scale)}${item.unit ? ` ${item.unit}` : ''} ${item.name}`;
  return `${formatAmount(scale)} × (${item.label})`;
}

function scaledIngredientStock(item: Recipe['ingredients'][number], scale: number) {
  if (item.availableQuantity === undefined || item.quantity === undefined) return item.stock;
  return `${formatAmount(item.availableQuantity)}${item.unit ? ` ${item.unit}` : ''} in stock${item.availableQuantity + 0.0000001 < item.quantity * scale ? ' · short' : ''}`;
}

type DeckEntry = { id: string; recipe: Recipe; plan?: PlannedMealView; draft?: CookingDraft };

type DeckLayout = 'stack' | 'split' | 'three' | 'quad';

function OnDeckPage({ onShowAll, entries, locations, onAddRecipe, onRemoveRecipe, notify, onCook, onProgressChange, undo }: { onShowAll?: () => void; entries: DeckEntry[]; locations: string[]; onAddRecipe: () => void; onRemoveRecipe: (id: string) => void; notify: Notify; onCook?: (id: string, options?: PreparationOptions) => Promise<PreparationResult>; onProgressChange: (id: string, active: boolean) => void; undo: Reversals }) {
  const [layout, setLayout] = useState<DeckLayout>(() => (localStorage.getItem('mise.on-deck-layout') as DeckLayout | null) ?? 'split');
  const [order, setOrder] = useState<string[]>(() => { try { return JSON.parse(localStorage.getItem('mise.on-deck-order') ?? '[]') as string[]; } catch { return []; } });
  const [draggingId, setDraggingId] = useState('');
  useEffect(() => {
    const ids = entries.map((entry) => entry.id);
    setOrder((current) => {
      const next = [...current.filter((id) => ids.includes(id)), ...ids.filter((id) => !current.includes(id))];
      return next.join('|') === current.join('|') ? current : next;
    });
  }, [entries]);
  useEffect(() => { localStorage.setItem('mise.on-deck-layout', layout); }, [layout]);
  useEffect(() => { localStorage.setItem('mise.on-deck-order', JSON.stringify(order)); }, [order]);
  const orderedRecipes = order.map((id) => entries.find((entry) => entry.id === id)).filter((entry): entry is DeckEntry => Boolean(entry));
  const moveRecipe = (id: string, targetId: string) => setOrder((current) => {
    if (id === targetId) return current;
    const next = current.filter((candidate) => candidate !== id);
    const targetIndex = next.indexOf(targetId);
    next.splice(targetIndex < 0 ? next.length : targetIndex, 0, id);
    return next;
  });
  const nudgeRecipe = (id: string, delta: number) => setOrder((current) => {
    const from = current.indexOf(id);
    const to = Math.max(0, Math.min(current.length - 1, from + delta));
    if (from < 0 || from === to) return current;
    const next = [...current];
    next.splice(to, 0, next.splice(from, 1)[0]);
    return next;
  });
  const layouts: Array<{ id: DeckLayout; label: string; icon?: LucideIcon }> = [
    { id: 'stack', label: 'One column', icon: LayoutList },
    { id: 'split', label: 'Side by side', icon: Columns2 },
    { id: 'three', label: 'Three panels' },
    { id: 'quad', label: 'Four corners', icon: Grid2X2 },
  ];
  return <div className="on-deck-workspace">
    <div className="on-deck-toolbar">{onShowAll && <button className="button secondary" onClick={onShowAll}>Show all on deck</button>}
      <div><strong>Workspace layout</strong></div>
      <div className="layout-switcher" role="group" aria-label="Workspace layout">{layouts.map((option) => { const Icon = option.icon; return <button key={option.id} className={layout === option.id ? 'active' : ''} aria-label={option.label} aria-pressed={layout === option.id} onClick={() => setLayout(option.id)} title={option.label}>{Icon ? <Icon /> : <b>3</b>}<span>{option.label}</span></button>; })}</div>
    </div>
    {orderedRecipes.length ? <div className={cx('on-deck-board', `layout-${layout}`)}>{orderedRecipes.map(({ id, recipe, plan, draft }, index) => <OnDeckRecipeCard key={id} recipe={recipe} plan={plan} draft={draft} locations={locations} dragging={draggingId === id} onDragStart={(event) => { setDraggingId(id); event.dataTransfer.effectAllowed = 'move'; event.dataTransfer.setData('text/plain', id); }} onDragEnd={() => setDraggingId('')} onDragOver={(event) => { event.preventDefault(); event.dataTransfer.dropEffect = 'move'; }} onDrop={(event) => { event.preventDefault(); moveRecipe(event.dataTransfer.getData('text/plain') || draggingId, id); setDraggingId(''); }} onNudge={(delta) => nudgeRecipe(id, delta)} canMoveEarlier={index > 0} canMoveLater={index < orderedRecipes.length - 1} onRemove={() => onRemoveRecipe(id)} notify={notify} onCook={onCook} onProgressChange={onProgressChange} undo={undo} />)}</div> : <div className="empty-deck"><CookingPot /><h2>Nothing is on deck</h2><button className="button primary" onClick={onAddRecipe}><Plus /> Add a recipe</button></div>}
  </div>;
}

function PieceIngredientControl({ ingredient, onChange, initiallyEnabled = false }: { ingredient: Recipe['ingredients'][number]; onChange: (value: PieceInput | null | undefined) => void; initiallyEnabled?: boolean }) {
  const [enabled, setEnabled] = useState(initiallyEnabled);
  const [lotId, setLotId] = useState(ingredient.pieceLots?.find((candidate) => candidate.remainingPieces !== undefined)?.id ?? ingredient.pieceLots?.[0]?.id ?? '');
  const [lotPieces, setLotPieces] = useState('');
  const [pieces, setPieces] = useState('1');
  const lot = ingredient.pieceLots?.find((candidate) => candidate.id === lotId);
  const count = lot?.remainingPieces ?? Number(lotPieces);
  const used = Number(pieces);
  const valid = Boolean(lot && Number.isFinite(count) && count > 0 && Number.isFinite(used) && used > 0 && used <= count + 0.0000001 && Number.isInteger(used * 4) && (lot?.remainingPieces !== undefined || Number.isInteger(count * 4)));
  // The callback is recreated by the parent; publish only when the user's inputs or lot snapshot change.
  useEffect(() => {
    onChange(!enabled ? undefined : valid && lot ? { ingredientId: ingredient.id!, lotId, pieces: used, expectedRemaining: lot.remainingBase, ...(lot.remainingPieces === undefined ? { lotPieces: count } : {}) } : null);
  }, [enabled, lotId, lotPieces, pieces, lot?.remainingBase, lot?.remainingPieces]);
  return <div className="piece-ingredient-control"><button type="button" className="text-button" aria-expanded={enabled} onClick={() => setEnabled(!enabled)}>{enabled ? 'Use recipe quantity for' : 'Choose pieces instead for'} {ingredient.name ?? ingredient.label}</button>{enabled && <div className="deck-batch-fields"><label className="field"><span>Package / lot</span><select value={lotId} onChange={(event) => { setLotId(event.target.value); setLotPieces(''); }}>{ingredient.pieceLots?.map((value) => <option key={value.id} value={value.id}>{value.label}</option>)}</select></label>{lot?.remainingPieces === undefined ? <label className="field"><span>Pieces currently in this package</span><input type="number" min="0.25" step="0.25" value={lotPieces} onChange={(event) => setLotPieces(event.target.value)} /></label> : <p>About {formatAmount(lot.remainingPieces)} pieces remain.</p>}<label className="field"><span>Pieces to cook</span><input type="number" min="0.25" step="0.25" value={pieces} onChange={(event) => setPieces(event.target.value)} /></label><div role="group" aria-label={`Piece quantity for ${ingredient.name ?? ingredient.label}`}>{[1, 0.5, 0.25].map((value) => <button type="button" className="button secondary" aria-pressed={Number(pieces) === value} key={value} onClick={() => setPieces(String(value))}>{value === 1 ? 'Whole' : value === 0.5 ? 'Half' : 'Quarter'}</button>)}</div><p>{valid && lot ? `~${formatAmount(lot.remainingBase * used / count)} g instead of recipe quantity.` : 'Enter pieces available and pieces to cook.'} Weight, nutrition and cost are estimated.</p></div>}</div>;
}

function PieceIngredientSetup({ ingredients, onChange }: { ingredients: Recipe['ingredients']; onChange: (id: string, value: PieceInput | null | undefined) => void }) {
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const candidates = ingredients.filter((item) => item.id && !item.pieceBasis && item.pieceLots?.length && !item.pieceLots.some((lot) => lot.remainingPieces !== undefined));
  if (!candidates.length) return null;
  return <details className="piece-setup"><summary>Adjust ingredient quantities</summary><label className="field"><span>Ingredient to adjust</span><select value="" onChange={(event) => setSelected((current) => new Set([...current, event.target.value]))}><option value="">Choose ingredient</option>{candidates.filter((item) => !selected.has(item.id!)).map((item) => <option key={item.id} value={item.id}>{item.name ?? item.label}</option>)}</select></label>{candidates.filter((item) => selected.has(item.id!)).map((item) => <PieceIngredientControl key={item.id} ingredient={item} initiallyEnabled onChange={(value) => onChange(item.id!, value)} />)}</details>;
}

function OnDeckRecipeCard({ recipe, plan, draft, locations, dragging, onDragStart, onDragEnd, onDragOver, onDrop, onNudge, canMoveEarlier, canMoveLater, onRemove, notify, onCook, onProgressChange, undo }: { recipe: Recipe; plan?: PlannedMealView; draft?: CookingDraft; locations: string[]; dragging: boolean; onDragStart: (event: React.DragEvent<HTMLButtonElement>) => void; onDragEnd: () => void; onDragOver: (event: React.DragEvent<HTMLElement>) => void; onDrop: (event: React.DragEvent<HTMLElement>) => void; onNudge: (delta: number) => void; canMoveEarlier: boolean; canMoveLater: boolean; onRemove: () => void; notify: Notify; onCook?: (id: string, options?: PreparationOptions) => Promise<PreparationResult>; onProgressChange: (id: string, active: boolean) => void; undo: Reversals }) {
  const storageKey = `mise.recipe-progress.${plan?.id ?? draft?.id ?? recipe.id}`;
  const cookingDraftId = draft && draft.id !== recipe.id ? draft.id : undefined;
  const [checks, setChecks] = useState<Set<string>>(() => { try { return new Set(JSON.parse(localStorage.getItem(storageKey) ?? '[]') as string[]); } catch { return new Set(); } });
  const [saving, setSaving] = useState(false);
  const [pendingCookOptions, setPendingCookOptions] = useState<PreparationOptions | null>(null);
  useEffect(() => {
    let active = true;
    void pendingMutationPayload<{ recipeId: string; options: PreparationOptions }>('prepare_recipe', cookingAttemptIdentity(recipe.id, { mealPlanId: plan?.id, cookingDraftId })).then((saved) => { if (active && saved) setPendingCookOptions(saved.options); }).catch(() => {});
    return () => { active = false; };
  }, [recipe.id, plan?.id, cookingDraftId]);
  const [pieceInputs, setPieceInputs] = useState<Record<string, PieceInput | null>>({});
  const invalidPieces = Object.values(pieceInputs).some((input) => input === null);
  const ingredientsRef = useRef<HTMLDetailsElement>(null);
  const methodRef = useRef<HTMLDetailsElement>(null);
  const batchRef = useRef<HTMLDivElement>(null);
  const jumpToSection = (section: HTMLElement | null) => {
    if (section instanceof HTMLDetailsElement) section.open = true;
    section?.scrollIntoView({ block: 'start', behavior: 'smooth' });
  };
  const [customBatchScale, setBatchScale] = useState(() => draft ? draft.servingsMade / recipe.servings : 1);
  const anchorIngredient = recipe.ingredients.find((item) => item.pieceBasis?.anchor);
  const anchorInput = anchorIngredient?.id ? pieceInputs[anchorIngredient.id] : undefined;
  const anchorScale = anchorIngredient?.pieceBasis && anchorInput?.scaleRecipe ? pieceWeight(anchorIngredient.pieceBasis, anchorInput.pieces, anchorIngredient.pieceLots?.find((lot) => lot.id === anchorInput.lotId), anchorInput.weightGrams) / anchorIngredient.pieceBasis.grams : undefined;
  const batchScale = anchorScale ?? (plan ? plan.scaleFactor ?? 1 : customBatchScale);
  const [useIngredientNutrition, setUseIngredientNutrition] = useState(false);
  const nutritionConflict = hasPieceNutritionConflict(recipe, pieceInputs, batchScale);
  const defaultServings = recipe.servings * batchScale;
  const [servingsMade, setServingsMade] = useState(defaultServings);
  const [servingsEaten, setServingsEaten] = useState(draft?.servingsEaten ?? 0);
  const [location, setLocation] = useState(locations.includes('fridge') ? 'fridge' : locations[0] ?? 'fridge');
  const total = recipe.ingredients.length + recipe.steps.length;
  useEffect(() => { localStorage.setItem(storageKey, JSON.stringify([...checks])); onProgressChange(plan?.id ?? draft?.id ?? recipe.id, checks.size > 0); }, [checks, recipe.id, storageKey]);
  const toggle = (key: string) => setChecks((current) => { const next = new Set(current); if (next.has(key)) next.delete(key); else next.add(key); return next; });
  useEffect(() => setServingsMade(defaultServings), [defaultServings]);
  const clearProgress = () => { setChecks(new Set()); localStorage.removeItem(storageKey); onProgressChange(plan?.id ?? draft?.id ?? recipe.id, false); };
  return <article className={cx('on-deck-card', dragging && 'dragging')} aria-label={recipe.name} onDragOver={onDragOver} onDrop={onDrop}>
    <div className="deck-card-header"><button className="deck-drag-handle" draggable onDragStart={onDragStart} onDragEnd={onDragEnd} onKeyDown={(event) => { if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') { event.preventDefault(); onNudge(-1); } if (event.key === 'ArrowRight' || event.key === 'ArrowDown') { event.preventDefault(); onNudge(1); } }} aria-label={`Drag ${recipe.name} panel. Use arrow keys to reorder.`}><GripVertical /></button><span className="deck-recipe-emoji">{recipe.emoji}</span><div><h2>{recipe.name}</h2><p>{servingLabel(defaultServings)} · {recipe.minutes} minutes</p></div><div className="deck-card-actions"><button className="icon-button" disabled={!canMoveEarlier} onClick={() => onNudge(-1)} aria-label={`Move ${recipe.name} earlier`}>←</button><button className="icon-button" disabled={!canMoveLater} onClick={() => onNudge(1)} aria-label={`Move ${recipe.name} later`}>→</button><button className="icon-button" onClick={onRemove} aria-label={`Remove ${recipe.name} from on deck`}><X /></button></div></div>
    <nav className="deck-section-nav" aria-label={`${recipe.name} cooking sections`}><button type="button" onClick={() => jumpToSection(ingredientsRef.current)}>Ingredients</button><button type="button" onClick={() => jumpToSection(methodRef.current)}>Method</button><button type="button" onClick={() => jumpToSection(batchRef.current)}>Batch</button></nav>
    <div className="deck-card-body"><details className="deck-section" open ref={methodRef}><summary>Method</summary>{batchScale !== 1 && <p className="muted">Ingredients scaled · Original method</p>}{recipe.steps.map((step, index) => <CheckRow key={step} checked={checks.has(`s${index}`)} onClick={() => toggle(`s${index}`)} title={`${index + 1}. ${step}`} />)}</details><small className="deck-nutrition">{Object.keys(pieceInputs).length || batchScale !== 1 || servingsMade !== recipe.servings ? 'Adjusted nutrition & cost unavailable' : `Original recipe: ${recipe.nutrition}`}</small><label className="field"><span>{plan ? 'Batch size (from plan)' : 'Batch size'}</span><input aria-label={`Recipe multiplier for ${recipe.name}`} type="number" min="0.25" step="0.25" value={Number(batchScale.toFixed(3))} readOnly={Boolean(plan) || anchorScale !== undefined} onChange={(event) => setBatchScale(Number(event.target.value))} /></label>{!plan && <small>Unplanned</small>}{plan && <div className="deck-plan-link"><CalendarDays /><span><strong>Planned {plan.slot.toLowerCase()}</strong><small>{formatServings(plan.plannedServings)} planned to eat · {formatAmount(plan.scaleFactor ?? 1)}× recipe</small></span></div>}<div className="cooking-progress"><span>{checks.size} of {total} complete</span><Progress value={total ? checks.size / total * 100 : 0} />{checks.size > 0 && <button className="text-button" onClick={clearProgress}>Reset</button>}</div><details className="deck-section" ref={ingredientsRef}><summary>Ingredients</summary>{recipe.ingredients.map((item, index) => <div key={item.id ?? item.label}><CheckRow checked={checks.has(`i${index}`)} onClick={() => toggle(`i${index}`)} title={item.id && Object.hasOwn(pieceInputs, item.id) ? `Original recipe requirement: ${scaledIngredient(item, batchScale)} — replaced by pieces below` : scaledIngredient(item, batchScale)} meta={item.id && Object.hasOwn(pieceInputs, item.id) ? 'Using the selected lot below' : scaledIngredientStock(item, batchScale)} />{item.id && item.pieceBasis && <RecipePieceControl ingredient={item} scale={batchScale} onChange={(value) => setPieceInputs((current) => ({ ...current, [item.id!]: value }))} />}{item.id && !item.pieceBasis && item.pieceLots?.some((lot) => lot.remainingPieces !== undefined) && <PieceIngredientControl ingredient={item} onChange={(value) => setPieceInputs((current) => { const next = { ...current }; if (value === undefined) delete next[item.id!]; else next[item.id!] = value; return next; })} />}</div>)}<PieceIngredientSetup ingredients={recipe.ingredients} onChange={(id, value) => setPieceInputs((current) => { const next = { ...current }; if (value === undefined) delete next[id]; else next[id] = value; return next; })} /></details><div ref={batchRef} className="deck-section"><h3>FINISH THE BATCH</h3><div className="deck-batch-fields"><label className="field"><span>Servings made</span><input aria-label={`Servings of ${recipe.name} made`} type="number" min="0.25" step="0.25" value={Number(servingsMade.toFixed(2))} onChange={(event) => setServingsMade(Number(event.target.value))} /></label><label className="field"><span>Store remaining in</span><select aria-label={`Storage location for ${recipe.name}`} value={location} onChange={(event) => setLocation(event.target.value)}>{locations.map((value) => <option key={value} value={value}>{value}</option>)}</select></label><label className="field"><span>Servings eaten now</span><input aria-label={`Servings of ${recipe.name} eaten now`} type="number" min="0" max={servingsMade} step="0.25" value={servingsEaten} onChange={(event) => setServingsEaten(Number(event.target.value))} /></label></div></div></div>
    <div className="deck-card-footer">{nutritionConflict && <div role="status" className="piece-nutrition-choice"><span>These quantities change the recipe's nutrition proportions.</span><label><input type="checkbox" checked={useIngredientNutrition} onChange={(event) => setUseIngredientNutrition(event.target.checked)} /> Use ingredient nutrition for this batch</label><small>Saved recipe nutrition stays unchanged.</small></div>}{pendingCookOptions && <p role="status">Retrying the same batch.</p>}<button className="button primary" disabled={!onCook || saving || (!pendingCookOptions && (invalidPieces || (nutritionConflict && !useIngredientNutrition) || !Number.isFinite(batchScale) || batchScale <= 0 || !Number.isFinite(servingsMade) || servingsMade <= 0 || !Number.isFinite(servingsEaten) || servingsEaten < 0 || servingsEaten > servingsMade))} onClick={() => { if (!onCook) return; setSaving(true); const submittedOptions = pendingCookOptions ?? { scale: batchScale, ...(nutritionConflict && useIngredientNutrition ? { useIngredientNutrition: true } : {}), ...(cookingDraftId ? { cookingDraftId } : {}), ...(Object.keys(pieceInputs).length ? { pieceInputs: Object.values(pieceInputs).filter((input): input is PieceInput => input !== null) } : {}), servingsMade, location, mealPlanId: plan?.id, servingsEaten }; setPendingCookOptions(submittedOptions); void onCook(recipe.id, submittedOptions).then((result) => { clearProgress(); onRemove(); const eaten = result.servingsMade - result.servingsRemaining; notify(`Made ${formatServings(result.servingsMade)} of ${recipe.name}; ${formatAmount(result.servingsRemaining)} stored in ${result.location}${eaten ? ` and ${formatAmount(eaten)} logged as eaten` : ''}.`, undo.undoPrep ? async () => { if (result.foodLogId && undo.voidFoodLog) await undo.voidFoodLog(result.foodLogId); await undo.undoPrep!(result.prepId); } : undefined); }).catch((error: unknown) => { if (isDefiniteMutationFailure(error)) setPendingCookOptions(null); notify(mutationError(error, `Could not cook ${recipe.name}.`)); }).finally(() => setSaving(false)); }}>{saving ? 'Saving…' : pendingCookOptions ? 'Retry saved batch' : 'Finish cooking'}</button></div>
  </article>;
}

function RecipePanel({ onStartCooking, recipe, cooking, onClose, notify, onCook, onFeedback, onProgressChange, undo }: RecipePanelProps) {
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
  if (prepId) return <div className="panel-layer"><button className="panel-scrim" onClick={onClose} aria-label="Close feedback" /><aside className="action-panel recipe-panel" role="dialog" aria-modal="true"><PanelHeader title={`How was ${recipe.name}?`} onClose={onClose} /><div className="panel-body feedback-form"><RatingInput label="Ease" value={ease} onChange={setEase} /><RatingInput label="Taste" value={taste} onChange={setTaste} /><label className="field"><span>Actual time (minutes)</span><input type="number" min="0" value={minutes} onChange={(event) => setMinutes(Number(event.target.value))} /></label></div><div className="panel-footer"><button className="button secondary" onClick={() => { clearProgress(); onClose(); }}>Skip</button><button className="button primary" disabled={saving || !onFeedback} onClick={() => { if (!onFeedback) return; setSaving(true); void onFeedback(prepId, ease, taste, minutes).then(() => { clearProgress(); onClose(); notify('Preparation feedback saved.'); }).catch((error: unknown) => notify(error instanceof Error ? error.message : 'Could not save feedback.')).finally(() => setSaving(false)); }}>{saving ? 'Saving…' : 'Save feedback'}</button></div></aside></div>;
  return <div className="panel-layer"><button className="panel-scrim" onClick={onClose} aria-label="Close panel" /><aside className="action-panel recipe-panel" role="dialog" aria-modal="true"><PanelHeader title={`${recipe.emoji} ${recipe.name}`} subtitle={`${servingLabel(recipe.servings)} · ${recipe.minutes} minutes · ${recipe.nutrition}`} onClose={onClose} /><div className="panel-body"><div className="cooking-progress"><span>{checks.size} of {total} complete</span><Progress value={total ? checks.size / total * 100 : 0} />{checks.size > 0 && <button className="text-button" onClick={clearProgress}>Reset</button>}</div><h3>INGREDIENTS</h3>{recipe.ingredients.map((item, index) => <CheckRow key={item.label} checked={checks.has(`i${index}`)} onClick={() => toggle(`i${index}`)} title={item.label} meta={item.stock} />)}<h3>METHOD</h3>{recipe.steps.map((step, index) => <CheckRow key={step} checked={checks.has(`s${index}`)} onClick={() => toggle(`s${index}`)} title={`${index + 1}. ${step}`} />)}</div><div className="panel-footer"><span className="panel-footer-spacer" /><button className="button primary" disabled={(!onStartCooking && !onCook) || saving} onClick={() => { if (onStartCooking) { onStartCooking(recipe); return; } if (!onCook) return; setSaving(true); void onCook(recipe.id).then((result) => { setPrepId(result.prepId); notify(`Made ${formatServings(result.servingsMade)} of ${recipe.name} in ${result.location}.`, result.prepId && undo.undoPrep ? async () => { await undo.undoPrep!(result.prepId); } : undefined); }).catch((error: unknown) => notify(error instanceof Error ? error.message : `Could not cook ${recipe.name}.`)).finally(() => setSaving(false)); }}>{saving ? 'Saving…' : cooking ? 'Finish cooking' : 'Make batch'}</button></div></aside></div>;
}

function InventoryLotsPanel({ food, onClose, notify, onConsume, onSetQuantity, undo }: { food: InventoryFood; onClose: () => void; notify: Notify; onConsume?: (id: string, quantity: number) => Promise<string | null>; onSetQuantity?: (id: string, remaining: number, discard: boolean, reason?: string) => Promise<string | null>; undo: Reversals }) {
  const [busy, setBusy] = useState('');
  // The id an action returns is what its undo aims at: a food log for a consume,
  // an inventory event for an adjust or a discard.
  const run = (id: string, action: () => Promise<string | null>, message: string, reverse?: (result: string) => Promise<void>) => {
    setBusy(id);
    void action()
      .then((result) => { notify(message, result && reverse ? async () => { await reverse(result); } : undefined); onClose(); })
      .catch((error: unknown) => notify(error instanceof Error ? error.message : 'Could not update this lot.'))
      .finally(() => setBusy(''));
  };
  return <div className="panel-layer"><button className="panel-scrim" onClick={onClose} aria-label="Close lot details" /><aside className="action-panel lot-detail-panel" role="dialog" aria-modal="true"><PanelHeader title={`${food.emoji} ${food.name}`} subtitle={`${food.total} across ${food.lotDetails?.length ?? 0} lot${food.lotDetails?.length === 1 ? '' : 's'}`} onClose={onClose} /><div className="panel-body lot-detail-list">{food.lotDetails?.map((lot) => {
    const unitSuffix = lot.displayUnit ? ` (${lot.displayUnit})` : '';
    const editableRemaining = Number(lot.remainingDisplay.toFixed(6));
    const toBase = (displayQuantity: number) => Math.abs(displayQuantity - editableRemaining) < 0.000000001
      ? lot.remainingBase
      : displayQuantity / lot.displayPerBase;
    return <form className="lot-detail-card" key={lot.id} onSubmit={(event) => event.preventDefault()}><div className="lot-detail-head"><strong>{lot.quantity}</strong><span>{lot.location}</span><em className={lot.tone}>{lot.dateLabel}</em></div><p>{inventoryValueLabel(lot.cost, lot.costIsEstimated)}</p>{lot.purchasePriceUnknown && <p>Purchase price unavailable</p>}<div className="lot-actions"><label><span>{`Consume${unitSuffix}`}</span><input name="consume" type="number" min="0.001" max={editableRemaining} step="any" defaultValue={Math.min(1, editableRemaining)} /></label><button className="button secondary" disabled={!onConsume || busy === lot.id} onClick={(event) => { const form = event.currentTarget.form!; const quantity = Number(new FormData(form).get('consume')); if (onConsume) run(lot.id, () => onConsume(lot.id, toBase(quantity)), `${quantity}${lot.displayUnit ? ` ${lot.displayUnit}` : ''} consumed and logged.`, undo.voidFoodLog); }}>Consume</button></div><div className="lot-actions"><label><span>{`Set remaining${unitSuffix}`}</span><input name="remaining" type="number" min="0" step="any" defaultValue={editableRemaining} /></label><button className="button secondary" disabled={!onSetQuantity || busy === lot.id} onClick={(event) => { const form = event.currentTarget.form!; const remaining = Number(new FormData(form).get('remaining')); if (onSetQuantity) run(lot.id, () => onSetQuantity(lot.id, toBase(remaining), false), 'Lot quantity adjusted.', undo.undoInventoryAdjustment); }}>Adjust</button><button className="button danger" disabled={!onSetQuantity || busy === lot.id} onClick={() => { if (onSetQuantity && window.confirm(`Discard all remaining ${food.name} in this lot as waste?`)) run(lot.id, () => onSetQuantity(lot.id, 0, true), 'Lot discarded as waste.', undo.undoInventoryAdjustment); }}><Trash2 /> Discard all</button></div></form>;
  })}{!food.lotDetails?.length && <div className="empty-inline">No available lots.</div>}</div></aside></div>;
}

type BulkScanRow = { barcode: string; product: ProductView; quantity: number; bestBy: string };

function BulkInventoryPanel({ onClose, notify, onSave }: { onClose: () => void; notify: Notify; onSave?: (kind: PanelKind, form: FormData) => Promise<string> }) {
  const { locations, products } = usePantryData();
  const [rows, setRows] = useState<BulkScanRow[]>([]);
  const [unknown, setUnknown] = useState<string[]>([]);
  const [defaultBestBy, setDefaultBestBy] = useState('');
  const [location, setLocation] = useState(locations[0] ?? 'pantry');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [copied, setCopied] = useState(false);
  const productByBarcode = useMemo(() => new Map(products.filter((product) => product.barcode).map((product) => [product.barcode, product])), [products]);

  function addBarcode(raw: string) {
    const barcode = raw.trim();
    if (!barcode) return;
    const product = productByBarcode.get(barcode);
    if (!product) {
      setUnknown((current) => current.includes(barcode) ? current : [...current, barcode]);
      return;
    }
    setRows((current) => {
      const existing = current.findIndex((row) => row.barcode === barcode && row.bestBy === defaultBestBy);
      if (existing < 0) return [...current, { barcode, product, quantity: 1, bestBy: defaultBestBy }];
      return current.map((row, index) => index === existing ? { ...row, quantity: row.quantity + 1 } : row);
    });
  }

  const lookupText = `Please look up these pantry products by UPC/EAN and return the product name, brand, package size, and nutrition label for each:\n${unknown.map((barcode) => `- ${barcode}`).join('\n')}`;
  async function copyUnknown() {
    try {
      await navigator.clipboard.writeText(lookupText);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1800);
    } catch { setError('Could not copy automatically. Select the list and copy it manually.'); }
  }
  async function save() {
    if (!rows.length) return;
    if (!onSave) { setError('A live Supabase connection is required to add inventory.'); return; }
    const form = new FormData();
    form.set('location', location);
    form.set('entries', JSON.stringify(rows.map((row) => ({ productId: row.product.id, packages: row.quantity, bestBy: row.bestBy || null }))));
    setSaving(true);
    setError('');
    try {
      const message = await onSave('bulk-import', form);
      if (unknown.length) {
        setRows([]);
        notify(message);
      } else {
        onClose();
        notify(message);
      }
    } catch (cause) { setError(mutationError(cause, 'Could not import inventory.')); }
    finally { setSaving(false); }
  }

  return <div className="panel-layer"><button className="panel-scrim" aria-label="Close bulk inventory scan" onClick={onClose} /><aside className="action-panel bulk-import-panel" role="dialog" aria-modal="true" aria-labelledby="panel-title"><PanelHeader title="Bulk inventory scan" subtitle="One scan = one package" onClose={onClose} /><div className="panel-body bulk-import-body"><BarcodeScanner onDetected={addBarcode} actionLabel="Add typed barcode" /><div className="form-grid two bulk-defaults"><label className="field"><span>Best by for new scans</span><input type="date" value={defaultBestBy} onChange={(event) => setDefaultBestBy(event.target.value)} /></label><label className="field"><span>Store in</span><select value={location} onChange={(event) => setLocation(event.target.value)}>{locations.map((value) => <option key={value}>{value}</option>)}</select></label></div>{rows.length > 0 && <PanelSection title={`READY TO ADD · ${rows.reduce((sum, row) => sum + row.quantity, 0)} PACKAGES`}><div className="bulk-scan-list">{rows.map((row, index) => <div className="bulk-scan-row" key={`${row.barcode}-${index}`}><span className="row-emoji">{row.product.emoji}</span><div className="grow"><strong>{row.product.label}</strong><small>{row.barcode}</small></div><label><span>Qty</span><input aria-label={`Quantity of ${row.product.label}`} type="number" min="1" step="1" value={row.quantity} onChange={(event) => setRows((current) => current.map((item, itemIndex) => itemIndex === index ? { ...item, quantity: Math.max(1, Number(event.target.value) || 1) } : item))} /></label><label><span>Best by</span><input aria-label={`Best by for ${row.product.label}`} type="date" value={row.bestBy} onChange={(event) => setRows((current) => current.map((item, itemIndex) => itemIndex === index ? { ...item, bestBy: event.target.value } : item))} /></label><button className="icon-button" aria-label={`Remove ${row.product.label}`} onClick={() => setRows((current) => current.filter((_, itemIndex) => itemIndex !== index))}><X /></button></div>)}</div></PanelSection>}{unknown.length > 0 && <PanelSection title={`NEEDS LOOKUP · ${unknown.length}`}><div className="unknown-scan-list"><p>Unknown barcodes</p><textarea readOnly value={lookupText} rows={Math.min(8, unknown.length + 3)} aria-label="Unknown barcode lookup list" /><button className="button secondary full" type="button" onClick={() => void copyUnknown()}><ClipboardList />{copied ? 'Copied' : 'Copy for ChatGPT'}</button></div></PanelSection>}{!rows.length && !unknown.length && <div className="empty-inline">Scanned products will collect here until you finish.</div>}{error && <div className="auth-error" role="alert">{error}</div>}</div><div className="panel-footer"><span className="panel-footer-spacer" /><button className="button primary" disabled={!rows.length || saving} onClick={() => void save()}>{saving ? 'Adding…' : `Add ${rows.reduce((sum, row) => sum + row.quantity, 0)} package${rows.reduce((sum, row) => sum + row.quantity, 0) === 1 ? '' : 's'}`}</button></div></aside></div>;
}

function BarcodeScanner({ onDetected, actionLabel }: { onDetected?: (barcode: string) => void; actionLabel?: string } = {}) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const controlsRef = useRef<IScannerControls | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const scanSessionRef = useRef(0);
  const [barcode, setBarcode] = useState('');
  const [scanning, setScanning] = useState(false);
  const [message, setMessage] = useState('Use your phone camera or enter the UPC / EAN.');
  const stop = (updateState = true) => {
    scanSessionRef.current += 1;
    controlsRef.current?.stop();
    controlsRef.current = null;
    streamRef.current?.getTracks().forEach((track) => track.stop());
    streamRef.current = null;
    if (videoRef.current) videoRef.current.srcObject = null;
    if (updateState) setScanning(false);
  };
  useEffect(() => () => stop(false), []);
  async function start() {
    const video = videoRef.current;
    if (!video) return;
    const session = scanSessionRef.current + 1;
    scanSessionRef.current = session;
    setScanning(true);
    setMessage('Waiting for Firefox camera permission…');
    try {
      if (window.isSecureContext === false) throw new DOMException('Camera access requires a secure HTTPS page.', 'SecurityError');
      if (!navigator.mediaDevices?.getUserMedia) throw new DOMException('This browser does not expose camera access.', 'NotSupportedError');
      const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: { ideal: 'environment' } }, audio: false });
      if (scanSessionRef.current !== session) { stream.getTracks().forEach((track) => track.stop()); return; }
      streamRef.current = stream;
      video.srcObject = stream;
      await video.play();
      setMessage('Camera is on. Loading barcode reader…');
      const { BarcodeFormat, BrowserMultiFormatReader } = await import('@zxing/browser');
      if (scanSessionRef.current !== session) return;
      const reader = new BrowserMultiFormatReader();
      reader.possibleFormats = [BarcodeFormat.UPC_A, BarcodeFormat.UPC_E, BarcodeFormat.EAN_8, BarcodeFormat.EAN_13, BarcodeFormat.CODE_128];
      const controls = await reader.decodeFromStream(
        stream,
        video,
        (result, _error, activeControls) => {
          if (!result || scanSessionRef.current !== session) return;
          const found = result.getText();
          scanSessionRef.current += 1;
          activeControls.stop();
          controlsRef.current = null;
          streamRef.current = null;
          setBarcode(found);
          setMessage(`Found ${found}`);
          setScanning(false);
          onDetected?.(found);
        },
      );
      if (scanSessionRef.current !== session) { controls.stop(); return; }
      controlsRef.current = controls;
      setMessage('Point the camera at the barcode.');
    } catch (cause) {
      if (scanSessionRef.current !== session) return;
      const name = cause instanceof DOMException ? cause.name : '';
      setMessage(
        name === 'NotAllowedError' || name === 'SecurityError'
          ? 'Firefox blocked the camera. Allow Camera for this site in Firefox permissions, then try again.'
          : name === 'NotFoundError'
            ? 'Firefox could not find a camera on this device.'
            : name === 'NotReadableError'
              ? 'The camera is busy. Close other apps using it, then try again.'
              : mutationError(cause, 'Camera access was not available.'),
      );
      stop();
    }
  }
  return <div className="scan-box"><div className={cx('scanner-frame', scanning && 'live')}><video ref={videoRef} muted playsInline /><ScanLine /><span role="status" aria-live="polite">{message}</span><i /><i /><i /><i /></div><button className="button secondary full" type="button" onClick={() => scanning ? stop() : void start()}>{scanning ? 'Stop camera' : 'Enable camera'}</button><label className="field"><span>UPC / EAN</span><input name="barcode" inputMode="numeric" autoComplete="off" value={barcode} onChange={(event) => setBarcode(event.target.value)} placeholder="Enter barcode" required={!onDetected} /></label>{onDetected && <button className="button secondary full" type="button" disabled={!barcode.trim()} onClick={() => { onDetected(barcode); setBarcode(''); setMessage('Ready for the next barcode.'); }}>{actionLabel ?? 'Add barcode'}</button>}</div>;
}

function RatingInput({ label, value, onChange }: { label: string; value: number; onChange: (value: number) => void }) {
  return <div className="rating-input"><span>{label}</span><div>{Array.from({ length: 5 }, (_, index) => <button type="button" className={index < value ? 'selected' : ''} aria-label={`${label} ${index + 1} out of 5`} key={index} onClick={() => onChange(value === index + 1 ? 0 : index + 1)}>★</button>)}</div><small>{value ? `${value}/5` : 'Not rated'}</small></div>;
}

function CheckRow({ checked, onClick, title, meta }: { checked: boolean; onClick: () => void; title: string; meta?: string }) {
  return <button className={cx('check-row', checked && 'checked')} onClick={onClick}><span className="check-box">{checked && <Check />}</span><div><strong>{title}</strong>{meta && <small>{meta}</small>}</div></button>;
}
