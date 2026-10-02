import { fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from './database.types';
import { App } from './App';
import { PantryDataProvider, previewPantryData, type PlannedMealView } from './pantry-data';
import { savePanelAction } from './lib/pantry-actions';
import { consumePlannedMeals } from './lib/pantry-repository';

beforeEach(() => localStorage.clear());
afterEach(() => { vi.useRealTimers(); vi.restoreAllMocks(); });
const dishes = previewPantryData.recipes.slice(0, 2).map((recipe, i) => ({ ...recipe, name: i ? 'Rice' : 'Chicken', servings: i ? 4 : 2, costPerServing: i ? 1 : 3, nutritionValues: { Calories: i ? 400 : 600, Protein: 40, Carbs: 40, Fat: 10, Fiber: 5, Sodium: 100 } }));
const data = { ...previewPantryData, recipes: dishes, settings: { ...previewPantryData.settings, timeZone: 'America/Los_Angeles' } };

it('saves independent Make/Eat quantities and restores the exact caller payload after a lost response and remount', async () => {
  vi.useFakeTimers({ toFake: ['Date'] }); vi.setSystemTime(new Date('2026-10-02T02:00:00Z'));
  const user = userEvent.setup();
  const saved = new Map<string, unknown>();
  const rpc = vi.fn(async (_name: string, args: { p_request_id: string; p_payload: unknown }) => {
    if (!saved.has(args.p_request_id)) saved.set(args.p_request_id, args.p_payload);
    return { data: { planIds: ['one', 'two'] }, error: rpc.mock.calls.length === 1 ? new Error('Response lost') : null };
  });
  const from = vi.fn(() => { throw Error('Unexpected direct table write'); });
  const client = { rpc, from } as unknown as SupabaseClient<Database>;
  const view = () => <PantryDataProvider data={data}><App onSaveAction={(kind, form) => savePanelAction(client, kind, form)} /></PantryDataProvider>;
  const open = async () => { await user.click(screen.getByRole('button', { name: 'Recipes' })); await user.click(screen.getByRole('button', { name: 'Choose recipes' })); };
  const first = render(view()); await open();
  const dialog = screen.getByRole('dialog');
  await waitFor(() => expect(within(dialog).getByRole('button', { name: /Chicken/ })).toBeEnabled());
  expect(within(dialog).getByLabelText('Date')).toHaveValue('2026-10-01');
  expect(within(dialog).getByLabelText('Time of day')).toHaveValue('dinner');
  await user.click(within(dialog).getByRole('button', { name: /Chicken/ }));
  await user.click(within(dialog).getByRole('button', { name: /Rice/ }));
  fireEvent.change(screen.getByLabelText('Make servings of Chicken'), { target: { value: '4' } });
  fireEvent.change(screen.getByLabelText('Eat servings of Chicken'), { target: { value: '1.5' } });
  fireEvent.change(screen.getByLabelText('Make servings of Rice'), { target: { value: '2' } });
  fireEvent.change(screen.getByLabelText('Eat servings of Rice'), { target: { value: '0.5' } });
  expect(screen.getByLabelText('Nutrition and cost preview')).toHaveTextContent('500 cal');
  expect(screen.getByLabelText('Nutrition and cost preview')).toHaveTextContent('$5.00');
  await user.click(screen.getByRole('button', { name: 'Plan meal' }));
  await waitFor(() => expect(screen.getByRole('button', { name: 'Retry meal' })).toBeEnabled());
  expect(rpc.mock.calls[0]).toEqual(['owner_append_plan', { p_request_id: expect.any(String), p_payload: { plan_date: '2026-10-01', daypart: 'dinner', dishes: [
    { recipe: dishes[0].id, scale_factor: 2, planned_servings: 1.5 }, { recipe: dishes[1].id, scale_factor: .5, planned_servings: .5 },
  ] } }]);
  first.unmount(); vi.setSystemTime(new Date('2026-10-03T18:00:00Z'));
  render(view()); await open();
  await waitFor(() => expect(screen.getByRole('button', { name: 'Retry meal' })).toBeEnabled());
  expect(screen.getByLabelText('Date')).toHaveValue('2026-10-01');
  expect(screen.getByLabelText('Make servings of Chicken')).toHaveValue(4);
  expect(screen.getByLabelText('Eat servings of Rice')).toHaveValue(.5);
  expect(screen.getByLabelText('Date')).toBeDisabled();
  await user.click(screen.getByRole('button', { name: 'Retry meal' }));
  await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
  expect(rpc.mock.calls[1]).toEqual(rpc.mock.calls[0]); expect(saved.size).toBe(1);
  await user.click(screen.getByRole('button', { name: 'Choose recipes' }));
  await waitFor(() => expect(within(screen.getByRole('dialog')).getByRole('button', { name: /Chicken/ })).toBeEnabled());
  expect(screen.queryByRole('button', { name: 'Retry meal' })).not.toBeInTheDocument();
  await user.click(within(screen.getByRole('dialog')).getByRole('button', { name: /Chicken/ }));
  await user.click(screen.getByRole('button', { name: 'Plan meal' }));
  await waitFor(() => expect(rpc).toHaveBeenCalledTimes(3));
  expect(rpc.mock.calls[2][1].p_request_id).not.toBe(rpc.mock.calls[0][1].p_request_id);
  expect(from).not.toHaveBeenCalled();
});

it('unlocks a rejected save for correction without leaving a stale retry on remount', async () => {
  const user = userEvent.setup();
  const rpc = vi.fn().mockResolvedValue({ data: null, error: { code: '23503', message: 'Recipe no longer exists' } });
  const client = { rpc } as unknown as SupabaseClient<Database>;
  render(<PantryDataProvider data={data}><App onSaveAction={(kind, form) => savePanelAction(client, kind, form)} /></PantryDataProvider>);
  await user.click(screen.getByRole('button', { name: 'Recipes' })); await user.click(screen.getByRole('button', { name: 'Choose recipes' }));
  await waitFor(() => expect(within(screen.getByRole('dialog')).getByRole('button', { name: /Chicken/ })).toBeEnabled());
  await user.click(within(screen.getByRole('dialog')).getByRole('button', { name: /Chicken/ }));
  fireEvent.change(screen.getByLabelText('Make servings of Chicken'), { target: { value: '0' } });
  expect(screen.getByRole('button', { name: 'Plan meal' })).toBeDisabled();
  fireEvent.change(screen.getByLabelText('Make servings of Chicken'), { target: { value: '2' } });
  await user.click(screen.getByRole('button', { name: 'Plan meal' }));
  await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent('Recipe no longer exists'));
  expect(screen.getByLabelText('Make servings of Chicken')).toBeEnabled();
  expect(screen.getByRole('button', { name: 'Plan meal' })).toBeEnabled();
  expect(localStorage.getItem('mise.pending-mutations.v1')).toBe('{}');
});

