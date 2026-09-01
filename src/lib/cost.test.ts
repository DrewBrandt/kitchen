import { describe, expect, it } from 'vitest';
import { completeCost, dailyFoodBudget, perServingCost, remainingValue } from './cost';

describe('cost model', () => {
  it('derives one per-serving price for a batch no matter how much is left', () => {
    // The bug this replaces: a 4-serving $4.72 batch with 2 servings left reported
    // $1.18 on one screen and $0.59 on another, because "value of the remaining
    // servings" was divided by total servings in some places and by remaining in
    // others. With a single stored batchCost the answer cannot disagree.
    const batchCost = 4.72;
    const servingsTotal = 4;

    expect(perServingCost(batchCost, servingsTotal)).toBeCloseTo(1.18, 10);
    for (const servingsLeft of [4, 3, 2, 1, 0]) {
      expect(perServingCost(batchCost, servingsTotal)).toBeCloseTo(1.18, 10);
      expect(remainingValue(batchCost, servingsTotal, servingsLeft)).toBeCloseTo(1.18 * servingsLeft, 10);
    }
  });

  it('values what is left as per-serving times servings left', () => {
    expect(remainingValue(4.72, 4, 2)).toBeCloseTo(2.36, 10);
    expect(remainingValue(1.14, 1, 1)).toBeCloseTo(1.14, 10);
    expect(remainingValue(4.72, 4, 0)).toBe(0);
  });

  it('reports no price rather than a wrong one', () => {
    expect(perServingCost(null, 4)).toBeNull();
    expect(perServingCost(undefined, 4)).toBeNull();
    expect(perServingCost(4.72, 0)).toBeNull();
    expect(perServingCost(4.72, -1)).toBeNull();
    expect(remainingValue(null, 4, 2)).toBeNull();
    expect(completeCost([6.5, null, null])).toBeNull();
    expect(completeCost([6.5, 2.25])).toBe(8.75);
  });

  it('derives the daily budget from the one weekly number', () => {
    expect(dailyFoodBudget(150)).toBeCloseTo(21.428571, 5);
    expect(dailyFoodBudget(150) * 7).toBeCloseTo(150, 10);
  });
});
