import { act, render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { expect, it, vi } from 'vitest';
import { App } from './App';
import { PantryDataProvider, previewPantryData } from './pantry-data';

it('retains the approximation marker and unknown completeness in Today food cost', () => {
  const entries = [
    { ...previewPantryData.foodLog[0], id: 'estimated', cost: 6.71, costIsEstimated: true },
    { ...previewPantryData.foodLog[0], id: 'unknown', cost: null, costIsEstimated: false },
  ];
  render(<PantryDataProvider data={{ ...previewPantryData, foodLog: entries }}><App /></PantryDataProvider>);
  const metric = screen.getByText('Food cost').closest('.headline-metric') as HTMLElement;
  expect(within(metric).getByText('~$6.71 + unknown')).toBeVisible();
});

it('shows Saving on the first cooking submission and offers retry only after uncertainty', async () => {
  localStorage.clear();
  let rejectCook!: (reason: Error) => void;
  const cook = vi.fn(() => new Promise<never>((_resolve, reject) => { rejectCook = reject; }));
  const recipe = previewPantryData.recipes[0];
  render(<PantryDataProvider data={{ ...previewPantryData, recipes: [recipe], plannedMeals: [] }}><App onCookRecipe={cook} /></PantryDataProvider>);
  await userEvent.click(screen.getByRole('button', { name: 'Recipes' }));
  await userEvent.click(screen.getByRole('button', { name: 'Make batch' }));
  const card = screen.getByRole('article', { name: recipe.name });
  await userEvent.click(within(card).getByRole('button', { name: 'Finish cooking' }));
  expect(within(card).getByRole('button', { name: 'Saving…' })).toBeDisabled();
  expect(within(card).queryByText(/retry/i)).not.toBeInTheDocument();
  await act(async () => rejectCook(new Error('Response lost')));
  expect(within(card).getByRole('button', { name: 'Retry saved batch' })).toBeEnabled();
});