it('Cook meal stages exact unfinished plan IDs, including repeated recipes, without unrelated or completed components', async () => {
  const user = userEvent.setup();
  const today = new Intl.DateTimeFormat('en-CA', { timeZone: data.settings.timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
  const base: PlannedMealView = { ...previewPantryData.plannedMeals[0], recipeId: dishes[0].id, dateKey: today, groupId: 'dinner', status: 'planned', isLeftover: false, consumptionStatus: 'planned', slot: 'DINNER' };
  const plans = [
    { ...base, id: 'dish-one', name: 'First chicken', scaleFactor: 2, plannedServings: 1.5 },
    { ...base, id: 'dish-two', name: 'Second chicken', scaleFactor: .5, plannedServings: .5 },
    { ...base, id: 'done', name: 'Already eaten', status: 'made' as const, consumptionStatus: 'fulfilled' },
    { ...base, id: 'made-only', name: 'Already made', status: 'made' as const },
    { ...base, id: 'eaten-only', name: 'Consumed component', consumptionStatus: 'fulfilled' },
    { ...base, id: 'unrelated', name: 'Other dinner', groupId: 'other', scaleFactor: 3 },
  ];
  const cook = vi.fn().mockResolvedValue({ prepId: 'new-prep', lotId: 'new-lot', servingsMade: 4, servingsRemaining: 4, location: 'fridge', foodLogId: null });
  const view = (rows: PlannedMealView[]) => <PantryDataProvider data={{ ...data, plannedMeals: rows }}><App onCookRecipe={cook} /></PantryDataProvider>;
  const { rerender } = render(view(plans));
  await user.click(screen.getByRole('button', { name: /This week/ }));
  await user.click(screen.getByRole('button', { name: 'Cook meal' }));
  await waitFor(() => expect(screen.getAllByRole('article', { name: 'Chicken' })).toHaveLength(2));
  expect(screen.getAllByLabelText('Recipe multiplier for Chicken').map((input) => (input as HTMLInputElement).value).sort()).toEqual(['0.5', '2']);
  const first = screen.getAllByRole('article', { name: 'Chicken' }).find((card) => (within(card).getByLabelText('Recipe multiplier for Chicken') as HTMLInputElement).value === '2')!;
  await user.click(within(first).getByRole('button', { name: 'Finish cooking' }));
  await waitFor(() => expect(cook).toHaveBeenCalledWith(dishes[0].id, expect.objectContaining({ mealPlanId: 'dish-one', scale: 2, servingsMade: 4 })));
  rerender(view(plans.map((plan) => plan.id === 'dish-one' ? { ...plan, status: 'made' } : plan)));
  await waitFor(() => expect(screen.getAllByRole('article', { name: 'Chicken' })).toHaveLength(1));
  expect(screen.getByLabelText('Recipe multiplier for Chicken')).toHaveValue(.5);
  expect(JSON.parse(localStorage.getItem('mise.on-deck-plan-focus')!)).toEqual(['dish-one', 'dish-two']);
});

it('logs each grouped dish with its own portion and exact plan ID through the actual consumption caller', async () => {
  const user = userEvent.setup();
  const dateKey = new Intl.DateTimeFormat('en-CA', { timeZone: data.settings.timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
  const base: PlannedMealView = { ...previewPantryData.plannedMeals[0], recipeId: dishes[0].id, dateKey, groupId: 'dinner', status: 'made', isLeftover: false, consumptionStatus: 'planned', slot: 'DINNER', preparedServingsAvailable: 4 };
  const plans = [{ ...base, id: 'first', name: 'First dish', plannedServings: 1.5 }, { ...base, id: 'second', name: 'Second dish', plannedServings: .5 }, { ...base, id: 'done', name: 'Eaten dish', consumptionStatus: 'fulfilled' }, { ...base, id: 'other', name: 'Other meal', groupId: 'unrelated' }];
  const rpc = vi.fn().mockResolvedValue({ data: ['log1', 'log2'], error: null });
  const client = { rpc } as unknown as SupabaseClient<Database>;
  render(<PantryDataProvider data={{ ...data, plannedMeals: plans }}><App onConsumePlannedMeals={(entries) => consumePlannedMeals(client, entries)} /></PantryDataProvider>);
  await user.click(screen.getByRole('button', { name: /This week/ }));
  const group = screen.getByRole('button', { name: 'View First dish, Second dish, Eaten dish details' }).closest('.week-meal-card') as HTMLElement;
  expect(within(group).getByLabelText('Servings of First dish eaten now')).toHaveValue(1.5);
  expect(within(group).getByLabelText('Servings of Second dish eaten now')).toHaveValue(.5);
  expect(within(group).queryByLabelText('Servings of Eaten dish eaten now')).not.toBeInTheDocument();
  await user.click(within(group).getByRole('button', { name: 'Log eaten' }));
  await waitFor(() => expect(rpc).toHaveBeenCalledExactlyOnceWith('consume_planned_meals', expect.objectContaining({ p_meal_plans: ['first', 'second'], p_servings: [1.5, .5] })));
});
