import { useEffect, useMemo, useState } from 'react';
import { BookOpen, CalendarDays, Check, ChevronDown, FlaskConical, PackageOpen, Search, Utensils, X } from 'lucide-react';
import type { Recipe } from './data';
import { usePantryData, type NutrientName, type NutritionValues, type PlannedMealView, type ProductView } from './pantry-data';
import { usd } from './lib/cost';
import { formatAmount, formatServings } from './lib/format';
import { nutritionForServings } from './lib/nutrition';

type SourceType = 'recipe' | 'pantry' | 'leftover';
type Notify = (message: string) => void;

const EMPTY_NUTRITION: NutritionValues = { Calories: 0, Protein: 0, Carbs: 0, Fat: 0, Fiber: 0, Sodium: 0 };

function recipePerServing(recipe: Recipe): NutritionValues {
  if (recipe.nutritionValues) return nutritionForServings(recipe.nutritionValues, recipe.servings, 1);
  const calories = Number(recipe.nutrition.match(/([\d,.]+)\s*cal/i)?.[1]?.replace(',', '') ?? 0);
  const protein = Number(recipe.nutrition.match(/([\d,.]+)\s*g\s*protein/i)?.[1]?.replace(',', '') ?? 0);
  return { ...EMPTY_NUTRITION, Calories: calories, Protein: protein };
}

function multiplyNutrition(values: NutritionValues, multiplier: number): NutritionValues {
  return Object.fromEntries(Object.entries(values).map(([label, value]) => [label, value * multiplier])) as NutritionValues;
}

function SourceTabs({ value, onChange, leftovers = true }: { value: SourceType; onChange: (value: SourceType) => void; leftovers?: boolean }) {
  const tabs = [
    { id: 'recipe' as const, label: 'Recipe', note: 'Make something', icon: BookOpen },
    { id: 'pantry' as const, label: 'Pantry item', note: 'Use what you have', icon: PackageOpen },
    ...(leftovers ? [{ id: 'leftover' as const, label: 'Leftovers', note: 'Eat a prepared batch', icon: Utensils }] : []),
  ];
  return <div className="source-tabs" role="tablist" aria-label="Plan source">{tabs.map((tab) => {
    const Icon = tab.icon;
    return <button key={tab.id} type="button" role="tab" aria-selected={value === tab.id} className={value === tab.id ? 'selected' : ''} onClick={() => onChange(tab.id)}><Icon /><span><strong>{tab.label}</strong><small>{tab.note}</small></span>{value === tab.id && <Check />}</button>;
  })}</div>;
}

function ChoiceList({ type, query, selectedId, onSelect }: { type: SourceType; query: string; selectedId: string; onSelect: (id: string) => void }) {
  const { plannedMeals, products, recipes } = usePantryData();
  const leftoverGroups = useMemo(() => [...plannedMeals.reduce((groups, plan) => {
    if (!plan.recipeId || plan.isLeftover) return groups;
    const current = groups.get(plan.groupId);
    groups.set(plan.groupId, current ? { ...current, name: current.name.includes(plan.name) ? current.name : `${current.name} + ${plan.name}` } : plan);
    return groups;
  }, new Map<string, PlannedMealView>()).values()], [plannedMeals]);
  const normalized = query.trim().toLowerCase();
  const choices = type === 'recipe'
    ? recipes.map((recipe) => ({ id: recipe.id, emoji: recipe.emoji, label: recipe.name, meta: `${recipe.minutes} min · ${formatServings(recipe.servings)} per batch`, badge: recipe.cookable === false ? 'Needs groceries' : 'Ready to cook' }))
    : type === 'pantry'
      ? products.map((product) => ({ id: product.id, emoji: product.emoji, label: product.label, meta: `${product.servingLabel} · ${formatServings(product.stockServings)} on hand`, badge: product.stockServings > 0 ? `${formatAmount(product.stockServings)} available` : 'Out of stock' }))
      : leftoverGroups.map((plan) => ({ id: plan.groupId, emoji: plan.emoji, label: plan.name, meta: `Originally planned ${new Date(`${plan.dateKey}T12:00:00`).toLocaleDateString([], { month: 'short', day: 'numeric' })}`, badge: 'Prepared serving' }));
  const filtered = choices.filter((choice) => !normalized || `${choice.label} ${choice.meta}`.toLowerCase().includes(normalized));
  return <div className="source-results" role="listbox" aria-label={`${type} choices`}>
    {filtered.map((choice) => <button key={choice.id} type="button" role="option" aria-selected={selectedId === choice.id} className={selectedId === choice.id ? 'selected' : ''} onClick={() => onSelect(choice.id)}><span className="source-choice-emoji">{choice.emoji}</span><span className="grow"><strong>{choice.label}</strong><small>{choice.meta}</small></span><em>{choice.badge}</em>{selectedId === choice.id && <Check />}</button>)}
    {!filtered.length && <div className="source-empty">No matches. Try a shorter search.</div>}
  </div>;
}

