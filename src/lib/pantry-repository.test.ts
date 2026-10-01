import { describe, expect, it, vi } from 'vitest';
import { correctConsumedQuantity, foodLogNutrition, cookRecipe, estimatedProductPortionCost, formatRecipeQuantity, groupFoodLogRows, pluralizeFoodName, resolveProductPrice, summarizeProductConsumption } from './pantry-repository';

describe('food log display groups', () => {
  const log = (id: string, product: string | null, occurredAt: string) => ({ id, product, occurred_at: occurredAt });

  it('groups the same product inside one hour while retaining each event', () => {
    const groups = groupFoodLogRows([
      log('orange-2', 'orange-juice', '2026-09-03T02:52:00Z'),
      log('orange-1', 'orange-juice', '2026-09-03T02:10:00Z'),
      log('toast', 'toast', '2026-09-03T02:30:00Z'),
    ] as unknown as Parameters<typeof groupFoodLogRows>[0]);

    expect(groups.map((group) => group.map((entry) => entry.id))).toEqual([
      ['orange-2', 'orange-1'],
      ['toast'],
    ]);
  });

  it('does not merge breakfast with dinner or combine unlinked manual entries', () => {
    const groups = groupFoodLogRows([
      log('dinner', 'orange-juice', '2026-09-03T23:00:00Z'),
      log('breakfast', 'orange-juice', '2026-09-03T12:00:00Z'),
      log('manual-2', null, '2026-09-03T18:20:00Z'),
      log('manual-1', null, '2026-09-03T18:00:00Z'),
    ] as unknown as Parameters<typeof groupFoodLogRows>[0]);

    expect(groups.map((group) => group.map((entry) => entry.id))).toEqual([
      ['dinner'],
      ['manual-2'],
      ['manual-1'],
      ['breakfast'],
    ]);
  });
});

describe('base food names', () => {
  it('keeps the singular name when no explicit plural is stored', () => {
    expect(pluralizeFoodName('Salt', null, 2)).toBe('Salt');
    expect(pluralizeFoodName('Vegetable oil', null, 2)).toBe('Vegetable oil');
  });

  it('uses an explicit plural for countable foods', () => {
    expect(pluralizeFoodName('Egg', 'Eggs', 2)).toBe('Eggs');
    expect(pluralizeFoodName('Egg', 'Eggs', 1)).toBe('Egg');
  });
});

describe('recipe quantity display', () => {
  it('keeps small recipe amounts readable in their requested unit', () => {
    expect(formatRecipeQuantity(0.125, 'tsp')).toBe('⅛ tsp');
    expect(formatRecipeQuantity(0.25, 'cup')).toBe('¼ cup');
  });

  it('uses familiar mixed fractions without discarding precision', () => {
    expect(formatRecipeQuantity(1.5, 'cup')).toBe('1½ cup');
    expect(formatRecipeQuantity(0.01, 'oz')).toBe('0.01 oz');
  });
});

describe('product page summaries', () => {
  it('totals consumed servings rather than counting log entries', () => {
    const usage = summarizeProductConsumption([
      { product: 'dum-dums', servings: 4, occurred_at: '2026-08-26T16:00:00Z' },
      { product: 'dum-dums', servings: 4, occurred_at: '2026-08-27T16:00:00Z' },
      { product: 'dum-dums', servings: 4, occurred_at: '2026-08-28T16:00:00Z' },
      { product: 'dum-dums', servings: 2, occurred_at: '2026-09-01T12:30:00Z' },
      { product: 'chicken-biscuit', servings: 2, occurred_at: '2026-08-25T12:00:00Z' },
    ]);

    expect(usage.get('dum-dums')).toEqual({ servingsConsumed: 14, lastUsedAt: '2026-09-01T12:30:00Z' });
    expect(usage.get('chicken-biscuit')?.servingsConsumed).toBe(2);
  });

  it('uses the latest normalized purchase price when a product estimate is missing', () => {
    const price = resolveProductPrice(
      { id: 'fairlife', package_qty_base: 14, estimated_cost: null, cost_source: null, cost_as_of: null },
      [
        { product: 'fairlife', initial_qty: 28, total_cost: 8.58, cost_source: 'Receipt', price_as_of: '2026-08-24', acquired_at: '2026-08-24T12:00:00Z', created_at: '2026-08-24T12:00:00Z' },
        { product: 'fairlife', initial_qty: 14, total_cost: 4.29, cost_source: 'User-provided purchase total', price_as_of: '2026-09-01', acquired_at: '2026-09-01T16:30:00Z', created_at: '2026-09-01T16:30:00Z' },
      ],
    );

    expect(price).toEqual({
      estimatedCost: 4.29,
      costSource: 'Latest recorded purchase · User-provided purchase total',
      costAsOf: '2026-09-01',
    });
  });
});

describe('estimated consumed product cost', () => {
  const product = (price: number | null) => ({ estimated_cost: price, package_qty_base: 1000, serving_qty_base: 100, nutrition_basis_qty: 100, servings_per_package: null }) as Parameters<typeof estimatedProductPortionCost>[0];
  it('allocates package price to eaten quantity rather than charging one package per serving', () => {
    expect(estimatedProductPortionCost(product(10), 0.5)).toBe(0.5);
    expect(estimatedProductPortionCost(product(10), 2)).toBe(2);
  });
  it('keeps unknown price different from a free package', () => {
    expect(estimatedProductPortionCost(product(null), 1)).toBeNull();
    expect(estimatedProductPortionCost(product(0), 1)).toBe(0);
  });
});

