import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { it, expect, vi } from 'vitest';
import { RecipePieceControl } from './RecipePieceControl';
const ingredient = { id: 'i', label: 'Tenderloin', stock: '', pieceBasis: { count: 1, grams: 450, label: 'tenderloin', sourceQuantity: 450, sourceUnit: 'g', provenance: 'saved estimate', anchor: true }, pieceLots: [{ id: 'l', label: 'Two-piece pack', remainingBase: 1350, remainingPieces: 2 }] };
it('prefills selected-piece weight from a multipiece lot and submits explicit anchor selection', async () => {
  const onChange = vi.fn();
  render(<RecipePieceControl ingredient={ingredient} scale={1} onChange={onChange} />);
  expect(screen.getByLabelText('Weight of selected pieces (g)')).toHaveValue(675);
  await userEvent.click(screen.getByLabelText('Scale recipe to these pieces'));
  await waitFor(() => expect(onChange).toHaveBeenLastCalledWith({ ingredientId: 'i', lotId: 'l', pieces: 1, expectedRemaining: 1350, scaleRecipe: true }));
});
it('prefills unknown count from the saved estimate and rejects shortage', async () => {
  const onChange = vi.fn();
  render(<RecipePieceControl ingredient={{ ...ingredient, pieceLots: [{ id: 'l', label: 'Unknown count', remainingBase: 300 }] }} scale={1} onChange={onChange} />);
  expect(screen.getByLabelText('Weight of selected pieces (g)')).toHaveValue(450);
  await waitFor(() => expect(onChange).toHaveBeenLastCalledWith(null));
});
