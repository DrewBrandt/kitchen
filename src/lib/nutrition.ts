import type { NutrientName, NutritionValues } from '../pantry-data';

export function nutritionForServings(values: NutritionValues, recipeYield: number, plannedServings: number): NutritionValues {
  if (!Number.isFinite(recipeYield) || recipeYield <= 0) throw new Error('Recipe yield must be positive.');
  if (!Number.isFinite(plannedServings) || plannedServings <= 0) throw new Error('Planned servings must be positive.');
  return Object.fromEntries((Object.keys(values) as NutrientName[]).map((label) => [label, values[label] / recipeYield * plannedServings])) as NutritionValues;
}
