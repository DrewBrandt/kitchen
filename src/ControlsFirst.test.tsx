import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, expect, it, vi } from 'vitest';
import { App } from './App';
import { PantryDataProvider, previewPantryData } from './pantry-data';
afterEach(() => vi.useRealTimers());
it('resets scroll on primary route changes without resetting in-page interactions', async () => {
  render(<App />);
  document.documentElement.scrollTop = 600;
  document.body.scrollTop = 600;
  await userEvent.click(screen.getByRole('button', { name: 'Grocery list' }));
  expect(document.documentElement.scrollTop).toBe(0);
  expect(document.body.scrollTop).toBe(0);
  document.documentElement.scrollTop = 400;
  await userEvent.click(screen.getByRole('button', { name: 'Next week' }));
  expect(document.documentElement.scrollTop).toBe(400);
  await userEvent.click(screen.getByRole('button', { name: 'This week' }));
  expect(document.documentElement.scrollTop).toBe(0);
});
it('uses the owner calendar for Food log and historical day selection', async () => {
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(new Date('2026-01-05T00:30:00Z'));
  render(<PantryDataProvider data={{ ...previewPantryData, settings: { ...previewPantryData.settings, timeZone: 'America/Los_Angeles' } }}><App /></PantryDataProvider>);
  await userEvent.click(screen.getByRole('button', { name: 'Food log' }));
  expect(screen.getByText('Sun, Jan 4')).toBeInTheDocument();
  expect(screen.getByRole('button', { name: 'Next day' })).toBeDisabled();
  await userEvent.click(screen.getByRole('button', { name: 'Previous day' }));
  expect(screen.getByText('Sat, Jan 3')).toBeInTheDocument();
  expect(screen.getByRole('button', { name: 'Next day' })).toBeEnabled();
});
it('reaches every page through mobile More and closes after navigation', async () => {
  render(<App />);
  const nav = screen.getByRole('navigation', { name: 'Mobile navigation' });
  for (const label of ['Inventory', 'Recipes', 'Food log', 'History', 'Trends']) {
    await userEvent.click(within(nav).getByRole('button', { name: 'More navigation' }));
    await userEvent.click(within(nav).getByRole('button', { name: label }));
    expect(screen.getByRole('heading', { name: label, level: 1 })).toBeInTheDocument();
    expect(within(nav).getByRole('button', { name: 'More navigation' })).toHaveAttribute('aria-expanded', 'false');
  }
});
it('keeps total shortage separate from the retained list quantity', async () => {
  const item = { id: 'changed', name: 'Rice', quantity: '2 kg', cost: null, demandNotice: 'old prose', demandComparison: { need: '3 kg', saved: '2 kg' } };
  render(<PantryDataProvider data={{ ...previewPantryData, grocerySections: [{ label: 'Pantry', emoji: '', items: [item] }] }}><App /></PantryDataProvider>);
  await userEvent.click(screen.getByRole('button', { name: 'Grocery list' }));
  expect(screen.getByText('3 kg total').parentElement).toHaveTextContent('Need 3 kg total');
  expect(screen.getAllByText('2 kg').some(node => node.parentElement?.textContent === 'On list 2 kg')).toBe(true);
  expect(screen.queryByText('old prose')).not.toBeInTheDocument();
  expect(screen.getByRole('button', { name: 'Rebuild from plan' })).toBeEnabled();
});
it('preserves History filter scroll while primary navigation still resets it', async () => {
  render(<App />);
  await userEvent.click(screen.getByRole('button', { name: 'History' }));
  const filters = screen.getByRole('group', { name: 'History activity' });
  await userEvent.click(within(filters).getByRole('button', { name: 'Cooking' }));
  document.documentElement.scrollTop = 114;
  await userEvent.click(within(filters).getByRole('button', { name: 'Food log' }));
  expect(document.documentElement.scrollTop).toBe(114);
  expect(document.body.scrollTop).toBe(114);
  expect(screen.getByRole('heading', { name: 'Day by day' })).toBeInTheDocument();
  await userEvent.click(screen.getByRole('button', { name: 'Inventory' }));
  expect(document.documentElement.scrollTop).toBe(0);
});
