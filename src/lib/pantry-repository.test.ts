import { describe, expect, it } from 'vitest';
import { formatRecipeQuantity } from './pantry-repository';

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
