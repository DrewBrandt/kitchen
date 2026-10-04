import { useState } from 'react';
import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { App } from './App';
import { PantryDataProvider, previewPantryData, type PlannedMealView } from './pantry-data';
import { loadPantryData, rebuildShoppingFromPlan } from './lib/pantry-repository';
import { planningWeek, type PlanningRange } from './lib/planning-week';

beforeEach(() => {
  localStorage.clear();
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(new Date('2026-12-27T12:30:00Z'));
});
afterEach(() => { vi.useRealTimers(); vi.restoreAllMocks(); });

const oldRange = { from: '2026-12-21', through: '2026-12-27' };
const currentRange = { from: '2026-12-28', through: '2027-01-03' };
const nextRange = { from: '2027-01-04', through: '2027-01-10' };
const data = { ...previewPantryData, settings: { ...previewPantryData.settings, timeZone: 'Pacific/Kiritimati' }, groceryGeneration: { ranges: [oldRange], unknownRange: false } };
const selected = () => screen.getByRole('group', { name: 'Planning week' });
const saved = () => screen.getByLabelText('Saved grocery ranges');

it('uses the owner calendar across year boundaries and shares the displayed week with both rebuild callers', async () => {
  const user = userEvent.setup();
  const rpc = vi.fn().mockResolvedValue({ data: 3, error: null });
  const rebuild = (range: PlanningRange) => rebuildShoppingFromPlan({ rpc } as unknown as Parameters<typeof rebuildShoppingFromPlan>[0], range);
  render(<PantryDataProvider data={data}><App onRebuildShopping={rebuild} /></PantryDataProvider>);
  await user.click(screen.getByRole('button', { name: /This week/ }));
  // It is already Monday in the owner timezone, while the device/UTC calendar is Sunday.
  expect(selected()).toHaveTextContent('Dec 28, 2026 – Jan 3, 2027');
  await user.click(screen.getByRole('button', { name: /Rebuild grocery list/ }));
  await waitFor(() => expect(rpc).toHaveBeenLastCalledWith('rebuild_shopping_from_plan', { p_from: currentRange.from, p_through: currentRange.through }));
  await user.click(screen.getByRole('button', { name: 'Next week' }));
  expect(selected()).toHaveTextContent('Jan 4 – Jan 10, 2027');
  await user.click(screen.getByRole('button', { name: /Grocery list/ }));
  expect(selected()).toHaveTextContent('Jan 4 – Jan 10, 2027');
  expect(saved()).toHaveTextContent('Generated for: Dec 21 – Dec 27, 2026');
  expect(rpc).toHaveBeenCalledTimes(1);
  await user.click(screen.getByRole('button', { name: /Rebuild from plan/ }));
  await waitFor(() => expect(rpc).toHaveBeenLastCalledWith('rebuild_shopping_from_plan', { p_from: nextRange.from, p_through: nextRange.through }));
  await user.click(screen.getByRole('button', { name: 'Previous week' }));
  await user.click(screen.getByRole('button', { name: 'Previous week' }));
  await user.click(screen.getByRole('button', { name: /This week/ }));
  expect(selected()).toHaveTextContent('Dec 21 – Dec 27, 2026');
  await user.click(screen.getAllByRole('button', { name: 'Add to this day' })[0]);
  await user.click(within(screen.getByRole('dialog')).getByRole('option', { name: /Simple Pancakes/ }));
  expect(within(screen.getByRole('dialog')).getByLabelText('Date')).toHaveValue('2026-12-21');
  expect(rpc).toHaveBeenCalledTimes(2);
});

it.each([
  ['2026-01-01', 0, '2025-12-29', '2026-01-04'],
  ['2026-03-01', 1, '2026-03-02', '2026-03-08'],
  ['2026-03-09', -1, '2026-03-02', '2026-03-08'],
] as const)('keeps calendar week boundaries for %s with offset %s', (today, offset, from, through) => {
  expect(planningWeek(today, offset)).toEqual({ from, through });
});

