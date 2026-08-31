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
  emoji: string;
  name: string;
  sub: string;
  total: string;
  due: string;
  tone: string;
  lots: string[];
}

export interface PantryData {
  inventorySections: Array<{ emoji: string; label: string; foods: InventoryFood[] }>;
  recipes: Recipe[];
  grocerySections: Array<{ emoji: string; label: string; items: Array<{ id?: string; name: string; quantity: string; checked?: boolean }> }>;
  nutrients: Array<{ label: string; value: string; target: string; pct: number; color: string }>;
  weekDays: Array<{ day: string; date: string; today?: boolean; meals: Array<{ slot: string; name: string; emoji: string }> }>;
  foodLog: Array<{ id?: string; emoji: string; label: string; serving: string; calories: string; protein: string; time: string; color: string }>;
  history: Array<{ day: string; date: string; meals: string[]; totals: string }>;
  foods: Array<{ id: string; name: string; emoji: string; measureStyle: 'discrete' | 'weight' | 'volume' }>;
  products: Array<{ id: string; foodId: string; name: string; label: string; isExternal: boolean }>;
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
  };
  externalProducts: Array<{ id: string; emoji: string; name: string; place: string; nutrition: string }>;
  preparedLots: Array<{ id: string; emoji: string; name: string; location: string; remaining: string; due: string }>;
  proteinTrend: Array<{ date: string; value: number }>;
  nutrientDrivers: Record<'Protein' | 'Calories' | 'Sodium', Array<{ label: string; pct: number }>>;
}

export const previewPantryData: PantryData = {
  inventorySections: INVENTORY_SECTIONS,
  recipes: RECIPES,
  grocerySections: GROCERY_SECTIONS.map((section) => ({
    ...section,
    items: section.items.map((item) => ({ ...item, checked: item.name === 'Eggs' })),
  })),
  nutrients: NUTRIENTS,
  weekDays: WEEK_DAYS,
  foodLog: FOOD_LOG,
  history: HISTORY,
  foods: [],
  products: [],
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
  },
  externalProducts: [],
  preparedLots: [],
  proteinTrend: Array.from({ length: 30 }, (_, index) => ({ date: String(index + 1), value: 0 })),
  nutrientDrivers: { Protein: [], Calories: [], Sodium: [] },
};

const PantryDataContext = createContext<PantryData>(previewPantryData);

export function PantryDataProvider({ data, children }: { data: PantryData; children: ReactNode }) {
  return <PantryDataContext.Provider value={data}>{children}</PantryDataContext.Provider>;
}

export function usePantryData() {
  return useContext(PantryDataContext);
}
