import { useEffect, useState } from 'react';
import { formatAmount } from './lib/format';
import { isDefiniteMutationFailure, mutationError, pendingMutationPayload } from './lib/mutation-feedback';

export interface QuantityCorrectionSnapshot {
  quantity: number;
  canonicalUnit: string;
  displayUnit: string;
  displayPerBase: number;
  calories: number | null;
  protein: number | null;
  cost: number | null;
  estimated: boolean;
}
export type CorrectionPayload = { id: string; expectedQuantity: number; quantity: number };

export function QuantityCorrectionEditor({ id, label, snapshot, save, close }: { id: string; label: string; snapshot: QuantityCorrectionSnapshot; save: (id: string, expected: number, quantity: number) => Promise<string>; close: () => void }) {
  const [amount, setAmount] = useState(String(Number((snapshot.quantity * snapshot.displayPerBase).toPrecision(12))));
  const [busy, setBusy] = useState(false);
  const [pending, setPending] = useState<CorrectionPayload>();
  const [error, setError] = useState('');
  const [hydrated, setHydrated] = useState(false);
  useEffect(() => {
    let active = true;
    void pendingMutationPayload<CorrectionPayload>('correct_consumed_quantity', { id }).then((value) => {
      if (!active) return;
      setPending(value);
      if (value) setAmount(String(value.quantity * snapshot.displayPerBase));
      setHydrated(true);
    }).catch((cause) => { if (active) setError(mutationError(cause)); });
    return () => { active = false; };
  }, [id, snapshot.displayPerBase]);
  const displayedOriginal = Number((snapshot.quantity * snapshot.displayPerBase).toPrecision(12));
  const entered = Number(amount);
  const quantity = pending?.quantity ?? (entered === displayedOriginal ? snapshot.quantity : entered / snapshot.displayPerBase);
  const original = pending?.expectedQuantity ?? snapshot.quantity;
  const ratio = quantity / original;
  const valid = amount.trim() !== '' && Number.isFinite(quantity) && quantity > 0;
  const delta = original - quantity;
  const value = (number: number | null, unit: string) => number === null ? 'Unknown' : `${formatAmount(number * ratio)} ${unit}`;
  return <form className="form-grid" aria-label="Correct consumed quantity" onSubmit={async (event) => {
    event.preventDefault();
    if (!hydrated || busy || !valid || (!pending && quantity === original)) return;
    setBusy(true); setError('');
    const payload = pending ?? { id, expectedQuantity: original, quantity };
    setPending(payload);
    try { await save(id, payload.expectedQuantity, payload.quantity); close(); }
    catch (cause) { if (isDefiniteMutationFailure(cause)) setPending(undefined); setError(mutationError(cause)); }
    finally { setBusy(false); }
  }}>
    <strong>Correct only {label}</strong>
    <p>Recorded: {formatAmount(displayedOriginal)} {snapshot.displayUnit} ({formatAmount(original)} {snapshot.canonicalUnit}).</p>
    <label className="field"><span>Correct amount eaten ({snapshot.displayUnit})</span><input type="number" min="0" step="any" value={amount} disabled={busy || Boolean(pending) || !hydrated} onChange={(event) => setAmount(event.target.value)} /></label>
    {valid && <div role="status"><p>Corrected amount: {formatAmount(quantity)} {snapshot.canonicalUnit}. {delta >= 0 ? 'Return' : 'Deduct'} {formatAmount(Math.abs(delta))} {snapshot.canonicalUnit} {delta >= 0 ? 'to' : 'from'} the original lot.</p><p>Corrected totals: {value(snapshot.calories, 'cal')} · {value(snapshot.protein, 'g protein')} · Recorded cost {snapshot.cost === null ? 'unknown' : `$${(snapshot.cost * ratio).toFixed(2)}`}{snapshot.estimated ? ' · estimated' : ''}.</p></div>}
    <p>This replaces the old event and cannot be undone. To record none, remove the event.</p>
    {pending && <p>Retrying the same correction.</p>}
    {error && <p role="alert">{error}</p>}
    <button className="button primary" disabled={!hydrated || busy || !valid || (!pending && quantity === original)}>{busy ? 'Saving…' : pending ? 'Retry correction' : 'Save quantity correction'}</button>
    <button type="button" className="button" disabled={busy} onClick={close}>Close correction</button>
  </form>;
}
