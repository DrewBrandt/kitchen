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
  lotDetails?: Array<{ id: string; quantity: string; location: string; dateLabel: string; tone: string; remainingBase: number; cost: number | null; costIsEstimated: boolean; costSource: string }>;
}

export type NutrientName = 'Calories' | 'Protein' | 'Carbs' | 'Fat' | 'Fiber' | 'Sodium';
export type NutritionValues = Record<NutrientName, number>;

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
  isExternal: boolean;
  nutrition: NutritionValues;
  useCount: number;
  lastUsedAt: string;
}

export interface PantryData {
  inventorySections: Array<{ emoji: string; label: string; foods: InventoryFood[] }>;
  recipes: Recipe[];
  grocerySections: Array<{ emoji: string; label: string; items: Array<{ id?: string; name: string; quantity: string; checked?: boolean; cost?: number | null }> }>;
  nutrients: Array<{ label: string; value: string; target: string; pct: number; color: string }>;
  weekDays: Array<{ day: string; date: string; dateKey?: string; today?: boolean; meals: Array<{ id?: string; groupId?: string; slot: string; name: string; emoji: string; recipeId?: string; status?: 'planned' | 'made' | 'skipped' | 'moved'; isLeftover?: boolean; cost?: number | null; costIsEstimated?: boolean }> }>;
  plannedMeals: Array<{ id: string; groupId: string; sourceGroupId?: string; dateKey: string; slot: string; name: string; emoji: string; recipeId?: string; status: 'planned' | 'made' | 'skipped' | 'moved'; isLeftover: boolean; cost: number | null; costIsEstimated: boolean }>;
  foodLog: Array<{ id?: string; emoji: string; label: string; serving: string; calories: string; protein: string; time: string; color: string; nutrition?: NutritionValues; cost?: number | null; costIsEstimated?: boolean }>;
  foodLogByDate: Record<string, {
    nutrients: Array<{ label: string; value: string; target: string; pct: number; color: string }>;
    foodLog: Array<{ id?: string; emoji: string; label: string; serving: string; calories: string; protein: string; time: string; color: string; nutrition?: NutritionValues; cost?: number | null; costIsEstimated?: boolean }>;
  }>;
  history: Array<{ day: string; date: string; dateKey?: string; meals: string[]; totals: string; cost?: number | null }>;
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
  };
  externalProducts: Array<{ id: string; emoji: string; name: string; place: string; nutrition: string; cost: number | null }>;
  preparedLots: Array<{ id: string; emoji: string; name: string; location: string; remaining: string; due: string; progress: number; cost: number | null; costIsEstimated: boolean }>;
  proteinTrend: Array<{ date: string; value: number }>;
  nutrientDrivers: Record<'Protein' | 'Calories' | 'Sodium', Array<{ label: string; pct: number }>>;
  nutritionHistory: Array<{ dateKey: string; label: string; values: NutritionValues; foods: Array<{ label: string; values: NutritionValues }> }>;
  todayProjection: NutritionValues;
}

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
  plannedMeals: [],
  foodLog: FOOD_LOG,
  foodLogByDate: {
    [new Date().toLocaleDateString('en-CA')]: { nutrients: NUTRIENTS, foodLog: FOOD_LOG },
  },
  history: HISTORY,
  foods: [],
  products: [
    { id: 'preview-product-1', foodId: 'preview-food-milk', foodName: 'Chocolate milk', name: 'Chocolate milk', label: 'Chocolate milk', brand: 'Fairlife', barcode: '811620020657', emoji: '🥛', isExternal: false, nutrition: { Calories: 150, Protein: 13, Carbs: 13, Fat: 4.5, Fiber: 2, Sodium: 280 }, useCount: 8, lastUsedAt: '2026-08-30T12:00:00Z', estimatedCost: 4.49, costSource: 'Store estimate', costAsOf: '2026-08-30' },
    { id: 'preview-product-2', foodId: 'preview-food-yogurt', foodName: 'Greek yogurt', name: 'Salted caramel mix-in yogurt', label: 'Salted caramel mix-in yogurt', brand: 'Oikos', barcode: '036632019742', emoji: '🥣', isExternal: false, nutrition: { Calories: 120, Protein: 11, Carbs: 14, Fat: 2, Fiber: 0, Sodium: 75 }, useCount: 5, lastUsedAt: '2026-08-29T12:00:00Z', estimatedCost: 1.79, costSource: 'Store estimate', costAsOf: '2026-08-29' },
    { id: 'preview-product-3', foodId: 'preview-food-yogurt', foodName: 'Greek yogurt', name: 'Vanilla Greek yogurt', label: 'Vanilla Greek yogurt', brand: 'Oikos', barcode: '036632032093', emoji: '🥣', isExternal: false, nutrition: { Calories: 90, Protein: 15, Carbs: 7, Fat: 0, Fiber: 0, Sodium: 55 }, useCount: 3, lastUsedAt: '2026-08-27T12:00:00Z', estimatedCost: 1.49, costSource: 'Store estimate', costAsOf: '2026-08-27' },
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
  },
  externalProducts: [],
  preparedLots: [],
  proteinTrend: Array.from({ length: 30 }, (_, index) => ({ date: String(index + 1), value: 0 })),
  nutrientDrivers: { Protein: [], Calories: [], Sodium: [] },
  nutritionHistory: [],
  todayProjection: { Calories: 310, Protein: 9, Carbs: 48, Fat: 9, Fiber: 2, Sodium: 520 },
};

const PantryDataContext = createContext<PantryData>(previewPantryData);

export function PantryDataProvider({ data, children }: { data: PantryData; children: ReactNode }) {
  return <PantryDataContext.Provider value={data}>{children}</PantryDataContext.Provider>;
}

export function usePantryData() {
  return useContext(PantryDataContext);
}
