import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { ManualConsumptionEditor } from './ManualConsumptionEditor';

const original = { label: 'Lunch', portionLabel: '2 portions', note: null, nutrition: { calories: 400, proteinG: null, carbsG: null, fatG: null, fiberG: null, sugarG: null, sodiumMg: 0, estimated: true, source: 'Original estimate' } };

describe('manual correction', () => {
  it('changes only the portion, preserving unknown nutrition, timestamp and provenance by omission', async () => {
    const save = vi.fn().mockResolvedValue(undefined);
    render(<ManualConsumptionEditor id="exact-event" original={original} save={save} close={vi.fn()} />);
    await userEvent.clear(screen.getByLabelText('Portion description'));
    await userEvent.type(screen.getByLabelText('Portion description'), '1 portion');
    await userEvent.click(screen.getByRole('button', { name: 'Save correction' }));
    expect(save).toHaveBeenCalledExactlyOnceWith('exact-event', { portionLabel: '1 portion' });
  });

  it('preserves unknown nutrients, known zero, and source when a nutrition total is corrected', async () => {
    const save = vi.fn().mockResolvedValue(undefined);
    render(<ManualConsumptionEditor id="exact-event" original={original} save={save} close={vi.fn()} />);
    await userEvent.clear(screen.getByLabelText('Calories'));
    await userEvent.type(screen.getByLabelText('Calories'), '200');
    await userEvent.click(screen.getByRole('button', { name: 'Save correction' }));
    expect(save).toHaveBeenCalledExactlyOnceWith('exact-event', { nutrition: { ...original.nutrition, calories: 200 } });
  });

  it('keeps edits available on failure and does not save an unchanged form', async () => {
    const save = vi.fn().mockRejectedValue(new Error('Disconnected'));
    const close = vi.fn();
    render(<ManualConsumptionEditor id="exact-event" original={original} save={save} close={close} />);
    await userEvent.type(screen.getByLabelText('Note'), 'Correction');
    await userEvent.click(screen.getByRole('button', { name: 'Save correction' }));
    expect(screen.getByRole('alert')).toHaveTextContent('Disconnected');
    expect(close).not.toHaveBeenCalled();
    await userEvent.clear(screen.getByLabelText('Note'));
    await userEvent.click(screen.getByRole('button', { name: 'Save correction' }));
    expect(save).toHaveBeenCalledTimes(1);
    expect(close).toHaveBeenCalledOnce();
  });
});
