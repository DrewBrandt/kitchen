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

export function formatServings(value: number) {
  return `${formatAmount(value)} serving${Math.abs(value - 1) < 0.001 ? '' : 's'}`;
}

export function formatNutritionAmount(value: number, nutrient: string) {
  if (!Number.isFinite(value)) return '—';
  const maximumFractionDigits = nutrient === 'Calories' || nutrient === 'Sodium' ? 0 : 1;
  return value.toLocaleString('en-US', { maximumFractionDigits });
}
