import type { RecipePieceBasis } from '../data';
export function pieceWeight(basis: RecipePieceBasis, pieces: number, lot?: { remainingBase: number; remainingPieces?: number }, knownWeight?: number) {
  return knownWeight ?? pieces * (lot?.remainingPieces ? lot.remainingBase / lot.remainingPieces : basis.grams / basis.count);
}
export function practicalPieces(value: number) { return Math.max(0.25, Math.round(value * 4) / 4); }
