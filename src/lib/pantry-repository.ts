import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '../database.types';
import type { NutritionValues, NutrientName, PantryData } from '../pantry-data';

type Client = SupabaseClient<Database>;
type FoodLogRow = Database['public']['Tables']['food_logs']['Row'];

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

const nutrientFields = {
  Calories: 'kcal', Protein: 'protein_g', Carbs: 'carbs_g', Fat: 'fat_g', Fiber: 'fiber_g', Sodium: 'sodium_mg',
} as const;

const nutritionValues = (row: Partial<Record<(typeof nutrientFields)[NutrientName], number | null>>): NutritionValues =>
  Object.fromEntries(Object.entries(nutrientFields).map(([label, field]) => [label, Number(row[field] ?? 0)])) as NutritionValues;

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

const usMeasurement = (quantity: number, source: UnitRow, unitRows: UnitRow[]) => {
  const base = quantity / Number(source.base_to_this_ratio);
  const wanted = source.measure_style === 'weight'
    ? (base >= 453.592 ? 'lb' : 'oz')
    : source.measure_style === 'volume'
      ? (base >= 4 ? 'cup' : base >= 1 ? 'tbsp' : 'tsp')
      : 'ct';
  const unit = unitRows.find((candidate) => candidate.short_name.toLowerCase() === wanted) ?? source;
  return { quantity: base * Number(unit.base_to_this_ratio), unit };
};

