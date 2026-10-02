import { cookingAttemptIdentity } from './cooking-stage';
import type { PlanningRange } from './planning-week';
import { preparedPlanAvailability } from './prepared-plan';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database, Json } from '../database.types';
import type { ShoppingReceipt, FoodLogEntry, NutritionValues, NutrientName, PantryData, PlannedMealConsumption, PreparationOptions, PreparationResult } from '../pantry-data';
import { DEFAULT_WEEKLY_FOOD_BUDGET, completeCost, perServingCost, remainingValue } from './cost';
import { formatAmount, formatServings, formatStockQuantity, shoppingQuantityPresentation } from './format';
import { runRetryableMutation } from './mutation-feedback';
import { nutritionForServings } from './nutrition';

type Client = SupabaseClient<Database>;
type FoodLogRow = Database['public']['Tables']['food_logs']['Row'];
type LotRow = Database['public']['Tables']['inventory_lots']['Row'];
type ProductRow = Database['public']['Tables']['products']['Row'];

type ProductConsumptionLog = Pick<FoodLogRow, 'product' | 'servings' | 'occurred_at'>;
type ProductCostLot = Pick<LotRow, 'product' | 'initial_qty' | 'total_cost' | 'cost_source' | 'price_as_of' | 'acquired_at' | 'created_at'> & { acquisitionCanceled?: boolean };
type ProductPrice = { estimatedCost: number | null; costSource: string; costAsOf: string };

export function summarizeProductConsumption(logs: ProductConsumptionLog[]) {
  const summaries = new Map<string, { servingsConsumed: number; lastUsedAt: string }>();
  for (const log of logs) {
    if (!log.product) continue;
    const current = summaries.get(log.product) ?? { servingsConsumed: 0, lastUsedAt: '' };
    const occurredAt = Date.parse(log.occurred_at);
    const lastUsedAt = Date.parse(current.lastUsedAt);
    summaries.set(log.product, {
      servingsConsumed: current.servingsConsumed + Number(log.servings ?? 1),
      lastUsedAt: !current.lastUsedAt || (Number.isFinite(occurredAt) && occurredAt > lastUsedAt) ? log.occurred_at : current.lastUsedAt,
    });
  }
  return summaries;
}

export function resolveProductPrice(product: Pick<ProductRow, 'id' | 'package_qty_base' | 'estimated_cost' | 'cost_source' | 'cost_as_of'>, lots: ProductCostLot[]): ProductPrice {
  if (product.estimated_cost !== null) {
    return {
      estimatedCost: Number(product.estimated_cost),
      costSource: product.cost_source ?? '',
      costAsOf: product.cost_as_of ?? '',
    };
  }
  const latest = lots
    .filter((lot) => !lot.acquisitionCanceled && lot.product === product.id && lot.total_cost !== null && Number(lot.initial_qty) > 0)
    .sort((left, right) => {
      const leftDate = left.price_as_of ?? left.acquired_at ?? left.created_at;
      const rightDate = right.price_as_of ?? right.acquired_at ?? right.created_at;
      return Date.parse(rightDate) - Date.parse(leftDate);
    })[0];
  if (!latest) return { estimatedCost: null, costSource: '', costAsOf: '' };
  return {
    estimatedCost: Number((Number(latest.total_cost) * Number(product.package_qty_base) / Number(latest.initial_qty)).toFixed(2)),
    costSource: ['Latest recorded purchase', latest.cost_source].filter(Boolean).join(' · '),
    costAsOf: latest.price_as_of ?? latest.acquired_at.slice(0, 10),
  };
}

type CostValue = { cost: number | null; estimated: boolean; source: string };
const INVENTORY_QUANTITY_EPSILON = 0.000001;

const productUnitCost = (product?: ProductRow): number | null => {
  if (!product || product.estimated_cost === null || Number(product.package_qty_base) <= 0) return null;
  return Number(product.estimated_cost) / Number(product.package_qty_base);
};

const lotCost = (lot: LotRow, quantity: number, product?: ProductRow): CostValue => {
  if (lot.total_cost !== null && Number(lot.initial_qty) > 0) {
    return { cost: Number(lot.total_cost) / Number(lot.initial_qty) * quantity, estimated: lot.cost_is_estimated, source: lot.cost_source ?? (lot.cost_is_estimated ? 'Lot estimate' : 'Purchase cost') };
  }
  const unitCost = productUnitCost(product);
  return { cost: unitCost === null ? null : unitCost * quantity, estimated: true, source: product?.cost_source ?? 'Product price estimate' };
};

const categoryEmoji = (category: string) => {
  if (/produce/i.test(category)) return '🥬';
  if (/egg|dairy|cheese/i.test(category)) return '🥚';
  if (/snack|chip/i.test(category)) return '🍫';
  if (/frozen/i.test(category)) return '❄️';
  return '🛒';
};

const formatQuantity = formatStockQuantity;

const recipeFractions: Array<[number, string]> = [
  [1 / 8, '⅛'], [1 / 4, '¼'], [1 / 3, '⅓'], [3 / 8, '⅜'],
  [1 / 2, '½'], [5 / 8, '⅝'], [2 / 3, '⅔'], [3 / 4, '¾'], [7 / 8, '⅞'],
];

export const formatRecipeQuantity = (value: number, unit?: string | null) => {
  if (!Number.isFinite(value)) return `${value} ${unit ?? ''}`.trim();
  const sign = value < 0 ? '-' : '';
  const absolute = Math.abs(value);
  let whole = Math.floor(absolute);
  const remainder = absolute - whole;
  const fraction = recipeFractions.find(([candidate]) => Math.abs(candidate - remainder) < 0.01)?.[1];
  if (Math.abs(1 - remainder) < 0.01) whole += 1;
  const quantity = fraction
    ? `${whole || ''}${fraction}`
    : Math.abs(1 - remainder) < 0.01 || remainder < 0.01
      ? String(whole)
      : String(Number(absolute.toFixed(3)));
  return `${sign}${quantity} ${unit ?? ''}`.trim();
};

const formatCost = (value: CostValue) => value.cost === null ? 'price unavailable' : `${value.estimated ? '~' : ''}$${value.cost.toFixed(2)}`;



const formatUsStock = (baseValue: number, unit?: Database['public']['Tables']['measure_conversions']['Row']) => {
  const converted = baseValue * Number(unit?.base_to_this_ratio ?? 1);
  const roundedOunces = Math.round(converted * 10) / 10;
  if (unit?.short_name === 'oz' && roundedOunces >= 16) {
    const pounds = Math.floor(roundedOunces / 16);
    const ounces = roundedOunces - pounds * 16;
    return `${pounds} lb${ounces >= 0.05 ? ` ${formatQuantity(ounces, 'oz')}` : ''}`;
  }
  return formatQuantity(converted, unit?.short_name);
};

const nutrientFields = {
  Calories: 'kcal', Protein: 'protein_g', Carbs: 'carbs_g', Fat: 'fat_g', Fiber: 'fiber_g', Sodium: 'sodium_mg',
} as const;

const nutritionValues = (row: Partial<Record<(typeof nutrientFields)[NutrientName], number | null>>): NutritionValues =>
  Object.fromEntries(Object.entries(nutrientFields).map(([label, field]) => [label, Number(row[field] ?? 0)])) as NutritionValues;

const emptyNutrition = (): NutritionValues => ({ Calories: 0, Protein: 0, Carbs: 0, Fat: 0, Fiber: 0, Sodium: 0 });

export const productQuantityForServings = (product: ProductRow, servings: number) => {
  const labelAligned = product.servings_per_package !== null
    && Number(product.servings_per_package) > 0
    && Number(product.package_qty_base) > 0
    && product.serving_qty_base !== null
    && product.nutrition_basis_qty !== null
    && Math.abs(Number(product.nutrition_basis_qty) - Number(product.serving_qty_base)) < INVENTORY_QUANTITY_EPSILON;
  return labelAligned
    ? servings * Number(product.package_qty_base) / Number(product.servings_per_package)
    : servings * Number(product.serving_qty_base ?? 1);
};

export const estimatedProductPortionCost = (product: ProductRow, servings: number): number | null => {
  const unitCost = productUnitCost(product);
  return unitCost === null ? null : unitCost * productQuantityForServings(product, servings);
};

const nutritionForProductServings = (product: ProductRow, food: FoodRow | undefined, servings: number): NutritionValues => {
  const quantity = productQuantityForServings(product, servings);
  const values = emptyNutrition();
  for (const [label, field] of Object.entries(nutrientFields) as Array<[NutrientName, (typeof nutrientFields)[NutrientName]]>) {
    const productValue = product[field];
    const sourceValue = productValue ?? food?.[field];
    const basis = productValue !== null && productValue !== undefined ? product.nutrition_basis_qty : food?.nutrition_basis_qty;
    values[label] = sourceValue === null || sourceValue === undefined || !basis || Number(basis) <= 0
      ? 0
      : Number(sourceValue) * quantity / Number(basis);
  }
  return values;
};

export const pluralizeFoodName = (name: string, plural: string | null | undefined, quantity: number) => {
  if (Math.abs(quantity - 1) < 0.001) return name;
  return plural || name;
};

type UnitRow = Database['public']['Tables']['measure_conversions']['Row'];
type FoodRow = Database['public']['Tables']['base_foods']['Row'];

