/** The forecast shortage is a total, not an increment to the retained list. */
export function groceryDemandNotice(shortageBase: number, savedRemainingBase: number | null, formatBase: (value: number) => string) {
  // Match inventory residue tolerance; unit round trips can differ below this.
  if (savedRemainingBase !== null && Math.abs(shortageBase - savedRemainingBase) <= 0.000001) return undefined;
  const saved = savedRemainingBase === null ? '' : ` Saved remaining list quantity: ${formatBase(savedRemainingBase)}.`;
  return `Current plan shortage: ${formatBase(shortageBase)} total.${saved} Your check and quantity were kept.`;
}