const daysUntil = (date: string | null) => {
  if (!date) return { label: 'Unknown', tone: 'muted' };
  const days = Math.ceil((new Date(`${date}T12:00:00`).getTime() - Date.now()) / 86_400_000);
  if (days < 0) return { label: `${Math.abs(days)} days overdue`, tone: 'urgent' };
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
  const [foodsResult, productsResult, lotsResult, unitsResult, categoriesResult, locationsResult, recipesResult, ingredientsResult, prepsResult, shoppingResult, plansResult, logsResult, settingsResult] = await Promise.all([
    client.from('base_foods').select('*'),
    client.from('products').select('*'),
    client.from('inventory_lots').select('*').gt('remaining_qty', 0),
    client.from('measure_conversions').select('*'),
    client.from('grocery_categories').select('*').order('sort_order'),
    client.from('locations').select('*').order('sort_order'),
    client.from('recipes').select('*').order('name'),
    client.from('recipe_ingredients').select('*').order('sort_order'),
    client.from('preps').select('*').is('voided_at', null),
    client.from('shopping_items').select('*').is('lot', null).order('created_at'),
    client.from('meal_plans').select('*').order('plan_date'),
    client.from('food_logs').select('*').is('voided_at', null).order('occurred_at', { ascending: false }),
    client.from('personal_settings').select('*').single(),
  ]);

  const firstError = [foodsResult, productsResult, lotsResult, unitsResult, categoriesResult, locationsResult, recipesResult, ingredientsResult, prepsResult, shoppingResult, plansResult, logsResult, settingsResult]
    .find((result) => result.error)?.error;
  if (firstError) throw firstError;

  const foods = new Map((foodsResult.data ?? []).map((food) => [food.id, food]));
  const products = new Map((productsResult.data ?? []).map((product) => [product.id, product]));
  const units = new Map((unitsResult.data ?? []).map((unit) => [unit.id, unit]));
  const categoryOrder = new Map((categoriesResult.data ?? []).map((category, index) => [category.category, index]));
  const orderCategories = <T,>(entries: Array<[string, T]>) => entries.sort(([left], [right]) =>
    (categoryOrder.get(left) ?? Number.MAX_SAFE_INTEGER) - (categoryOrder.get(right) ?? Number.MAX_SAFE_INTEGER) || left.localeCompare(right));
  const rawLots = (lotsResult.data ?? []).filter((lot) => !lot.prep);
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
      const ratio = Number(displayUnit?.base_to_this_ratio ?? 1);
      return {
        productId: firstProduct?.id,
        emoji: food.emoji ?? '🍽️',
        name: food.name,
        sub: [food.ingredient_role, food.grocery_category].filter(Boolean).join(' · ') || 'Pantry item',
        total: formatQuantity(total * ratio, displayUnit?.short_name),
        due: due.label,
        tone: due.tone,
        lots: stockLots.map((lot) => `${formatQuantity(Number(lot.remaining_qty) * ratio, displayUnit?.short_name)} ${lot.location ?? 'unassigned'}`),
      };
    }),
  }));

  const recipeRows = recipesResult.data ?? [];
  const unitRows = unitsResult.data ?? [];
  const recipes = recipeRows.map((recipe) => {
    const recipeIngredients = (ingredientsResult.data ?? []).filter((ingredient) => ingredient.recipe === recipe.id);
    const steps = Array.isArray(recipe.instructions) ? recipe.instructions.map(String) : [];
    const kcal = Number(recipe.override_kcal ?? 0);
    const protein = Number(recipe.override_protein_g ?? 0);
    const recipePreps = (prepsResult.data ?? []).filter((prep) => prep.recipe === recipe.id);
    const easeRatings = recipePreps.map((prep) => prep.ease_rating).filter((rating) => rating > 0);
    const tasteRatings = recipePreps.map((prep) => prep.taste_rating).filter((rating) => rating > 0);
    return {
      id: recipe.id,
      emoji: recipe.emoji ?? '🍳',
      name: recipe.name,
      servings: Number(recipe.servings),
      minutes: Math.max(10, steps.length * 5),
      nutrition: kcal ? `${Math.round(kcal / Number(recipe.servings))} cal · ${Math.round(protein / Number(recipe.servings))} g protein per serving` : 'Nutrition calculated from ingredients',
      ingredients: recipeIngredients.map((ingredient) => {
        const food = foods.get(ingredient.ingredient);
        const unit = units.get(ingredient.unit);
        if (!food || !unit) return { label: `${formatQuantity(Number(ingredient.qty))} Ingredient`, stock: 'Unit unavailable · short' };
        const display = usMeasurement(Number(ingredient.qty), unit, unitRows);
        const neededBase = toFoodBase(food, Number(ingredient.qty), unit);
        const availableBase = stockByFood.get(ingredient.ingredient) ?? 0;
        const enough = availableBase + 0.0000001 >= neededBase;
        const availableInDisplayStyle = fromFoodBase(food, availableBase, display.unit);
        const ingredientName = pluralize(food.name, food.plural, display.quantity);
        return { label: `${formatQuantity(display.quantity, display.unit.short_name)} ${ingredientName}`, stock: `${formatQuantity(availableInDisplayStyle, display.unit.short_name)} in stock${enough ? '' : ' · short'}` };
      }),
      steps,
      ease: easeRatings.length ? Number((easeRatings.reduce((total, value) => total + value, 0) / easeRatings.length).toFixed(1)) : 0,
      taste: tasteRatings.length ? Number((tasteRatings.reduce((total, value) => total + value, 0) / tasteRatings.length).toFixed(1)) : 0,
      prepCount: recipePreps.length,
      nutritionValues: { Calories: kcal, Protein: protein, Carbs: Number(recipe.override_carbs_g ?? 0), Fat: Number(recipe.override_fat_g ?? 0), Fiber: Number(recipe.override_fiber_g ?? 0), Sodium: Number(recipe.override_sodium_mg ?? 0) },
      cookable: recipeIngredients.every((ingredient) => {
        const unit = units.get(ingredient.unit);
        const food = foods.get(ingredient.ingredient);
        return Boolean(unit && food && (stockByFood.get(ingredient.ingredient) ?? 0) + 0.0000001 >= toFoodBase(food, Number(ingredient.qty), unit));
      }),
    };
  });

  const externalProducts = [...products.values()].filter((product) => product.is_external).map((product) => ({
    id: product.id,
    emoji: product.emoji ?? foods.get(product.food)?.emoji ?? '🥡',
    name: product.name,
    place: product.brand ?? 'Saved food',
    nutrition: `${Math.round(Number(product.kcal ?? 0))} cal · ${Math.round(Number(product.protein_g ?? 0))} g protein`,
  }));

  const preparedLots = (lotsResult.data ?? []).filter((lot) => lot.prep).map((lot) => {
    const prep = (prepsResult.data ?? []).find((candidate) => candidate.id === lot.prep);
    const recipe = prep ? recipeRows.find((candidate) => candidate.id === prep.recipe) : undefined;
    return {
      id: lot.id,
      emoji: recipe?.emoji ?? '🥘',
      name: recipe?.name ?? 'Prepared batch',
      location: lot.location ?? 'unassigned',
      remaining: `${formatQuantity(Number(lot.remaining_qty))} of ${formatQuantity(Number(lot.initial_qty))} servings`,
      due: daysUntil(lot.use_by).label,
      progress: Number(lot.initial_qty) ? Number(lot.remaining_qty) / Number(lot.initial_qty) * 100 : 0,
    };
  });

  const groceryGroups = new Map<string, PantryData['grocerySections'][number]['items']>();
  for (const item of shoppingResult.data ?? []) {
    const food = item.food ? foods.get(item.food) : undefined;
    const category = food?.grocery_category ?? 'Pantry & other';
    const items = groceryGroups.get(category) ?? [];
    items.push({
      id: item.id,
      name: item.free_text ?? food?.name ?? 'Grocery item',
      quantity: item.quantity_label ?? (item.qty_needed ? formatQuantity(Number(item.qty_needed), units.get(item.unit ?? '')?.short_name) : 'As needed'),
      checked: Boolean(item.checked_at),
    });
    groceryGroups.set(category, items);
  }
  const grocerySections = orderCategories([...groceryGroups.entries()]).map(([label, items]) => ({ emoji: categoryEmoji(label), label, items }));

  const settings = settingsResult.data;
  if (!settings) throw new Error('Personal settings are missing.');
  const logs = logsResult.data ?? [];
  const todayKey = dateKeyInZone(new Date(), settings.time_zone);
  const todayLogs = logs.filter((log) => dateKeyInZone(new Date(log.occurred_at), settings.time_zone) === todayKey);
  const nutrientSpec = [
    ['Calories', 'kcal', settings.nutrition_calories, 'cal', '#86d7ac'],
    ['Protein', 'protein_g', settings.nutrition_protein_g, 'g', '#86d7ac'],
    ['Carbs', 'carbs_g', settings.nutrition_carbs_g, 'g', '#8fbce6'],
    ['Fat', 'fat_g', settings.nutrition_fat_g, 'g', '#b0a6e0'],
    ['Fiber', 'fiber_g', settings.nutrition_fiber_g, 'g', '#e5c07b'],
    ['Sodium', 'sodium_mg', settings.nutrition_sodium_mg, 'mg', '#e88592'],
  ] as const;
  const buildNutrients = (dayLogs: FoodLogRow[]) => nutrientSpec.map(([label, field, target, unit, color]) => {
    const value = sum(dayLogs, field);
    return { label, value: `${Math.round(value).toLocaleString()}${unit === 'cal' ? '' : ` ${unit}`}`, target: `/ ${Number(target).toLocaleString()} ${unit}`, pct: Math.min(100, Math.round(value / Number(target) * 100)), color };
  });
  const palette = ['#53d7a0', '#5eb5f5', '#a78bfa', '#f59e6b', '#f472b6', '#f2d06b', '#4fd1c5', '#ef7d7d'];
  const buildFoodLog = (dayLogs: FoodLogRow[]) => dayLogs.map((log, index) => ({
    id: log.id,
    emoji: log.kind === 'external' ? '🥡' : '🍽️',
    label: log.label,
    serving: `${Number(log.servings ?? 1)} serving${Number(log.servings ?? 1) === 1 ? '' : 's'}${log.nutrition_is_estimated ? ' · estimated' : ''}`,
    calories: `${Math.round(Number(log.kcal ?? 0))} cal`,
    protein: `${Math.round(Number(log.protein_g ?? 0))} g protein`,
    time: new Date(log.occurred_at).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' }),
    color: palette[index % palette.length],
    nutrition: nutritionValues(log),
  }));
  const nutrients = buildNutrients(todayLogs);
  const foodLog = buildFoodLog(todayLogs);

  const byDay = new Map<string, FoodLogRow[]>();
  for (const log of logs) {
    const key = dateKeyInZone(new Date(log.occurred_at), settings.time_zone);
    byDay.set(key, [...(byDay.get(key) ?? []), log]);
  }
  const foodLogByDate = Object.fromEntries([...byDay.entries()].map(([date, dayLogs]) => [date, {
    nutrients: buildNutrients(dayLogs),
    foodLog: buildFoodLog(dayLogs),
  }]));
  const history = [...byDay.entries()].slice(0, 14).map(([date, dayLogs]) => {
    const parsed = new Date(`${date}T12:00:00`);
    return {
      dateKey: date,
      day: parsed.toLocaleDateString([], { weekday: 'long' }),
      date: parsed.toLocaleDateString([], { month: 'short', day: 'numeric' }).toUpperCase(),
      meals: dayLogs.map((log) => log.label),
      totals: `${Math.round(sum(dayLogs, 'kcal')).toLocaleString()} cal\n${Math.round(sum(dayLogs, 'protein_g'))} g protein`,
    };
  });

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
      return { id: plan.id, slot: plan.daypart.toUpperCase(), name: plan.name ?? recipe?.name ?? 'Planned meal', emoji: plan.emoji ?? recipe?.emoji ?? '🍽️', recipeId: recipe?.id };
    });
    return { day: date.toLocaleDateString([], { weekday: 'short' }).toUpperCase(), date: String(date.getDate()), dateKey: key, today: key === todayKey, meals };
  });

  const plannedMeals = (plansResult.data ?? []).map((plan) => {
    const recipe = plan.recipe ? recipeRows.find((row) => row.id === plan.recipe) : undefined;
    return { id: plan.id, dateKey: plan.plan_date, slot: plan.daypart.toUpperCase(), name: plan.name ?? recipe?.name ?? 'Planned meal', emoji: plan.emoji ?? recipe?.emoji ?? '🍽️', recipeId: recipe?.id };
  });
  const nutritionHistory = [...byDay.entries()].map(([dateKey, dayLogs]) => ({
    dateKey,
    label: new Date(`${dateKey}T12:00:00`).toLocaleDateString([], { month: 'short', day: 'numeric' }),
    values: Object.fromEntries(Object.entries(nutrientFields).map(([label, field]) => [label, sum(dayLogs, field)])) as NutritionValues,
    foods: dayLogs.map((log) => ({ label: log.label, values: nutritionValues(log) })),
  }));
  const todayProjection = (plansResult.data ?? []).filter((plan) => plan.plan_date === todayKey).reduce((totals, plan) => {
    const recipe = plan.recipe ? recipeRows.find((row) => row.id === plan.recipe) : undefined;
    if (!recipe) return totals;
    const values = nutritionValues({ kcal: recipe.override_kcal, protein_g: recipe.override_protein_g, carbs_g: recipe.override_carbs_g, fat_g: recipe.override_fat_g, fiber_g: recipe.override_fiber_g, sodium_mg: recipe.override_sodium_mg });
    for (const label of Object.keys(totals) as NutrientName[]) totals[label] += values[label] * Number(plan.scale_factor);
    return totals;
  }, { Calories: 0, Protein: 0, Carbs: 0, Fat: 0, Fiber: 0, Sodium: 0 } as NutritionValues);

  return {
    inventorySections,
    recipes,
    grocerySections,
    nutrients,
    weekDays,
    plannedMeals,
    foodLog,
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
      emoji: product.emoji ?? foods.get(product.food)?.emoji ?? '🍽️',
      isExternal: product.is_external,
      nutrition: nutritionValues(product),
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
    },
    externalProducts,
    preparedLots,
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
  const { error } = await client.from('food_logs').update({ voided_at: new Date().toISOString() }).eq('id', id);
  if (error) throw error;
}

