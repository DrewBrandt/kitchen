import { expect, it } from 'vitest';
import { planDisplayStatus } from './plan-display-status';
import type { PlannedMealView } from '../pantry-data';
const product = { status: 'planned', consumptionStatus: 'planned', sourceKind: 'product', consumeFromInventory: true, isLeftover: false } satisfies Partial<PlannedMealView>;

it.each([true, false])('does not call inventory-backed product demand ready (past=%s)', (past) => {
  expect(planDisplayStatus([product], past)).toMatchObject({ label: 'Planned', tone: 'planned' });
  expect(planDisplayStatus([{ ...product, consumeFromInventory: undefined }], past).label).toBe('Planned');
});
it('keeps external consumption distinct from pantry demand, including mixed groups', () => {
  const external = { ...product, consumeFromInventory: false };
  expect(planDisplayStatus([external], false).label).toBe('No prep');
  expect(planDisplayStatus([external, product], false).label).toBe('Planned');
  expect(planDisplayStatus([external, { ...product, consumptionStatus: 'fulfilled' }], false).label).toBe('No prep');
});
it('keeps exact-lot shortages actionable and completed consumption eaten', () => {
  const exact = { ...product, sourceKind: 'lot' as const, sourceShortfall: 'Selected lot is short' };
  expect(planDisplayStatus([exact], false).label).toBe('Check source');
  expect(planDisplayStatus([exact, product], false).label).toBe('Check source');
  expect(planDisplayStatus([{ ...exact, sourceShortfall: undefined }], false).label).toBe('Ready');
  expect(planDisplayStatus([{ ...product, consumptionStatus: 'fulfilled' }], false).label).toBe('Eaten');
});
