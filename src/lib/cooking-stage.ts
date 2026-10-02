import type { PlannedMealView, PreparationOptions } from '../pantry-data';

export type StagedDish = { recipeId: string; servingsMade: number; servingsEaten: number };
export type CookingDraft = StagedDish & { id: string };

export function isCookablePlan(plan: PlannedMealView) {
  return Boolean(plan.recipeId) && plan.status === 'planned' && !plan.isLeftover && plan.consumptionStatus !== 'fulfilled';
}

export function cookingAttemptIdentity(recipeId: string, options: PreparationOptions) {
  return { recipeId, mealPlanId: options.mealPlanId ?? null, ...(options.cookingDraftId ? { cookingDraftId: options.cookingDraftId } : {}) };
}