it('uses the previous owner week when UTC has already reached Monday', async () => {
  vi.setSystemTime(new Date('2026-01-05T00:30:00Z'));
  const rebuild = vi.fn().mockResolvedValue(0);
  render(<PantryDataProvider data={{ ...data, settings: { ...data.settings, timeZone: 'America/Los_Angeles' } }}><App onRebuildShopping={rebuild} /></PantryDataProvider>);
  await userEvent.click(screen.getByRole('button', { name: /Grocery list/ }));
  expect(selected()).toHaveTextContent('Dec 29, 2025 – Jan 4, 2026');
  await userEvent.click(screen.getByRole('button', { name: /Rebuild from plan/ }));
  await waitFor(() => expect(rebuild).toHaveBeenCalledExactlyOnceWith({ from: '2025-12-29', through: '2026-01-04' }));
});

it('keeps an in-flight rebuild bound to its submitted range while navigation stays read-only', async () => {
  let finish!: (count: number) => void;
  const rebuild = vi.fn(() => new Promise<number>((resolve) => { finish = resolve; }));
  const view = (range: PlanningRange) => <PantryDataProvider data={{ ...data, groceryGeneration: { ranges: [range], unknownRange: false } }}><App onRebuildShopping={rebuild} /></PantryDataProvider>;
  const mounted = render(view(oldRange));
  const user = userEvent.setup();
  await user.click(screen.getByRole('button', { name: /Grocery list/ }));
  await user.click(screen.getByRole('button', { name: /Rebuild from plan/ }));
  await user.click(screen.getByRole('button', { name: 'Next week' }));
  expect(screen.getByRole('button', { name: /Rebuild from plan/ })).toBeDisabled();
  expect(rebuild).toHaveBeenCalledExactlyOnceWith(currentRange);
  await act(async () => { finish(3); });
  mounted.rerender(view(currentRange));
  expect(saved()).toHaveTextContent('Dec 28, 2026 – Jan 3, 2027');
  expect(selected()).toHaveTextContent('Jan 4 – Jan 10, 2027');
  expect(rebuild).toHaveBeenCalledTimes(1);
});

it('changes saved range only with refreshed database metadata, including failed rebuilds and another session', async () => {
  const user = userEvent.setup();
  const rebuild = vi.fn().mockRejectedValue(new Error('Rebuild failed'));
  const view = (ranges: PlanningRange[]) => <PantryDataProvider data={{ ...data, groceryGeneration: { ranges, unknownRange: false } }}><App onRebuildShopping={rebuild} /></PantryDataProvider>;
  const mounted = render(view([oldRange]));
  await user.click(screen.getByRole('button', { name: /Grocery list/ }));
  await user.click(screen.getByRole('button', { name: 'Next week' }));
  await user.click(screen.getByRole('button', { name: /Rebuild from plan/ }));
  await waitFor(() => expect(screen.getByText('Rebuild failed')).toBeInTheDocument());
  expect(saved()).toHaveTextContent('Dec 21 – Dec 27, 2026');
  expect(selected()).toHaveTextContent('Jan 4 – Jan 10, 2027');
  rebuild.mockResolvedValue(2);
  await user.click(screen.getByRole('button', { name: /Rebuild from plan/ }));
  await waitFor(() => expect(screen.getByRole('button', { name: /Rebuild from plan/ })).toBeEnabled());
  expect(saved()).toHaveTextContent('Dec 21 – Dec 27, 2026');
  mounted.rerender(view([nextRange]));
  expect(saved()).toHaveTextContent('Generated for: Jan 4 – Jan 10, 2027');
  mounted.rerender(view([oldRange, currentRange]));
  expect(saved()).toHaveTextContent('Dec 21 – Dec 27, 2026; Dec 28, 2026 – Jan 3, 2027');
  expect(selected()).toHaveTextContent('Jan 4 – Jan 10, 2027');
  expect(rebuild).toHaveBeenCalledTimes(2);
});

