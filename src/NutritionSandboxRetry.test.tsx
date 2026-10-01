import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterEach, expect, it, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from './database.types';
import { App } from './App';
import { savePanelAction } from './lib/pantry-actions';

afterEach(() => { vi.restoreAllMocks(); localStorage.clear(); });

it('retries scratchpad append after a lost response and remount with the original identity and timing', async () => {
  localStorage.clear();
  const day = vi.spyOn(Date.prototype, 'toLocaleDateString').mockReturnValue('2026-10-01');
  const hour = vi.spyOn(Date.prototype, 'getHours').mockReturnValue(12);
  const committed = new Map<string, unknown>();
  const rpc = vi.fn(async (_name: string, args: { p_request_id: string; p_payload: unknown }) => {
    if (!committed.has(args.p_request_id)) committed.set(args.p_request_id, args.p_payload);
    // The first append committed, but its response never reached the browser.
    return { data: {}, error: committed.size === 1 && rpc.mock.calls.length === 1 ? new Error('Network response lost') : null };
  });
  const from = vi.fn(() => { throw new Error('Unexpected table write'); });
  const client = { rpc, from } as unknown as SupabaseClient<Database>;
  const app = () => <App onSaveAction={(kind, form) => savePanelAction(client, kind, form)} />;
  const user = userEvent.setup();
  async function choose() {
    await user.click(screen.getByRole('button', { name: 'Food log' }));
    await user.click(screen.getByRole('button', { name: /What if I ate something else/ }));
    await user.click(screen.getByRole('option', { name: /Bailey's/ }));
  }
  const first = render(app());
  await choose();
  await user.click(screen.getByRole('button', { name: 'Add to today' }));
  await waitFor(() => expect(screen.getByRole('button', { name: 'Retry addition' })).toBeEnabled());
  expect(screen.getByText(/^Pending:/)).toHaveTextContent('Pending: 2026-10-01 · dinner');
  expect(rpc).toHaveBeenCalledTimes(1);
  expect(committed.size).toBe(1);
  expect(rpc.mock.calls[0][1].p_request_id).toMatch(/^[0-9a-f-]{36}$/);
  expect(rpc.mock.calls[0][1].p_payload).toMatchObject({ plan_date: '2026-10-01', daypart: 'dinner' });

  first.unmount();
  day.mockReturnValue('2026-10-02'); hour.mockReturnValue(23);
  render(app());
  await choose();
  await waitFor(() => expect(screen.getByRole('button', { name: 'Retry addition' })).toBeEnabled());
  expect(screen.getByText(/^Pending:/)).toHaveTextContent('Pending: 2026-10-01 · dinner');
  expect(screen.queryByRole('button', { name: 'Add to today' })).not.toBeInTheDocument();

  // Different amount, lot, or source represents a new addition. Returning to
  // the pending selection restores its original visible date and retry action.
  async function expectNew() {
    await waitFor(() => expect(screen.getByRole('button', { name: 'Add to today' })).toBeEnabled());
    expect(screen.queryByText(/^Pending:/)).not.toBeInTheDocument();
  }
  async function expectRetry() {
    await waitFor(() => expect(screen.getByRole('button', { name: 'Retry addition' })).toBeEnabled());
    expect(screen.getByText(/^Pending:/)).toHaveTextContent('Pending: 2026-10-01 · dinner');
  }
  await user.click(screen.getByRole('button', { name: 'Increase amount' })); await expectNew();
  await user.click(screen.getByRole('button', { name: 'Decrease amount' })); await expectRetry();
  await user.click(screen.getByRole('radio', { name: /pantry.*9.3 servings/ })); await expectNew();
  await user.click(screen.getByRole('radio', { name: /Choose automatically/ })); await expectRetry();
  await user.click(screen.getByRole('tab', { name: /Recipe/ }));
  await user.click(screen.getByRole('option', { name: /Simple Pancakes/ })); await expectNew();
  await user.click(screen.getByRole('tab', { name: /Pantry item/ }));
  await user.click(screen.getByRole('option', { name: /Bailey's/ })); await expectRetry();
  expect(rpc).toHaveBeenCalledTimes(1);
  await user.click(screen.getByRole('button', { name: 'Retry addition' }));
  await waitFor(() => expect(screen.queryByRole('button', { name: 'Retry addition' })).not.toBeInTheDocument());
  expect(rpc.mock.calls[1]).toEqual(rpc.mock.calls[0]);
  expect(committed.size).toBe(1);

  // Success clears the pending attempt; an intentional new addition is distinct.
  await user.click(screen.getByRole('button', { name: /What if I ate something else/ }));
  await user.click(screen.getByRole('button', { name: 'Add to today' }));
  await waitFor(() => expect(rpc).toHaveBeenCalledTimes(3));
  expect(rpc.mock.calls[2][1].p_request_id).not.toBe(rpc.mock.calls[0][1].p_request_id);
  expect(rpc.mock.calls[2][1].p_payload).toMatchObject({ plan_date: '2026-10-02', daypart: 'snack' });
  expect(committed.size).toBe(2);
  expect(from).not.toHaveBeenCalled();
});
