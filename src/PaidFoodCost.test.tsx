import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { expect, it } from 'vitest';
import { loadPantryData } from './lib/pantry-repository';
import { App } from './App';
import { PantryDataProvider } from './pantry-data';

type Row = Record<string, any>;
const now = new Date().toISOString();
const log = (paid: number | null, value: number | null, kind = 'manual'): Row => ({ id: 'meal', label: 'Dessert', kind, product: null, recipe: null, occurred_at: now, servings: 1, cost: value, total_price: value, out_of_pocket_cost: paid, cost_is_estimated: false, nutrition_is_estimated: true, nutrition_status: 'complete', kcal: 200, protein_g: 5, carbs_g: 20, fat_g: 10, fiber_g: 1, sugar_g: 8, sodium_mg: 5, time_precision: 'exact', voided_at: null });
function fixture(meal: Row) {
  const tables: Record<string, Row[]> = { food_logs: [meal], inventory_lots: [], inventory_events: [], personal_settings: [{ time_zone: 'UTC' }] };
  const db = { rpc: async () => ({ data: {}, error: null }), from(table: string) { let data: any = tables[table] ?? []; const query: any = new Proxy({}, { get(_target, key) { if (key === 'then') return (yes: any, no: any) => Promise.resolve({ data, error: null }).then(yes, no); return (...args: any[]) => { if (key === 'is') data = data.filter((row: Row) => row[args[0]] == args[1]); if (key === 'single') data = data[0]; return query; }; } }); return query; } };
  return { tables, load: () => loadPantryData(db as unknown as Parameters<typeof loadPantryData>[0]) };
}

it('shows free outside food as actual zero paid with unknown food value and estimated nutrition', async () => {
  const data = await fixture(log(0, null)).load();
  expect(data.foodLog[0]).toMatchObject({ cost: 0, foodValue: null, costIsEstimated: false });
  expect(data.foodLog[0].nutritionIsEstimated).toBe(true);
  expect(data.spendHistory[0]).toMatchObject({ spend: 0, spendMissingCost: 0, away: 0 });
  render(<PantryDataProvider data={data}><App /></PantryDataProvider>);
  const metric = screen.getByText('Food cost').closest('.headline-metric')!;
  expect(within(metric as HTMLElement).getByText('$0.00')).toBeVisible();
  await userEvent.click(screen.getByRole('button', { name: 'Food log' }));
  await userEvent.click(screen.getByRole('button', { name: 'View Dessert consumption event' }));
  expect(screen.getByText('Full food value').parentElement).toHaveTextContent('Price unavailable');
  expect(screen.getByText('Food cost · you paid').parentElement).toHaveTextContent('$0.00');
});

it('uses the paid fast-food amount instead of its larger full value', async () => {
  const data = await fixture(log(12, 18)).load();
  expect(data.foodLog[0]).toMatchObject({ cost: 12, foodValue: 18 });
  expect(data.history[0].cost).toBe(12);
  expect(data.spendHistory[0]).toMatchObject({ spend: 12, away: 12 });
});

it('allocates purchased ingredient and prepared leftover paid amounts on consumption, not acquisition day', async () => {
  const f = fixture(log(null, 10, 'prepared'));
  f.tables.inventory_lots = [{ id: 'leftover', prep: 'prep', initial_qty: 4, remaining_qty: 3, total_cost: 20, out_of_pocket_cost: 8, acquired_at: '2026-09-01T12:00:00Z', cost_is_estimated: false }];
  f.tables.inventory_events = [{ id: 'eaten', lot: 'leftover', food_log: 'meal', reason: 'eaten', quantity_delta: -1, occurred_at: now }];
  f.tables.inventory_event_costs = [{ inventory_event_id: 'eaten', cost: 5 }];
  const data = await f.load();
  expect(data.foodLog[0]).toMatchObject({ cost: 2, foodValue: 5 });
  expect(data.spendHistory).toHaveLength(1);
  expect(data.spendHistory[0]).toMatchObject({ dateKey: now.slice(0, 10), spend: 2 });
  f.tables.inventory_lots[0].prep = null;
  expect((await f.load()).foodLog[0].cost).toBe(2);
});

it('preserves unknown paid amounts even when full value is known', async () => {
  const f = fixture(log(null, 9));
  let data = await f.load();
  expect(data.foodLog[0]).toMatchObject({ cost: null, foodValue: 9 });
  expect(data.spendHistory[0].spendMissingCost).toBe(1);
  render(<PantryDataProvider data={data}><App /></PantryDataProvider>);
  expect(screen.getByText('$0.00 + unknown')).toBeVisible();
  expect(screen.getByText('Paid amounts missing')).toBeVisible();
  f.tables.inventory_lots = [{ id: 'unknown', initial_qty: 4, remaining_qty: 3, total_cost: 36, out_of_pocket_cost: null }];
  f.tables.inventory_events = [{ id: 'eaten', lot: 'unknown', food_log: 'meal', reason: 'eaten', quantity_delta: -1, occurred_at: now }];
  data = await f.load();
  expect(data.foodLog[0].cost).toBeNull();
});

it('removes undone consumption from paid totals without creating purchase-day spending', async () => {
  const f = fixture(log(12, 18));
  expect((await f.load()).spendHistory[0].spend).toBe(12);
  f.tables.food_logs[0].voided_at = now;
  const data = await f.load();
  expect(data.foodLog).toEqual([]);
  expect(data.spendHistory).toEqual([]);
});


it('keeps partial nutrition separate from its estimated flag, provenance and editable snapshot', async () => {
  const meal = { ...log(0, null), kcal: 100, protein_g: null, nutrition_status: 'partial', nutrition_source: 'Visual portion estimate', nutrition_estimate: { confidence: 'low', rationale: 'Small slice, recipe unknown' } };
  const data = await fixture(meal).load();
  expect(data.foodLog[0]).toMatchObject({ nutritionStatus: 'partial', nutritionIsEstimated: true });
  expect(data.foodLog[0].events![0]).toMatchObject({ nutritionSource: meal.nutrition_source, nutritionConfidence: 'low', nutritionRationale: 'Small slice, recipe unknown', manual: { nutrition: { estimated: true, source: meal.nutrition_source } } });
  render(<PantryDataProvider data={data}><App onUpdateFoodLog={async () => {}} /></PantryDataProvider>);
  await userEvent.click(screen.getByRole('button', { name: 'Food log' }));
  const row = screen.getByRole('button', { name: 'View Dessert consumption event' });
  expect(within(row).getByText('Estimated nutrition')).toBeVisible();
  expect(within(row).getByText(/partial nutrition/)).toBeVisible();
  await userEvent.click(row);
  const dialog = screen.getByRole('dialog');
  expect(within(dialog).getAllByText('Estimated nutrition').length).toBeGreaterThan(0);
  await userEvent.click(within(dialog).getByText('Estimated nutrition · source'));
  expect(within(dialog).getByText('Source: Visual portion estimate')).toBeVisible();
  expect(within(dialog).getByText('Confidence: low')).toBeVisible();
  expect(within(dialog).getByText('Small slice, recipe unknown')).toBeVisible();
  await userEvent.click(within(dialog).getByRole('button', { name: 'Edit consumption 1' }));
  expect(within(dialog).getByRole('checkbox', { name: 'Nutrition is estimated' })).toBeChecked();
});
