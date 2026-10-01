import { describe, expect, it } from 'vitest';
import { normalizeProductQuantities } from './pantry-actions';
const form = (overrides: Record<string, string> = {}) => {
  const value = new FormData();
  for (const [key, entry] of Object.entries({ measure_style: 'weight', package_qty_base: '32', serving_qty_base: '4', nutrition_basis_qty: '4', estimated_cost: '', ...overrides })) value.set(key, entry);
  return value;
};
const ounces = { measure_style: 'weight', base_to_this_ratio: 1 / 28.349523125 };
describe('product quantity entry', () => {
  it('converts a two-pound package and four-ounce nutrition serving into grams exactly once', () => {
    const result = normalizeProductQuantities(form(), ounces);
    expect(result.packageQuantity).toBeCloseTo(907.18474);
    expect(result.servingQuantity).toBeCloseTo(113.3980925);
    expect(result.nutritionBasis).toBeCloseTo(113.3980925);
    expect(result.packageQuantity / result.servingQuantity).toBe(8);
  });
  it('preserves count-based packages and nutrition bases', () => {
    expect(normalizeProductQuantities(form({ measure_style: 'discrete', package_qty_base: '6', serving_qty_base: '1', nutrition_basis_qty: '1' }), { measure_style: 'discrete', base_to_this_ratio: 1 })).toEqual({ packageQuantity: 6, servingQuantity: 1, nutritionBasis: 1 });
  });
  it('rejects style mismatch rather than treating fluid ounces as grams', () => {
    expect(() => normalizeProductQuantities(form(), { measure_style: 'volume', base_to_this_ratio: 1 })).toThrow(/Stock style/);
  });
  it.each(['0', '-1', '', 'NaN', 'Infinity'])('rejects invalid nutrition basis %s', (value) => {
    expect(() => normalizeProductQuantities(form({ nutrition_basis_qty: value }), ounces)).toThrow();
  });
  it('does not require a made-up price and rejects negative costs or nutrition', () => {
    expect(() => normalizeProductQuantities(form(), ounces)).not.toThrow();
    expect(() => normalizeProductQuantities(form({ estimated_cost: '-1' }), ounces)).toThrow(/negative/);
    expect(() => normalizeProductQuantities(form({ kcal: '-1' }), ounces)).toThrow(/negative/);
  });
});