const toFoodBase = (food: FoodRow, quantity: number, unit: UnitRow) => {
  const unitBase = quantity / Number(unit.base_to_this_ratio);
  if (food.measure_style === unit.measure_style) return unitBase;
  if (food.measure_style === 'weight' && unit.measure_style === 'volume') return unitBase * Number(food.g_per_fl_oz);
  if (food.measure_style === 'volume' && unit.measure_style === 'weight') return unitBase / Number(food.g_per_fl_oz);
  if (food.measure_style === 'weight' && unit.measure_style === 'discrete') return unitBase * Number(food.g_per_count);
  if (food.measure_style === 'discrete' && unit.measure_style === 'weight') return unitBase / Number(food.g_per_count);
  if (food.measure_style === 'volume' && unit.measure_style === 'discrete') return unitBase * Number(food.g_per_count) / Number(food.g_per_fl_oz);
  if (food.measure_style === 'discrete' && unit.measure_style === 'volume') return unitBase * Number(food.g_per_fl_oz) / Number(food.g_per_count);
  return Number.POSITIVE_INFINITY;
};

const fromFoodBase = (food: FoodRow, base: number, unit: UnitRow) => {
  let unitBase = base;
  if (food.measure_style === 'weight' && unit.measure_style === 'volume') unitBase = base / Number(food.g_per_fl_oz);
  else if (food.measure_style === 'volume' && unit.measure_style === 'weight') unitBase = base * Number(food.g_per_fl_oz);
  else if (food.measure_style === 'weight' && unit.measure_style === 'discrete') unitBase = base / Number(food.g_per_count);
  else if (food.measure_style === 'discrete' && unit.measure_style === 'weight') unitBase = base * Number(food.g_per_count);
  else if (food.measure_style === 'volume' && unit.measure_style === 'discrete') unitBase = base * Number(food.g_per_fl_oz) / Number(food.g_per_count);
  else if (food.measure_style === 'discrete' && unit.measure_style === 'volume') unitBase = base * Number(food.g_per_count) / Number(food.g_per_fl_oz);
  return unitBase * Number(unit.base_to_this_ratio);
};

const daysUntil = (date: string | null) => {
  if (!date) return { label: 'Unknown', tone: 'muted' };
  const days = Math.ceil((new Date(`${date}T12:00:00`).getTime() - Date.now()) / 86_400_000);
  if (days < 0) return { label: `${Math.abs(days)} day${Math.abs(days) === 1 ? '' : 's'} past date`, tone: 'urgent' };
  if (days === 0) return { label: 'Today', tone: 'urgent' };
  return { label: `${days} days`, tone: days <= 3 ? 'urgent' : days <= 7 ? 'warn' : 'safe' };
};

const sum = (rows: FoodLogRow[], field: keyof Pick<FoodLogRow, 'kcal' | 'protein_g' | 'carbs_g' | 'fat_g' | 'fiber_g' | 'sodium_mg'>) =>
  rows.reduce((total, row) => total + Number(row[field] ?? 0), 0);

const FOOD_LOG_GROUP_WINDOW_MS = 60 * 60 * 1000;

export const groupFoodLogRows = (logs: FoodLogRow[]) => {
  const groups: FoodLogRow[][] = [];
  const latestGroupByProduct = new Map<string, { group: FoodLogRow[]; newestTime: number }>();

  for (const log of [...logs].sort((left, right) => right.occurred_at.localeCompare(left.occurred_at))) {
    const occurredAt = Date.parse(log.occurred_at);
    const candidate = log.product && log.time_precision !== 'dateOnly' ? latestGroupByProduct.get(log.product) : undefined;
    if (candidate && Number.isFinite(occurredAt) && candidate.newestTime - occurredAt <= FOOD_LOG_GROUP_WINDOW_MS) {
      candidate.group.push(log);
      continue;
    }

    const group = [log];
    groups.push(group);
    if (log.product && log.time_precision !== 'dateOnly' && Number.isFinite(occurredAt)) latestGroupByProduct.set(log.product, { group, newestTime: occurredAt });
  }

  return groups;
};

const dateKeyInZone = (date: Date, timeZone: string) => {
  try {
    const parts = new Intl.DateTimeFormat('en-US', { year: 'numeric', month: '2-digit', day: '2-digit', timeZone }).formatToParts(date);
    const value = (type: Intl.DateTimeFormatPartTypes) => parts.find((part) => part.type === type)?.value ?? '';
    return `${value('year')}-${value('month')}-${value('day')}`;
  } catch {
    return date.toLocaleDateString('en-CA');
  }
};

export function recordedCorrectionTotals(log: Pick<FoodLogRow, 'kcal' | 'protein_g' | 'cost' | 'nutrition_is_estimated' | 'cost_is_estimated'>) {
  return { calories: log.kcal, protein: log.protein_g, cost: log.cost, estimated: log.nutrition_is_estimated || log.cost_is_estimated };
}

export function foodLogNutrition(rows: FoodLogRow[]): Record<NutrientName, number | null> {
  return Object.fromEntries(Object.entries(nutrientFields).map(([label, field]) => [label, rows.every((row) => row[field] !== null) ? sum(rows, field) : null])) as Record<NutrientName, number | null>;
}

