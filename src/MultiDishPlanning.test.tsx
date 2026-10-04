import { fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from './database.types';
import { App } from './App';
import { PantryDataProvider, previewPantryData, type PlannedMealView } from './pantry-data';
import { savePanelAction } from './lib/pantry-actions';
import { cookRecipe, consumePlannedMeals } from './lib/pantry-repository';

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
  expect(first.querySelector('.deck-card-header')).toHaveTextContent('4 servings');
  expect(first.querySelector('.deck-card-body > details > summary')).toHaveTextContent('Method');
  expect(first.querySelector('.deck-card-body > details')).toHaveAttribute('open');
  await user.click(within(first).getByRole('button', { name: 'Finish cooking' }));
  await waitFor(() => expect(cook).toHaveBeenCalledWith(dishes[0].id, expect.objectContaining({ mealPlanId: 'dish-one', scale: 2, servingsMade: 4 })));
  rerender(view(plans.map((plan) => plan.id === 'dish-one' ? { ...plan, status: 'made' } : plan)));
  await waitFor(() => expect(screen.getAllByRole('article', { name: 'Chicken' })).toHaveLength(1));
  expect(screen.getByLabelText('Recipe multiplier for Chicken')).toHaveValue(.5);
  expect(JSON.parse(localStorage.getItem('mise.on-deck-plan-focus')!)).toEqual(['dish-one', 'dish-two']);
  await user.click(screen.getByRole('button', { name: 'Show all on deck' }));
  expect(screen.getAllByRole('article', { name: 'Chicken' })).toHaveLength(2);
  expect(screen.getAllByLabelText('Recipe multiplier for Chicken').map((input) => (input as HTMLInputElement).value).sort()).toEqual(['0.5', '3']);
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


it('stages configured unplanned dishes alongside matching plans, deduplicates repeat staging and finishes only the selected draft', async () => {
  const user = userEvent.setup();
  const dateKey = new Intl.DateTimeFormat('en-CA', { timeZone: data.settings.timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
  const plan = { ...previewPantryData.plannedMeals[0], id: 'matching-plan', recipeId: dishes[0].id, dateKey, status: 'planned' as const, isLeftover: false, consumptionStatus: 'planned', scaleFactor: 3 };
  const cook = vi.fn().mockResolvedValue({ prepId: 'prep', lotId: 'lot', servingsMade: 4, servingsRemaining: 2.5, location: 'fridge' });
  const view = () => <PantryDataProvider data={{ ...data, plannedMeals: [plan] }}><App onCookRecipe={cook} /></PantryDataProvider>;
  const stage = async (make: number, rice: boolean) => {
    await user.click(screen.getByRole('button', { name: 'Recipes' }));
    await user.click(screen.getByRole('button', { name: 'Choose recipes' }));
    await waitFor(() => expect(within(screen.getByRole('dialog')).getByRole('button', { name: /Chicken/ })).toBeEnabled());
    await user.click(within(screen.getByRole('dialog')).getByRole('button', { name: /Chicken/ }));
    fireEvent.change(screen.getByLabelText('Make servings of Chicken'), { target: { value: String(make) } });
    fireEvent.change(screen.getByLabelText('Eat servings of Chicken'), { target: { value: '1.5' } });
    if (rice) {
      await user.click(within(screen.getByRole('dialog')).getByRole('button', { name: /Rice/ }));
      fireEvent.change(screen.getByLabelText('Make servings of Rice'), { target: { value: '2' } });
      fireEvent.change(screen.getByLabelText('Eat servings of Rice'), { target: { value: '.5' } });
    }
    await user.click(screen.getByRole('button', { name: 'Add to On deck' }));
  };
  const first = render(view());
  await stage(4, true); await stage(4, true);
  expect(screen.getAllByRole('article', { name: 'Chicken' })).toHaveLength(2);
  expect(screen.getAllByRole('article', { name: 'Rice' })).toHaveLength(1);
  await stage(2, false);
  expect(screen.getAllByRole('article', { name: 'Chicken' })).toHaveLength(3);
  first.unmount(); render(view());
  await user.click(screen.getByRole('button', { name: 'On deck' }));
  const chicken = screen.getAllByRole('article', { name: 'Chicken' }).find((card) => (within(card).getByLabelText('Recipe multiplier for Chicken') as HTMLInputElement).value === '2')!;
  expect(within(chicken).getByText('Unplanned')).toBeInTheDocument();
  expect(within(chicken).getByLabelText('Servings of Chicken made')).toHaveValue(4);
  expect(within(chicken).getByLabelText('Servings of Chicken eaten now')).toHaveValue(1.5);
  const rice = screen.getByRole('article', { name: 'Rice' });
  expect(within(rice).getByLabelText('Recipe multiplier for Rice')).toHaveValue(.5);
  expect(within(rice).getByLabelText('Servings of Rice made')).toHaveValue(2);
  expect(within(rice).getByLabelText('Servings of Rice eaten now')).toHaveValue(.5);
  await user.click(within(chicken).getByRole('button', { name: 'Finish cooking' }));
  await waitFor(() => expect(cook).toHaveBeenCalledExactlyOnceWith(dishes[0].id, expect.objectContaining({ scale: 2, servingsMade: 4, servingsEaten: 1.5, mealPlanId: undefined, cookingDraftId: expect.any(String) })));
  expect(screen.getAllByRole('article', { name: 'Chicken' })).toHaveLength(2);
  expect(screen.getAllByLabelText('Recipe multiplier for Chicken').map((input) => (input as HTMLInputElement).value).sort()).toEqual(['1', '3']);
  expect(screen.getByRole('article', { name: 'Rice' })).toBeInTheDocument();
});

it('generic Make batch stays unplanned, reuses its draft on repeated clicks and leaves a matching plan untouched', async () => {
  const user = userEvent.setup();
  const dateKey = new Intl.DateTimeFormat('en-CA', { timeZone: data.settings.timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
  const plan = { ...previewPantryData.plannedMeals[0], id: 'unrelated-plan', recipeId: dishes[0].id, dateKey, status: 'planned' as const, isLeftover: false, consumptionStatus: 'planned', scaleFactor: 3 };
  const cook = vi.fn().mockResolvedValue({ prepId: 'prep', lotId: 'lot', servingsMade: 2, servingsRemaining: 2, location: 'fridge' });
  render(<PantryDataProvider data={{ ...data, recipes: [dishes[0]], plannedMeals: [plan] }}><App onCookRecipe={cook} /></PantryDataProvider>);
  for (let i = 0; i < 2; i++) {
    await user.click(screen.getByRole('button', { name: 'Recipes' }));
    await user.click(screen.getByRole('button', { name: 'Make batch' }));
  }
  const cards = screen.getAllByRole('article', { name: 'Chicken' });
  expect(cards).toHaveLength(2);
  const unplanned = cards.find((card) => within(card).queryByText('Unplanned'))!;
  expect(within(unplanned).getByLabelText('Recipe multiplier for Chicken')).toHaveValue(1);
  await user.click(within(unplanned).getByRole('button', { name: 'Finish cooking' }));
  await waitFor(() => expect(cook).toHaveBeenCalledExactlyOnceWith(dishes[0].id, expect.objectContaining({ mealPlanId: undefined, scale: 1 })));
  expect(screen.getAllByRole('article', { name: 'Chicken' })).toHaveLength(1);
  expect(screen.getByLabelText('Recipe multiplier for Chicken')).toHaveValue(3);
  expect(screen.getByLabelText('Recipe multiplier for Chicken')).toHaveAttribute('readonly');
});


it('remounts a staged card after an uncertain cooking response and replays only its original unplanned batch', async () => {
  const user = userEvent.setup();
  const dateKey = new Intl.DateTimeFormat('en-CA', { timeZone: data.settings.timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
  const plan = { ...previewPantryData.plannedMeals[0], id: 'matching-plan', recipeId: dishes[0].id, dateKey, status: 'planned' as const, isLeftover: false, consumptionStatus: 'planned', scaleFactor: 3 };
  const committed = new Map<string, unknown>();
  const rpc = vi.fn(async (_name: string, args: Record<string, unknown>) => {
    if (!committed.has(String(args.p_request_id))) committed.set(String(args.p_request_id), args);
    return { data: { prepId: 'saved-prep', lotId: 'saved-lot', servingsMade: 4, servingsRemaining: 2.5, location: 'fridge' }, error: rpc.mock.calls.length === 1 ? new Error('Response lost') : null };
  });
  const client = { rpc } as unknown as SupabaseClient<Database>;
  const view = () => <PantryDataProvider data={{ ...data, recipes: [dishes[0]], plannedMeals: [plan] }}><App onCookRecipe={(id, options) => cookRecipe(client, id, options)} /></PantryDataProvider>;
  const first = render(view());
  await user.click(screen.getByRole('button', { name: 'Recipes' }));
  await user.click(screen.getByRole('button', { name: 'Choose recipes' }));
  await waitFor(() => expect(within(screen.getByRole('dialog')).getByRole('button', { name: /Chicken/ })).toBeEnabled());
  await user.click(within(screen.getByRole('dialog')).getByRole('button', { name: /Chicken/ }));
  fireEvent.change(screen.getByLabelText('Make servings of Chicken'), { target: { value: '4' } });
  fireEvent.change(screen.getByLabelText('Eat servings of Chicken'), { target: { value: '1.5' } });
  await user.click(screen.getByRole('button', { name: 'Add to On deck' }));
  const draft = () => screen.getAllByRole('article', { name: 'Chicken' }).find((card) => within(card).queryByText('Unplanned'))!;
  await user.click(within(draft()).getByRole('button', { name: 'Finish cooking' }));
  await waitFor(() => expect(within(draft()).getByRole('button', { name: 'Retry saved batch' })).toBeEnabled());
  const persistedDrafts = localStorage.getItem('mise.on-deck-drafts');
  first.unmount(); render(view());
  await user.click(screen.getByRole('button', { name: 'On deck' }));
  await waitFor(() => expect(within(draft()).getByRole('button', { name: 'Retry saved batch' })).toBeEnabled());
  expect(localStorage.getItem('mise.on-deck-drafts')).toBe(persistedDrafts);
  expect(within(draft()).getByLabelText('Servings of Chicken made')).toHaveValue(4);
  expect(within(draft()).getByLabelText('Servings of Chicken eaten now')).toHaveValue(1.5);
  fireEvent.change(within(draft()).getByLabelText('Servings of Chicken made'), { target: { value: '8' } });
  fireEvent.change(within(draft()).getByLabelText('Servings of Chicken eaten now'), { target: { value: '.25' } });
  await user.click(within(draft()).getByRole('button', { name: 'Retry saved batch' }));
  await waitFor(() => expect(screen.queryByText('Unplanned')).not.toBeInTheDocument());
  expect(rpc).toHaveBeenCalledTimes(2);
  expect(rpc.mock.calls[1]).toEqual(rpc.mock.calls[0]);
  expect(rpc.mock.calls[0][1]).toMatchObject({ p_recipe: dishes[0].id, p_scale: 2, p_servings: 4, p_eaten_servings: 1.5 });
  expect(rpc.mock.calls[0][1]).not.toHaveProperty('p_meal_plan');
  expect(committed.size).toBe(1);
  expect(screen.getAllByRole('article', { name: 'Chicken' })).toHaveLength(1);
  expect(screen.getByLabelText('Recipe multiplier for Chicken')).toHaveValue(3);
  expect(localStorage.getItem('mise.pending-mutations.v1')).toBe('{}');
});

it('associates grouped planned and eaten portions with their named dishes', async () => {
  const dateKey = new Intl.DateTimeFormat('en-CA', { timeZone: data.settings.timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
  const base = { ...previewPantryData.plannedMeals[0], dateKey, groupId: 'named-dinner', status: 'made' as const, isLeftover: false, slot: 'DINNER' };
  const save = vi.fn().mockResolvedValue(undefined);
  const plans = [{ ...base, id: 'broccoli', name: 'Broccoli', plannedServings: 1, actualServings: .5, consumptionStatus: 'fulfilled' }, { ...base, id: 'rice', name: 'Rice', plannedServings: 2, consumptionStatus: 'planned' }];
  render(<PantryDataProvider data={{ ...data, plannedMeals: plans }}><App onSetPlannedConsumptionServings={save} /></PantryDataProvider>);
  await userEvent.click(screen.getByRole('button', { name: 'This week' }));
  const broccoli = screen.getByRole('group', { name: 'Broccoli portion' });
  const rice = screen.getByRole('group', { name: 'Rice portion' });
  expect(within(broccoli).getByText('Broccoli')).toBeVisible();
  expect(within(broccoli).getByLabelText('Planned servings for Broccoli')).toHaveValue(1);
  expect(within(broccoli).getByLabelText('Planned servings for Broccoli')).toBeDisabled();
  expect(within(broccoli).getByText('½ servings eaten')).toBeVisible();
  expect(within(rice).getByText('Rice')).toBeVisible();
  expect(within(rice).getByLabelText('Planned servings for Rice')).toHaveValue(2);
  fireEvent.change(within(rice).getByLabelText('Planned servings for Rice'), { target: { value: '1.5' } });
  await userEvent.click(within(rice).getByRole('button', { name: 'Save' }));
  await waitFor(() => expect(save).toHaveBeenCalledExactlyOnceWith('rice', 1.5));
});
