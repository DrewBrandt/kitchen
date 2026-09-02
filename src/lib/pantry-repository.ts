import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '../database.types';
import type { NutritionValues, NutrientName, PantryData, PlannedMealConsumption, PreparationOptions, PreparationResult } from '../pantry-data';
import { DEFAULT_WEEKLY_FOOD_BUDGET, perServingCost, remainingValue } from './cost';
import { nutritionForServings } from './nutrition';

type Client = SupabaseClient<Database>;
type FoodLogRow = Database['public']['Tables']['food_logs']['Row'];
type LotRow = Database['public']['Tables']['inventory_lots']['Row'];
type ProductRow = Database['public']['Tables']['products']['Row'];

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

const formatQuantity = (value: number, unit?: string | null) => {
  const rounded = Math.abs(value - Math.round(value)) < 0.01 ? Math.round(value) : Number(value.toFixed(1));
  return `${rounded} ${unit ?? ''}`.trim();
};

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
  if (unit?.short_name === 'oz' && converted >= 16) {
    const pounds = Math.floor(converted / 16);
    const ounces = converted - pounds * 16;
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

const pluralize = (name: string, plural: string | null | undefined, quantity: number) => {
  if (Math.abs(quantity - 1) < 0.001) return name;
  if (plural) return plural;
  if (/(s|x|z|ch|sh)$/i.test(name)) return `${name}es`;
  if (/[^aeiou]y$/i.test(name)) return `${name.slice(0, -1)}ies`;
  return `${name}s`;
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

const dateKeyInZone = (date: Date, timeZone: string) => {
  try {
    const parts = new Intl.DateTimeFormat('en-US', { year: 'numeric', month: '2-digit', day: '2-digit', timeZone }).formatToParts(date);
    const value = (type: Intl.DateTimeFormatPartTypes) => parts.find((part) => part.type === type)?.value ?? '';
    return `${value('year')}-${value('month')}-${value('day')}`;
  } catch {
    return date.toLocaleDateString('en-CA');
  }
};

export async function loadPantryData(client: Client): Promise<PantryData> {
  const [foodsResult, productsResult, lotsResult, unitsResult, categoriesResult, locationsResult, recipesResult, ingredientsResult, prepsResult, shoppingResult, plansResult, plannedConsumptionsResult, logsResult, settingsResult, eventsResult, eventCostsResult] = await Promise.all([
    client.from('base_foods').select('*'),
    client.from('products').select('*'),
    client.from('inventory_lots').select('*'),
    client.from('measure_conversions').select('*'),
    client.from('grocery_categories').select('*').order('sort_order'),
    client.from('locations').select('*').order('sort_order'),
    client.from('recipes').select('*').order('name'),
    client.from('recipe_ingredients').select('*').order('sort_order'),
    client.from('preps').select('*').is('voided_at', null),
    client.from('shopping_items').select('*').is('lot', null).order('created_at'),
    client.from('meal_plans').select('*').order('plan_date'),
    client.from('planned_consumptions').select('*'),
    client.from('food_logs').select('*').is('voided_at', null).order('occurred_at', { ascending: false }),
    client.from('personal_settings').select('*').single(),
    client.from('inventory_events').select('*').is('voided_at', null).or('food_log.not.is.null,reason.eq.waste'),
    client.from('inventory_event_costs').select('*'),
  ]);

  const firstError = [foodsResult, productsResult, lotsResult, unitsResult, categoriesResult, locationsResult, recipesResult, ingredientsResult, prepsResult, shoppingResult, plansResult, plannedConsumptionsResult, logsResult, settingsResult, eventsResult, eventCostsResult]
    .find((result) => result.error)?.error;
  if (firstError) throw firstError;

  const foods = new Map((foodsResult.data ?? []).map((food) => [food.id, food]));
  const products = new Map((productsResult.data ?? []).map((product) => [product.id, product]));
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
        lots: stockLots.map((lot) => `${formatUsStock(Number(lot.remaining_qty), displayUnit)} ${lot.location ?? 'unassigned'} · ${formatCost(lotCost(lot, Number(lot.remaining_qty), products.get(lot.product ?? '')))}`),
        cost: knownCosts.length === stockLots.length ? knownCosts.reduce((total, value) => total + value, 0) : null,
        costIsEstimated: costValues.some((value) => value.estimated),
        lotDetails: stockLots.map((lot) => {
          const lotDue = daysUntil(lot.use_by);
          const value = lotCost(lot, Number(lot.remaining_qty), products.get(lot.product ?? ''));
          const remainingBase = Number(lot.remaining_qty);
          const remainingDisplay = displayUnit ? fromFoodBase(food, remainingBase, displayUnit) : remainingBase;
          const displayPerBase = displayUnit ? fromFoodBase(food, 1, displayUnit) : 1;
          return { id: lot.id, quantity: formatUsStock(remainingBase, displayUnit), location: lot.location ?? 'unassigned', dateLabel: lotDue.label, tone: lotDue.tone, remainingBase, remainingDisplay, displayUnit: displayUnit?.short_name ?? '', displayPerBase, cost: value.cost, costIsEstimated: value.estimated, costSource: value.source };
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
      servings: Number(recipe.servings),
      minutes: Math.max(10, steps.length * 5),
      nutrition: `${kcal ? `${Math.round(kcal / Number(recipe.servings))} cal · ${Math.round(protein / Number(recipe.servings))} g protein per serving` : 'Nutrition calculated from ingredients'} · ${formatCost({ cost: estimatedCost, estimated: ingredientCosts.some((value) => value.estimated), source: 'Recipe ingredients' })} batch`,
      ingredients: recipeIngredients.map((ingredient) => {
        const food = foods.get(ingredient.ingredient);
        const unit = units.get(ingredient.unit);
        const requestedQuantity = Number(ingredient.qty);
        if (!food || !unit) return { label: `${formatRecipeQuantity(requestedQuantity)} Ingredient`, stock: 'Unit unavailable · short' };
        const ingredientName = pluralize(food.name, food.plural, requestedQuantity);
        if (food.always_available) return { label: `${formatRecipeQuantity(requestedQuantity, unit.short_name)} ${ingredientName}`, stock: 'Always available' };
        const neededBase = toFoodBase(food, Number(ingredient.qty), unit);
        const availableBase = stockByFood.get(ingredient.ingredient) ?? 0;
        const enough = availableBase + 0.0000001 >= neededBase;
        const availableInRequestedUnit = fromFoodBase(food, availableBase, unit);
        return { label: `${formatRecipeQuantity(requestedQuantity, unit.short_name)} ${ingredientName}`, stock: `${formatRecipeQuantity(availableInRequestedUnit, unit.short_name)} in stock${enough ? '' : ' · short'}` };
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
  const plannedConsumptions = new Map((plannedConsumptionsResult.data ?? []).map((consumption) => [consumption.meal_plan, consumption]));
  const prepByMealPlan = new Map((prepsResult.data ?? []).filter((prep) => prep.meal_plan).map((prep) => [prep.meal_plan!, prep]));
  const preparedLotByPrep = new Map((lotsResult.data ?? []).filter((lot) => lot.prep).map((lot) => [lot.prep!, lot]));

  const preparedLots = availableLots.filter((lot) => lot.prep).map((lot) => {
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

  const groceryGroups = new Map<string, PantryData['grocerySections'][number]['items']>();
  for (const item of shoppingResult.data ?? []) {
    const food = item.food ? foods.get(item.food) : undefined;
    const pinnedProduct = item.pinned_product ? products.get(item.pinned_product) : undefined;
    const pricedProduct = pinnedProduct ?? [...products.values()].filter((product) => product.food === item.food && product.estimated_cost !== null)
      .sort((left, right) => (productUnitCost(left) ?? Infinity) - (productUnitCost(right) ?? Infinity))[0];
    const itemUnit = item.unit ? units.get(item.unit) : undefined;
    const neededBase = food && itemUnit && item.qty_needed !== null ? toFoodBase(food, Number(item.qty_needed), itemUnit) : null;
    const itemRate = productUnitCost(pricedProduct);
    const itemCost = neededBase !== null && itemRate !== null ? neededBase * itemRate : pricedProduct?.estimated_cost === null || pricedProduct?.estimated_cost === undefined ? null : Number(pricedProduct.estimated_cost);
    const category = food?.grocery_category ?? 'Pantry & other';
    const items = groceryGroups.get(category) ?? [];
    items.push({
      id: item.id,
      name: item.free_text ?? food?.name ?? 'Grocery item',
      quantity: item.quantity_label ?? (item.qty_needed ? formatQuantity(Number(item.qty_needed), units.get(item.unit ?? '')?.short_name) : 'As needed'),
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
  const costForLog = (log: FoodLogRow): CostValue => {
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
    if (log.cost !== null) return { cost: Number(log.cost), estimated: log.cost_is_estimated, source: log.cost_source ?? 'Directly logged cost' };
    const product = log.product ? products.get(log.product) : undefined;
    if (product?.estimated_cost !== null && product?.estimated_cost !== undefined) return { cost: Number(product.estimated_cost) * Number(log.servings ?? 1), estimated: true, source: product.cost_source ?? 'Product price estimate' };
    const recipe = log.recipe ? recipeCosts.get(log.recipe) : undefined;
    if (recipe?.costPerServing !== null && recipe?.costPerServing !== undefined) return { cost: recipe.costPerServing * Number(log.servings ?? 1), estimated: true, source: 'Recipe estimate' };
    return { cost: null, estimated: true, source: 'Price unavailable' };
  };
  const buildFoodLog = (dayLogs: FoodLogRow[]) => dayLogs.map((log, index) => ({
    id: log.id,
    emoji: (log.product ? products.get(log.product)?.emoji ?? foods.get(products.get(log.product)?.food ?? '')?.emoji : undefined) ?? '🍽️',
    label: log.label,
    serving: `${log.portion_label ?? (log.servings === null ? 'Portion not specified' : `${Number(log.servings)} serving${Number(log.servings) === 1 ? '' : 's'}`)}${log.nutrition_status === 'unknown' ? ' · nutrition unknown' : log.nutrition_status === 'partial' ? ' · partial nutrition' : log.nutrition_is_estimated ? ' · estimated' : ''}`,
    calories: log.kcal === null ? 'Calories unknown' : `${Math.round(Number(log.kcal))} cal`,
    protein: log.protein_g === null ? 'Protein unknown' : `${Math.round(Number(log.protein_g))} g protein`,
    time: new Date(log.occurred_at).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' }),
    color: palette[index % palette.length],
    nutrition: log.nutrition_status === 'unknown' ? undefined : nutritionValues(log),
    nutritionStatus: log.nutrition_status as 'complete' | 'partial' | 'unknown',
    cost: costForLog(log).cost,
    costIsEstimated: costForLog(log).estimated,
  }));
  const nutrients = buildNutrients(todayLogs);
  const foodLog = buildFoodLog(todayLogs);
  const nutritionIncompleteEntries = todayLogs.filter((log) => log.nutrition_status !== 'complete').length;

  const byDay = new Map<string, FoodLogRow[]>();
  for (const log of logs) {
    const key = dateKeyInZone(new Date(log.occurred_at), settings.time_zone);
    byDay.set(key, [...(byDay.get(key) ?? []), log]);
  }
  const foodLogByDate = Object.fromEntries([...byDay.entries()].map(([date, dayLogs]) => [date, {
    nutrients: buildNutrients(dayLogs),
    foodLog: buildFoodLog(dayLogs),
    nutritionIncompleteEntries: dayLogs.filter((log) => log.nutrition_status !== 'complete').length,
  }]));
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
  const spendByDay = new Map<string, number>();
  for (const [date, dayLogs] of byDay) {
    spendByDay.set(date, dayLogs.reduce((total, log) => total + (costForLog(log).cost ?? 0), 0));
  }
  const wasteByDay = new Map<string, number>();
  for (const event of wasteEvents) {
    const key = dateKeyInZone(new Date(event.occurred_at), settings.time_zone);
    wasteByDay.set(key, (wasteByDay.get(key) ?? 0) + (eventCostById.get(event.id) ?? 0));
  }
  const awayByDay = new Map<string, number>();
  for (const event of eventsResult.data ?? []) {
    if (event.reason !== 'eaten') continue;
    const lot = lotsResult.data?.find((candidate) => candidate.id === event.lot);
    if (!lot?.is_external) continue;
    const key = dateKeyInZone(new Date(event.occurred_at), settings.time_zone);
    awayByDay.set(key, (awayByDay.get(key) ?? 0) + (eventCostById.get(event.id) ?? 0));
  }
  const spendHistory = [...new Set([...spendByDay.keys(), ...wasteByDay.keys(), ...awayByDay.keys()])].sort().map((dateKey) => ({
    dateKey,
    spend: spendByDay.get(dateKey) ?? 0,
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

  const start = new Date(`${todayKey}T12:00:00`);
  start.setHours(12, 0, 0, 0);
  start.setDate(start.getDate() - ((start.getDay() + 6) % 7));
  const weekDays = Array.from({ length: 7 }, (_, offset) => {
    const date = new Date(start);
    date.setDate(start.getDate() + offset);
    const key = dateKeyInZone(date, settings.time_zone);
    const meals = (plansResult.data ?? []).filter((plan) => plan.plan_date === key).map((plan) => {
      const recipe = plan.recipe ? recipeRows.find((row) => row.id === plan.recipe) : undefined;
      const costedRecipe = recipe ? recipeCosts.get(recipe.id) : undefined;
      const consumption = plannedConsumptions.get(plan.id);
      const prep = prepByMealPlan.get(plan.id);
      return { id: plan.id, groupId: plan.group_id ?? plan.id, slot: plan.daypart.toUpperCase(), name: plan.name ?? recipe?.name ?? 'Planned meal', emoji: plan.emoji ?? recipe?.emoji ?? '🍽️', recipeId: recipe?.id, status: plan.status, isLeftover: plan.intent === 'leftover', scaleFactor: Number(plan.scale_factor), plannedServings: Number(consumption?.servings ?? 1), actualServings: consumption?.food_log ? Number(foodLogsById.get(consumption.food_log)?.servings ?? 0) : undefined, consumptionStatus: consumption?.status ?? 'planned', prepId: prep?.id, preparedLotId: prep ? preparedLotByPrep.get(prep.id)?.id : undefined, cost: plan.intent === 'leftover' ? 0 : costedRecipe?.estimatedCost === null || costedRecipe?.estimatedCost === undefined ? null : costedRecipe.estimatedCost * Number(plan.scale_factor), costIsEstimated: plan.intent !== 'leftover' && Boolean(costedRecipe?.costIsEstimated) };
    });
    return { day: date.toLocaleDateString([], { weekday: 'short' }).toUpperCase(), date: String(date.getDate()), dateKey: key, today: key === todayKey, meals };
  });

  const plannedMeals = (plansResult.data ?? []).map((plan) => {
    const recipe = plan.recipe ? recipeRows.find((row) => row.id === plan.recipe) : undefined;
    const costedRecipe = recipe ? recipeCosts.get(recipe.id) : undefined;
    const consumption = plannedConsumptions.get(plan.id);
    const prep = prepByMealPlan.get(plan.id);
    return { id: plan.id, groupId: plan.group_id ?? plan.id, sourceGroupId: plan.leftover_of_group_id ?? undefined, dateKey: plan.plan_date, slot: plan.daypart.toUpperCase(), name: plan.name ?? recipe?.name ?? 'Planned meal', emoji: plan.emoji ?? recipe?.emoji ?? '🍽️', recipeId: recipe?.id, status: plan.status, isLeftover: plan.intent === 'leftover', scaleFactor: Number(plan.scale_factor), plannedServings: Number(consumption?.servings ?? 1), actualServings: consumption?.food_log ? Number(foodLogsById.get(consumption.food_log)?.servings ?? 0) : undefined, consumptionStatus: consumption?.status ?? 'planned', prepId: prep?.id, preparedLotId: prep ? preparedLotByPrep.get(prep.id)?.id : undefined, cost: plan.intent === 'leftover' ? 0 : costedRecipe?.estimatedCost === null || costedRecipe?.estimatedCost === undefined ? null : costedRecipe.estimatedCost * Number(plan.scale_factor), costIsEstimated: plan.intent !== 'leftover' && Boolean(costedRecipe?.costIsEstimated) };
  });
  const nutritionHistory = [...byDay.entries()].map(([dateKey, dayLogs]) => ({
    dateKey,
    label: new Date(`${dateKey}T12:00:00`).toLocaleDateString([], { month: 'short', day: 'numeric' }),
    values: Object.fromEntries(Object.entries(nutrientFields).map(([label, field]) => [label, sum(dayLogs, field)])) as NutritionValues,
    nutritionIncompleteEntries: dayLogs.filter((log) => log.nutrition_status !== 'complete').length,
    foods: dayLogs.map((log) => ({ label: log.label, values: nutritionValues(log) })),
  }));
  const todayProjection = (plansResult.data ?? []).filter((plan) => plan.plan_date === todayKey && plan.status === 'planned' && plannedConsumptions.get(plan.id)?.status === 'planned').reduce((totals, plan) => {
    const recipe = plan.recipe ? recipeCosts.get(plan.recipe) : undefined;
    if (!recipe) return totals;
    const servings = Number(plannedConsumptions.get(plan.id)?.servings ?? 1);
    const values = nutritionForServings(recipe.nutritionValues, recipe.servings, servings);
    for (const label of Object.keys(totals) as NutrientName[]) totals[label] += values[label];
    return totals;
  }, emptyNutrition());

  return {
    inventorySections,
    recipes,
    grocerySections,
    nutrients,
    weekDays,
    plannedMeals,
    foodLog,
    nutritionIncompleteEntries,
    foodLogByDate,
    history,
    foods: [...foods.values()].map((food) => ({ id: food.id, name: food.name, emoji: food.emoji ?? '🍽️', measureStyle: food.measure_style })),
    products: [...products.values()].map((product) => ({
      id: product.id,
      foodId: product.food,
      foodName: foods.get(product.food)?.name ?? 'Food',
      name: product.name,
      label: [product.brand, product.name].filter(Boolean).join(' · '),
      brand: product.brand ?? '',
      barcode: product.barcode ?? '',
      estimatedCost: product.estimated_cost === null ? null : Number(product.estimated_cost),
      costSource: product.cost_source ?? '',
      costAsOf: product.cost_as_of ?? '',
      emoji: product.emoji ?? foods.get(product.food)?.emoji ?? '🍽️',
      nutrition: nutritionValues(product),
      useCount: product.use_count,
      lastUsedAt: product.last_used_at ?? '',
    })),
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
  const { data, error } = await client.rpc('prepare_recipe', {
    p_recipe: recipeId,
    p_scale: options.scale ?? 1,
    ...(options.servingsMade === undefined ? {} : { p_servings: options.servingsMade }),
    p_location: options.location ?? 'fridge',
    ...(options.mealPlanId ? { p_meal_plan: options.mealPlanId } : {}),
    p_eaten_servings: options.servingsEaten ?? 0,
  });
  if (error) throw error;
  const result = data as Record<string, unknown>;
  return {
    prepId: String(result.prepId),
    lotId: String(result.lotId),
    mealPlanId: result.mealPlanId ? String(result.mealPlanId) : null,
    servingsMade: Number(result.servingsMade),
    servingsRemaining: Number(result.servingsRemaining),
    location: String(result.location),
    foodLogId: result.foodLogId ? String(result.foodLogId) : null,
  };
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
  if (error) throw error;
}

export async function consumePlannedMeals(client: Client, consumptions: PlannedMealConsumption[]) {
  const { data, error } = await client.rpc('consume_planned_meals', {
    p_meal_plans: consumptions.map((consumption) => consumption.mealPlanId),
    p_servings: consumptions.map((consumption) => consumption.servings),
  });
  if (error) throw error;
  return data;
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
  const { data, error } = await client.rpc('consume_inventory_lot', { p_lot: lotId, p_quantity: quantity });
  if (error) throw error;
  return data;
}

export async function setInventoryLotQuantity(client: Client, lotId: string, remaining: number, discard = false) {
  const { data, error } = await client.rpc('set_inventory_lot_quantity', { p_lot: lotId, p_remaining: remaining, p_discard: discard });
  if (error) throw error;
  return data;
}

export async function cookRecipes(client: Client, recipeIds: string[]) {
  const { error } = await client.rpc('cook_recipes', { p_recipes: recipeIds });
  if (error) throw error;
}

export async function consumePreparedLot(client: Client, lotId: string, quantity = 1) {
  const { data, error } = await client.rpc('consume_prepared_lot', { p_lot: lotId, p_quantity: quantity });
  if (error) throw error;
  return data;
}

export async function rebuildShoppingFromPlan(client: Client) {
  const start = new Date();
  start.setDate(start.getDate() - ((start.getDay() + 6) % 7));
  const through = new Date(start);
  through.setDate(start.getDate() + 6);
  const { data, error } = await client.rpc('rebuild_shopping_from_plan', {
    p_from: start.toLocaleDateString('en-CA'),
    p_through: through.toLocaleDateString('en-CA'),
  });
  if (error) throw error;
  return data;
}
