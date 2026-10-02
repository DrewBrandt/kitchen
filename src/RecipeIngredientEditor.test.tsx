import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { expect, it } from 'vitest';
import { RecipeIngredientEditor } from './RecipeIngredientEditor';
import { RECIPES } from './data';

it('keeps IDs attached through a duplicate quantity collision, reorder, removal and addition', async () => {
  const user = userEvent.setup();
  const recipe = { ...RECIPES[0], ingredientText: '10 g Rice\n20 g Rice', ingredients: [{ id: 'a', label: 'Rice', stock: '' }, { id: 'b', label: 'Rice', stock: '' }] };
  const { container } = render(<form><RecipeIngredientEditor recipe={recipe} /></form>);
  const payload = () => { const form = new FormData(container.querySelector('form')!); return { ids: JSON.parse(String(form.get('ingredient_ids'))), lines: form.get('ingredients') }; };
  await user.clear(screen.getByLabelText('Ingredient 1'));
  await user.type(screen.getByLabelText('Ingredient 1'), '20 g Rice');
  expect(payload()).toEqual({ ids: ['a', 'b'], lines: '20 g Rice\n20 g Rice' });
  await user.click(screen.getByRole('button', { name: 'Move ingredient 2 up' }));
  expect(payload().ids).toEqual(['b', 'a']);
  await user.click(screen.getByRole('button', { name: 'Remove ingredient 1' }));
  await user.click(screen.getByRole('button', { name: 'Add ingredient' }));
  expect(payload().ids).toEqual(['a', null]);
});

it('opts a weighed ingredient into saved pieces and an anchor without changing canonical quantity', async () => {
  const recipe = { ...RECIPES[0], ingredientText: '450 g Chicken', ingredients: [{ id: 'a', label: 'Chicken', name: 'Chicken', stock: '', quantity: 450, unit: 'g', baseGrams: 450 }] };
  const { container } = render(<form><RecipeIngredientEditor recipe={recipe} /></form>);
  await userEvent.click(screen.getByRole('button', { name: 'Use pieces for ingredient 1' }));
  await userEvent.clear(screen.getByLabelText('Piece count for ingredient 1'));
  await userEvent.type(screen.getByLabelText('Piece count for ingredient 1'), '3');
  await userEvent.click(screen.getByLabelText('Allow scaling from ingredient 1'));
  const form = new FormData(container.querySelector('form')!);
  expect(form.get('ingredients')).toBe('450 g Chicken');
  expect(JSON.parse(String(form.get('ingredient_piece_bases')))[0]).toMatchObject({ count: 3, grams: 450, sourceQuantity: 450, sourceUnit: 'g', anchor: true });
});

it('rounds displayed mass without rewriting the saved ingredient or estimate', () => {
  const grams = 907.184739989;
  const recipe = { ...RECIPES[0], ingredientText: `${grams} g Chicken`, ingredients: [{ id: 'a', label: 'Chicken', stock: '', pieceBasis: { count: 4, grams, label: 'thighs', sourceQuantity: 2, sourceUnit: 'lb', provenance: 'fixture' } }] };
  const { container } = render(<form><RecipeIngredientEditor recipe={recipe} /></form>);
  expect(screen.getByLabelText('Ingredient 1')).toHaveValue('907.18 g Chicken');
  const form = new FormData(container.querySelector('form')!);
  expect(form.get('ingredients')).toBe(`${grams} g Chicken`);
  expect(JSON.parse(String(form.get('ingredient_piece_bases')))[0].grams).toBe(grams);
});
