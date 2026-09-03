import { createContext, useContext, type ReactNode } from 'react';
import {
  FOOD_LOG,
  GROCERY_SECTIONS,
  HISTORY,
  INVENTORY_SECTIONS,
  NUTRIENTS,
  RECIPES,
  WEEK_DAYS,
  type Recipe,
} from './data';
import { DEFAULT_WEEKLY_FOOD_BUDGET, perServingCost, remainingValue } from './lib/cost';

export interface InventoryFood {
  productId?: string;
  emoji: string;
  name: string;
  sub: string;
  total: string;
  due: string;
  tone: string;
  lots: string[];
  cost: number | null;
  costIsEstimated: boolean;
  lotDetails?: Array<{ id: string; quantity: string; location: string; dateLabel: string; tone: string; remainingBase: number; remainingDisplay: number; displayUnit: string; displayPerBase: number; cost: number | null; costIsEstimated: boolean; costSource: string }>;
}

export type NutrientName = 'Calories' | 'Protein' | 'Carbs' | 'Fat' | 'Fiber' | 'Sodium';
export type NutritionValues = Record<NutrientName, number>;

export interface FoodLogEntry {
  id?: string;
  emoji: string;
  label: string;
  serving: string;
  calories: string;
  protein: string;
  time: string;
  color: string;
  nutrition?: NutritionValues;
  nutritionStatus?: 'complete' | 'partial' | 'unknown';
  cost?: number | null;
  costIsEstimated?: boolean;
}

export interface ProductView {
  id: string;
  foodId: string;
  foodName: string;
  name: string;
  label: string;
  brand: string;
  barcode: string;
  estimatedCost: number | null;
  costSource: string;
  costAsOf: string;
  emoji: string;
  nutrition: NutritionValues;
  nutritionPerServing: NutritionValues;
  packageQtyBase: number;
  servingQtyBase: number;
  servingLabel: string;
  stockServings: number;
  costPerServing: number | null;
  availableLots: Array<{
    id: string;
    location: string;
    remainingBase: number;
    remainingServings: number;
    dateLabel: string;
    costPerServing: number | null;
    costIsEstimated: boolean;
  }>;
  servingsConsumed: number;
  lastUsedAt: string;
}

export interface PlannedMealView {
  id: string;
  groupId: string;
  sourceGroupId?: string;
  dateKey: string;
  slot: string;
  name: string;
  emoji: string;
  recipeId?: string;
  productId?: string;
  inventoryLotId?: string;
  sourceKind?: 'recipe' | 'product' | 'lot';
  status: 'planned' | 'made' | 'skipped' | 'moved';
  isLeftover: boolean;
  scaleFactor?: number;
  plannedServings: number;
  actualServings?: number;
  consumptionStatus: string;
  prepId?: string;
  preparedLotId?: string;
  cost: number | null;
  costIsEstimated: boolean;
  nutrition?: NutritionValues;
}

export interface PreparationOptions {
  scale?: number;
  servingsMade?: number;
  location?: string;
  mealPlanId?: string;
  servingsEaten?: number;
}

export interface PlannedMealConsumption {
  mealPlanId: string;
  servings: number;
}

export interface PreparationResult {
  prepId: string;
  lotId: string;
  mealPlanId: string | null;
  servingsMade: number;
  servingsRemaining: number;
  location: string;
  foodLogId: string | null;
}

