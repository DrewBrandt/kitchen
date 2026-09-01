// The single source of truth for money.
//
// A prepared batch stores exactly one cost number: what the whole batch cost.
// Everything else is derived here, so a batch can never report two different
// per-serving prices depending on which screen you are looking at.

export const DEFAULT_WEEKLY_FOOD_BUDGET = 150;

/** What one serving of a batch cost. Always batchCost / servingsTotal. */
export function perServingCost(batchCost: number | null | undefined, servingsTotal: number): number | null {
  if (batchCost === null || batchCost === undefined) return null;
  if (!Number.isFinite(servingsTotal) || servingsTotal <= 0) return null;
  return batchCost / servingsTotal;
}

/** What the servings still in the fridge are worth. Per-serving x servings left. */
export function remainingValue(batchCost: number | null | undefined, servingsTotal: number, servingsLeft: number): number | null {
  const perServing = perServingCost(batchCost, servingsTotal);
  if (perServing === null) return null;
  return perServing * Math.max(0, servingsLeft);
}

/** The daily budget is never stored; it is the weekly budget divided by seven. */
export function dailyFoodBudget(weeklyFoodBudget: number): number {
  return weeklyFoodBudget / 7;
}

export function usd(value: number | null | undefined, estimated = false): string {
  if (value === null || value === undefined) return 'Price unavailable';
  return `${estimated ? '~' : ''}$${value.toFixed(2)}`;
}
