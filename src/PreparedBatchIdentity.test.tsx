import { render, screen, within, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { expect, it, vi } from 'vitest';
import { App } from './App';
import { PantryDataProvider, previewPantryData } from './pantry-data';
import { formatPreparedAt } from './lib/format';

it('distinguishes equal-name equal-yield ready batches by pantry-local preparation time and eats the selected lot', async () => {
  const timeZone = 'America/Phoenix';
  const dates = ['2026-09-01T12:00:00Z', '2026-10-01T20:30:38Z'];
  const onEat = vi.fn().mockResolvedValue('log');
  const preparedLots = dates.map((preparedAt, index) => ({ ...previewPantryData.preparedLots[0], id: `rice-${index}`, name: 'Steamed white rice', preparedAt, servingsTotal: 2, servingsLeft: 2, remaining: '2 of 2 servings' }));
  render(<PantryDataProvider data={{ ...previewPantryData, preparedLots, settings: { ...previewPantryData.settings, timeZone } }}><App onConsumePrepared={onEat} /></PantryDataProvider>);
  for (const date of dates) expect(screen.getByText(`Prepared ${formatPreparedAt(date, timeZone)}`)).toBeVisible();
  const newest = screen.getByRole('group', { name: `Steamed white rice — Prepared ${formatPreparedAt(dates[1], timeZone)}` });
  expect(within(newest).getByText(/1:30 PM/)).toBeVisible();
  await userEvent.click(within(newest).getByRole('button', { name: 'Log eaten' }));
  await waitFor(() => expect(onEat).toHaveBeenCalledWith('rice-1', 1));
});


it('discards the selected batch portion with a reason and exposes normal undo', async () => {
  const discard = vi.fn().mockResolvedValue('waste-event');
  const undo = vi.fn().mockResolvedValue(undefined);
  const eat = vi.fn();
  const lot = { ...previewPantryData.preparedLots[0], id: 'discard-lot', servingsLeft: 3 };
  render(<PantryDataProvider data={{ ...previewPantryData, preparedLots: [lot] }}><App onSetInventoryLotQuantity={discard} onUndoInventoryAdjustment={undo} onConsumePrepared={eat} /></PantryDataProvider>);
  await userEvent.click(screen.getByRole('button', { name: 'Discard' }));
  await userEvent.type(screen.getByLabelText('Reason (optional)'), 'Dropped on floor');
  await userEvent.click(screen.getByRole('button', { name: 'Discard 1 serving' }));
  await waitFor(() => expect(discard).toHaveBeenCalledWith('discard-lot', 2, true, 'Dropped on floor'));
  expect(eat).not.toHaveBeenCalled();
  await userEvent.click(screen.getByRole('button', { name: 'Undo' }));
  await waitFor(() => expect(undo).toHaveBeenCalledWith('waste-event'));
});
