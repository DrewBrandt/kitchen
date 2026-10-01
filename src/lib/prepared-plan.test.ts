import { describe, expect, it } from 'vitest';
import { preparedPlanAvailability } from './prepared-plan';

const plan = { id: 'leftover', recipe: 'rice', inventory_lot: null, intent: 'leftover', source_meal_plan: 'future', leftover_of_group_id: 'group' };
const plans = [{ id: 'future', recipe: 'rice', group_id: 'group' }, { id: 'old', recipe: 'rice', group_id: 'old-group' }];
const oldPrep = { id: 'old-prep', recipe: 'rice', meal_plan: 'old', voided_at: null };
const oldLot = { id: 'old-lot', prep: oldPrep.id, remaining_qty: 2 };

describe('linked prepared-stock readiness', () => {
  it('waits for the exact source even when the same recipe is already in stock', () => {
    expect(preparedPlanAvailability(plan, plans, [oldPrep], [oldLot])).toEqual({ preparedServingsAvailable: 0, waitingForPreparation: true });
  });
  it('uses only a live linked batch and distinguishes exhausted from not cooked', () => {
    const prep = { ...oldPrep, id: 'new-prep', meal_plan: 'future' };
    expect(preparedPlanAvailability(plan, plans, [oldPrep, prep], [oldLot, { id: 'new', prep: prep.id, remaining_qty: 0.5 }])).toEqual({ preparedServingsAvailable: 0.5, waitingForPreparation: false });
    expect(preparedPlanAvailability(plan, plans, [prep], [{ id: 'new', prep: prep.id, remaining_qty: 0 }])).toEqual({ preparedServingsAvailable: 0, waitingForPreparation: false });
    expect(preparedPlanAvailability(plan, plans, [{ ...prep, voided_at: '2026-10-01' }], [oldLot])).toEqual({ preparedServingsAvailable: 0, waitingForPreparation: true });
  });
  it('does not combine distinct batches, and exact-lot selections remain exact', () => {
    const preps = [1, 2].map((n) => ({ ...oldPrep, id: `prep-${n}`, meal_plan: 'future' }));
    const lots = [1, 2].map((n) => ({ id: `lot-${n}`, prep: `prep-${n}`, remaining_qty: n }));
    expect(preparedPlanAvailability(plan, plans, preps, lots).preparedServingsAvailable).toBe(2);
    expect(preparedPlanAvailability({ ...plan, inventory_lot: 'lot-1', intent: 'consume' }, plans, preps, lots).preparedServingsAvailable).toBe(1);
  });
  it('supports legacy group binding only when no exact source was recorded', () => {
    expect(preparedPlanAvailability({ ...plan, source_meal_plan: null, leftover_of_group_id: 'old-group' }, plans, [oldPrep], [oldLot]).preparedServingsAvailable).toBe(2);
    expect(preparedPlanAvailability({ ...plan, recipe: 'chicken', source_meal_plan: null, leftover_of_group_id: 'old-group' }, plans, [oldPrep], [oldLot]).preparedServingsAvailable).toBe(0);
  });
});
