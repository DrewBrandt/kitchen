import type { StagedDish } from './lib/cooking-stage';
import { useEffect, useState } from 'react';
import { X } from 'lucide-react';
import type { PanelKind } from './data';
import { usePantryData, type NutritionValues } from './pantry-data';
import { ImpactStrip, recipePerServing } from './PlanComposer';
import { formatServings } from './lib/format';
import { completeCost } from './lib/cost';
import { isDefiniteMutationFailure, mutationError, pendingMutationPayload } from './lib/mutation-feedback';
import { mealBuilderIdentity, mealBuilderOperation, type GroupedPlanPayload } from './lib/pantry-actions';

type Dish = { recipe: string; make: string; eat: string };
export function CombinedMealPanel({ onClose, onStage, onSave, notify }: {
  onClose: () => void; onStage: (dishes: StagedDish[]) => void;
  onSave?: (kind: PanelKind, form: FormData) => Promise<string>; notify: (message: string) => void;
}) {
  const { recipes, settings } = usePantryData();
  const [dishes, setDishes] = useState<Dish[]>([]);
  const [date, setDate] = useState(() => new Intl.DateTimeFormat('en-CA', { timeZone: settings.timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date()));
  const [daypart, setDaypart] = useState('dinner');
  const [choosing, setChoosing] = useState(true);
  const [pending, setPending] = useState<GroupedPlanPayload>();
  const [loaded, setLoaded] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  useEffect(() => {
    let active = true;
    void pendingMutationPayload<GroupedPlanPayload>(mealBuilderOperation, mealBuilderIdentity).then((saved) => {
      if (!active) return;
      if (saved) {
        setPending(saved); setDate(saved.plan_date); setDaypart(saved.daypart); setChoosing(false);
        setDishes(saved.dishes.map((dish) => ({ recipe: dish.recipe, make: String(dish.scale_factor * (recipes.find((recipe) => recipe.id === dish.recipe)?.servings ?? 1)), eat: String(dish.planned_servings) })));
      }
      setLoaded(true);
    }).catch((cause) => { if (active) setError(mutationError(cause)); });
    return () => { active = false; };
  }, []);
  const locked = saving || Boolean(pending) || !loaded;
  const valid = dishes.length > 0 && Boolean(date) && dishes.every((dish) => recipes.some((recipe) => recipe.id === dish.recipe) && Number.isFinite(Number(dish.make)) && Number(dish.make) > 0 && Number.isFinite(Number(dish.eat)) && Number(dish.eat) > 0);
  const nutrition = dishes.reduce<NutritionValues>((total, dish) => {
    const recipe = recipes.find((item) => item.id === dish.recipe);
    if (recipe) for (const [key, value] of Object.entries(recipePerServing(recipe))) total[key as keyof NutritionValues] += value * (Number(dish.eat) || 0);
    return total;
  }, { Calories: 0, Protein: 0, Carbs: 0, Fat: 0, Fiber: 0, Sodium: 0 });
  const cost = completeCost(dishes.map((dish) => { const recipe = recipes.find((item) => item.id === dish.recipe); return recipe?.costPerServing == null ? null : recipe.costPerServing * (Number(dish.eat) || 0); }));
  function update(index: number, key: 'make' | 'eat', value: string) { setDishes((current) => current.map((dish, i) => i === index ? { ...dish, [key]: value } : dish)); }
  async function save() {
    if (!onSave || saving || !loaded || (!pending && !valid)) return;
    const payload = pending ?? { plan_date: date, daypart, dishes: dishes.map((dish) => ({ recipe: dish.recipe, scale_factor: Number(dish.make) / recipes.find((recipe) => recipe.id === dish.recipe)!.servings, planned_servings: Number(dish.eat) })) };
    setPending(payload); setSaving(true); setError('');
    const form = new FormData(); form.set('plan_date', payload.plan_date); form.set('daypart', payload.daypart); form.set('dishes', JSON.stringify(payload.dishes));
    try { const message = await onSave('meal', form); setPending(undefined); notify(message); onClose(); }
    catch (cause) { if (isDefiniteMutationFailure(cause)) setPending(undefined); setError(mutationError(cause)); }
    finally { setSaving(false); }
  }
  return <div className="panel-layer"><button className="panel-scrim" onClick={onClose} aria-label="Close panel" /><aside className="action-panel" role="dialog" aria-modal="true" aria-label="Build a meal">
    <div className="panel-header"><h2>Build a meal</h2><button type="button" className="icon-button" aria-label="Close panel" onClick={onClose}><X /></button></div>
    <div className="panel-body">
      {dishes.map((dish, index) => <div className="meal-dish-row" key={dish.recipe}>
        <strong>{recipes.find((recipe) => recipe.id === dish.recipe)?.name ?? 'Recipe unavailable'}</strong>
        <div className="form-grid two">
          <label className="field"><span>Make</span><input aria-label={`Make servings of ${recipes.find((recipe) => recipe.id === dish.recipe)?.name}`} type="number" min="0.01" step="any" value={dish.make} disabled={locked} onChange={(event) => update(index, 'make', event.target.value)} /></label>
          <label className="field"><span>Eat</span><input aria-label={`Eat servings of ${recipes.find((recipe) => recipe.id === dish.recipe)?.name}`} type="number" min="0.01" step="any" value={dish.eat} disabled={locked} onChange={(event) => update(index, 'eat', event.target.value)} /></label>
        </div>
        <button type="button" className="text-button" disabled={locked} onClick={() => setDishes((current) => current.filter((_, i) => i !== index))}>Remove {recipes.find((recipe) => recipe.id === dish.recipe)?.name}</button>
      </div>)}
      <button type="button" className="button secondary" disabled={locked} aria-expanded={choosing} onClick={() => setChoosing((value) => !value)}>Add dish</button>
      {choosing && recipes.filter((recipe) => !dishes.some((dish) => dish.recipe === recipe.id)).map((recipe) => <button type="button" disabled={locked} className="meal-recipe-choice" key={recipe.id} onClick={() => setDishes((current) => [...current, { recipe: recipe.id, make: String(recipe.servings), eat: '1' }])}>
        <span className="check-box" aria-hidden="true" /><span><strong>{recipe.emoji} {recipe.name}</strong><small>{formatServings(recipe.servings)} per batch</small></span>
      </button>)}
      <div className="form-grid two">
        <label className="field"><span>Date</span><input type="date" value={date} disabled={locked} onChange={(event) => setDate(event.target.value)} /></label>
        <label className="field"><span>Time of day</span><select value={daypart} disabled={locked} onChange={(event) => setDaypart(event.target.value)}>{['breakfast', 'brunch', 'lunch', 'dinner', 'snack', 'dessert'].map((value) => <option key={value} value={value}>{value[0].toUpperCase() + value.slice(1)}</option>)}</select></label>
      </div>
      {dishes.length > 0 && <ImpactStrip nutrition={nutrition} cost={cost} estimated={dishes.some((dish) => recipes.find((recipe) => recipe.id === dish.recipe)?.costIsEstimated)} />}
      {error && <p role="alert">{error}</p>}
    </div>
    <div className="panel-footer"><button className="button secondary" disabled={locked || !valid || dishes.some((dish) => Number(dish.eat) > Number(dish.make))} onClick={() => onStage(dishes.map((dish) => ({ recipeId: dish.recipe, servingsMade: Number(dish.make), servingsEaten: Number(dish.eat) })))}>Add to On deck</button><button className="button primary" disabled={saving || !loaded || !onSave || (!pending && !valid)} onClick={() => void save()}>{saving ? 'Saving…' : pending ? 'Retry meal' : 'Plan meal'}</button></div>
  </aside></div>;
}