export async function loadPantryData(client: Client): Promise<PantryData> {
  const [foodsResult, productsResult, lotsResult, unitsResult, categoriesResult, locationsResult, recipesResult, ingredientsResult, prepsResult, shoppingResult, plansResult, plannedConsumptionsResult, logsResult, settingsResult, eventsResult, eventCostsResult] = await Promise.all([
    client.from('base_foods').select('*'),
    client.from('products').select('*').is('archived_at', null),
    client.from('inventory_lots').select('*'),
    client.from('measure_conversions').select('*'),
    client.from('grocery_categories').select('*').order('sort_order'),
    client.from('locations').select('*').order('sort_order'),
    client.from('recipes').select('*').order('name'),
    client.from('recipe_ingredients').select('*').order('sort_order'),
    client.from('preps').select('*').is('voided_at', null),
    client.from('shopping_items').select('*').order('created_at'),
    client.from('meal_plans').select('*').order('plan_date'),
    client.from('planned_consumptions').select('*'),
    client.from('food_logs').select('*').is('voided_at', null).order('occurred_at', { ascending: false }),
    client.from('personal_settings').select('*').single(),
    client.from('inventory_events').select('*').is('voided_at', null).or('food_log.not.is.null,reason.eq.waste,reason.eq.adjust'),
    client.from('inventory_event_costs').select('*'),
  ]);

  const firstError = [foodsResult, productsResult, lotsResult, unitsResult, categoriesResult, locationsResult, recipesResult, ingredientsResult, prepsResult, shoppingResult, plansResult, plannedConsumptionsResult, logsResult, settingsResult, eventsResult, eventCostsResult]
    .find((result) => result.error)?.error;
  if (firstError) throw firstError;

  const foods = new Map((foodsResult.data ?? []).map((food) => [food.id, food]));
  const products = new Map((productsResult.data ?? []).map((product) => [product.id, product]));
  const productConsumption = summarizeProductConsumption(logsResult.data ?? []);
  const lotsByProduct = new Map<string, ProductCostLot[]>();
  const activeEventIds = new Set((eventsResult.data ?? []).map((event) => event.id));
  for (const lot of lotsResult.data ?? []) {
    if (lot.product) lotsByProduct.set(lot.product, [...(lotsByProduct.get(lot.product) ?? []), { ...lot, acquisitionCanceled: Boolean(lot.acquisition_void_event && activeEventIds.has(lot.acquisition_void_event)) }]);
  }
  const units = new Map((unitsResult.data ?? []).map((unit) => [unit.id, unit]));
  const categoryOrder = new Map((categoriesResult.data ?? []).map((category, index) => [category.category, index]));
  const orderCategories = <T,>(entries: Array<[string, T]>) => entries.sort(([left], [right]) =>
    (categoryOrder.get(left) ?? Number.MAX_SAFE_INTEGER) - (categoryOrder.get(right) ?? Number.MAX_SAFE_INTEGER) || left.localeCompare(right));
  const availableLots = (lotsResult.data ?? []).filter((lot) => Number(lot.remaining_qty) > INVENTORY_QUANTITY_EPSILON);
  const rawLots = availableLots.filter((lot) => !lot.prep);
  const stockByFood = new Map<string, number>();
  for (const lot of rawLots) {
    const product = lot.product ? products.get(lot.product) : undefined;
    if (product) stockByFood.set(product.food, (stockByFood.get(product.food) ?? 0) + Number(lot.remaining_qty));
  }

  const inventoryGroups = new Map<string, Map<string, NonNullable<typeof foodsResult.data>[number] & { lots: NonNullable<typeof lotsResult.data> }>>();
  for (const lot of rawLots) {
    const product = lot.product ? products.get(lot.product) : undefined;
    const food = product ? foods.get(product.food) : undefined;
    if (!food) continue;
    const category = food.grocery_category ?? 'Pantry & other';
    const categoryFoods = inventoryGroups.get(category) ?? new Map();
    const entry = categoryFoods.get(food.id) ?? { ...food, lots: [] };
    entry.lots.push(lot);
    categoryFoods.set(food.id, entry);
    inventoryGroups.set(category, categoryFoods);
  }

  const inventorySections = orderCategories([...inventoryGroups.entries()]).map(([category, groupedFoods]) => ({
    emoji: categoryEmoji(category),
    label: category,
    foods: [...groupedFoods.values()].map((food) => {
      const stockLots = food.lots;
      const total = stockLots.reduce((amount, lot) => amount + Number(lot.remaining_qty), 0);
      const earliest = stockLots.map((lot) => lot.use_by).filter(Boolean).sort()[0] ?? null;
      const due = daysUntil(earliest);
      const firstProduct = products.get(stockLots[0].product ?? '');
      const displayUnit = food.display_unit ? units.get(food.display_unit) : undefined;
      const costValues = stockLots.map((lot) => lotCost(lot, Number(lot.remaining_qty), products.get(lot.product ?? '')));
      const knownCosts = costValues.map((value) => value.cost).filter((value): value is number => value !== null);
      return {
        productId: firstProduct?.id,
        emoji: food.emoji ?? '🍽️',
        name: food.name,
        sub: [food.ingredient_role, food.grocery_category].filter(Boolean).join(' · ') || 'Pantry item',
        total: formatUsStock(total, displayUnit),
        due: due.label,
        tone: due.tone,
        lots: stockLots.map((lot) => `${formatUsStock(Number(lot.remaining_qty), displayUnit)} ${lot.location ?? 'unassigned'}`),
        cost: knownCosts.length === stockLots.length ? knownCosts.reduce((total, value) => total + value, 0) : null,
        costIsEstimated: costValues.some((value) => value.estimated),
        purchasePriceUnknown: stockLots.some((lot) => lot.total_cost === null),
        lotDetails: stockLots.map((lot) => {
          const lotDue = daysUntil(lot.use_by);
          const value = lotCost(lot, Number(lot.remaining_qty), products.get(lot.product ?? ''));
          const remainingBase = Number(lot.remaining_qty);
          const remainingDisplay = displayUnit ? fromFoodBase(food, remainingBase, displayUnit) : remainingBase;
          const displayPerBase = displayUnit ? fromFoodBase(food, 1, displayUnit) : 1;
          return { id: lot.id, quantity: formatUsStock(remainingBase, displayUnit), location: lot.location ?? 'unassigned', dateLabel: lotDue.label, tone: lotDue.tone, remainingBase, remainingDisplay, displayUnit: displayUnit?.short_name ?? '', displayPerBase, cost: value.cost, costIsEstimated: value.estimated, costSource: value.source, purchasePriceUnknown: lot.total_cost === null };
        }),
      };
    }),
  }));

  const recipeRows = recipesResult.data ?? [];
  const recipeNutrition = new Map<string, NutritionValues>();
  for (const recipe of recipeRows) {
    const totals = emptyNutrition();
    const recipeIngredients = (ingredientsResult.data ?? []).filter((ingredient) => ingredient.recipe === recipe.id);
    for (const ingredient of recipeIngredients) {
      const food = foods.get(ingredient.ingredient);
      const unit = units.get(ingredient.unit);
      if (!food || !unit) continue;
      const product = ingredient.pinned_product ? products.get(ingredient.pinned_product) : undefined;
      const quantity = toFoodBase(food, Number(ingredient.qty), unit);
      for (const [label, field] of Object.entries(nutrientFields) as Array<[NutrientName, (typeof nutrientFields)[NutrientName]]>) {
        const sourceValue = product?.[field] ?? food[field];
        const basis = product?.[field] !== null && product?.[field] !== undefined ? product.nutrition_basis_qty : food.nutrition_basis_qty;
        if (sourceValue !== null && sourceValue !== undefined && Number(basis) > 0) totals[label] += quantity * Number(sourceValue) / Number(basis);
      }
    }
    const overrideBasis = Number(recipe.override_basis_qty ?? 0);
    const servings = Number(recipe.servings);
    for (const [label, field] of Object.entries(nutrientFields) as Array<[NutrientName, (typeof nutrientFields)[NutrientName]]>) {
      const override = recipe[`override_${field}` as keyof typeof recipe];
      if (override !== null && override !== undefined && overrideBasis > 0) totals[label] = Number(override) / overrideBasis * servings;
    }
    recipeNutrition.set(recipe.id, totals);
  }
  const costForFoodQuantity = (foodId: string, quantity: number, pinnedProduct: string | null): CostValue => {
    if (foods.get(foodId)?.always_available) return { cost: 0, estimated: false, source: 'Always available' };
    let remaining = quantity;
    let total = 0;
    let estimated = false;
    const matchingLots = rawLots.filter((lot) => products.get(lot.product ?? '')?.food === foodId)
      .sort((left, right) => Number(Boolean(right.product === pinnedProduct)) - Number(Boolean(left.product === pinnedProduct)) || (left.use_by ?? '9999').localeCompare(right.use_by ?? '9999'));
    for (const lot of matchingLots) {
      const used = Math.min(remaining, Number(lot.remaining_qty));
      if (used <= 0) continue;
      const value = lotCost(lot, used, products.get(lot.product ?? ''));
      if (value.cost === null) return { cost: null, estimated: true, source: 'Price unavailable' };
      total += value.cost;
      estimated ||= value.estimated;
      remaining -= used;
      if (remaining <= 0.0000001) break;
    }
    if (remaining > 0.0000001) {
      const fallbackProducts = [...products.values()].filter((product) => product.food === foodId && product.estimated_cost !== null);
      const fallback = (pinnedProduct ? products.get(pinnedProduct) : undefined) ?? fallbackProducts.sort((left, right) => (productUnitCost(left) ?? Infinity) - (productUnitCost(right) ?? Infinity))[0];
      const rate = productUnitCost(fallback);
      if (rate === null) return { cost: null, estimated: true, source: 'Price unavailable' };
      total += remaining * rate;
      estimated = true;
    }
    return { cost: total, estimated, source: estimated ? 'Inventory and product estimates' : 'Inventory purchase costs' };
  };
  const recipes = recipeRows.map((recipe) => {
    const recipeIngredients = (ingredientsResult.data ?? []).filter((ingredient) => ingredient.recipe === recipe.id);
    const steps = Array.isArray(recipe.instructions) ? recipe.instructions.map(String) : [];
    const nutrition = recipeNutrition.get(recipe.id) ?? emptyNutrition();
    const kcal = nutrition.Calories;
    const protein = nutrition.Protein;
    const recipePreps = (prepsResult.data ?? []).filter((prep) => prep.recipe === recipe.id);
    const easeRatings = recipePreps.map((prep) => prep.ease_rating).filter((rating) => rating > 0);
    const tasteRatings = recipePreps.map((prep) => prep.taste_rating).filter((rating) => rating > 0);
    const ingredientCosts = recipeIngredients.map((ingredient) => {
      const unit = units.get(ingredient.unit);
      const food = foods.get(ingredient.ingredient);
      return unit && food ? costForFoodQuantity(food.id, toFoodBase(food, Number(ingredient.qty), unit), ingredient.pinned_product) : { cost: null, estimated: true, source: 'Price unavailable' };
    });
    const estimatedCost = ingredientCosts.every((value) => value.cost !== null) ? ingredientCosts.reduce((total, value) => total + Number(value.cost), 0) : null;
    return {
      id: recipe.id,
      emoji: recipe.emoji ?? '🍳',
      name: recipe.name,
      hasNutritionOverride: [recipe.override_kcal, recipe.override_protein_g, recipe.override_carbs_g, recipe.override_fat_g, recipe.override_fiber_g, recipe.override_sugar_g, recipe.override_sodium_mg].some((value) => value != null),
      servings: Number(recipe.servings),
      minutes: Math.max(10, steps.length * 5),
      nutrition: `${kcal ? `${Math.round(kcal / Number(recipe.servings))} cal · ${Math.round(protein / Number(recipe.servings))} g protein per serving` : 'Nutrition calculated from ingredients'} · ${formatCost({ cost: estimatedCost, estimated: ingredientCosts.some((value) => value.estimated), source: 'Recipe ingredients' })} batch`,
      ingredients: recipeIngredients.map((ingredient) => {
        const food = foods.get(ingredient.ingredient);
        const unit = units.get(ingredient.unit);
        const requestedQuantity = Number(ingredient.qty);
        if (!food || !unit) return { id: ingredient.id, label: `${formatRecipeQuantity(requestedQuantity)} Ingredient`, stock: 'Unit unavailable · short' };
        const ingredientName = pluralizeFoodName(food.name, food.plural, requestedQuantity);
        const pieceLots = food.measure_style === 'weight' && !food.always_available ? rawLots.filter((lot) => lot.product && products.get(lot.product)?.food === food.id && (!ingredient.pinned_product || lot.product === ingredient.pinned_product) && Number(lot.remaining_qty) > 0).map((lot) => ({
          id: lot.id,
          label: `${products.get(lot.product!)?.name ?? food.name} · ${formatAmount(Number(lot.remaining_qty))} g · ${lot.location ?? 'unassigned'}`,
          remainingBase: Number(lot.remaining_qty),
          remainingPieces: lot.piece_count && lot.piece_basis_qty ? Number(lot.remaining_qty) * Number(lot.piece_count) / Number(lot.piece_basis_qty) : undefined,
        })) : [];
        const pieceFields = { id: ingredient.id, pieceLots, ...(food.measure_style === 'weight' && !food.always_available ? { baseGrams: toFoodBase(food, requestedQuantity, unit) } : {}), ...(ingredient.piece_basis ? { pieceBasis: ingredient.piece_basis as unknown as import('../data').RecipePieceBasis } : {}) };
        if (food.always_available) return { ...pieceFields, quantity: requestedQuantity, unit: unit.short_name, name: ingredientName, label: pieceFields.pieceBasis ? `${formatAmount(pieceFields.pieceBasis.count)} ${pieceFields.pieceBasis.label} (~${formatAmount(pieceFields.pieceBasis.grams)} g estimated)` : `${formatRecipeQuantity(requestedQuantity, unit.short_name)} ${ingredientName}`, stock: 'Always available' };
        const neededBase = toFoodBase(food, Number(ingredient.qty), unit);
        const availableBase = stockByFood.get(ingredient.ingredient) ?? 0;
        const enough = availableBase + 0.0000001 >= neededBase;
        const availableInRequestedUnit = fromFoodBase(food, availableBase, unit);
        return { ...pieceFields, quantity: requestedQuantity, unit: unit.short_name, name: ingredientName, availableQuantity: availableInRequestedUnit, label: pieceFields.pieceBasis ? `${formatAmount(pieceFields.pieceBasis.count)} ${pieceFields.pieceBasis.label} (~${formatAmount(pieceFields.pieceBasis.grams)} g estimated)` : `${formatRecipeQuantity(requestedQuantity, unit.short_name)} ${ingredientName}`, stock: `${formatRecipeQuantity(availableInRequestedUnit, unit.short_name)} in stock${enough ? '' : ' · short'}` };
      }),
      steps,
      ease: easeRatings.length ? Number((easeRatings.reduce((total, value) => total + value, 0) / easeRatings.length).toFixed(1)) : 0,
      taste: tasteRatings.length ? Number((tasteRatings.reduce((total, value) => total + value, 0) / tasteRatings.length).toFixed(1)) : 0,
      prepCount: recipePreps.length,
      sourceUrl: recipe.source_url ?? '',
      promptForFeedback: recipe.prompt_for_feedback,
      ingredientText: recipeIngredients.map((ingredient) => `${Number(ingredient.qty)} ${units.get(ingredient.unit)?.short_name ?? ''} ${foods.get(ingredient.ingredient)?.name ?? 'Ingredient'}`).join('\n'),
      instructionText: steps.join('\n'),
      nutritionValues: nutrition,
      cookable: recipeIngredients.every((ingredient) => {
        const unit = units.get(ingredient.unit);
        const food = foods.get(ingredient.ingredient);
        return Boolean(unit && food && (food.always_available || (stockByFood.get(ingredient.ingredient) ?? 0) + 0.0000001 >= toFoodBase(food, Number(ingredient.qty), unit)));
      }),
      estimatedCost,
      costPerServing: estimatedCost === null ? null : estimatedCost / Number(recipe.servings),
      costIsEstimated: ingredientCosts.some((value) => value.estimated),
    };
  });
  const recipeCosts = new Map(recipes.map((recipe) => [recipe.id, recipe]));
  const productViews: PantryData['products'] = [...products.values()].map((product) => {
    const food = foods.get(product.food);
    const usage = productConsumption.get(product.id);
    const price = resolveProductPrice(product, lotsByProduct.get(product.id) ?? []);
    const servingQtyBase = productQuantityForServings(product, 1);
    const productLots = rawLots.filter((lot) => lot.product === product.id)
      .sort((left, right) => (left.use_by ?? '9999-12-31').localeCompare(right.use_by ?? '9999-12-31') || left.acquired_at.localeCompare(right.acquired_at));
    const costPerServing = price.estimatedCost === null || Number(product.package_qty_base) <= 0
      ? null
      : price.estimatedCost * servingQtyBase / Number(product.package_qty_base);
    return {
      id: product.id,
      foodId: product.food,
      foodName: food?.name ?? 'Food',
      name: product.name,
      label: [product.brand, product.name].filter(Boolean).join(' · '),
      brand: product.brand ?? '',
      barcode: product.barcode ?? '',
      ...price,
      emoji: product.emoji ?? food?.emoji ?? '🍽️',
      nutrition: nutritionValues(product),
      nutritionPerServing: nutritionForProductServings(product, food, 1),
      packageQtyBase: Number(product.package_qty_base),
      servingQtyBase,
      servingLabel: product.serving_label ?? '1 serving',
      stockServings: productLots.reduce((total, lot) => total + Number(lot.remaining_qty), 0) / servingQtyBase,
      costPerServing,
      availableLots: productLots.map((lot) => {
        const value = lotCost(lot, servingQtyBase, product);
        return {
          id: lot.id,
          location: lot.location ?? 'unassigned',
          remainingBase: Number(lot.remaining_qty),
          remainingServings: Number(lot.remaining_qty) / servingQtyBase,
          dateLabel: daysUntil(lot.use_by).label,
          costPerServing: value.cost,
          costIsEstimated: value.estimated,
        };
      }),
      servingsConsumed: usage?.servingsConsumed ?? 0,
      lastUsedAt: usage?.lastUsedAt ?? '',
    };
  });
  const productViewsById = new Map(productViews.map((product) => [product.id, product]));
  const plannedConsumptions = new Map((plannedConsumptionsResult.data ?? []).map((consumption) => [consumption.meal_plan, consumption]));
  const prepByMealPlan = new Map((prepsResult.data ?? []).filter((prep) => prep.meal_plan).map((prep) => [prep.meal_plan!, prep]));
  const preparedLotByPrep = new Map((lotsResult.data ?? []).filter((lot) => lot.prep).map((lot) => [lot.prep!, lot]));

  // Reuse the same quantity/yield nutrition resolver used by consumption SQL.
  const activePreparedLots = (lotsResult.data ?? []).filter((lot) => lot.prep && (prepsResult.data ?? []).some((prep) => prep.id === lot.prep));
  const preparedNutrition = new Map(await Promise.all(activePreparedLots.map(async (lot) => {
    const { data, error } = await client.rpc('lot_nutrition_json', { p_lot: lot.id });
    return [lot.id, error || !data ? undefined : nutritionValues(data as Parameters<typeof nutritionValues>[0])] as const;
  })));
  const allPreparedLots = activePreparedLots.map((lot) => {
    const prep = (prepsResult.data ?? []).find((candidate) => candidate.id === lot.prep);
    const recipe = prep ? recipeRows.find((candidate) => candidate.id === prep.recipe) : undefined;
    const servingsTotal = Number(lot.initial_qty);
    const servingsLeft = Number(lot.remaining_qty);
    // One unambiguous number per batch: what the whole batch cost. Per-serving and
    // value-remaining are derived from it in src/lib/cost.ts and nowhere else.
    const directBatch = lotCost(lot, servingsTotal);
    const recipeEstimate = prep?.recipe ? recipeCosts.get(prep.recipe) : undefined;
    const batch: CostValue = directBatch.cost !== null
      ? directBatch
      : recipeEstimate?.costPerServing !== null && recipeEstimate?.costPerServing !== undefined
        ? { cost: recipeEstimate.costPerServing * servingsTotal, estimated: true, source: 'Recipe estimate' }
        : { cost: null, estimated: true, source: 'Price unavailable' };
    return {
      id: lot.id,
      preparedAt: prep?.prepped_at,
      nutritionPerServing: preparedNutrition.get(lot.id),
      prepId: prep?.id,
      mealPlanId: prep?.meal_plan ?? undefined,
      emoji: recipe?.emoji ?? '🥘',
      name: recipe?.name ?? prep?.label ?? 'Prepared batch',
      location: lot.location ?? 'unassigned',
      remaining: `${formatQuantity(servingsLeft)} of ${formatQuantity(servingsTotal)} servings`,
      due: daysUntil(lot.use_by).label,
      progress: servingsTotal ? servingsLeft / servingsTotal * 100 : 0,
      batchCost: batch.cost,
      servingsTotal,
      servingsLeft,
      costPerServing: perServingCost(batch.cost, servingsTotal),
      valueRemaining: remainingValue(batch.cost, servingsTotal, servingsLeft),
      costIsEstimated: batch.estimated,
    };
  });

  const preparedLots = allPreparedLots.filter((lot) => lot.servingsLeft > INVENTORY_QUANTITY_EPSILON);

  const receiptHistory = (shoppingResult.data ?? []).flatMap((item) => {
    const lot = (lotsResult.data ?? []).find((candidate) => candidate.id === item.lot);
    if (!lot || lot.acquisition_void_event || !(item.received_qty_base > 0)) return [];
    const product = lot.product ? products.get(lot.product) : undefined;
    const food = product ? foods.get(product.food) : undefined;
    const unit = food?.display_unit ? units.get(food.display_unit) : undefined;
    return [{ lotId: lot.id, name: product?.name ?? item.free_text ?? food?.name ?? 'Receipt', acquiredAt: lot.acquired_at, quantity: formatQuantity(food && unit ? fromFoodBase(food, Number(lot.initial_qty), unit) : Number(lot.initial_qty), unit?.short_name), cost: lot.total_cost }];
  }).sort((a,b) => b.acquiredAt.localeCompare(a.acquiredAt));
  const groceryGroups = new Map<string, PantryData['grocerySections'][number]['items']>();
  // Include inactive rows: a rebuild with no shortage still records its range there.
  // No rows cannot establish a previous rebuild, and per-food reconciliation can leave mixed ranges.
  const generatedRows = (shoppingResult.data ?? []).filter((item) => item.source === 'generated');
  const groceryGeneration = {
    ranges: [...new Map(generatedRows.flatMap((item) => item.generated_from && item.generated_through
      ? [[`${item.generated_from}/${item.generated_through}`, { from: item.generated_from, through: item.generated_through }] as const]
      : [])).values()].sort((a, b) => a.from.localeCompare(b.from) || a.through.localeCompare(b.through)),
    unknownRange: generatedRows.some((item) => !item.generated_from || !item.generated_through),
  };
  for (const item of shoppingResult.data ?? []) {
    if (item.source === 'generated' && item.generated_active === false) continue;
    const food = item.food ? foods.get(item.food) : undefined;
    const pinnedProduct = item.pinned_product ? products.get(item.pinned_product) : undefined;
    const requiredProduct = item.generated_product ? products.get(item.generated_product) : undefined;
    const pricedProduct = requiredProduct ?? pinnedProduct ?? [...products.values()].filter((product) => product.food === item.food && product.estimated_cost !== null)
      .sort((left, right) => (productUnitCost(left) ?? Infinity) - (productUnitCost(right) ?? Infinity))[0];
    const itemUnit = item.unit ? units.get(item.unit) : undefined;
    const neededBase = food && itemUnit && item.qty_needed !== null ? toFoodBase(food, Number(item.qty_needed), itemUnit) : null;
    const remainingBase = neededBase === null ? null : Math.max(0, neededBase - Number(item.received_qty_base ?? 0));
    const shortageBase = Number(item.generated_shortage_base ?? 0);
    if (item.lot && remainingBase !== null && remainingBase <= INVENTORY_QUANTITY_EPSILON && shortageBase <= INVENTORY_QUANTITY_EPSILON) continue;
    const remainingDisplay = food && itemUnit && remainingBase !== null ? fromFoodBase(food, remainingBase, itemUnit) : null;
    const itemRate = productUnitCost(pricedProduct);
    const itemCost = neededBase !== null && itemRate !== null ? (remainingBase ?? neededBase) * itemRate : pricedProduct?.estimated_cost === null || pricedProduct?.estimated_cost === undefined ? null : Number(pricedProduct.estimated_cost);
    const category = food?.grocery_category ?? 'Pantry & other';
    const items = groceryGroups.get(category) ?? [];
    items.push({
      id: item.id,
      name: item.free_text ?? requiredProduct?.name ?? food?.name ?? 'Grocery item',
      requiredProductId: item.generated_product ?? undefined, requiredProductName: requiredProduct ? [requiredProduct.brand, requiredProduct.name].filter(Boolean).join(' · ') : undefined,
      foodId: item.food ?? undefined, pinnedProductId: item.pinned_product ?? undefined, unitId: item.unit ?? undefined,
      quantityNeeded: remainingDisplay ?? item.qty_needed ?? undefined, receiptLotId: item.lot ?? undefined,
      demandNotice: item.generated_demand_changed && food && itemUnit ? `Plan now needs ${formatQuantity(fromFoodBase(food, shortageBase, itemUnit), itemUnit.short_name)} more. Your check and quantity were kept.` : undefined,
      ...(item.lot && remainingDisplay !== null ? { quantity: `${formatQuantity(remainingDisplay, itemUnit?.short_name)} outstanding` } : shoppingQuantityPresentation(item.quantity_label, item.qty_needed === null ? null : Number(item.qty_needed), itemUnit?.short_name, item.source === 'generated')),
      checked: Boolean(item.checked_at),
      cost: itemCost,
    });
    groceryGroups.set(category, items);
  }
  const grocerySections = orderCategories([...groceryGroups.entries()]).map(([label, items]) => ({ emoji: categoryEmoji(label), label, items }));

  const settings = settingsResult.data;

  if (!settings) throw new Error('Personal settings are missing.');
  const logs = logsResult.data ?? [];
  const foodLogsById = new Map(logs.map((log) => [log.id, log]));
  const todayKey = dateKeyInZone(new Date(), settings.time_zone);
  const preparationHistory = (prepsResult.data ?? []).map((prep) => {
    const recipe = recipeRows.find((candidate) => candidate.id === prep.recipe);
    const lot = preparedLotByPrep.get(prep.id);
    return {
      id: prep.id,
      recipeId: prep.recipe,
      emoji: recipe?.emoji ?? '🥘',
      name: recipe?.name ?? 'Prepared batch',
      preparedAt: prep.prepped_at,
      dateKey: dateKeyInZone(new Date(prep.prepped_at), settings.time_zone),
      servingsMade: Number(prep.actual_yield_qty ?? lot?.initial_qty ?? 0),
      servingsRemaining: Number(lot?.remaining_qty ?? 0),
      location: lot?.location ?? 'unassigned',
    };
  }).sort((left, right) => right.preparedAt.localeCompare(left.preparedAt));
  const todayLogs = logs.filter((log) => dateKeyInZone(new Date(log.occurred_at), settings.time_zone) === todayKey);
  const nutrientSpec = [
    ['Calories', 'kcal', settings.nutrition_calories, 'cal', '#5fe0a0'],
    ['Protein', 'protein_g', settings.nutrition_protein_g, 'g', '#5fe0a0'],
    ['Carbs', 'carbs_g', settings.nutrition_carbs_g, 'g', '#57a8f2'],
    ['Fat', 'fat_g', settings.nutrition_fat_g, 'g', '#a184f5'],
    ['Fiber', 'fiber_g', settings.nutrition_fiber_g, 'g', '#f0b13f'],
    ['Sodium', 'sodium_mg', settings.nutrition_sodium_mg, 'mg', '#f2637a'],
  ] as const;
  const buildNutrients = (dayLogs: FoodLogRow[]) => nutrientSpec.map(([label, field, target, unit, color]) => {
    const value = sum(dayLogs, field);
    const incomplete = dayLogs.some((log) => log[field] === null);
    return { label, value: `${Math.round(value).toLocaleString()}${incomplete ? '+' : ''}${unit === 'cal' ? '' : ` ${unit}`}`, target: `/ ${Number(target).toLocaleString()} ${unit}`, pct: Math.min(100, Math.round(value / Number(target) * 100)), color };
  });
  const palette = ['#5fe0a0', '#57a8f2', '#a184f5', '#f0b13f', '#f2637a', '#35d6c8', '#f59e6b', '#f472b6'];
  const eventCostById = new Map((eventCostsResult.data ?? []).map((row) => [row.inventory_event_id ?? '', row.cost === null ? null : Number(row.cost)]));
  const eventsByLog = new Map<string, NonNullable<typeof eventsResult.data>>();
  for (const event of eventsResult.data ?? []) if (event.food_log) eventsByLog.set(event.food_log, [...(eventsByLog.get(event.food_log) ?? []), event]);
  const valueForLog = (log: FoodLogRow): CostValue => {
    const events = eventsByLog.get(log.id) ?? [];
    if (events.length) {
      let total = 0;
      let estimated = false;
      for (const event of events) {
        const exact = eventCostById.get(event.id);
        const lot = (lotsResult.data ?? []).find((candidate) => candidate.id === event.lot);
        const fallback = lot ? lotCost(lot, Math.abs(Number(event.quantity_delta)), products.get(lot.product ?? '')) : { cost: null, estimated: true, source: 'Price unavailable' };
        const cost = exact ?? fallback.cost;
        if (cost === null) return { cost: null, estimated: true, source: 'Price unavailable' };
        total += cost;
        estimated ||= exact === null || fallback.estimated;
      }
      return { cost: total, estimated, source: estimated ? 'Inventory estimate' : 'Inventory event cost' };
    }
    if (log.kind === 'manual') return { cost: log.total_price == null ? null : Number(log.total_price), estimated: log.cost_is_estimated, source: log.cost_source ?? 'Recorded food value' };
    if (log.cost !== null) return { cost: Number(log.cost), estimated: log.cost_is_estimated, source: log.cost_source ?? 'Directly logged cost' };
    const product = log.product ? products.get(log.product) : undefined;
    if (product?.estimated_cost !== null && product?.estimated_cost !== undefined) return { cost: estimatedProductPortionCost(product, Number(log.servings ?? 1)), estimated: true, source: product.cost_source ?? 'Product price estimate' };
    const recipe = log.recipe ? recipeCosts.get(log.recipe) : undefined;
    if (recipe?.costPerServing !== null && recipe?.costPerServing !== undefined) return { cost: recipe.costPerServing * Number(log.servings ?? 1), estimated: true, source: 'Recipe estimate' };
    return { cost: null, estimated: true, source: 'Price unavailable' };
  };
  // Personal food cost follows the portion eaten, not the acquisition date.
  // Prepared lots already carry paid amounts from their actual ingredient events.
  // Catalog estimates and economic value are never evidence of what the owner paid.
  const costForLog = (log: FoodLogRow): CostValue => {
    const events = (eventsByLog.get(log.id) ?? []).filter((event) => event.reason === 'eaten');
    if (events.length) {
      const portions = events.map((event) => {
        const lot = (lotsResult.data ?? []).find((candidate) => candidate.id === event.lot);
        return lot?.out_of_pocket_cost == null || !lot.initial_qty ? null
          : Number(lot.out_of_pocket_cost) * Math.abs(Number(event.quantity_delta)) / Number(lot.initial_qty);
      });
      return { cost: completeCost(portions), estimated: events.some((event) => (lotsResult.data ?? []).find((lot) => lot.id === event.lot)?.cost_is_estimated), source: 'Paid cost allocated from source lots' };
    }
    return { cost: log.out_of_pocket_cost == null ? null : Number(log.out_of_pocket_cost), estimated: log.cost_is_estimated, source: 'Recorded amount paid' };
  };
  const quantityCorrectionForLog = (log: FoodLogRow) => {
    if (!['inventory', 'prepared'].includes(log.kind)) return {};
    const events = eventsByLog.get(log.id) ?? [];
    const unavailable = { quantityCorrectionUnavailable: 'Quantity correction requires one exact source lot and cannot change a purchase-linked entry.' };
    if (events.length !== 1 || events[0].reason !== 'eaten' || events[0].quantity_delta >= 0 || (lotsResult.data ?? []).some((lot) => lot.acquisition_food_log === log.id)) return unavailable;
    const lot = (lotsResult.data ?? []).find((lot) => lot.id === events[0].lot);
    if (!lot) return unavailable;
    const product = lot.product ? products.get(lot.product) : undefined;
    const food = product ? foods.get(product.food) : undefined;
    if (!lot.prep && !food) return unavailable;
    const canonicalUnit = lot.prep ? 'servings' : food!.measure_style === 'weight' ? 'g' : food!.measure_style === 'volume' ? 'fl oz' : 'count';
    const unit = food?.display_unit ? units.get(food.display_unit) : undefined;
    const safeUnit = !lot.prep && unit && unit.measure_style === food?.measure_style ? unit : undefined;
    const displayPerBase = safeUnit && food ? fromFoodBase(food, 1, safeUnit) : 1;
    if (!Number.isFinite(displayPerBase) || displayPerBase <= 0) return unavailable;
    return { quantityCorrection: { quantity: -Number(events[0].quantity_delta), canonicalUnit, displayUnit: safeUnit?.short_name ?? canonicalUnit, displayPerBase, ...recordedCorrectionTotals(log), cost: costForLog(log).cost } };
  };
  const buildFoodLog = (dayLogs: FoodLogRow[]) => groupFoodLogRows(dayLogs).map((group, index) => {
    const log = group[0];
    const statuses = group.map((entry) => entry.nutrition_status);
    const nutritionStatus: NonNullable<FoodLogEntry['nutritionStatus']> = statuses.every((status) => status === 'complete')
      ? 'complete'
      : statuses.every((status) => status === 'unknown') ? 'unknown' : 'partial';
    const totalServings = group.every((entry) => entry.servings !== null)
      ? group.reduce((total, entry) => total + Number(entry.servings), 0)
      : null;
    const costs = group.map(costForLog);
    const cost = costs.every((value) => value.cost !== null)
      ? costs.reduce((total, value) => total + Number(value.cost), 0)
      : null;
    const oldest = group.at(-1)!;
    const formatTime = (entry: FoodLogRow) => entry.time_precision === 'dateOnly' ? 'Time not specified' : new Date(entry.occurred_at).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit', timeZone: settings.time_zone });
    const time = oldest.occurred_at === log.occurred_at ? formatTime(log) : `${formatTime(oldest)}–${formatTime(log)}`;
    const summedNutrition = foodLogNutrition(group);
    const serving = group.length === 1
      ? log.portion_label ?? (log.servings === null ? 'Portion not specified' : formatServings(Number(log.servings)))
      : `${totalServings === null ? 'Combined portions' : formatServings(totalServings)} · ${group.length} events`;
    const qualifier = nutritionStatus === 'unknown' ? ' · nutrition unknown' : nutritionStatus === 'partial' ? ' · partial nutrition' : group.some((entry) => entry.nutrition_is_estimated) ? ' · estimated' : '';
    return {
      id: log.id,
      eventIds: group.map((entry) => entry.id),
      events: group.map((entry) => ({ ...quantityCorrectionForLog(entry), ...(entry.kind === 'manual' && !entry.product && !entry.recipe ? { manual: { label: entry.label, portionLabel: entry.portion_label, note: entry.note, nutrition: { calories: entry.kcal, proteinG: entry.protein_g, carbsG: entry.carbs_g, fatG: entry.fat_g, fiberG: entry.fiber_g, sugarG: entry.sugar_g, sodiumMg: entry.sodium_mg, estimated: entry.nutrition_is_estimated, source: entry.nutrition_source } } } : {}), id: entry.id, label: entry.label, portion: entry.portion_label ?? (entry.servings === null ? 'Portion not specified' : formatServings(Number(entry.servings))), time: formatTime(entry), cost: costForLog(entry).cost, costIsEstimated: costForLog(entry).estimated, foodValue: valueForLog(entry).cost, foodValueIsEstimated: valueForLog(entry).estimated })),
      emoji: (log.product ? products.get(log.product)?.emoji ?? foods.get(products.get(log.product)?.food ?? '')?.emoji : undefined) ?? '🍽️',
      label: log.label,
      serving: `${serving}${qualifier}`,
      calories: group.every((entry) => entry.kcal === null) ? 'Calories unknown' : `${Math.round(sum(group, 'kcal'))} cal`,
      protein: group.every((entry) => entry.protein_g === null) ? 'Protein unknown' : `${Math.round(sum(group, 'protein_g'))} g protein`,
      time,
      color: palette[index % palette.length],
      nutrition: nutritionStatus === 'unknown' ? undefined : summedNutrition,
      nutritionStatus,
      cost,
      costIsEstimated: costs.some((value) => value.estimated),
      foodValue: completeCost(group.map((entry) => valueForLog(entry).cost)),
      foodValueIsEstimated: group.some((entry) => valueForLog(entry).estimated),
    };
  });
  const nutrients = buildNutrients(todayLogs);
  const foodLog = buildFoodLog(todayLogs);
  const nutritionIncompleteEntries = foodLog.filter((entry) => entry.nutritionStatus !== 'complete').length;

  const byDay = new Map<string, FoodLogRow[]>();
  for (const log of logs) {
    const key = dateKeyInZone(new Date(log.occurred_at), settings.time_zone);
    byDay.set(key, [...(byDay.get(key) ?? []), log]);
  }
  const foodLogByDate = Object.fromEntries([...byDay.entries()].map(([date, dayLogs]) => {
    const dayFoodLog = buildFoodLog(dayLogs);
    return [date, {
      nutrients: buildNutrients(dayLogs),
      foodLog: dayFoodLog,
      nutritionIncompleteEntries: dayFoodLog.filter((entry) => entry.nutritionStatus !== 'complete').length,
    }];
  }));
  // History carries the numbers the page renders rather than pre-formatted strings,
  // so the heat strip and stat strip derive from real rows instead of re-parsing text.
  const history = [...byDay.entries()].slice(0, 90).map(([date, dayLogs]) => {
    const parsed = new Date(`${date}T12:00:00`);
    const priced = dayLogs.every((log) => costForLog(log).cost !== null);
    return {
      dateKey: date,
      day: parsed.toLocaleDateString([], { weekday: 'long' }),
      date: parsed.toLocaleDateString([], { month: 'short', day: 'numeric' }).toUpperCase(),
      meals: dayLogs.map((log) => log.label),
      mealDetails: dayLogs.map((log) => ({
        id: log.id,
        label: log.label,
        emoji: (log.product ? products.get(log.product)?.emoji : undefined) ?? (log.recipe ? recipeRows.find((row) => row.id === log.recipe)?.emoji : undefined) ?? '🍽️',
        cost: costForLog(log).cost,
        costIsEstimated: costForLog(log).estimated,
      })),
      totals: `${Math.round(sum(dayLogs, 'kcal')).toLocaleString()} cal\n${Math.round(sum(dayLogs, 'protein_g'))} g protein`,
      calories: sum(dayLogs, 'kcal'),
      protein: sum(dayLogs, 'protein_g'),
      cost: priced ? dayLogs.reduce((total, log) => total + Number(costForLog(log).cost), 0) : null,
      mealsMissingCost: dayLogs.filter((log) => costForLog(log).cost === null).length,
      nutritionIncompleteEntries: dayLogs.filter((log) => log.nutrition_status !== 'complete').length,
    };
  });

  // Waste is a real series now: discards write 'waste' events, and the event-cost
  // view prices each one from the lot it came off. Nothing here is estimated into
  // existence — an unpriced discard contributes 0 rather than a guess.
  const wasteEvents = (eventsResult.data ?? []).filter((event) => event.reason === 'waste');
  const discardHistory = wasteEvents.map((event) => {
    const lot = lotsResult.data?.find((candidate) => candidate.id === event.lot);
    const prepared = allPreparedLots.find((batch) => batch.id === event.lot);
    const product = lot?.product ? products.get(lot.product) : undefined;
    const food = product ? foods.get(product.food) : undefined;
    const unit = food?.display_unit ? units.get(food.display_unit) : undefined;
    return {
      eventId: event.id,
      name: prepared?.name ?? product?.name ?? food?.name ?? 'Discarded food',
      occurredAt: event.occurred_at,
      dateKey: dateKeyInZone(new Date(event.occurred_at), settings.time_zone),
      quantity: lot?.prep ? formatServings(Math.abs(Number(event.quantity_delta))) : formatUsStock(Math.abs(Number(event.quantity_delta)), unit),
      reason: event.note,
      cost: eventCostById.get(event.id) ?? null,
    };
  }).sort((left, right) => right.occurredAt.localeCompare(left.occurredAt));
  const spendByDay = new Map<string, number>();
  for (const [date, dayLogs] of byDay) {
    spendByDay.set(date, dayLogs.reduce((total, log) => total + (costForLog(log).cost ?? 0), 0));
  }
  const wasteByDay = new Map<string, number>();
  for (const event of wasteEvents) {
    const key = dateKeyInZone(new Date(event.occurred_at), settings.time_zone);
    wasteByDay.set(key, (wasteByDay.get(key) ?? 0) + (eventCostById.get(event.id) ?? 0));
  }
  const outsideLogs = logs.filter((log) => log.kind === 'manual' || (eventsByLog.get(log.id) ?? []).some((event) => lotsResult.data?.find((lot) => lot.id === event.lot)?.is_external));
  const awayByDay = new Map<string, number>();
  for (const log of outsideLogs) {
    const key = dateKeyInZone(new Date(log.occurred_at), settings.time_zone);
    awayByDay.set(key, (awayByDay.get(key) ?? 0) + (costForLog(log).cost ?? 0));
  }
  const spendHistory = [...new Set([...spendByDay.keys(), ...wasteByDay.keys(), ...awayByDay.keys()])].sort().map((dateKey) => ({
    dateKey,
    spend: spendByDay.get(dateKey) ?? 0,
    spendMissingCost: (byDay.get(dateKey) ?? []).filter((log) => costForLog(log).cost === null).length,
    costIsEstimated: (byDay.get(dateKey) ?? []).some((log) => costForLog(log).estimated),
    wasteMissingCost: wasteEvents.filter((event) => dateKeyInZone(new Date(event.occurred_at), settings.time_zone) === dateKey && eventCostById.get(event.id) == null).length,
    awayMissingCost: outsideLogs.filter((log) => dateKeyInZone(new Date(log.occurred_at), settings.time_zone) === dateKey && costForLog(log).cost === null).length,
    waste: wasteByDay.get(dateKey) ?? 0,
    away: awayByDay.get(dateKey) ?? 0,
  }));

  // Three causes, each decided by what the lot actually was, not by a label.
  const wasteCauses = [
    { label: 'Expired in the fridge', note: 'produce and dairy', amount: 0 },
    { label: 'Prepared batches discarded', note: 'leftovers past date', amount: 0 },
    { label: 'Opened and forgotten', note: 'partial packages', amount: 0 },
  ];
  for (const event of wasteEvents) {
    const lot = lotsResult.data?.find((candidate) => candidate.id === event.lot);
    const cost = eventCostById.get(event.id) ?? 0;
    if (lot?.prep) wasteCauses[1].amount += cost;
    else if (lot?.use_by && lot.use_by <= dateKeyInZone(new Date(event.occurred_at), settings.time_zone)) wasteCauses[0].amount += cost;
    else wasteCauses[2].amount += cost;
  }

  const proteinTrend = Array.from({ length: 30 }, (_, index) => {
    const date = new Date();
    date.setHours(12, 0, 0, 0);
    date.setDate(date.getDate() - (29 - index));
    const key = dateKeyInZone(date, settings.time_zone);
    return { date: String(date.getDate()), value: sum(byDay.get(key) ?? [], 'protein_g') };
  });
  const recentCutoff = new Date();
  recentCutoff.setDate(recentCutoff.getDate() - 29);
  recentCutoff.setHours(0, 0, 0, 0);
  const recentLogs = logs.filter((log) => new Date(log.occurred_at) >= recentCutoff);
  const driverFields = { Protein: 'protein_g', Calories: 'kcal', Sodium: 'sodium_mg' } as const;
  const nutrientDrivers = Object.fromEntries(Object.entries(driverFields).map(([label, field]) => {
    const totals = new Map<string, number>();
    for (const log of recentLogs) totals.set(log.label, (totals.get(log.label) ?? 0) + Number(log[field] ?? 0));
    const grandTotal = [...totals.values()].reduce((total, value) => total + value, 0);
    const rows = [...totals.entries()].sort((left, right) => right[1] - left[1]).slice(0, 5).map(([foodLabel, value]) => ({
      label: foodLabel,
      pct: grandTotal ? Math.round(value / grandTotal * 100) : 0,
    }));
    return [label, rows];
  })) as PantryData['nutrientDrivers'];

  const plannedMeals: PantryData['plannedMeals'] = (plansResult.data ?? []).map((plan) => {
    const recipe = plan.recipe ? recipeRows.find((row) => row.id === plan.recipe) : undefined;
    const costedRecipe = recipe ? recipeCosts.get(recipe.id) : undefined;
    const exactLot = plan.inventory_lot ? (lotsResult.data ?? []).find((lot) => lot.id === plan.inventory_lot) : undefined;
    const productId = plan.product ?? exactLot?.product ?? undefined;
    const product = productId ? productViewsById.get(productId) : undefined;
    const lot = exactLot ? product?.availableLots.find((candidate) => candidate.id === exactLot.id) : undefined;
    const sourcePrep = prepByMealPlan.get(plan.source_meal_plan ?? plan.id);
    const sourceLot = sourcePrep ? preparedLotByPrep.get(sourcePrep.id) : undefined;
    const prepared = allPreparedLots.find((batch) => batch.id === (exactLot?.id ?? sourceLot?.id));
    const consumption = plannedConsumptions.get(plan.id);
    const prep = prepByMealPlan.get(plan.id);
    const servings = Number(consumption?.servings ?? 1);
    const sourceKind = plan.inventory_lot ? 'lot' : plan.product ? 'product' : 'recipe';
    const sourceAvailable = plan.inventory_lot ? (prepared?.servingsLeft ?? lot?.remainingServings ?? 0) : undefined;
    const monday = new Date(plan.plan_date + 'T12:00:00Z');
    monday.setUTCDate(monday.getUTCDate() - (monday.getUTCDay() + 6) % 7);
    const weekStart = monday.toISOString().slice(0, 10); monday.setUTCDate(monday.getUTCDate() + 7);
    const weekEnd = monday.toISOString().slice(0, 10);
    const exactDemand = plan.inventory_lot ? (plansResult.data ?? []).filter((row) => row.inventory_lot === plan.inventory_lot && ['planned', 'made'].includes(row.status) && row.plan_date >= weekStart && row.plan_date < weekEnd && plannedConsumptions.get(row.id)?.status === 'planned').reduce((sum, row) => sum + Number(plannedConsumptions.get(row.id)?.servings ?? 0), 0) : 0;
    const nutrition = prepared?.nutritionPerServing
      ? Object.fromEntries(Object.entries(prepared.nutritionPerServing).map(([label, value]) => [label, value * servings])) as NutritionValues
      : product
      ? Object.fromEntries(Object.entries(product.nutritionPerServing).map(([label, value]) => [label, value * servings])) as NutritionValues
      : costedRecipe
        ? nutritionForServings(costedRecipe.nutritionValues, costedRecipe.servings, servings)
        : emptyNutrition();
    const portionCost = prepared
      ? prepared.costPerServing === null ? null : prepared.costPerServing * servings
      : product
      ? (lot?.costPerServing ?? product.costPerServing) === null ? null : Number(lot?.costPerServing ?? product.costPerServing) * servings
      : costedRecipe?.costPerServing === null || costedRecipe?.costPerServing === undefined
        ? null
        : costedRecipe.costPerServing * servings;
    return {
      id: plan.id,
      groupId: plan.group_id ?? plan.id,
      sourceGroupId: plan.leftover_of_group_id ?? undefined,
      dateKey: plan.plan_date,
      slot: plan.daypart.toUpperCase(),
      name: plan.name ?? prepared?.name ?? recipe?.name ?? product?.label ?? 'Planned item',
      emoji: plan.emoji ?? prepared?.emoji ?? recipe?.emoji ?? product?.emoji ?? '🍽️',
      recipeId: recipe?.id,
      productId,
      inventoryLotId: plan.inventory_lot ?? undefined,
      sourceServingsAvailable: sourceAvailable,
      sourceShortfall: sourceAvailable !== undefined && consumption?.status === 'planned' && exactDemand > sourceAvailable + INVENTORY_QUANTITY_EPSILON ? 'Selected lot is short for this week. Adjust portions or remove a plan.' : undefined,
      sourceKind,
      consumeFromInventory: plan.consume_from_inventory ?? undefined,
      status: plan.status,
      ...(plan.recipe || exactLot?.prep ? preparedPlanAvailability(plan, plansResult.data ?? [], prepsResult.data ?? [], lotsResult.data ?? []) : {}),
      isLeftover: plan.intent === 'leftover' || Boolean(exactLot?.prep),
      scaleFactor: Number(plan.scale_factor),
      plannedServings: servings,
      actualServings: consumption?.food_log ? Number(foodLogsById.get(consumption.food_log)?.servings ?? 0) : undefined,
      consumptionStatus: consumption?.status ?? 'planned',
      prepId: prep?.id,
      preparedLotId: prep ? preparedLotByPrep.get(prep.id)?.id : undefined,
      cost: portionCost,
      costIsEstimated: prepared?.costIsEstimated ?? (product ? (lot?.costIsEstimated ?? true) : Boolean(costedRecipe?.costIsEstimated)),
      nutrition,
    };
  });

  const start = new Date(`${todayKey}T12:00:00`);
  start.setHours(12, 0, 0, 0);
  start.setDate(start.getDate() - ((start.getDay() + 6) % 7));
  const weekDays = Array.from({ length: 7 }, (_, offset) => {
    const date = new Date(start);
    date.setDate(start.getDate() + offset);
    const key = dateKeyInZone(date, settings.time_zone);
    const meals = plannedMeals.filter((plan) => plan.dateKey === key);
    return { day: date.toLocaleDateString([], { weekday: 'short' }).toUpperCase(), date: String(date.getDate()), dateKey: key, today: key === todayKey, meals };
  });
  const nutritionHistory = [...byDay.entries()].map(([dateKey, dayLogs]) => ({
    dateKey,
    label: new Date(`${dateKey}T12:00:00`).toLocaleDateString([], { month: 'short', day: 'numeric' }),
    values: Object.fromEntries(Object.entries(nutrientFields).map(([label, field]) => [label, sum(dayLogs, field)])) as NutritionValues,
    nutritionIncompleteEntries: dayLogs.filter((log) => log.nutrition_status !== 'complete').length,
    foods: dayLogs.map((log) => ({ label: log.label, values: nutritionValues(log) })),
  }));
  const todayProjection = plannedMeals.filter((plan) => plan.dateKey === todayKey && plan.status === 'planned' && plan.consumptionStatus === 'planned').reduce((totals, plan) => {
    for (const label of Object.keys(totals) as NutrientName[]) totals[label] += plan.nutrition?.[label] ?? 0;
    return totals;
  }, emptyNutrition());

  return {
    inventorySections,
    recipes,
    grocerySections,
    groceryGeneration,
    receiptHistory,
    discardHistory,
    nutrients,
    weekDays,
    plannedMeals,
    foodLog,
    nutritionIncompleteEntries,
    foodLogByDate,
    history,
    foods: [...foods.values()].map((food) => ({ id: food.id, name: food.name, emoji: food.emoji ?? '🍽️', measureStyle: food.measure_style })),
    products: productViews,
    units: [...units.values()].map((unit) => ({ id: unit.id, label: `${unit.full_name} (${unit.short_name})`, shortName: unit.short_name, measureStyle: unit.measure_style })),
    categories: (categoriesResult.data ?? []).map((category) => category.category),
    locations: (locationsResult.data ?? []).map((location) => location.location),
    settings: {
      calories: Number(settings.nutrition_calories),
      proteinG: Number(settings.nutrition_protein_g),
      carbsG: Number(settings.nutrition_carbs_g),
      fatG: Number(settings.nutrition_fat_g),
      fiberG: Number(settings.nutrition_fiber_g),
      sodiumMg: Number(settings.nutrition_sodium_mg),
      allergies: settings.allergies,
      dietaryRules: settings.dietary_rules,
      dislikes: settings.dislikes,
      favorites: settings.favorites,
      timeZone: settings.time_zone,
      planningNotes: settings.planning_notes ?? '',
      weeklyFoodBudget: Number(settings.weekly_food_budget ?? DEFAULT_WEEKLY_FOOD_BUDGET),
    },
    preparedLots,
    preparationHistory,
    spendHistory,
    wasteCauses,
    proteinTrend,
    nutrientDrivers,
    nutritionHistory,
    todayProjection,
  };
}