describe('piece cooking retry contract', () => {
  it('reuses request ID and time after an ambiguous failure and starts a new intentional operation after success', async () => {
    const rpc = vi.fn().mockResolvedValueOnce({ data: null, error: { message: 'Connection lost' } }).mockResolvedValue({ data: { prepId: 'prep', lotId: 'lot', servingsMade: 3, servingsRemaining: 3, location: 'fridge' }, error: null });
    const client = { rpc } as unknown as Parameters<typeof cookRecipe>[0];
    const options = { pieceInputs: [{ ingredientId: 'ingredient', lotId: 'lot', pieces: 2, lotPieces: 6, expectedRemaining: 900 }] };
    await expect(cookRecipe(client, 'recipe', options)).rejects.toMatchObject({ message: 'Connection lost' });
    await cookRecipe(client, 'recipe', options);
    expect(rpc.mock.calls[0][1].p_request_id).toBe(rpc.mock.calls[1][1].p_request_id);
    expect(rpc.mock.calls[0][1].p_occurred_at).toBe(rpc.mock.calls[1][1].p_occurred_at);
    expect(rpc.mock.calls[1][1].p_piece_inputs).toEqual(options.pieceInputs);
    await cookRecipe(client, 'recipe', options);
    expect(rpc.mock.calls[2][1].p_request_id).not.toBe(rpc.mock.calls[1][1].p_request_id);
  });
});


describe('cooking recovery across refreshed inventory and reload', () => {
  it('freezes the submitted piece payload until a lost response is reconciled', async () => {
    localStorage.clear();
    const rpc = vi.fn().mockResolvedValueOnce({ data: null, error: { message: 'Connection lost', code: '' } }).mockResolvedValue({ data: { prepId: 'already-saved-prep', lotId: 'output', servingsMade: 3, servingsRemaining: 3, location: 'fridge' }, error: null });
    const client = { rpc } as unknown as Parameters<typeof cookRecipe>[0];
    const original = { servingsMade: 3, pieceInputs: [{ ingredientId: 'ingredient', lotId: 'input', pieces: 2, lotPieces: 6, expectedRemaining: 900 }] };
    await expect(cookRecipe(client, 'recipe', original)).rejects.toMatchObject({ message: 'Connection lost' });
    // The server committed. Realtime/focus refresh now reports less mass and persisted piece count.
    const refreshed = { servingsMade: 3, pieceInputs: [{ ingredientId: 'ingredient', lotId: 'input', pieces: 2, expectedRemaining: 600 }] };
    vi.resetModules();
    const reloaded = await import('./pantry-repository');
    await reloaded.cookRecipe(client, 'recipe', refreshed);
    expect(rpc.mock.calls[1][1].p_request_id).toBe(rpc.mock.calls[0][1].p_request_id);
    expect(rpc.mock.calls[1][1].p_occurred_at).toBe(rpc.mock.calls[0][1].p_occurred_at);
    expect(rpc.mock.calls[1][1].p_piece_inputs).toEqual(original.pieceInputs);
    await reloaded.cookRecipe(client, 'recipe', refreshed);
    expect(rpc.mock.calls[2][1].p_request_id).not.toBe(rpc.mock.calls[0][1].p_request_id);
    expect(rpc.mock.calls[2][1].p_piece_inputs).toEqual(refreshed.pieceInputs);
  });
});


describe('quantity correction retry contract', () => {
  it('freezes the exact original and corrected quantities across changed input and reload', async () => {
    localStorage.clear();
    const rpc=vi.fn().mockResolvedValueOnce({ data:null,error:{message:'Connection lost'} }).mockResolvedValue({data:{id:'replacement'},error:null});
    const client={rpc} as unknown as Parameters<typeof correctConsumedQuantity>[0];
    await expect(correctConsumedQuantity(client,'original',200,100)).rejects.toMatchObject({message:'Connection lost'});
    vi.resetModules();
    const reloaded=await import('./pantry-repository');
    await reloaded.correctConsumedQuantity(client,'original',150,50);
    expect(rpc.mock.calls[1]).toEqual(rpc.mock.calls[0]);
    expect(rpc.mock.calls[1][1]).toMatchObject({p_food_log:'original',p_expected_quantity:200,p_quantity:100});
    await reloaded.correctConsumedQuantity(client,'replacement',100,50);
    expect(rpc.mock.calls[2][1].p_request_id).not.toBe(rpc.mock.calls[0][1].p_request_id);
  });
});

describe('consumption detail uncertainty', () => {
  it('distinguishes unknown from known zero and does not present partial group sums as complete', () => {
    const rows = [{ kcal: 100, protein_g: null, carbs_g: 0, fat_g: null, fiber_g: null, sodium_mg: null }] as unknown as Parameters<typeof foodLogNutrition>[0];
    expect(foodLogNutrition(rows)).toMatchObject({ Calories: 100, Protein: null, Carbs: 0 });
    expect(foodLogNutrition([...rows, { ...rows[0], kcal: null }])).toMatchObject({ Calories: null, Carbs: 0 });
  });
});