export interface PantryData {
  inventorySections: Array<{ emoji: string; label: string; foods: InventoryFood[] }>;
  recipes: Recipe[];
  grocerySections: Array<{ emoji: string; label: string; items: Array<{ id?: string; name: string; quantity: string; checked?: boolean; cost?: number | null }> }>;
  nutrients: Array<{ label: string; value: string; target: string; pct: number; color: string }>;
  weekDays: Array<{ day: string; date: string; dateKey?: string; today?: boolean; meals: Array<Partial<PlannedMealView> & Pick<PlannedMealView, 'slot' | 'name' | 'emoji'>> }>;
  plannedMeals: PlannedMealView[];
  foodLog: FoodLogEntry[];
  nutritionIncompleteEntries: number;
  foodLogByDate: Record<string, {
    nutrients: Array<{ label: string; value: string; target: string; pct: number; color: string }>;
    foodLog: FoodLogEntry[];
    nutritionIncompleteEntries: number;
  }>;
  history: Array<{
    day: string;
    date: string;
    dateKey?: string;
    meals: string[];
    mealDetails?: Array<{ id?: string; label: string; emoji: string; cost: number | null; costIsEstimated: boolean }>;
    totals: string;
    calories?: number;
    protein?: number;
    cost?: number | null;
    mealsMissingCost?: number;
    nutritionIncompleteEntries?: number;
  }>;
  foods: Array<{ id: string; name: string; emoji: string; measureStyle: 'discrete' | 'weight' | 'volume' }>;
  products: ProductView[];
  units: Array<{ id: string; label: string; shortName: string; measureStyle: 'discrete' | 'weight' | 'volume' }>;
  categories: string[];
  locations: string[];
  settings: {
    calories: number;
    proteinG: number;
    carbsG: number;
    fatG: number;
    fiberG: number;
    sodiumMg: number;
    allergies: string[];
    dietaryRules: string[];
    dislikes: string[];
    favorites: string[];
    timeZone: string;
    planningNotes: string;
    weeklyFoodBudget: number;
  };
  preparedLots: Array<{ id: string; prepId?: string; mealPlanId?: string; emoji: string; name: string; location: string; remaining: string; due: string; progress: number; batchCost: number | null; servingsTotal: number; servingsLeft: number; costPerServing: number | null; valueRemaining: number | null; costIsEstimated: boolean }>;
  preparationHistory: Array<{ id: string; recipeId: string | null; emoji: string; name: string; preparedAt: string; dateKey: string; servingsMade: number; servingsRemaining: number; location: string }>;
  spendHistory: Array<{ dateKey: string; spend: number; waste: number; away: number }>;
  wasteCauses: Array<{ label: string; note: string; amount: number }>;
  proteinTrend: Array<{ date: string; value: number }>;
  nutrientDrivers: Record<'Protein' | 'Calories' | 'Sodium', Array<{ label: string; pct: number }>>;
  nutritionHistory: Array<{ dateKey: string; label: string; values: NutritionValues; nutritionIncompleteEntries: number; foods: Array<{ label: string; values: NutritionValues }> }>;
  todayProjection: NutritionValues;
}

const previewDateKey = (daysFromToday = 0) => {
  const date = new Date();
  date.setHours(12, 0, 0, 0);
  date.setDate(date.getDate() + daysFromToday);
  return date.toLocaleDateString('en-CA');
};