export async function setShoppingItemChecked(client: Client, id: string, checked: boolean) {
  const { error } = await client.from('shopping_items').update({ checked_at: checked ? new Date().toISOString() : null }).eq('id', id);
  if (error) throw error;
}

export async function correctConsumedQuantity(client: Client, id: string, expectedQuantity: number, quantity: number): Promise<string> {
  return runRetryableMutation(client, 'correct_consumed_quantity', { id, expectedQuantity, quantity }, async (requestId, _time, submitted) => {
    const { data, error } = await client.rpc('correct_consumed_quantity', { p_request_id: requestId, p_food_log: submitted.id, p_expected_quantity: submitted.expectedQuantity, p_quantity: submitted.quantity });
    if (error) throw error;
    const result = data as { id?: string } | null;
    if (!result?.id) throw new Error('Correction result could not be confirmed. Retry this correction.');
    return result.id;
  }, { id });
}

export async function updateFoodLog(client: Client, id: string, patch: Json) {
  const { error } = await client.rpc('gpt_update_consumption', { p_food_log: id, p_patch: patch });
  if (error) throw error;
}

export async function voidFoodLog(client: Client, id: string) {
  const { error } = await client.rpc('void_food_log', { p_food_log: id });
  if (error) throw error;
}

export async function restoreFoodLog(client: Client, id: string) {
  const { error } = await client.rpc('restore_food_log', { p_food_log: id });
  if (error) throw error;
}

