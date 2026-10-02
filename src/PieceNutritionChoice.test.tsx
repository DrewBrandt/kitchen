import { render, screen, within, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { expect, it, vi } from 'vitest';
import { App } from './App';
import { PantryDataProvider, previewPantryData } from './pantry-data';
import { RECIPES } from './data';

it('blocks nonuniform overridden cooking until explicit batch-only consent', async () => {
  localStorage.clear();
  const user = userEvent.setup();
  const onCookRecipe = vi.fn().mockResolvedValue({ prepId: 'prep', lotId: 'made', servingsMade: 4, servingsRemaining: 4, location: 'fridge' });
  const recipe = { ...RECIPES[0], id: 'piece-test', name: 'Piece test', hasNutritionOverride: true, servings: 4,
    ingredients: [{ id: 'ingredient', label: '3 thighs', stock: '900 g', baseGrams: 600, quantity: 600, unit: 'g', name: 'Chicken', pieceBasis: { count: 3, grams: 600, label: 'thighs', sourceQuantity: 600, sourceUnit: 'g', provenance: 'fixture' }, pieceLots: [{ id: 'lot', label: 'Pack', remainingBase: 900, remainingPieces: 6 }] }] };
  render(<PantryDataProvider data={{ ...previewPantryData, recipes: [recipe], plannedMeals: [] }}><App onCookRecipe={onCookRecipe} /></PantryDataProvider>);
  await user.click(screen.getByRole('button', { name: 'Recipes' }));
  await user.click(screen.getByRole('button', { name: 'Make batch' }));
  const card = screen.getByRole('article', { name: 'Piece test' });
  await waitFor(() => expect(within(card).getByRole('button', { name: 'Finish cooking' })).toBeDisabled());
  expect(within(card).getByText('Saved recipe nutrition stays unchanged.')).toBeInTheDocument();
  await user.click(within(card).getByLabelText('Use ingredient nutrition for this batch'));
  await user.click(within(card).getByRole('button', { name: 'Finish cooking' }));
  await waitFor(() => expect(onCookRecipe).toHaveBeenCalledWith('piece-test', expect.objectContaining({ useIngredientNutrition: true })));
});
