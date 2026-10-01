const DISPLAY_FRACTIONS: Array<[number, string]> = [
  [1 / 8, '⅛'], [1 / 6, '⅙'], [1 / 4, '¼'], [1 / 3, '⅓'], [3 / 8, '⅜'],
  [1 / 2, '½'], [5 / 8, '⅝'], [2 / 3, '⅔'], [3 / 4, '¾'], [5 / 6, '⅚'], [7 / 8, '⅞'],
];

export function formatAmount(value: number, maximumFractionDigits = 2) {
  if (!Number.isFinite(value)) return '—';
  const sign = value < 0 ? '-' : '';
  const absolute = Math.abs(value);
  let whole = Math.floor(absolute);
  const remainder = absolute - whole;
  if (Math.abs(1 - remainder) < 0.01) return `${sign}${whole + 1}`;
  if (remainder < 0.01) return `${sign}${whole}`;
  const fraction = DISPLAY_FRACTIONS.find(([candidate]) => Math.abs(candidate - remainder) < 0.01)?.[1];
  if (fraction) return `${sign}${whole || ''}${fraction}`;
  return value.toLocaleString(undefined, { maximumFractionDigits });
}

export function formatPreparedAt(value: string, timeZone: string) {
  return new Date(value).toLocaleString([], { timeZone, month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit' });
}

/** Stock should never look empty solely because the display unit is large. */
export function formatStockQuantity(value: number, unit?: string | null) {
  if (!Number.isFinite(value)) return '—';
  const absolute = Math.abs(value);
  const quantity = absolute > 0 && absolute < 0.001
    ? `${value < 0 ? '-' : ''}<0.001`
    : String(Number(value.toFixed(absolute < 1 ? 3 : 1)));
  return `${quantity} ${unit ?? ''}`.trim();
}

export function formatServings(value: number) {
  return `${formatAmount(value)} serving${Math.abs(value - 1) < 0.001 ? '' : 's'}`;
}

export function formatNutritionAmount(value: number, nutrient: string) {
  if (!Number.isFinite(value)) return '—';
  const maximumFractionDigits = nutrient === 'Calories' || nutrient === 'Sodium' ? 0 : 1;
  return value.toLocaleString('en-US', { maximumFractionDigits });
}

/** Preserve stored text while exposing a positive amount hidden by a legacy zero label. */
export function shoppingQuantityPresentation(label: string | null, value: number | null, unit?: string | null, generated = false) {
  if (label !== null) {
    const match = label.trim().match(/^0(?:[.,]0+)?\s*(.*)$/);
    const isZeroLabel = unit && match && match[1].toLowerCase() === unit.toLowerCase();
    if (generated && value !== null && Number.isFinite(value) && value > 0 && isZeroLabel) {
      return { quantity: formatStockQuantity(value, unit), savedQuantityLabel: label };
    }
    return { quantity: label };
  }
  return { quantity: value !== null ? formatStockQuantity(value, unit) : 'As needed' };
}