export async function undoInventoryAdjustment(client: Client, eventId: string) {
  const { error } = await client.rpc('undo_inventory_adjustment', { p_event: eventId });
  if (error) throw error;
}

export async function undoPrep(client: Client, prepId: string) {
  const { error } = await client.rpc('undo_prep', { p_prep: prepId });
  if (error) throw error;
}

export async function cookRecipe(client: Client, recipeId: string, options: PreparationOptions = {}): Promise<PreparationResult> {
  return runRetryableMutation(client, 'prepare_recipe', { recipeId, options }, async (requestId, occurredAt, submitted) => {
    const { recipeId: submittedRecipeId, options: savedOptions } = submitted;
    const { data, error } = await client.rpc('prepare_recipe', {
      p_recipe: submittedRecipeId, p_request_id: requestId, p_occurred_at: occurredAt,
      p_scale: savedOptions.scale ?? 1,
      ...(savedOptions.servingsMade === undefined ? {} : { p_servings: savedOptions.servingsMade }),
      p_location: savedOptions.location ?? 'fridge',
      ...(savedOptions.mealPlanId ? { p_meal_plan: savedOptions.mealPlanId } : {}),
      p_eaten_servings: savedOptions.servingsEaten ?? 0,
      ...(savedOptions.pieceInputs?.length ? { p_piece_inputs: savedOptions.pieceInputs.map((input) => ({ ...input, ...(savedOptions.useIngredientNutrition ? { useIngredientNutrition: true } : {}) })) } : {}),
    });
    if (error) throw error;
    const result = data as Record<string, unknown>;
    return {
      prepId: String(result.prepId), lotId: String(result.lotId),
      mealPlanId: result.mealPlanId ? String(result.mealPlanId) : null,
      servingsMade: Number(result.servingsMade), servingsRemaining: Number(result.servingsRemaining),
      location: String(result.location), foodLogId: result.foodLogId ? String(result.foodLogId) : null,
    };
  }, cookingAttemptIdentity(recipeId, options));
}