function LotChoice({ product, value, onChange }: { product: ProductView; value: string; onChange: (value: string) => void }) {
  return <div className="stock-choice">
    <div className="stock-choice-head"><span>Which stock?</span><small>Automatic uses the first expiring lot when you log it.</small></div>
    <label className={value === 'any' ? 'selected' : ''}><input type="radio" checked={value === 'any'} onChange={() => onChange('any')} /><span><strong>Choose automatically</strong><small>{formatServings(product.stockServings)} across {product.availableLots.length} lot{product.availableLots.length === 1 ? '' : 's'}</small></span></label>
    {product.availableLots.map((lot) => <label key={lot.id} className={value === lot.id ? 'selected' : ''}><input type="radio" checked={value === lot.id} onChange={() => onChange(lot.id)} /><span><strong>{lot.location} · {formatServings(lot.remainingServings)}</strong><small>{lot.dateLabel} · {lot.costPerServing === null ? 'Price unavailable' : `${lot.costIsEstimated ? '~' : ''}${usd(lot.costPerServing)} per serving`}</small></span></label>)}
  </div>;
}

function ImpactStrip({ nutrition, cost, estimated }: { nutrition: NutritionValues; cost: number | null; estimated?: boolean }) {
  const stats: Array<[string, string]> = [
    ['Calories', `${Math.round(nutrition.Calories).toLocaleString()} cal`],
    ['Protein', `${formatAmount(nutrition.Protein)} g`],
    ['Carbs', `${formatAmount(nutrition.Carbs)} g`],
    ['Cost', cost === null ? 'Unavailable' : `${estimated ? '~' : ''}${usd(cost)}`],
  ];
  return <div className="impact-strip" aria-label="Nutrition and cost preview">{stats.map(([label, value]) => <div key={label}><span>{label}</span><strong>{value}</strong></div>)}</div>;
}

