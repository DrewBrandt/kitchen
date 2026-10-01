import { useState } from 'react';
import type { Json } from './database.types';
import { mutationError } from './lib/mutation-feedback';

export interface ManualConsumptionSnapshot {
  label: string;
  portionLabel: string | null;
  note: string | null;
  nutrition: Record<string, number | string | boolean | null>;
}

const nutrients = { calories: 'Calories', proteinG: 'Protein (g)', carbsG: 'Carbs (g)', fatG: 'Fat (g)', fiberG: 'Fiber (g)', sugarG: 'Sugar (g)', sodiumMg: 'Sodium (mg)' };

export function ManualConsumptionEditor({ id, original, save, close }: { id: string; original: ManualConsumptionSnapshot; save: (id: string, patch: Json) => Promise<void>; close: () => void }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  return <form className="form-grid" aria-label="Edit manual consumption" onSubmit={async (event) => {
    event.preventDefault();
    if (busy) return;
    const form = new FormData(event.currentTarget);
    const patch: Record<string, Json> = {};
    for (const key of ['label', 'portionLabel', 'note'] as const) {
      const value = String(form.get(key) ?? '').trim();
      if (value !== (original[key] ?? '')) patch[key] = value || null;
    }
    const nutrition = { ...original.nutrition };
    let changed = false;
    for (const key of Object.keys(nutrients)) {
      const text = String(form.get(key) ?? '').trim();
      const value = text === '' ? null : Number(text);
      if (value !== null && (!Number.isFinite(value) || value < 0)) { setError('Nutrition must be nonnegative, or blank for unknown.'); return; }
      if (value !== original.nutrition[key]) { nutrition[key] = value; changed = true; }
    }
    if (changed) patch.nutrition = nutrition;
    if (!Object.keys(patch).length) { close(); return; }
    setBusy(true); setError('');
    try { await save(id, patch); close(); }
    catch (cause) { setError(mutationError(cause, 'Could not save this correction.')); }
    finally { setBusy(false); }
  }}>
    <p>Changing the portion text won’t update nutrition or cost.</p>
    <label className="field"><span>Food name</span><input name="label" required defaultValue={original.label} /></label>
    <label className="field"><span>Portion description</span><input name="portionLabel" defaultValue={original.portionLabel ?? ''} /></label>
    <label className="field"><span>Note</span><input name="note" defaultValue={original.note ?? ''} /></label>
    <p>Nutrition totals · blank = unknown</p>
    {Object.entries(nutrients).map(([key, label]) => <label className="field" key={key}><span>{label}</span><input name={key} type="number" min="0" step="any" defaultValue={original.nutrition[key] === null ? '' : String(original.nutrition[key] ?? '')} /></label>)}
    {error && <p role="alert">{error}</p>}
    <button type="submit" className="button primary" disabled={busy}>{busy ? 'Saving…' : 'Save correction'}</button>
    <button type="button" className="button" disabled={busy} onClick={close}>Cancel edit</button>
  </form>;
}
