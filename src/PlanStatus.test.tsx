import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { App } from './App';
import { PantryDataProvider, previewPantryData, type PlannedMealView } from './pantry-data';
import { preparedPlanAvailability } from './lib/prepared-plan';

const dateKey = () => new Intl.DateTimeFormat('en-CA', { timeZone: previewPantryData.settings.timeZone }).format(new Date());
const sources = [
  { id: 'source', recipe: 'rice', group_id: 'source-group' },
  { id: 'other-source', recipe: 'rice', group_id: 'other-group' },
];
const oldPrep = { id: 'old-prep', recipe: 'rice', meal_plan: 'other-source', voided_at: null };
const oldLot = { id: 'old-lot', prep: oldPrep.id, remaining_qty: 2 };
const sourcePrep = { id: 'new-prep', recipe: 'rice', meal_plan: 'source', voided_at: null as string | null };

function meal(id: string, overrides: Partial<PlannedMealView> = {}): PlannedMealView {
  return { ...previewPantryData.plannedMeals[0], id, name: id, groupId: id, dateKey: dateKey(), sourceKind: 'recipe', isLeftover: true, status: 'made', consumptionStatus: 'planned', plannedServings: 1, ...overrides };
}

function linked(id: string, source: string, preps: typeof sourcePrep[], remaining: number, fulfilled = false) {
  const availability = preparedPlanAvailability(
    { id, recipe: 'rice', inventory_lot: null, intent: 'leftover', source_meal_plan: source, leftover_of_group_id: null },
    sources, [oldPrep, ...preps], [oldLot, { id: 'new-lot', prep: sourcePrep.id, remaining_qty: remaining }],
  );
  return meal(id, { ...availability, consumptionStatus: fulfilled ? 'fulfilled' : 'planned' });
}

const consume = vi.fn().mockResolvedValue([]);
const view = (plans: PlannedMealView[]) => <PantryDataProvider data={{ ...previewPantryData, plannedMeals: plans }}><App onConsumePlannedMeals={consume} /></PantryDataProvider>;
const card = (name: string) => screen.getByRole('button', { name: `View ${name} details` }).closest('.week-meal-card') as HTMLElement;
function expectStatus(name: string, label: string, tone: string, ready: boolean) {
  const element = card(name);
  expect(within(element).getByText(label)).toHaveClass('plan-status', tone);
  expect(element).not.toHaveClass('made');
  if (label === 'Eaten') expect(element).toHaveClass('eaten');
  else expect(element).not.toHaveClass('eaten');
  if (ready) {
    expect(element).toHaveClass('ready-to-eat');
    expect(within(element).getByRole('button', { name: 'Log eaten' })).toBeEnabled();
  } else {
    expect(element).not.toHaveClass('ready-to-eat');
    expect(within(element).queryByRole('button', { name: 'Log eaten' })).not.toBeInTheDocument();
  }
}

beforeEach(() => { localStorage.clear(); consume.mockClear(); });

describe('plan status from live preparation and consumption', () => {
  it('follows prepare, consume, void, and source undo for every dependent without using older rice', async () => {
    const plans = (preps: typeof sourcePrep[], remaining: number, fulfilled = false) => [
      linked('Tomorrow rice', 'source', preps, remaining, fulfilled),
      linked('Later rice', 'source', preps, remaining),
      linked('Other rice', 'other-source', preps, remaining),
    ];
    const { rerender } = render(view(plans([], 0)));
    await userEvent.click(screen.getByRole('button', { name: /This week/ }));
    expectStatus('Tomorrow rice', 'Waiting for preparation', 'planned', false);
    expectStatus('Other rice', 'Ready · not eaten', 'ready', true);

    rerender(view(plans([sourcePrep], 2)));
    expectStatus('Tomorrow rice', 'Ready · not eaten', 'ready', true);
    rerender(view(plans([sourcePrep], 1, true)));
    expectStatus('Tomorrow rice', 'Eaten', 'eaten', false);
    expectStatus('Later rice', 'Ready · not eaten', 'ready', true);
    rerender(view(plans([sourcePrep], 2)));
    expectStatus('Tomorrow rice', 'Ready · not eaten', 'ready', true);

    rerender(view(plans([{ ...sourcePrep, voided_at: '2026-10-01T20:00:00Z' }], 0)));
    for (const name of ['Tomorrow rice', 'Later rice']) {
      expectStatus(name, 'Waiting for preparation', 'planned', false);
      expect(within(card(name)).getByRole('status')).toHaveTextContent('not cooked yet');
    }
    expectStatus('Other rice', 'Ready · not eaten', 'ready', true);
  });

  it('distinguishes exhausted live source from absent source even though both have zero available', async () => {
    render(view([linked('Exhausted rice', 'source', [sourcePrep], 0), linked('Unmade rice', 'source', [], 0)]));
    await userEvent.click(screen.getByRole('button', { name: /This week/ }));
    expectStatus('Exhausted rice', 'No servings remaining', 'planned', false);
    expect(within(card('Exhausted rice')).getByRole('status')).toHaveTextContent('no servings left');
    expectStatus('Unmade rice', 'Waiting for preparation', 'planned', false);
  });

  it('keeps grouped waiting, partially eaten, and fully eaten display consistent with the action', async () => {
    const rice = meal('Rice', { groupId: 'meal', waitingForPreparation: false, preparedServingsAvailable: 2 });
    const chicken = meal('Chicken', { groupId: 'meal', waitingForPreparation: true, preparedServingsAvailable: 0 });
    const { rerender } = render(view([rice, chicken]));
    await userEvent.click(screen.getByRole('button', { name: /This week/ }));
    expectStatus('Rice, Chicken', 'Waiting for preparation', 'planned', false);
    const eatenRice = { ...rice, consumptionStatus: 'fulfilled', preparedServingsAvailable: 0 };
    const readyChicken = { ...chicken, waitingForPreparation: false, preparedServingsAvailable: 2 };
    rerender(view([eatenRice, readyChicken]));
    expectStatus('Rice, Chicken', 'Ready · not eaten', 'ready', true);
    expect(screen.queryByRole('spinbutton', { name: 'Servings of Rice eaten now' })).not.toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Log eaten' }));
    expect(consume).toHaveBeenCalledWith([{ mealPlanId: 'Chicken', servings: 1 }]);
    rerender(view([eatenRice, { ...readyChicken, consumptionStatus: 'fulfilled', preparedServingsAvailable: 0 }]));
    expectStatus('Rice, Chicken', 'Eaten', 'eaten', false);
  });

  it('preserves ordinary preparation status and cook action after undo', async () => {
    const source = meal('Source rice', { isLeftover: false, status: 'planned' });
    const { rerender } = render(view([source]));
    await userEvent.click(screen.getByRole('button', { name: /This week/ }));
    expect(within(card('Source rice')).getByText('Planned')).toHaveClass('planned');
    expect(within(card('Source rice')).getByRole('button', { name: /^Cook / })).toBeInTheDocument();
    rerender(view([{ ...source, status: 'made', preparedServingsAvailable: 2 }]));
    expect(card('Source rice')).toHaveClass('made');
    expect(within(card('Source rice')).getByText('Made · not eaten')).toHaveClass('made');
    rerender(view([source]));
    expect(card('Source rice')).not.toHaveClass('made');
    expect(within(card('Source rice')).getByText('Planned')).toBeInTheDocument();
    expect(within(card('Source rice')).queryByRole('button', { name: 'Log eaten' })).not.toBeInTheDocument();
  });
});
