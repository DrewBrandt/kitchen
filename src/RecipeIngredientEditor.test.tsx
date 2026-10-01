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
