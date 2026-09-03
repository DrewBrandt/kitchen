import { describe, expect, it } from 'vitest';
import { formatAmount, formatNutritionAmount, formatServings } from './format';

describe('friendly quantities', () => {
  it('turns storage-level precision into a readable serving amount', () => {
    expect(formatAmount(0.8341674133937468)).toBe('⅚');
    expect(formatServings(0.8341674133937468)).toBe('⅚ servings');
  });

  it('keeps useful decimals without floating-point noise', () => {
    expect(formatAmount(9.333333333333334)).toBe('9⅓');
    expect(formatAmount(1.234567)).toBe('1.23');
  });

  it('uses ordinary rounded numbers instead of kitchen fractions for nutrition', () => {
    expect(formatNutritionAmount(1105.333333, 'Calories')).toBe('1,105');
    expect(formatNutritionAmount(15.666667, 'Protein')).toBe('15.7');
    expect(formatNutritionAmount(602.593, 'Sodium')).toBe('603');
  });
});
