import { render, screen, within, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { expect, it, vi } from 'vitest';
import { ShoppingReceiptEditor, DurableUndo } from './ShoppingReceiptEditor';
import { PantryDataProvider, previewPantryData } from './pantry-data';
import { App } from './App';

it('carries the food and quantity, searches suitable products, and preserves unknown price', async () => {
  const save = vi.fn().mockResolvedValue(undefined);
  const close = vi.fn();
  const data = { ...previewPantryData, foods: [{ id: 'chicken', name: 'Chicken', emoji: '', measureStyle: 'weight' as const }], units: [{ id: 'g', label: 'grams', shortName: 'g', measureStyle: 'weight' as const }], products: [
    { ...previewPantryData.products[0], id: 'breast', foodId: 'chicken', label: 'Chicken breast' },
    { ...previewPantryData.products[0], id: 'rice', foodId: 'rice', label: 'Unrelated rice' },
  ] };
  render(<PantryDataProvider data={data}><ShoppingReceiptEditor item={{ id: 'row', name: 'Chicken', quantity: '500 g', foodId: 'chicken', unitId: 'g', quantityNeeded: 500 }} onSave={save} onClose={close} /></PantryDataProvider>);
  expect(screen.getByLabelText('Quantity bought')).toHaveValue(500);
  expect(screen.queryByRole('option', { name: 'Unrelated rice' })).not.toBeInTheDocument();
  await userEvent.type(screen.getByLabelText('Search products'), 'breast');
  await userEvent.selectOptions(screen.getByLabelText('Product'), 'breast');
  await userEvent.clear(screen.getByLabelText('Quantity bought'));
  await userEvent.type(screen.getByLabelText('Quantity bought'), '200');
  await userEvent.click(screen.getByRole('button', { name: 'Add to inventory' }));
  await waitFor(() => expect(save).toHaveBeenCalledWith('row', expect.objectContaining({ foodId: 'chicken', productId: 'breast', quantity: 200, unit: 'g', totalPrice: null })));
  expect(close).toHaveBeenCalledOnce();
});

it('offers durable prep/receipt undo in history and shows dependency errors inline', async () => {
  const undoPrep = vi.fn().mockRejectedValue({ message: 'This batch has already been eaten from' });
  const undoReceipt = vi.fn().mockResolvedValue(undefined);
  const now = new Date().toISOString();
  render(<PantryDataProvider data={{ ...previewPantryData, preparationHistory: [{ id: 'prep', recipeId: 'r', name: 'QA batch', emoji: '', preparedAt: now, dateKey: now.slice(0,10), servingsMade: 3, servingsRemaining: 2, location: 'fridge' }], receiptHistory: [{ lotId: 'receipt', name: 'QA groceries', acquiredAt: now, quantity: '500 g', cost: null }] }}><App onUndoPrep={undoPrep} onUndoReceipt={undoReceipt} /></PantryDataProvider>);
  expect(screen.getByText('Food cost')).toBeInTheDocument();
  await userEvent.click(screen.getByRole('button', { name: 'History' }));
  expect(screen.getByText('Food cost')).toBeInTheDocument();
  await userEvent.click(screen.getByRole('button', { name: 'Undo prep QA batch' }));
  expect(await screen.findByRole('alert')).toHaveTextContent('already been eaten');
  await userEvent.click(screen.getByRole('button', { name: 'Undo receipt QA groceries' }));
  expect(undoReceipt).toHaveBeenCalledWith('receipt');
});

it('keeps unconfigured powders/grains quiet while permitting explicit chicken setup and configured direct controls', async () => {
  localStorage.clear();
  const ingredients = ['Flour','Rice','Chicken','Configured chicken'].map((name,index) => ({ id: String(index), name, label: `100 g ${name}`, quantity: 100, unit: 'g', stock: '500 g', pieceLots: [{ id: `lot-${index}`, label: name, remainingBase: 500, ...(index===3 ? { remainingPieces: 5 } : {}) }] }));
  const recipe = { ...previewPantryData.recipes[0], ingredients };
  render(<PantryDataProvider data={{ ...previewPantryData, recipes: [recipe], plannedMeals: [] }}><App /></PantryDataProvider>);
  await userEvent.click(screen.getByRole('button', { name: 'Recipes' }));
  await userEvent.click(screen.getByRole('button', { name: 'Make batch' }));
  const card = within(screen.getByRole('article', { name: recipe.name }));
  expect(card.queryByRole('button', { name: 'Choose pieces instead for Flour' })).not.toBeInTheDocument();
  expect(card.queryByRole('button', { name: 'Choose pieces instead for Rice' })).not.toBeInTheDocument();
  expect(card.getByRole('button', { name: 'Choose pieces instead for Configured chicken' })).toBeInTheDocument();
  await userEvent.click(card.getByText('Adjust ingredient quantities'));
  await userEvent.selectOptions(card.getByLabelText('Ingredient to adjust'), '2');
  expect(card.getByLabelText('Pieces currently in this package')).toBeInTheDocument();
  expect(card.getByRole('option', { name: 'Chicken', selected: true })).toHaveValue('lot-2');
});

it('prevents duplicate undo clicks while an action is pending', async () => {
  const action = vi.fn(() => new Promise<void>(() => {}));
  render(<DurableUndo label="Undo receipt" action={action} />);
  await userEvent.click(screen.getByRole('button', { name: 'Undo receipt' }));
  expect(screen.getByRole('button', { name: 'Undo receipt' })).toBeDisabled();
  expect(screen.getByRole('button', { name: 'Undo receipt' })).toHaveTextContent('Undoing');
  expect(action).toHaveBeenCalledOnce();
});

it('keeps checked changed demand visible and does not claim shopping is complete', async () => {
  const notice = 'Plan now needs 200 g more. Your check and quantity were kept.';
  render(<PantryDataProvider data={{ ...previewPantryData, grocerySections: [{ emoji: '', label: 'Pantry', items: [{ id: 'row', name: 'Rice', quantity: '100 g', checked: true, demandNotice: notice }] }] }}><App /></PantryDataProvider>);
  await userEvent.click(screen.getByRole('button', { name: 'Grocery list' }));
  expect(screen.getByText(notice)).toBeVisible();
  expect(screen.getByText('1 changed demand to review')).toBeVisible();
  expect(screen.queryByText('All items checked')).not.toBeInTheDocument();
});
