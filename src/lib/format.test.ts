import { describe, expect, it } from 'vitest';
import { formatAmount, formatServings } from './format';

describe('friendly quantities', () => {
  it('turns storage-level precision into a readable serving amount', () => {
    expect(formatAmount(0.8341674133937468)).toBe('⅚');
    expect(formatServings(0.8341674133937468)).toBe('⅚ servings');
  });

  it('keeps useful decimals without floating-point noise', () => {
    expect(formatAmount(9.333333333333334)).toBe('9⅓');
    expect(formatAmount(1.234567)).toBe('1.23');
  });
});
