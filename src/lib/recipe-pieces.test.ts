import { describe, it, expect } from 'vitest';
import { pieceWeight, practicalPieces } from './recipe-pieces';
const basis = { count: 3, grams: 450, label: 'thighs', sourceQuantity: 1, sourceUnit: 'lb', provenance: 'saved importer estimate' };
describe('recipe piece sizing', () => {
  it('uses saved estimates without inventing a lot count', () => expect(pieceWeight(basis, 3, { remainingBase: 2000 })).toBe(450));
  it('uses known lot averages ahead of the saved estimate', () => expect(pieceWeight(basis, 3, { remainingBase: 1200, remainingPieces: 6 })).toBe(600));
  it('scales a tenderloin anchor by selected weight, not multipiece pack weight', () => {
    const tenderloin = { ...basis, count: 1, grams: 450 };
    expect(pieceWeight(tenderloin, 1, { remainingBase: 1350, remainingPieces: 2 }) / tenderloin.grams).toBe(1.5);
    expect(pieceWeight(tenderloin, 1, { remainingBase: 1350 }, 675) / tenderloin.grams).toBe(1.5);
    expect(pieceWeight(tenderloin, 1, { remainingBase: 1350 })).toBe(450);
  });
  it('offers practical quarter-piece quantities', () => { expect(practicalPieces(3.14159)).toBe(3.25); expect(practicalPieces(0.02)).toBe(0.25); });
});
