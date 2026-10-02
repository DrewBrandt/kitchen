import { useEffect, useState } from 'react';
import type { Recipe } from './data';
import type { PieceInput } from './pantry-data';
import { pieceWeight, practicalPieces } from './lib/recipe-pieces';
import { formatAmount } from './lib/format';
export function RecipePieceControl({ ingredient, scale, onChange }: { ingredient: Recipe['ingredients'][number]; scale: number; onChange: (value: PieceInput | null) => void }) {
  const basis = ingredient.pieceBasis!;
  const [lotId, setLotId] = useState(ingredient.pieceLots?.[0]?.id ?? '');
  const [pieces, setPieces] = useState(String(practicalPieces(basis.count * scale)));
  const [known, setKnown] = useState('');
  const [anchor, setAnchor] = useState(false);
  const lot = ingredient.pieceLots?.find((item) => item.id === lotId);
  useEffect(() => { if (!anchor) { setPieces(String(practicalPieces(basis.count * scale))); setKnown(''); } }, [scale, anchor]);
  const weight = pieceWeight(basis, Number(pieces), lot, known === '' ? undefined : Number(known));
  const valid = Boolean(lot && Number(pieces) > 0 && Number.isInteger(Number(pieces) * 4) && Number.isFinite(weight) && weight > 0 && weight <= lot.remainingBase + 0.0000001);
  useEffect(() => { onChange(valid && lot ? { ingredientId: ingredient.id!, lotId, pieces: Number(pieces), expectedRemaining: lot.remainingBase, ...(known === '' ? {} : { weightGrams: weight }), scaleRecipe: anchor } : null); }, [lotId, pieces, known, anchor, valid, lot?.remainingBase, lot?.remainingPieces]);
  return <div className="deck-batch-fields">
    <label className="field"><span>{basis.label} to cook</span><input type="number" min="0.25" step="0.25" value={pieces} onChange={(e) => { setPieces(e.target.value); setKnown(''); }} /></label>
    <label className="field"><span>Package / lot</span><select value={lotId} onChange={(e) => { setLotId(e.target.value); setKnown(''); }}><option value="" disabled>Select inventory</option>{ingredient.pieceLots?.map((item) => <option key={item.id} value={item.id}>{item.label}</option>)}</select></label>
    <label className="field"><span>Weight of selected pieces (g)</span><input type="number" min="0.01" step="any" value={known === '' ? Math.round(weight * 100) / 100 : known} onChange={(e) => setKnown(e.target.value)} /></label>
    <small>{known !== '' ? 'Entered weight' : lot?.remainingPieces ? 'Estimated from lot average' : 'Estimated from saved recipe'}: {formatAmount(weight)} g. {valid ? '' : 'Choose a lot with enough stock and a positive whole, half or quarter count.'}</small>
    {basis.anchor && <label><input type="checkbox" checked={anchor} onChange={(e) => setAnchor(e.target.checked)} /> Scale recipe to these pieces</label>}
    <small>Source: {basis.sourceQuantity} {basis.sourceUnit}; {basis.provenance}.</small>
  </div>;
}
