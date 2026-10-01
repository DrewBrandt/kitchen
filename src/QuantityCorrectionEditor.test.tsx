import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { QuantityCorrectionEditor } from './QuantityCorrectionEditor';

const snapshot = { quantity: 2, canonicalUnit: 'servings', displayUnit: 'servings', displayPerBase: 1, calories: 400, protein: null, cost: null, estimated: true };
beforeEach(() => localStorage.clear());
describe('quantity correction editor', () => {
  it('previews exact event stock and known totals without turning unknowns into zero', async () => {
    const save = vi.fn().mockResolvedValue('replacement');
    render(<QuantityCorrectionEditor id="exact-event" label="Chicken" snapshot={snapshot} save={save} close={vi.fn()} />);
    const input = screen.getByLabelText('Correct amount eaten (servings)');
    await waitFor(() => expect(input).toBeEnabled());
    expect(screen.getByRole('button', { name: 'Save quantity correction' })).toBeDisabled();
    await userEvent.clear(input); await userEvent.type(input, '1');
    expect(screen.getByText(/Return 1 servings to the original lot/)).toBeInTheDocument();
    expect(screen.getByText(/Corrected totals: 200 cal.*Unknown.*Recorded cost unknown/)).toBeInTheDocument();
    expect(screen.queryByText('Event exact-event')).not.toBeInTheDocument();
    expect(screen.getByText(/cannot be undone/)).toBeVisible();
    await userEvent.click(screen.getByRole('button', { name: 'Save quantity correction' }));
    expect(save).toHaveBeenCalledExactlyOnceWith('exact-event', 2, 1);
  });
  it('converts practical display units back to canonical quantities and rejects zero', async () => {
    const save = vi.fn().mockResolvedValue('replacement');
    render(<QuantityCorrectionEditor id="raw-event" label="Milk" snapshot={{ ...snapshot, quantity: 8, canonicalUnit: 'fl oz', displayUnit: 'cup', displayPerBase: 0.125, cost: 0 }} save={save} close={vi.fn()} />);
    const input = screen.getByLabelText('Correct amount eaten (cup)');
    await waitFor(() => expect(input).toBeEnabled());
    await userEvent.clear(input); await userEvent.type(input, '0');
    expect(screen.getByRole('button', { name: 'Save quantity correction' })).toBeDisabled();
    await userEvent.clear(input); await userEvent.type(input, '0.5');
    expect(screen.getByText(/Corrected amount: 4 fl oz.*Return 4 fl oz/)).toBeInTheDocument();
    expect(screen.getByText(/Recorded cost \$0.00/)).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Save quantity correction' }));
    expect(save).toHaveBeenCalledExactlyOnceWith('raw-event', 8, 4);
  });
  it('freezes ambiguous corrections for retry and shows stale-original errors without closing', async () => {
    const save = vi.fn().mockRejectedValueOnce(new Error('Connection lost')).mockRejectedValueOnce({ code: 'P0001', message: 'Consumed quantity changed; refresh before correcting it' });
    const close = vi.fn();
    render(<QuantityCorrectionEditor id="event" label="Chicken" snapshot={snapshot} save={save} close={close} />);
    const input = screen.getByLabelText('Correct amount eaten (servings)');
    await waitFor(() => expect(input).toBeEnabled());
    await userEvent.clear(input); await userEvent.type(input, '1');
    await userEvent.click(screen.getByRole('button', { name: 'Save quantity correction' }));
    expect(screen.getByRole('alert')).toHaveTextContent('Connection lost');
    expect(input).toBeDisabled();
    await userEvent.click(screen.getByRole('button', { name: 'Retry correction' }));
    expect(save).toHaveBeenNthCalledWith(2, 'event', 2, 1);
    expect(screen.getByRole('alert')).toHaveTextContent('refresh before correcting');
    expect(input).toBeEnabled();
    expect(close).not.toHaveBeenCalled();
  });
});
