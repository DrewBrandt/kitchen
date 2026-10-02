import { useState } from 'react';
import type { Recipe } from './data';

/** Keep identity attached to the editable row through quantity changes and reordering. */
export function RecipeIngredientEditor({ recipe }: { recipe: Recipe }) {
  const [rows, setRows] = useState(() => (recipe.ingredientText ?? '').split('\n').filter(Boolean).map((text, index) => ({ key: crypto.randomUUID(), id: recipe.ingredients[index]?.id ?? null, pieceBasis: recipe.ingredients[index]?.pieceBasis ?? null, original: recipe.ingredients[index] as Recipe['ingredients'][number] | undefined, text })));
  function move(index: number, offset: number) {
    setRows((current) => { const next = [...current]; [next[index], next[index + offset]] = [next[index + offset], next[index]]; return next; });
  }
  return <fieldset className="recipe-ingredient-editor"><legend>Ingredients</legend>
    <input type="hidden" name="ingredients" value={rows.map((row) => row.text).join('\n')} />
    <input type="hidden" name="ingredient_piece_bases" value={JSON.stringify(rows.map((row) => row.pieceBasis))} />
    <input type="hidden" name="ingredient_ids" value={JSON.stringify(rows.map((row) => row.id))} />
    {rows.map((row, index) => <div className="recipe-ingredient-edit-row" key={row.key}>
      <label className="field"><span>Ingredient {index + 1}</span><input required value={row.text} onChange={(event) => setRows((current) => current.map((item) => item.key === row.key ? { ...item, text: event.target.value } : item))} /></label>
      {!row.pieceBasis && row.original?.baseGrams && <button type="button" className="text-button" onClick={() => setRows((current) => current.map((item) => item.key === row.key ? { ...item, pieceBasis: { count: 1, grams: row.original!.baseGrams!, label: row.original!.name ?? 'pieces', sourceQuantity: row.original!.quantity!, sourceUnit: row.original!.unit!, provenance: 'User-supplied recipe estimate', anchor: false } } : item))}>Use pieces for ingredient {index + 1}</button>}
      {row.pieceBasis && <div className="deck-batch-fields">
        <label className="field"><span>Piece count for ingredient {index + 1}</span><input type="number" required min="0.25" step="0.25" value={row.pieceBasis.count} onChange={(e) => setRows((current) => current.map((item) => item.key === row.key ? { ...item, pieceBasis: { ...item.pieceBasis!, count: Number(e.target.value) } } : item))} /></label>
        <label className="field"><span>Piece label for ingredient {index + 1}</span><input required value={row.pieceBasis.label} onChange={(e) => setRows((current) => current.map((item) => item.key === row.key ? { ...item, pieceBasis: { ...item.pieceBasis!, label: e.target.value } } : item))} /></label>
        <label><input type="checkbox" checked={Boolean(row.pieceBasis.anchor)} onChange={(e) => setRows((current) => current.map((item) => item.key === row.key ? { ...item, pieceBasis: { ...item.pieceBasis!, anchor: e.target.checked } } : item))} /> Allow scaling from ingredient {index + 1}</label>
        <small>This count represents approximately {row.pieceBasis.grams} g in the recipe. Choose at most one scaling ingredient. Remove the estimate before changing its weight or food.</small>
        <button type="button" className="text-button" onClick={() => setRows((current) => current.map((item) => item.key === row.key ? { ...item, pieceBasis: null } : item))}>Remove piece estimate</button>
      </div>}
      <div><button className="button compact" type="button" aria-label={`Move ingredient ${index + 1} up`} disabled={index === 0} onClick={() => move(index, -1)}>Up</button>
      <button className="button compact" type="button" aria-label={`Move ingredient ${index + 1} down`} disabled={index === rows.length - 1} onClick={() => move(index, 1)}>Down</button>
      <button className="button compact" type="button" aria-label={`Remove ingredient ${index + 1}`} onClick={() => setRows((current) => current.filter((item) => item.key !== row.key))}>Remove</button></div>
    </div>)}
    <button className="button compact" type="button" onClick={() => setRows((current) => [...current, { key: crypto.randomUUID(), id: null, pieceBasis: null, original: undefined, text: '' }])}>Add ingredient</button>
  </fieldset>;
}