export async function logExternalProduct(client: Client, id: string) {
  const { data: product, error: productError } = await client.from('products').select('*').eq('id', id).eq('is_external', true).single();
  if (productError) throw productError;
  const { error } = await client.from('food_logs').insert({
    label: [product.brand, product.name].filter(Boolean).join(' · '),
    kind: 'external',
    product: product.id,
    servings: 1,
    kcal: product.kcal,
    protein_g: product.protein_g,
    carbs_g: product.carbs_g,
    fat_g: product.fat_g,
    fiber_g: product.fiber_g,
    sugar_g: product.sugar_g,
    sodium_mg: product.sodium_mg,
    nutrition_is_estimated: product.nutrition_is_estimated,
  });
  if (error) throw error;
}

export async function cookRecipe(client: Client, recipeId: string) {
  const { data, error } = await client.rpc('cook_recipe', { p_recipe: recipeId });
  if (error) throw error;
  return data;
}

export async function savePrepFeedback(client: Client, prepId: string, ease: number, taste: number, actualMinutes: number) {
  const { error } = await client.rpc('save_prep_feedback', { p_prep: prepId, p_ease: ease, p_taste: taste, p_actual_minutes: actualMinutes });
  if (error) throw error;
}

export async function removePlannedMeal(client: Client, planId: string) {
  const { error } = await client.from('meal_plans').delete().eq('id', planId);
  if (error) throw error;
}

export async function cookRecipes(client: Client, recipeIds: string[]) {
  const { error } = await client.rpc('cook_recipes', { p_recipes: recipeIds });
  if (error) throw error;
}

export async function consumePreparedLot(client: Client, lotId: string, quantity = 1) {
  const { error } = await client.rpc('consume_prepared_lot', { p_lot: lotId, p_quantity: quantity });
  if (error) throw error;
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