it('keeps direct-product and grouped portion edits explicit without rebuilding or relabeling saved demand', async () => {
  const user = userEvent.setup();
  const rebuild = vi.fn().mockResolvedValue(3);
  const edit = vi.fn();
  const base: PlannedMealView = { ...previewPantryData.plannedMeals[0], status: 'planned', consumptionStatus: 'planned', isLeftover: false, dateKey: '2027-01-05', plannedServings: 1 };
  const initial = [
    { ...base, id: 'yogurt', name: 'Yogurt', groupId: 'snack', recipeId: undefined, sourceKind: 'product' as const, consumeFromInventory: true },
    { ...base, id: 'chicken', name: 'Chicken', groupId: 'dinner' },
    { ...base, id: 'rice', name: 'Rice', groupId: 'dinner' },
  ];
  function Harness() {
    const [plannedMeals, setPlans] = useState(initial);
    return <PantryDataProvider data={{ ...data, plannedMeals }}><App onRebuildShopping={rebuild} onSetPlannedConsumptionServings={async (id, servings) => {
      edit(id, servings); setPlans((plans) => plans.map((plan) => plan.id === id ? { ...plan, plannedServings: servings } : plan));
    }} /></PantryDataProvider>;
  }
  render(<Harness />);
  await user.click(screen.getByRole('button', { name: /This week/ }));
  await user.click(screen.getByRole('button', { name: 'Next week' }));
  for (const [name, id, amount] of [['Yogurt', 'yogurt', 2], ['Chicken', 'chicken', 1.5], ['Rice', 'rice', 0.75]] as const) {
    fireEvent.change(screen.getByLabelText(`Planned servings for ${name}`), { target: { value: String(amount) } });
    await user.click(screen.getByRole('button', { name: 'Save' }));
    await waitFor(() => expect(edit).toHaveBeenLastCalledWith(id, amount));
  }
  expect(rebuild).not.toHaveBeenCalled();
  await user.click(screen.getByRole('button', { name: /Grocery list/ }));
  expect(saved()).toHaveTextContent('Dec 21 – Dec 27, 2026');
  expect(selected()).toHaveTextContent('Jan 4 – Jan 10, 2027');
  await user.click(screen.getByRole('button', { name: /Rebuild from plan/ }));
  await waitFor(() => expect(rebuild).toHaveBeenCalledExactlyOnceWith(nextRange));
});

it('loads actual saved ranges without treating hidden, mixed, manual or legacy rows as the selection', async () => {
  const rows = [
    { id: 'hidden', source: 'generated', generated_active: false, generated_from: oldRange.from, generated_through: oldRange.through, checked_at: '2026-12-21T12:00:00Z', note: 'keep', qty_needed: 7 },
    { id: 'visible', source: 'generated', generated_from: currentRange.from, generated_through: currentRange.through },
    { id: 'duplicate', source: 'generated', generated_from: currentRange.from, generated_through: currentRange.through },
    { id: 'legacy', source: 'generated', generated_from: null, generated_through: null },
    { id: 'manual', source: 'manual', generated_from: nextRange.from, generated_through: nextRange.through },
  ].map((row) => ({ quantity_label: null, qty_needed: null, received_qty_base: 0, ...row }));
  const before = structuredClone(rows);
  const tables: Record<string, unknown[]> = { personal_settings: [{ time_zone: 'UTC' }], shopping_items: rows };
  const db = { from(table: string) {
    let result: unknown = tables[table] ?? [];
    const query: any = new Proxy({}, { get(_target, key) {
      if (key === 'then') return (yes: any, no: any) => Promise.resolve({ data: result, error: null }).then(yes, no);
      return () => { if (key === 'single') result = (result as unknown[])[0]; return query; };
    } }); return query;
  } };
  const loaded = await loadPantryData(db as Parameters<typeof loadPantryData>[0]);
  expect(loaded.groceryGeneration).toEqual({ ranges: [oldRange, currentRange], unknownRange: true });
  expect(loaded.grocerySections.flatMap((section) => section.items).map((item) => item.id)).not.toContain('hidden');
  expect(rows).toEqual(before);
  render(<PantryDataProvider data={loaded}><App /></PantryDataProvider>);
  await userEvent.click(screen.getByRole('button', { name: /Grocery list/ }));
  expect(saved()).toHaveTextContent('some ranges unavailable');
});

it('warns on uncovered selection while recognizing an expanded cross-week source range', async()=>{
  const rebuild=vi.fn();
  render(<PantryDataProvider data={{...data,groceryGeneration:{ranges:[{from:oldRange.through,through:currentRange.through}],unknownRange:false}}}><App onRebuildShopping={rebuild}/></PantryDataProvider>);
  await userEvent.click(screen.getByRole('button',{name:/Grocery list/}));
  expect(screen.queryByLabelText('Grocery coverage warning')).not.toBeInTheDocument();
  await userEvent.click(screen.getByRole('button',{name:'Previous week'}));
  expect(screen.getByLabelText('Grocery coverage warning')).toHaveTextContent('Changing weeks does not regenerate groceries');
  expect(saved()).toHaveTextContent(/Dec 27, 2026 . Jan 3, 2027/);
  expect(rebuild).not.toHaveBeenCalled();
});
