import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';
import { DayPlanFields } from './PlanComposer';
import { PantryDataProvider, previewPantryData, type PantryData } from './pantry-data';

function mount(data: PantryData) {
  return render(<PantryDataProvider data={data}><form aria-label="Plan"><DayPlanFields /></form></PantryDataProvider>);
}

describe('leftover planning', () => {
  it('labels an overdue preparation as planned and not cooked, retaining its scheduled date', async () => {
    mount({ ...previewPantryData, preparedLots: [], plannedMeals: [{ ...previewPantryData.plannedMeals[0], dateKey: '2020-09-04', status: 'planned', isLeftover: false }] });
    await userEvent.click(screen.getByRole('tab', { name: /Leftovers/ }));
    const option = screen.getByRole('option', { name: /Planned, not cooked/ });
    expect(option).toHaveTextContent('Scheduled Sep 4, 2020');
    expect(option).toHaveTextContent('Past scheduled date');
    expect(option).not.toHaveTextContent('Future preparation');
    expect(option).toBeEnabled();
  });
  it('can plan an exact cooked batch after its original plan is gone, using actual yield nutrition and cost', async () => {
    const user = userEvent.setup();
    mount({ ...previewPantryData, plannedMeals: [], preparedLots: [{ ...previewPantryData.preparedLots[0], name: 'Chicken dinner', mealPlanId: undefined, costPerServing: 4, nutritionPerServing: { Calories: 400, Protein: 30, Carbs: 5, Fat: 10, Fiber: 1, Sodium: 100 } }] });
    await user.click(screen.getByRole('tab', { name: /Leftovers/ }));
    await user.click(screen.getByRole('option', { name: /Chicken dinner/ }));
    const form = screen.getByRole('form', { name: 'Plan' }) as HTMLFormElement;
    const values = new FormData(form);
    expect(values.get('intent')).toBe('consume');
    expect(values.get('inventory_lot')).toBe('preview-prep-1');
    expect(values.get('source_group_id')).toBe('');
    const preview = screen.getByLabelText('Nutrition and cost preview');
    expect(within(preview).getByText('400 cal')).toBeInTheDocument();
    expect(within(preview).getByText('~$4.00')).toBeInTheDocument();
    await user.clear(screen.getByLabelText(/Servings you.ll eat/));
    await user.type(screen.getByLabelText(/Servings you.ll eat/), '0.5');
    expect(within(preview).getByText('200 cal')).toBeInTheDocument();
    expect(within(preview).getByText('~$2.00')).toBeInTheDocument();
  });

  it('keeps every dish in a future leftover group and includes each portion in the preview', async () => {
    const user = userEvent.setup();
    const recipes = previewPantryData.recipes.slice(0, 2).map((recipe, i) => ({ ...recipe, name: ['Chicken', 'Rice'][i], servings: 4, costPerServing: i + 1, nutritionValues: { Calories: (i + 1) * 400, Protein: 40, Carbs: 40, Fat: 10, Fiber: 4, Sodium: 100 } }));
    const plannedMeals = recipes.map((recipe, i) => ({ ...previewPantryData.plannedMeals[0], id: `plan-${i}`, groupId: 'dinner', name: recipe.name, recipeId: recipe.id }));
    mount({ ...previewPantryData, recipes, plannedMeals, preparedLots: [] });
    await user.click(screen.getByRole('tab', { name: /Leftovers/ }));
    await user.click(screen.getByRole('option', { name: /Chicken \+ Rice/ }));
    expect(screen.getByText('Chicken + Rice')).toBeInTheDocument();
    const preview = screen.getByLabelText('Nutrition and cost preview');
    expect(within(preview).getByText('300 cal')).toBeInTheDocument();
    expect(within(preview).getByText('~$3.00')).toBeInTheDocument();
  });

  it('distinguishes otherwise identical batches by preparation date and time', async () => {
    const user = userEvent.setup();
    const first = { ...previewPantryData.preparedLots[0], id: 'batch-monday', preparedAt: '2026-09-28T18:00:00Z' };
    const second = { ...first, id: 'batch-tuesday', preparedAt: '2026-09-29T18:00:00Z' };
    mount({ ...previewPantryData, settings: { ...previewPantryData.settings, timeZone: 'UTC' }, preparedLots: [first, second] });
    await user.click(screen.getByRole('tab', { name: /Leftovers/ }));
    expect(screen.getByRole('option', { name: /Made Sep 28, 2026/ })).toBeInTheDocument();
    await user.click(screen.getByRole('option', { name: /Made Sep 29, 2026/ }));
    const form = screen.getByRole('form', { name: 'Plan' }) as HTMLFormElement;
    expect(new FormData(form).get('inventory_lot')).toBe('batch-tuesday');
  });

  it('shows unavailable cost rather than free food for an unpriced prepared batch', async () => {
    const user = userEvent.setup();
    mount({ ...previewPantryData, preparedLots: [{ ...previewPantryData.preparedLots[0], costPerServing: null }] });
    await user.click(screen.getByRole('tab', { name: /Leftovers/ }));
    await user.click(screen.getByRole('option', { name: /Already cooked/ }));
    expect(within(screen.getByLabelText('Nutrition and cost preview')).getByText('Cost').parentElement).toHaveTextContent('Unavailable');
  });
});

it('keeps unequal source portions and allows rice alone while preparation is pending', async () => {
 const recipes = previewPantryData.recipes.slice(0,2).map((r,i)=>({...r,name:i?'Rice':'Chicken'}));
 const plannedMeals = recipes.map((r,i)=>({...previewPantryData.plannedMeals[0],id:'source-'+i,groupId:'unequal',recipeId:r.id,name:r.name,plannedServings:i?1:0.5,status:'planned' as const,isLeftover:false}));
 const view=mount({...previewPantryData,recipes,plannedMeals,preparedLots:[]});
 await userEvent.click(screen.getByRole('tab',{name:/Leftovers/}));
 await userEvent.click(screen.getByRole('option',{name:/Chicken \+ Rice/}));
 expect(screen.getByLabelText('Servings of Chicken to eat')).toHaveValue(.5);
 expect(screen.getByLabelText('Servings of Rice to eat')).toHaveValue(1);
 expect(screen.getAllByText('Not cooked yet')).toHaveLength(2);
 const payload=()=>JSON.parse(String(new FormData(screen.getByRole('form',{name:'Plan'}) as HTMLFormElement).get('leftover_dishes')));
 expect(payload()).toEqual([{source_meal_plan:'source-0',planned_servings:.5},{source_meal_plan:'source-1',planned_servings:1}]);
 await userEvent.click(screen.getByRole('checkbox',{name:'Chicken'}));
 expect(payload()).toEqual([{source_meal_plan:'source-1',planned_servings:1}]);
 expect(screen.queryByLabelText('Servings of Chicken to eat')).not.toBeInTheDocument();
 view.unmount();
});
