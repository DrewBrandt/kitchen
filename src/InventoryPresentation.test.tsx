import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { expect, it, vi } from 'vitest';
import { App } from './App';
import { PantryDataProvider, previewPantryData } from './pantry-data';
import { ShoppingReceiptEditor } from './ShoppingReceiptEditor';
import { inventoryValueLabel } from './lib/cost';
import { formatStockQuantity } from './lib/format';

it('keeps real small amounts distinct from empty stock', () => {
  expect(formatStockQuantity(1 / 28.349523125, 'oz')).toBe('0.035 oz');
  expect(formatStockQuantity(0.006, 'oz')).toBe('0.006 oz');
  expect(formatStockQuantity(0.00004, 'oz')).toBe('<0.001 oz');
  expect(formatStockQuantity(0, 'oz')).toBe('0 oz');
  expect(formatStockQuantity(27.231498718, 'oz')).toBe('27.2 oz');
});

it('distinguishes unknown, free, and positive sub-cent inventory values', () => {
  expect(inventoryValueLabel(null, true)).toBe('Inventory value unavailable');
  expect(inventoryValueLabel(0, false)).toBe('Inventory value: $0.00');
  expect(inventoryValueLabel(1.89 / 907, true)).toBe('Estimated inventory value: <$0.01');
  expect(inventoryValueLabel(2.49, false)).toBe('Inventory value: $2.49');
});

it('keeps compact estimated value in inventory and purchase-price uncertainty in details', async () => {
  const food = { emoji: '', name: 'QA rice', sub: 'Pantry', total: '0.035 oz', due: 'No date', tone: '', lots: ['0.035 oz pantry'], cost: 1.89 / 907, costIsEstimated: true, purchasePriceUnknown: true, lotDetails: [{ id: 'qa', quantity: '0.035 oz', location: 'pantry', dateLabel: 'No date', tone: '', remainingBase: 1, remainingDisplay: 1 / 28.349523125, displayUnit: 'oz', displayPerBase: 1 / 28.349523125, cost: 1.89 / 907, costIsEstimated: true, costSource: 'Catalog estimate', purchasePriceUnknown: true }] };
  render(<PantryDataProvider data={{ ...previewPantryData, inventorySections: [{ emoji: '', label: 'Pantry', foods: [food] }] }}><App /></PantryDataProvider>);
  await userEvent.click(screen.getByRole('button', { name: 'Inventory' }));
  expect(screen.getByLabelText('Estimated inventory value: <$0.01')).toHaveTextContent('~<$0.01');
  expect(screen.queryByText('Purchase price unavailable for some stock')).not.toBeInTheDocument();
  await userEvent.click(screen.getByText('QA rice').closest('button')!);
  const dialog = within(screen.getByRole('dialog'));
  expect(dialog.getByText('Estimated inventory value: <$0.01')).toBeVisible();
  expect(dialog.getByText('Purchase price unavailable')).toBeVisible();
  expect(screen.queryByText('~$0.00')).not.toBeInTheDocument();
});

it('associates receipt labels explicitly and sorts foods without mutating shared data', () => {
  const foods = ['Zucchini', 'Apple', 'Rice'].map((name) => ({ id: name, name, emoji: '', measureStyle: 'weight' as const }));
  render(<PantryDataProvider data={{ ...previewPantryData, foods }}><ShoppingReceiptEditor item={{ id: 'qa', name: 'QA', quantity: '' }} onSave={vi.fn()} onClose={vi.fn()} /></PantryDataProvider>);
  const select = screen.getByLabelText('Food acquired') as HTMLSelectElement;
  expect(Array.from(select.options).map((option) => option.text)).toEqual(['Choose food', 'Apple', 'Rice', 'Zucchini']);
  expect(foods.map((food) => food.name)).toEqual(['Zucchini', 'Apple', 'Rice']);
  for (const label of ['Food acquired', 'Product', 'Unit', 'Quantity bought', 'Price paid (optional)']) {
    const control = screen.getByLabelText(label) as HTMLInputElement | HTMLSelectElement;
    expect(control.id).not.toBe('');
    expect(Array.from(control.labels ?? []).some((node) => node.htmlFor === control.id)).toBe(true);
  }
});

it('shows recorded grocery quantity and keeps the old label in collapsed details', async () => {
  render(<PantryDataProvider data={{ ...previewPantryData, grocerySections: [{ emoji: '', label: 'Herbs', items: [{ name: 'Dried oregano', quantity: '0.012 oz', savedQuantityLabel: '0 oz', cost: 0.04 }] }] }}><App /></PantryDataProvider>);
  await userEvent.click(screen.getByRole('button', { name: 'Grocery list' }));
  const row = screen.getByText('Dried oregano').closest('.grocery-row')!;
  const labels = row.querySelectorAll('.grocery-quantity strong');
  expect(labels[0]).toHaveTextContent('0.012 oz');
  expect(labels).toHaveLength(1);
  const saved = screen.getByText('0 oz');
  expect(saved.closest('details')).not.toHaveAttribute('open');
  await userEvent.click(screen.getByText('Saved label'));
  expect(saved.closest('details')).toHaveAttribute('open');
});


it('lets past-date stock be inspected without recommending cooking it', async () => {
  const food = { emoji: '', name: 'Past-date milk', sub: 'Fridge', total: '1 cup', due: '12 days past date', tone: 'urgent', lots: ['1 cup fridge'], cost: null, costIsEstimated: false,
    lotDetails: [{ id: 'dated-lot', quantity: '1 cup', location: 'fridge', dateLabel: '12 days past date', tone: 'urgent', remainingBase: 1, remainingDisplay: 1, displayUnit: 'cup', displayPerBase: 1, cost: null, costIsEstimated: false, costSource: '' }] };
  render(<PantryDataProvider data={{ ...previewPantryData, inventorySections: [{ emoji: '', label: 'Dairy', foods: [food] }] }}><App /></PantryDataProvider>);
  expect(screen.getByText('Check dates')).toBeVisible();
  expect(screen.getByText('12 days past date')).toBeVisible();
  expect(screen.queryByRole('button', { name: /Cook these before they spoil/ })).not.toBeInTheDocument();
  await userEvent.click(screen.getByRole('button', { name: /Past-date milk/ }));
  expect(within(screen.getByRole('dialog')).getByText('12 days past date')).toBeVisible();
  await userEvent.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Close' }));
  await userEvent.click(screen.getByRole('button', { name: /Review inventory/ }));
  expect(screen.getByRole('heading', { name: 'Inventory', level: 1 })).toBeVisible();
  expect(screen.getByText('Past-date milk')).toBeVisible();
});

it('uses a neutral empty state when no inventory dates are flagged', () => {
  render(<PantryDataProvider data={{ ...previewPantryData, inventorySections: [] }}><App /></PantryDataProvider>);
  expect(screen.getByText('No dates flagged')).toBeVisible();
});