export async function savePrepFeedback(client: Client, prepId: string, ease: number, taste: number, actualMinutes: number) {
  const { error } = await client.rpc('save_prep_feedback', { p_prep: prepId, p_ease: ease, p_taste: taste, p_actual_minutes: actualMinutes });
  if (error) throw error;
}

export async function removePlannedMeal(client: Client, planId: string) {
  const { error } = await client.from('meal_plans').delete().eq('id', planId);
  if (error) throw error;
}

export async function removePlannedMeals(client: Client, planIds: string[]) {
  const { error } = await client.from('meal_plans').delete().in('id', planIds);
  if (error?.code === '23503') throw new Error('This preparation still supplies future leftovers. Remove those leftover plans or reassign them to a cooked batch first.');
  if (error) throw error;
}

export async function consumePlannedMeals(client: Client, consumptions: PlannedMealConsumption[]) {
  return runRetryableMutation(client, 'consume_planned_meals', consumptions, async (requestId, occurredAt) => {
  const { data, error } = await client.rpc('consume_planned_meals', { p_request_id: requestId, p_occurred_at: occurredAt,
    p_meal_plans: consumptions.map((consumption) => consumption.mealPlanId),
    p_servings: consumptions.map((consumption) => consumption.servings),
  });
  if (error) throw error;
  return data;
  });
}

