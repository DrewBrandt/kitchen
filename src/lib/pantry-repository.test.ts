import { describe, expect, it } from 'vitest';
import { formatRecipeQuantity, pluralizeFoodName, resolveProductPrice, summarizeProductConsumption } from './pantry-repository';

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
