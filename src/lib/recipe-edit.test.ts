import { expect, it, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '../database.types';
import { savePanelAction } from './pantry-actions';
import { shoppingQuantityPresentation } from './format';

function fixture(error: Error | null = null) {
  const rpc = vi.fn().mockResolvedValue({ error });
  const from = vi.fn((table: string) => {
    if (table === 'base_foods') return { select: vi.fn().mockResolvedValue({ data: [{ id: 'food', name: 'Rice' }] }) };
    if (table === 'measure_conversions') return { select: vi.fn().mockResolvedValue({ data: [{ id: 'unit', full_name: 'gram', short_name: 'g' }] }) };
    throw new Error(`Unexpected direct write: ${table}`);
  });
  const form = new FormData();
  for (const [key, value] of Object.entries({ ingredient_ids: '["row-a"]', recipe_id: 'recipe', name: 'New name', servings: '2', instructions: 'Boil\nServe', ingredients: '10 g Rice', source_url: 'https://example.com', prompt_for_feedback: 'on' })) form.set(key, value);
  return { client: { from, rpc } as unknown as SupabaseClient<Database>, rpc, from, form };
}

it('edits the recipe and ingredients in one RPC and omits fields outside the editor', async () => {
  const { client, rpc, from, form } = fixture();
  await savePanelAction(client, 'recipe', form);
  expect(rpc).toHaveBeenCalledExactlyOnceWith('gpt_update_recipe', {
    p_recipe: 'recipe', p_patch: { name: 'New name', emoji: null, servings: 2, instructions: ['Boil', 'Serve'], sourceUrl: 'https://example.com', promptForFeedback: true,
      ingredients: [{ id: 'row-a', foodId: 'food', quantity: 10, unit: 'unit', sortOrder: 0 }] },
  });
  expect(from.mock.calls.map(([table]) => table)).toEqual(['base_foods', 'measure_conversions']);
});

it('propagates a rejected atomic edit without fallback writes', async () => {
  const error = new Error('Recipe dependency rejected');
  const { client, rpc, form } = fixture(error);
  await expect(savePanelAction(client, 'recipe', form)).rejects.toBe(error);
  expect(rpc).toHaveBeenCalledTimes(1);
});

it.each(['', '10 unknown Rice', '10 g Unknown'])('rejects invalid edit ingredients before a mutation: %s', async (ingredients) => {
  const { client, rpc, form } = fixture(); form.set('ingredients', ingredients);
  await expect(savePanelAction(client, 'recipe', form)).rejects.toThrow();
  expect(rpc).not.toHaveBeenCalled();
});

it('clarifies legacy generated zero labels while preserving their exact text', () => {
  expect(shoppingQuantityPresentation('0 oz', 0.011757987317254566, 'oz', true)).toEqual({ quantity: '0.012 oz', savedQuantityLabel: '0 oz' });
  expect(shoppingQuantityPresentation(' 0.0 OZ ', 0.00001, 'oz', true)).toEqual({ quantity: '<0.001 oz', savedQuantityLabel: ' 0.0 OZ ' });
  expect(shoppingQuantityPresentation('0 oz', 0, 'oz', true)).toEqual({ quantity: '0 oz' });
  expect(shoppingQuantityPresentation('0 oz', 0.01, 'oz', false)).toEqual({ quantity: '0 oz' });
  expect(shoppingQuantityPresentation('0 oz optional', 0.01, 'oz', true)).toEqual({ quantity: '0 oz optional' });
  expect(shoppingQuantityPresentation('0.012 oz', 0.012, 'oz', true)).toEqual({ quantity: '0.012 oz' });
  expect(shoppingQuantityPresentation('Buy a jar', 0.012, 'oz', true)).toEqual({ quantity: 'Buy a jar' });
  expect(shoppingQuantityPresentation(null, 0.012, 'oz', true)).toEqual({ quantity: '0.012 oz' });
});

it('passes duplicate ingredient identities in their explicit edited order', async () => {
  const { client, rpc, form } = fixture();
  form.set('ingredients', '20 g Rice\n20 g Rice');
  form.set('ingredient_ids', '["row-b","row-a"]');
  await savePanelAction(client, 'recipe-edit', form);
  expect(rpc.mock.calls[0][1].p_patch.ingredients).toEqual([
    { id: 'row-b', foodId: 'food', quantity: 20, unit: 'unit', sortOrder: 0 },
    { id: 'row-a', foodId: 'food', quantity: 20, unit: 'unit', sortOrder: 1 },
  ]);
});
