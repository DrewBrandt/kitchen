import type { RecipePieceBasis } from '../data';
export function pieceWeight(basis: RecipePieceBasis, pieces: number, lot?: { remainingBase: number; remainingPieces?: number }, knownWeight?: number) {
  return knownWeight ?? pieces * (lot?.remainingPieces ? lot.remainingBase / lot.remainingPieces : basis.grams / basis.count);
}
export function practicalPieces(value: number) { return Math.max(0.25, Math.round(value * 4) / 4); }

export function hasPieceNutritionConflict(recipe: import('../data').Recipe, inputs: Record<string, import('../pantry-data').PieceInput | null>, scale: number) {
  if (!recipe.hasNutritionOverride) return false;
  return Object.values(inputs).some((input) => {
    if (!input) return false;
    const ingredient = recipe.ingredients.find((item) => item.id === input.ingredientId);
    const lot = ingredient?.pieceLots?.find((item) => item.id === input.lotId);
    if (!ingredient || !lot || ingredient.baseGrams === undefined) return true;
    const grams = ingredient.pieceBasis ? pieceWeight(ingredient.pieceBasis, input.pieces, lot, input.weightGrams)
      : input.pieces * lot.remainingBase / (lot.remainingPieces ?? input.lotPieces ?? NaN);
    return !Number.isFinite(grams) || Math.abs(grams - ingredient.baseGrams * scale) > 0.0001;
  });
}
