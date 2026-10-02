// Portion allocation helpers work for either recorded paid cost or food value.
// Callers must keep these distinct; unknown amounts remain unknown.

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

/** A group has a total only when every component has a price. */
export function completeCost(values: Array<number | null | undefined>): number | null {
  if (values.some((value) => value === null || value === undefined)) return null;
  return values.reduce<number>((total, value) => total + Number(value), 0);
}

export function usd(value: number | null | undefined, estimated = false): string {
  if (value === null || value === undefined) return 'Price unavailable';
  return `${estimated ? '~' : ''}$${value.toFixed(2)}`;
}

/** A stock valuation is distinct from the actual amount paid for its purchase. */
export function inventoryValueLabel(value: number | null | undefined, estimated: boolean, compact = false): string {
  if (value === null || value === undefined) return compact ? 'Value unavailable' : 'Inventory value unavailable';
  const amount = value > 0 && value < 0.01 ? '<$0.01' : usd(value);
  if (compact) return `${estimated ? '~' : ''}${amount}`;
  return `${estimated ? 'Estimated inventory value' : 'Inventory value'}: ${amount}`;
}