export const previewPantryData: PantryData = {
  inventorySections: INVENTORY_SECTIONS.map((section) => ({
    ...section,
    foods: section.foods.map((food, index) => ({
      ...food,
      cost: [3.18, 4.29, 4.76, 3.89, 2.44, 1.35][index] ?? 2.5,
      costIsEstimated: true,
      lotDetails: [{
        id: `preview-${section.label}-${index}`,
        quantity: food.total,
        location: food.sub.split(' · ')[0] ?? 'pantry',
        dateLabel: food.due,
        tone: food.tone,
        remainingBase: 1,
        remainingDisplay: 1,
        displayUnit: '',
        displayPerBase: 1,
        cost: [3.18, 4.29, 4.76, 3.89, 2.44, 1.35][index] ?? 2.5,
        costIsEstimated: true,
        costSource: 'Product price estimate',
      }],
    })),
  })),
  recipes: RECIPES,
  grocerySections: GROCERY_SECTIONS.map((section) => ({
    ...section,
    items: section.items.map((item, index) => ({ ...item, checked: item.name === 'Eggs', cost: [2.18, 3.49, 4.79, 3.98, 4.29][index] ?? 3.49 })),
  })),
  nutrients: NUTRIENTS,
  weekDays: WEEK_DAYS,
  plannedMeals: [
    { id: 'preview-plan-pancakes', groupId: 'preview-plan-pancakes', dateKey: previewDateKey(), slot: 'BREAKFAST', name: 'Simple Pancakes', emoji: '🥞', recipeId: 'pancakes', sourceKind: 'recipe', status: 'planned', isLeftover: false, scaleFactor: 1, plannedServings: 1, consumptionStatus: 'planned', cost: 4.72, costIsEstimated: true, nutrition: { Calories: 310, Protein: 9, Carbs: 48, Fat: 9, Fiber: 2, Sodium: 520 } },
    { id: 'preview-plan-eggs', groupId: 'preview-plan-eggs', dateKey: previewDateKey(), slot: 'DINNER', name: 'Soft Scrambled Eggs', emoji: '🍳', recipeId: 'eggs', sourceKind: 'recipe', status: 'planned', isLeftover: false, scaleFactor: 1, plannedServings: 1, consumptionStatus: 'planned', cost: 1.14, costIsEstimated: true, nutrition: { Calories: 220, Protein: 13, Carbs: 2, Fat: 17, Fiber: 0, Sodium: 340 } },
    { id: 'preview-plan-eggs-later', groupId: 'preview-plan-eggs-later', dateKey: previewDateKey(2), slot: 'DINNER', name: 'Soft Scrambled Eggs', emoji: '🍳', recipeId: 'eggs', sourceKind: 'recipe', status: 'planned', isLeftover: false, scaleFactor: 1, plannedServings: 1, consumptionStatus: 'planned', cost: 1.14, costIsEstimated: true, nutrition: { Calories: 220, Protein: 13, Carbs: 2, Fat: 17, Fiber: 0, Sodium: 340 } },
  ],
  foodLog: FOOD_LOG,
  nutritionIncompleteEntries: 0,
  foodLogByDate: {
    [new Date().toLocaleDateString('en-CA')]: { nutrients: NUTRIENTS, foodLog: FOOD_LOG, nutritionIncompleteEntries: 0 },
  },
  history: HISTORY,
  foods: [],
  products: [
    { id: 'preview-product-1', foodId: 'preview-food-milk', foodName: 'Chocolate milk', name: 'Chocolate milk', label: 'Fairlife · Chocolate milk', brand: 'Fairlife', barcode: '811620020657', emoji: '🥛', nutrition: { Calories: 150, Protein: 13, Carbs: 13, Fat: 4.5, Fiber: 2, Sodium: 280 }, nutritionPerServing: { Calories: 150, Protein: 13, Carbs: 13, Fat: 4.5, Fiber: 2, Sodium: 280 }, packageQtyBase: 52, servingQtyBase: 12, servingLabel: '1 cup (12 fl oz)', stockServings: 3.5, costPerServing: 1.04, availableLots: [{ id: 'preview-fairlife-lot', location: 'fridge', remainingBase: 42, remainingServings: 3.5, dateLabel: '5 days', costPerServing: 1.04, costIsEstimated: true }], servingsConsumed: 8, lastUsedAt: '2026-08-30T12:00:00Z', estimatedCost: 4.49, costSource: 'Store estimate', costAsOf: '2026-08-30' },
    { id: 'preview-product-2', foodId: 'preview-food-yogurt', foodName: 'Greek yogurt', name: 'Salted caramel mix-in yogurt', label: 'Oikos · Salted caramel mix-in yogurt', brand: 'Oikos', barcode: '036632019742', emoji: '🥣', nutrition: { Calories: 120, Protein: 11, Carbs: 14, Fat: 2, Fiber: 0, Sodium: 75 }, nutritionPerServing: { Calories: 120, Protein: 11, Carbs: 14, Fat: 2, Fiber: 0, Sodium: 75 }, packageQtyBase: 1, servingQtyBase: 1, servingLabel: '1 container', stockServings: 2, costPerServing: 1.79, availableLots: [{ id: 'preview-oikos-caramel-lot', location: 'fridge', remainingBase: 2, remainingServings: 2, dateLabel: '8 days', costPerServing: 1.79, costIsEstimated: true }], servingsConsumed: 5, lastUsedAt: '2026-08-29T12:00:00Z', estimatedCost: 1.79, costSource: 'Store estimate', costAsOf: '2026-08-29' },
    { id: 'preview-product-3', foodId: 'preview-food-yogurt', foodName: 'Vanilla Greek yogurt', name: 'Vanilla Greek yogurt', label: 'Oikos · Vanilla Greek yogurt', brand: 'Oikos', barcode: '036632032093', emoji: '🥣', nutrition: { Calories: 90, Protein: 15, Carbs: 7, Fat: 0, Fiber: 0, Sodium: 55 }, nutritionPerServing: { Calories: 90, Protein: 15, Carbs: 7, Fat: 0, Fiber: 0, Sodium: 55 }, packageQtyBase: 1, servingQtyBase: 1, servingLabel: '1 container', stockServings: 1, costPerServing: 1.49, availableLots: [{ id: 'preview-oikos-vanilla-lot', location: 'fridge', remainingBase: 1, remainingServings: 1, dateLabel: '4 days', costPerServing: 1.49, costIsEstimated: true }], servingsConsumed: 3, lastUsedAt: '2026-08-27T12:00:00Z', estimatedCost: 1.49, costSource: 'Store estimate', costAsOf: '2026-08-27' },
    { id: 'preview-product-4', foodId: 'preview-food-liqueur', foodName: 'Irish cream liqueur', name: 'Original Irish Cream', label: "Bailey's · Original Irish Cream", brand: "Bailey's", barcode: '', emoji: '🥃', nutrition: { Calories: 147, Protein: 1.4, Carbs: 11.3, Fat: 5.8, Fiber: 0, Sodium: 34 }, nutritionPerServing: { Calories: 147, Protein: 1.4, Carbs: 11.3, Fat: 5.8, Fiber: 0, Sodium: 34 }, packageQtyBase: 25.36, servingQtyBase: 1.5, servingLabel: '1.5 fl oz', stockServings: 9.3, costPerServing: 1.77, availableLots: [{ id: 'preview-baileys-lot', location: 'pantry', remainingBase: 14, remainingServings: 9.3, dateLabel: 'Date unknown', costPerServing: 1.77, costIsEstimated: true }], servingsConsumed: 2, lastUsedAt: '2026-08-23T20:00:00Z', estimatedCost: 29.99, costSource: 'Store estimate', costAsOf: '2026-08-23' },
  ],
  units: [],
  categories: [],
  locations: ['pantry', 'fridge', 'freezer'],
  settings: {
    calories: 2300,
    proteinG: 130,
    carbsG: 260,
    fatG: 75,
    fiberG: 30,
    sodiumMg: 2300,
    allergies: [],
    dietaryRules: [],
    dislikes: [],
    favorites: [],
    timeZone: 'America/New_York',
    planningNotes: '',
    weeklyFoodBudget: DEFAULT_WEEKLY_FOOD_BUDGET,
  },
  preparedLots: [
    { id: 'preview-prep-1', prepId: 'preview-prep-event-1', mealPlanId: 'preview-plan-pancakes', emoji: '🥞', name: 'Simple Pancakes', location: 'fridge', remaining: '2 of 4 servings', due: '3 days left', progress: 50, batchCost: 4.72, servingsTotal: 4, servingsLeft: 2, costPerServing: perServingCost(4.72, 4), valueRemaining: remainingValue(4.72, 4, 2), costIsEstimated: true },
    { id: 'preview-prep-2', prepId: 'preview-prep-event-2', mealPlanId: 'preview-plan-eggs', emoji: '🍳', name: 'Soft Scrambled Eggs', location: 'fridge', remaining: '1 of 1 serving', due: '1 day left', progress: 100, batchCost: 1.14, servingsTotal: 1, servingsLeft: 1, costPerServing: perServingCost(1.14, 1), valueRemaining: remainingValue(1.14, 1, 1), costIsEstimated: true },
  ],
  preparationHistory: [
    { id: 'preview-prep-event-1', recipeId: 'pancakes', emoji: '🥞', name: 'Simple Pancakes', preparedAt: new Date().toISOString(), dateKey: previewDateKey(), servingsMade: 4, servingsRemaining: 2, location: 'fridge' },
    { id: 'preview-prep-event-2', recipeId: 'eggs', emoji: '🍳', name: 'Soft Scrambled Eggs', preparedAt: new Date().toISOString(), dateKey: previewDateKey(), servingsMade: 1, servingsRemaining: 1, location: 'fridge' },
  ],
  spendHistory: [],
  wasteCauses: [
    { label: 'Expired in the fridge', note: 'produce and dairy', amount: 0 },
    { label: 'Prepared batches discarded', note: 'leftovers past date', amount: 0 },
    { label: 'Opened and forgotten', note: 'partial packages', amount: 0 },
  ],
  proteinTrend: Array.from({ length: 30 }, (_, index) => ({ date: String(index + 1), value: 0 })),
  nutrientDrivers: { Protein: [], Calories: [], Sodium: [] },
  nutritionHistory: [],
  todayProjection: { Calories: 530, Protein: 22, Carbs: 50, Fat: 26, Fiber: 2, Sodium: 860 },
};

const PantryDataContext = createContext<PantryData>(previewPantryData);

export function PantryDataProvider({ data, children }: { data: PantryData; children: ReactNode }) {
  return <PantryDataContext.Provider value={data}>{children}</PantryDataContext.Provider>;
}

export function usePantryData() {
  return useContext(PantryDataContext);
}
