import { useId, useState } from 'react';
import { usePantryData, type GroceryItem, type ShoppingReceipt } from './pantry-data';
import { mutationError } from './lib/mutation-feedback';

export function ShoppingReceiptEditor({ item, onSave, onClose }: { item: GroceryItem; onSave: (id: string, receipt: ShoppingReceipt) => Promise<void>; onClose: () => void }) {
  const { products, foods, units, locations } = usePantryData();
  const formId = useId();
  const sortedFoods = [...foods].sort((a, b) => a.name.localeCompare(b.name));
  const [foodId, setFoodId] = useState(item.foodId ?? '');
  const [search, setSearch] = useState('');
  const [productId, setProductId] = useState(item.requiredProductId ?? item.pinnedProductId ?? '');
  const [quantity, setQuantity] = useState(String(item.quantityNeeded ?? ''));
  const [unit, setUnit] = useState(item.unitId ?? '');
  const [price, setPrice] = useState('');
  const [location, setLocation] = useState('pantry');
  const [bestBy, setBestBy] = useState('');
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const food = foods.find((candidate) => candidate.id === foodId);
  const suitableProducts = products.filter((product) => product.foodId === foodId);
  const valid = item.id && food && unit && Number(quantity) > 0 && Number.isFinite(Number(quantity)) && (price === '' || (Number(price) >= 0 && Number.isFinite(Number(price))));
  return <form className="receipt-editor" aria-label={`Receive ${item.name}`} onSubmit={(event) => {
    event.preventDefault(); if (!valid || !item.id || busy) return;
    setBusy(true); setError('');
    void onSave(item.id, { foodId, productId: productId || null, quantity: Number(quantity), unit, totalPrice: price === '' ? null : Number(price), location, bestBy: bestBy || null, note: note || null })
      .then(onClose).catch((cause: unknown) => setError(mutationError(cause))).finally(() => setBusy(false));
  }}>
    <h3>Receive {item.name}</h3>
    {!item.foodId && <label htmlFor={`${formId}-food`}>Food acquired<select id={`${formId}-food`} required value={foodId} onChange={(event) => { setFoodId(event.target.value); setProductId(''); setUnit(''); }}><option value="">Choose food</option>{sortedFoods.map((value) => <option key={value.id} value={value.id}>{value.name}</option>)}</select></label>}
    <label htmlFor={`${formId}-search`}>Search products<input id={`${formId}-search`} type="search" value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search this food’s products" /></label>
    <label htmlFor={`${formId}-product`}>Product<select id={`${formId}-product`} value={productId} onChange={(event) => setProductId(event.target.value)}><option value="">Plain / unbranded {food?.name ?? 'food'}</option>{suitableProducts.filter((product) => product.id === productId || product.label.toLowerCase().includes(search.toLowerCase())).map((product) => <option key={product.id} value={product.id}>{product.label}</option>)}</select></label>
    {item.requiredProductId && productId !== item.requiredProductId && <p role="status">Plan still needs {item.requiredProductName ?? item.name}.</p>}
    <div className="form-grid two"><label htmlFor={`${formId}-quantity`}>Quantity bought<input id={`${formId}-quantity`} required type="number" min="0.000001" step="any" value={quantity} onChange={(event) => setQuantity(event.target.value)} /></label><label htmlFor={`${formId}-unit`}>Unit<select id={`${formId}-unit`} required value={unit} onChange={(event) => setUnit(event.target.value)}><option value="">Choose unit</option>{units.filter((value) => value.measureStyle === food?.measureStyle || value.id === unit).map((value) => <option key={value.id} value={value.id}>{value.label}</option>)}</select></label></div>
    <label htmlFor={`${formId}-price`}>Price paid (optional)<input id={`${formId}-price`} type="number" min="0" step="0.01" value={price} onChange={(event) => setPrice(event.target.value)} placeholder="Unknown" /></label>
    <details><summary>More details</summary><label htmlFor={`${formId}-location`}>Store in<select id={`${formId}-location`} value={location} onChange={(event) => setLocation(event.target.value)}>{locations.map((value) => <option key={value}>{value}</option>)}</select></label><label htmlFor={`${formId}-best-by`}>Best by<input id={`${formId}-best-by`} type="date" value={bestBy} onChange={(event) => setBestBy(event.target.value)} /></label><label htmlFor={`${formId}-note`}>Note<input id={`${formId}-note`} value={note} onChange={(event) => setNote(event.target.value)} /></label></details>

    {error && <p role="alert">{error}</p>}
    <div className="card-actions"><button className="button primary" disabled={!valid || busy}>{busy ? 'Receiving…' : 'Add to inventory'}</button><button type="button" className="button secondary" onClick={onClose} disabled={busy}>Cancel</button></div>
  </form>;
}

export function DurableUndo({ label, action }: { label: string; action?: () => Promise<void> }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  return <div><button className="button secondary compact" aria-label={label} disabled={!action || busy} onClick={() => { if (!action) return; setBusy(true); setError(''); void action().catch((cause: unknown) => setError(mutationError(cause))).finally(() => setBusy(false)); }}>{busy ? 'Undoing…' : 'Undo'}</button>{error && <p role="alert">{error}</p>}</div>;
}