export async function setPlannedConsumptionServings(client: Client, planId: string, servings: number) {
  if (!Number.isFinite(servings) || servings <= 0) throw new Error('Planned servings must be positive.');
  const { error } = await client.from('planned_consumptions').update({ servings }).eq('meal_plan', planId).eq('status', 'planned').select('id').single();
  if (error) throw error;
}

export async function removeShoppingItem(client: Client, itemId: string) {
  const { error } = await client.from('shopping_items').delete().eq('id', itemId);
  if (error) throw error;
}

export async function consumeInventoryLot(client: Client, lotId: string, quantity: number) {
  return runRetryableMutation(client, 'consume_inventory_lot', { lotId, quantity }, async (requestId, occurredAt) => {
  const { data, error } = await client.rpc('consume_inventory_lot', { p_request_id: requestId, p_occurred_at: occurredAt, p_lot: lotId, p_quantity: quantity });
  if (error) throw error;
  return data;
  });
}

export async function setInventoryLotQuantity(client: Client, lotId: string, remaining: number, discard = false, reason = '') {
  return runRetryableMutation(client, 'set_inventory_lot_quantity', { lotId, remaining, discard, reason }, async (requestId) => {
  const { data, error } = await client.rpc('set_inventory_lot_quantity', { p_request_id: requestId, p_lot: lotId, p_remaining: remaining, p_discard: discard, p_note: reason });
  if (error) throw error;
  return data;
  });
}