export function DayPlanFields({ values = {}, onValidityChange }: { values?: Record<string, string>; onValidityChange?: (valid: boolean) => void }) {
  const { plannedMeals, products, recipes } = usePantryData();
  const today = new Date().toLocaleDateString('en-CA');
  const initialType: SourceType = values.recipe ? 'recipe' : values.product ? 'pantry' : 'recipe';
  const [type, setType] = useState<SourceType>(initialType);
  const [selectedId, setSelectedId] = useState(values.recipe ?? values.product ?? '');
  const [sourceExpanded, setSourceExpanded] = useState(!selectedId);
  const [query, setQuery] = useState('');
  const [stockChoice, setStockChoice] = useState(values.inventory_lot ?? 'any');
  const [servings, setServings] = useState('1');
  const selectedRecipe = type === 'recipe' ? recipes.find((recipe) => recipe.id === selectedId) : undefined;
  const selectedProduct = type === 'pantry' ? products.find((product) => product.id === selectedId) : undefined;
  const selectedLeftover = type === 'leftover' ? plannedMeals.find((plan) => plan.groupId === selectedId) : undefined;
  const selectedLeftoverRecipe = selectedLeftover?.recipeId ? recipes.find((recipe) => recipe.id === selectedLeftover.recipeId) : undefined;
  const [batchServings, setBatchServings] = useState(String(selectedRecipe?.servings ?? 1));
  const amount = Math.max(0, Number(servings) || 0);
  const nutrition = selectedRecipe ? multiplyNutrition(recipePerServing(selectedRecipe), amount)
    : selectedProduct ? multiplyNutrition(selectedProduct.nutritionPerServing, amount)
      : selectedLeftoverRecipe ? multiplyNutrition(recipePerServing(selectedLeftoverRecipe), amount)
        : EMPTY_NUTRITION;
  const costPerServing = selectedRecipe?.costPerServing ?? selectedProduct?.costPerServing ?? (selectedLeftover ? 0 : null);
  const selectedLot = selectedProduct?.availableLots.find((lot) => lot.id === stockChoice);
  const cost = costPerServing === null || costPerServing === undefined ? null : (selectedLot?.costPerServing ?? costPerServing) * amount;
  const exactLot = selectedProduct && stockChoice !== 'any' ? stockChoice : '';
  const chooseType = (next: SourceType) => { setType(next); setSelectedId(''); setStockChoice('any'); setQuery(''); setSourceExpanded(true); };
  const chooseSource = (id: string) => {
    setSelectedId(id);
    setStockChoice('any');
    setSourceExpanded(false);
    const recipe = recipes.find((candidate) => candidate.id === id);
    if (recipe) setBatchServings(String(recipe.servings));
  };
  useEffect(() => {
    onValidityChange?.(Boolean(selectedId) && amount > 0 && (!selectedRecipe || Number(batchServings) > 0));
  }, [amount, batchServings, onValidityChange, selectedId, selectedRecipe]);
  return <div className={`plan-composer${sourceExpanded ? '' : ' source-chosen'}`}>
    <section className="composer-step"><div className="composer-step-title"><i>1</i><div><strong>Choose what you’ll have</strong><small>Start broad. Lot details appear only when they matter.</small></div></div>
      <SourceTabs value={type} onChange={chooseType} />
      {sourceExpanded ? <>
        <label className="source-search"><Search /><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder={`Search ${type === 'pantry' ? 'pantry items' : type === 'leftover' ? 'planned meals' : 'recipes'}…`} aria-label="Search plan sources" />{query && <button type="button" onClick={() => setQuery('')} aria-label="Clear search"><X /></button>}</label>
        <ChoiceList type={type} query={query} selectedId={selectedId} onSelect={chooseSource} />
      </> : <div className="selected-source-summary"><span>{selectedRecipe?.emoji ?? selectedProduct?.emoji ?? selectedLeftover?.emoji}</span><div className="grow"><strong>{selectedRecipe?.name ?? selectedProduct?.label ?? selectedLeftover?.name}</strong><small>{selectedProduct?.servingLabel ?? (selectedRecipe ? `${selectedRecipe.minutes} min · ${formatServings(selectedRecipe.servings)} per batch` : 'Prepared serving')}</small></div><button type="button" onClick={() => setSourceExpanded(true)}>Change</button></div>}
      {selectedProduct && <LotChoice product={selectedProduct} value={stockChoice} onChange={setStockChoice} />}
    </section>

    {(selectedRecipe || selectedProduct || selectedLeftover) && <section className="composer-step"><div className="composer-step-title"><i>2</i><div><strong>Set the portion and timing</strong><small>{selectedProduct?.servingLabel ?? (selectedRecipe ? `One serving is 1/${selectedRecipe.servings} of the usual batch.` : 'Use the serving size from the original recipe.')}</small></div></div>
      <input type="hidden" name="intent" value={type === 'pantry' ? 'consume' : type === 'leftover' ? 'leftover' : 'prepare'} />
      <input type="hidden" name="recipe" value={selectedRecipe?.id ?? ''} />
      <input type="hidden" name="product" value={selectedProduct && !exactLot ? selectedProduct.id : ''} />
      <input type="hidden" name="inventory_lot" value={exactLot} />
      <input type="hidden" name="source_group_id" value={selectedLeftover?.groupId ?? ''} />
      <input type="hidden" name="scale_factor" value={selectedRecipe ? Math.max(0.01, Number(batchServings) / selectedRecipe.servings) : 1} />
      <div className="composer-fields">
        <label className="field"><span>Servings you’ll eat</span><input name="planned_servings" type="number" min="0.01" step="any" required value={servings} onChange={(event) => setServings(event.target.value)} /></label>
        {selectedRecipe && <label className="field"><span>Servings to make</span><input type="number" min="0.25" step="0.25" required value={batchServings} onChange={(event) => setBatchServings(event.target.value)} /></label>}
        <label className="field"><span>Date</span><input name="plan_date" type="date" required defaultValue={values.plan_date || today} /></label>
        <label className="field"><span>Time of day</span><select name="daypart" required defaultValue={values.daypart || 'dinner'}>{['breakfast', 'brunch', 'lunch', 'dinner', 'snack', 'dessert'].map((value) => <option key={value} value={value}>{value[0].toUpperCase() + value.slice(1)}</option>)}</select></label>
      </div>
      <ImpactStrip nutrition={nutrition} cost={cost} estimated={selectedLot?.costIsEstimated ?? selectedRecipe?.costIsEstimated ?? Boolean(selectedProduct)} />
      {selectedProduct && amount > selectedProduct.stockServings && <div className="composer-warning">You have {formatServings(selectedProduct.stockServings)} on hand, less than this plan. Lower the portion or add inventory first.</div>}
      <details className="optional-note"><summary>Optional note <ChevronDown /></summary><label className="field"><span>Note</span><input name="note" placeholder="Anything useful for future you" /></label></details>
    </section>}
  </div>;
}

