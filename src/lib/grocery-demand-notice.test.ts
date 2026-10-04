import { expect, it } from 'vitest';
import { groceryDemandNotice } from './grocery-demand-notice';
import { formatStockQuantity } from './format';

it('suppresses chicken unit-roundtrip noise without adding a second full shortage', () => {
  expect(groceryDemandNotice(81.6447399892089525, 81.6447399892089523981, String)).toBeUndefined();
  expect(groceryDemandNotice(81.64474, 81.64474001, String)).toBeUndefined();
});

it('labels oregano current total and retained amount rather than calling the total additional', () => {
  expect(groceryDemandNotice(0.5, 0.33333333335, value => formatStockQuantity(value * 0.03527396195, 'oz')))
    .toBe('Current plan shortage: 0.018 oz total. Saved remaining list quantity: 0.012 oz. Your check and quantity were kept.');
});

it('handles outstanding receipt quantities and unknown saved quantities without guessing a delta', () => {
  expect(groceryDemandNotice(200, 100, value => `${value} g`)).toContain('200 g total. Saved remaining list quantity: 100 g.');
  expect(groceryDemandNotice(200, null, value => `${value} g`)).toBe('Current plan shortage: 200 g total. Your check and quantity were kept.');
});
