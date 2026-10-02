import { beforeEach, expect, it, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '../database.types';
import { savePanelAction } from './pantry-actions';
import { createFormAttempt } from './mutation-feedback';

function fixture() {
  const rpc = vi.fn().mockResolvedValue({ data: {}, error: null });
  const from = vi.fn((table: string) => {
    if (table === 'base_foods') return { select: vi.fn().mockResolvedValue({ data: [{ id: 'food', name: 'Rice' }] }) };
    if (table === 'measure_conversions') return { select: vi.fn().mockResolvedValue({ data: [{ id: 'unit', short_name: 'g', full_name: 'gram' }] }) };
    throw new Error(`Unexpected table write or source resolution: ${table}`);
  });
  return { rpc, from, client: { rpc, from } as unknown as SupabaseClient<Database> };
}
const formOf = (values: Record<string, string | undefined>) => {
  const form = new FormData(); for (const [key, value] of Object.entries(values)) if (value !== undefined) form.set(key, value); return form;
};
beforeEach(() => localStorage.clear());

it('creates recipe and ordered ingredients in one call, retaining browser defaults', async () => {
  const { client, rpc, from } = fixture();
  await savePanelAction(client, 'recipe', formOf({ request_id: 'request', name: 'Rice', ingredients: '90 g Rice\n10 g Rice', instructions: 'Boil\nServe' }));
  expect(rpc).toHaveBeenCalledExactlyOnceWith('owner_create_recipe', { p_request_id: 'request', p_payload: {
    name: 'Rice', emoji: null, servings: 1, instructions: ['Boil', 'Serve'], source_url: null, prompt_for_feedback: false,
    ingredients: [{ ingredient: 'food', qty: 90, unit: 'unit', sort_order: 0 }, { ingredient: 'food', qty: 10, unit: 'unit', sort_order: 1 }],
  } });
  expect(from.mock.calls.map(([name]) => name)).toEqual(['base_foods', 'measure_conversions']);
});

it('continues to allow recipe creation without ingredients', async () => {
  const { client, rpc } = fixture();
  await savePanelAction(client, 'recipe', formOf({ name: 'Empty' }));
  expect(rpc.mock.calls[0][1].p_payload.ingredients).toEqual([]);
});

it.each([
  { intent: 'prepare', recipe: 'recipe', scale_factor: '0.5' },
  { intent: 'leftover', source_group_id: 'group' },
  { intent: 'consume', inventory_lot: 'exact-lot' },
  { intent: 'consume', product: 'product' },
])('appends $intent atomically without table writes or grocery rebuild', async (source) => {
  const { client, rpc, from } = fixture();
  await savePanelAction(client, 'meal', formOf({ request_id: 'request', plan_date: '2026-10-02', daypart: 'lunch', planned_servings: '0.75', ...source }));
  expect(rpc).toHaveBeenCalledExactlyOnceWith('owner_append_plan', { p_request_id: 'request', p_payload: {
    intent: source.intent, plan_date: '2026-10-02', daypart: 'lunch', planned_servings: 0.75,
    scale_factor: source.scale_factor ? 0.5 : 1, recipe: source.recipe ?? null, product: source.product ?? null,
    inventory_lot: source.inventory_lot ?? null, source_group_id: source.source_group_id ?? null, note: null,
  } });
  expect(from).not.toHaveBeenCalled();
});

it.each(['recipe', 'meal'] as const)('retains request identity on uncertain %s retries and never falls back to CRUD', async (kind) => {
  const { client, rpc } = fixture();
  const values = { name: 'Rice', recipe: 'recipe', plan_date: '2026-10-02', daypart: 'lunch', action_kind: kind };
  const form = await createFormAttempt()(formOf(values));
  rpc.mockResolvedValueOnce({ error: new Error('Network response lost') });
  await expect(savePanelAction(client, kind, form)).rejects.toThrow('Network response lost');
  const retry = await createFormAttempt()(formOf(values));
  await savePanelAction(client, kind, retry);
  expect(rpc.mock.calls[1]).toEqual(rpc.mock.calls[0]);
});

it('retries exact unequal leftover sources after recreation with one atomic call', async () => {
 const {client,rpc}=fixture();
 const values={intent:'leftover',source_group_id:'dinner',plan_date:'2026-10-03',daypart:'lunch',leftover_dishes:JSON.stringify([{source_meal_plan:'chicken',planned_servings:.5},{source_meal_plan:'rice',planned_servings:1}])};
 rpc.mockResolvedValueOnce({error:new Error('Response lost')});
 await expect(savePanelAction(client,'meal',await createFormAttempt()(formOf(values)))).rejects.toThrow('Response lost');
 await savePanelAction(client,'meal',await createFormAttempt()(formOf(values)));
 expect(rpc.mock.calls[1]).toEqual(rpc.mock.calls[0]);
 expect(rpc.mock.calls[1][1].p_payload.leftover_dishes).toEqual(JSON.parse(values.leftover_dishes));
});