export function NutritionSandbox({ onPlan, onConsumeLot, notify }: { onPlan?: (form: FormData) => Promise<string>; onConsumeLot?: (id: string, quantity: number) => Promise<string | null>; notify: Notify }) {
  const { foodLog, products, recipes, settings, todayProjection } = usePantryData();
  const [open, setOpen] = useState(false);
  const [type, setType] = useState<SourceType>('pantry');
  const [selectedId, setSelectedId] = useState('');
  const [query, setQuery] = useState('');
  const [servings, setServings] = useState('1');
  const [stockChoice, setStockChoice] = useState('any');
  const [saving, setSaving] = useState('');
  const selectedProduct = type === 'pantry' ? products.find((product) => product.id === selectedId) : undefined;
  const selectedRecipe = type === 'recipe' ? recipes.find((recipe) => recipe.id === selectedId) : undefined;
  const amount = Math.max(0, Number(servings) || 0);
  const candidate = selectedProduct ? multiplyNutrition(selectedProduct.nutritionPerServing, amount) : selectedRecipe ? multiplyNutrition(recipePerServing(selectedRecipe), amount) : EMPTY_NUTRITION;
  const current = Object.fromEntries((Object.keys(EMPTY_NUTRITION) as NutrientName[]).map((label) => [label, foodLog.reduce((sum, entry) => sum + Number(entry.nutrition?.[label] ?? 0), 0)])) as NutritionValues;
  const baseline = Object.fromEntries((Object.keys(current) as NutrientName[]).map((label) => [label, current[label] + todayProjection[label]])) as NutritionValues;
  const targets: NutritionValues = { Calories: settings.calories, Protein: settings.proteinG, Carbs: settings.carbsG, Fat: settings.fatG, Fiber: settings.fiberG, Sodium: settings.sodiumMg };
  const exactLot = selectedProduct?.availableLots.find((lot) => lot.id === stockChoice);
  const costPerServing = exactLot?.costPerServing ?? selectedProduct?.costPerServing ?? selectedRecipe?.costPerServing ?? null;
  const chooseType = (next: SourceType) => { setType(next); setSelectedId(''); setQuery(''); setStockChoice('any'); };
  async function plan() {
    if ((!selectedProduct && !selectedRecipe) || !onPlan || amount <= 0) return;
    const form = new FormData();
    form.set('intent', selectedProduct ? 'consume' : 'prepare');
    form.set('product', selectedProduct && stockChoice === 'any' ? selectedProduct.id : '');
    form.set('inventory_lot', selectedProduct && stockChoice !== 'any' ? stockChoice : '');
    form.set('recipe', selectedRecipe?.id ?? '');
    form.set('plan_date', new Date().toLocaleDateString('en-CA'));
    form.set('daypart', new Date().getHours() >= 20 ? 'snack' : 'dinner');
    form.set('scale_factor', '1');
    form.set('planned_servings', String(amount));
    setSaving('plan');
    try { notify(await onPlan(form)); setOpen(false); }
    catch (error) { notify(error instanceof Error ? error.message : 'Could not add this to today.'); }
    finally { setSaving(''); }
  }
  async function logNow() {
    if (!selectedProduct || !exactLot || !onConsumeLot || amount <= 0) return;
    setSaving('log');
    try { await onConsumeLot(exactLot.id, amount * selectedProduct.servingQtyBase); notify(`${formatServings(amount)} of ${selectedProduct.label} logged.`); setOpen(false); }
    catch (error) { notify(error instanceof Error ? error.message : 'Could not log this item.'); }
    finally { setSaving(''); }
  }
  if (!open) return <button className="sandbox-invite" onClick={() => setOpen(true)}><span className="sandbox-icon"><FlaskConical /></span><span className="grow"><strong>What if I ate something else?</strong><small>Try a food or drink against today’s totals before you commit.</small></span><span>Try a food</span></button>;
  return <section className="nutrition-sandbox" aria-labelledby="sandbox-title">
    <div className="sandbox-head"><span className="sandbox-icon"><FlaskConical /></span><div className="grow"><strong id="sandbox-title">Try it against your day</strong><small>This is a scratchpad. Nothing changes until you plan or log it.</small></div><button className="icon-button" onClick={() => setOpen(false)} aria-label="Close nutrition scratchpad"><X /></button></div>
    <div className="sandbox-workspace">
      <div className="sandbox-picker">
        <SourceTabs value={type} onChange={chooseType} leftovers={false} />
        <label className="source-search"><Search /><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder={`Search ${type === 'pantry' ? 'pantry items' : 'recipes'}…`} aria-label="Search foods to try" />{query && <button type="button" onClick={() => setQuery('')} aria-label="Clear search"><X /></button>}</label>
        <ChoiceList type={type} query={query} selectedId={selectedId} onSelect={(id) => { setSelectedId(id); setStockChoice('any'); }} />
        {(selectedProduct || selectedRecipe) && <div className="sandbox-portion"><label className="field"><span>Amount to try</span><div className="portion-input"><button type="button" onClick={() => setServings(String(Math.max(0.25, amount - 0.25)))} aria-label="Decrease amount">−</button><input type="number" min="0.01" step="any" value={servings} onChange={(event) => setServings(event.target.value)} /><button type="button" onClick={() => setServings(String(amount + 0.25))} aria-label="Increase amount">+</button></div><small>{selectedProduct?.servingLabel ?? 'recipe servings'}</small></label></div>}
        {selectedProduct && <LotChoice product={selectedProduct} value={stockChoice} onChange={setStockChoice} />}
      </div>
      <div className="sandbox-impact">
        {!selectedProduct && !selectedRecipe ? <div className="sandbox-placeholder"><FlaskConical /><strong>Pick something to see the tradeoff</strong><small>We’ll compare today as logged + planned with the new amount.</small></div> : <>
          <div className="impact-head"><span>{selectedProduct?.emoji ?? selectedRecipe?.emoji}</span><div><strong>{selectedProduct?.label ?? selectedRecipe?.name}</strong><small>{formatServings(amount)} adds {Math.round(candidate.Calories)} calories{costPerServing === null ? '' : ` · ${usd(costPerServing * amount)}`}</small></div></div>
          <div className="impact-table"><div className="impact-table-head"><span>Nutrient</span><span>Before</span><span>Change</span><span>After</span></div>{(['Calories', 'Protein', 'Carbs', 'Fat', 'Sodium'] as NutrientName[]).map((label) => {
            const after = baseline[label] + candidate[label];
            const unit = label === 'Calories' ? 'cal' : label === 'Sodium' ? 'mg' : 'g';
            const over = (label === 'Calories' || label === 'Sodium') && after > targets[label];
            return <div className={over ? 'over' : ''} key={label}><strong>{label}</strong><span>{formatAmount(baseline[label])}</span><span>+{formatAmount(candidate[label])}</span><span><b>{formatAmount(after)}</b> / {formatAmount(targets[label])} {unit}</span><i style={{ width: `${Math.min(100, after / Math.max(1, targets[label]) * 100)}%` }} /></div>;
          })}</div>
          <div className="sandbox-actions"><button className="button secondary" disabled={!exactLot || !onConsumeLot || saving !== '' || exactLot.remainingServings + 0.0001 < amount} onClick={() => void logNow()} title={!exactLot ? 'Choose one exact lot to log now' : undefined}>{saving === 'log' ? 'Logging…' : 'Log eaten now'}</button><button className="button primary" disabled={!onPlan || saving !== ''} onClick={() => void plan()}><CalendarDays />{saving === 'plan' ? 'Adding…' : 'Add to today'}</button></div>
          {selectedProduct && !exactLot && <small className="sandbox-action-hint">Choose an exact lot above to log immediately, or leave it automatic and add it to today’s plan.</small>}
        </>}
      </div>
    </div>
  </section>;
}