export async function cookRecipes(client: Client, recipeIds: string[]) {
  return runRetryableMutation(client, 'cook_recipes', recipeIds, async (requestId) => {
  const { error } = await client.rpc('cook_recipes', { p_request_id: requestId, p_recipes: recipeIds });
  if (error) throw error;
  });
}

export async function consumePreparedLot(client: Client, lotId: string, quantity = 1) {
  return runRetryableMutation(client, 'consume_prepared_lot', { lotId, quantity }, async (requestId, occurredAt) => {
  const { data, error } = await client.rpc('consume_prepared_lot', { p_request_id: requestId, p_occurred_at: occurredAt, p_lot: lotId, p_quantity: quantity });
  if (error) throw error;
  return data;
  });
}

export async function rebuildShoppingFromPlan(client: Client, range: PlanningRange) {
  const { data, error } = await client.rpc('rebuild_shopping_from_plan', {
    p_from: range.from,
    p_through: range.through,
  });
  if (error) throw error;
  return data;
}

export async function receiveShoppingItem(client: Client, itemId: string, receipt: ShoppingReceipt) {
  await runRetryableMutation(client, 'receive_shopping_item', { itemId, receipt }, async (requestId, occurredAt, submitted) => {
    const { error } = await client.rpc('receive_shopping_item', { p_request_id: requestId, p_item: submitted.itemId, p_receipt: { ...submitted.receipt, acquiredAt: occurredAt } });
    if (error) throw error;
  });
}
export async function undoInventoryReceipt(client: Client, lotId: string) {
  await runRetryableMutation(client, 'undo_inventory_receipt', { lotId }, async (requestId) => {
    const { error } = await client.rpc('undo_inventory_receipt', { p_request_id: requestId, p_lot: lotId });
    if (error) throw error;
  });
}
