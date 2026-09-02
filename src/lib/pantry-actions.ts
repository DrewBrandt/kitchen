import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '../database.types';
import type { PanelKind } from '../data';

type Client = SupabaseClient<Database>;

const text = (form: FormData, key: string) => String(form.get(key) ?? '').trim();
const optionalText = (form: FormData, key: string) => text(form, key) || null;
const number = (form: FormData, key: string, fallback?: number) => {
  const raw = text(form, key);
  if (!raw && fallback !== undefined) return fallback;
  const parsed = Number(raw);
  if (!Number.isFinite(parsed)) throw new Error(`${key.replaceAll('_', ' ')} must be a number.`);
  return parsed;
};
const optionalNumber = (form: FormData, key: string) => text(form, key) ? number(form, key) : null;
const list = (form: FormData, key: string) => text(form, key).split(',').map((item) => item.trim()).filter(Boolean);

async function createProductAndFood(client: Client, form: FormData) {
  const name = text(form, 'name');
  const unit = text(form, 'unit');
  if (!name || !unit) throw new Error('Name and stock unit are required.');

  const { data: food, error: foodError } = await client.from('base_foods').insert({
    name,
    plural: optionalText(form, 'plural'),
    emoji: optionalText(form, 'emoji'),
    measure_style: text(form, 'measure_style') as Database['public']['Enums']['measure_style'],
    display_unit: unit,
    grocery_category: optionalText(form, 'grocery_category'),
    ingredient_role: optionalText(form, 'ingredient_role'),
    always_available: form.get('always_available') === 'on',
    nutrition_basis_qty: number(form, 'nutrition_basis_qty', 100),
    kcal: number(form, 'kcal', 0),
    protein_g: number(form, 'protein_g', 0),
    carbs_g: number(form, 'carbs_g', 0),
    fat_g: number(form, 'fat_g', 0),
    fiber_g: number(form, 'fiber_g', 0),
    sodium_mg: number(form, 'sodium_mg', 0),
    nutrition_is_estimated: form.get('nutrition_is_estimated') === 'on',
  }).select('id').single();
  if (foodError) throw foodError;

  const { error: productError } = await client.from('products').insert({
    food: food.id,
    name,
    brand: optionalText(form, 'brand'),
    barcode: optionalText(form, 'barcode'),
    package_qty_base: number(form, 'package_qty_base', 1),
    package_unit: unit,
    serving_qty_base: number(form, 'serving_qty_base', 1),
    nutrition_basis_qty: number(form, 'nutrition_basis_qty', 100),
    kcal: number(form, 'kcal', 0),
    protein_g: number(form, 'protein_g', 0),
    carbs_g: number(form, 'carbs_g', 0),
    fat_g: number(form, 'fat_g', 0),
    fiber_g: number(form, 'fiber_g', 0),
    sodium_mg: number(form, 'sodium_mg', 0),
    nutrition_is_estimated: form.get('nutrition_is_estimated') === 'on',
    emoji: optionalText(form, 'emoji'),
    estimated_cost: optionalNumber(form, 'estimated_cost'),
    cost_source: optionalText(form, 'cost_source'),
    cost_as_of: optionalText(form, 'cost_as_of'),
  });
  if (productError) {
    await client.from('base_foods').delete().eq('id', food.id);
    throw productError;
  }
}

async function saveRecipe(client: Client, form: FormData) {
  const name = text(form, 'name');
  const recipeId = optionalText(form, 'recipe_id');
  if (!name) throw new Error('Recipe name is required.');

  const { data: foods, error: foodsError } = await client.from('base_foods').select('id,name');
  const { data: units, error: unitsError } = await client.from('measure_conversions').select('id,full_name,short_name');
  if (foodsError) throw foodsError;
  if (unitsError) throw unitsError;

  const ingredients = text(form, 'ingredients').split(/\r?\n/).map((line) => line.trim()).filter(Boolean).map((line, index) => {
    const match = line.match(/^([0-9]*\.?[0-9]+)\s+(\S+)\s+(.+)$/);
    if (!match) throw new Error(`Ingredient line ${index + 1} must look like “1.5 cup All-purpose flour”.`);
    const [, quantity, unitName, foodName] = match;
    const unit = units?.find((candidate) => [candidate.short_name, candidate.full_name].some((value) => value.toLowerCase() === unitName.toLowerCase()));
    const food = foods?.find((candidate) => candidate.name.toLowerCase() === foodName.toLowerCase());
    if (!unit) throw new Error(`Unknown unit “${unitName}” on ingredient line ${index + 1}.`);
    if (!food) throw new Error(`Unknown food “${foodName}” on ingredient line ${index + 1}. Define it first.`);
    return { ingredient: food.id, qty: Number(quantity), unit: unit.id, sort_order: index };
  });

  const steps = text(form, 'instructions').split(/\r?\n/).map((step) => step.trim()).filter(Boolean);
  const recipeValues = {
    name,
    emoji: optionalText(form, 'emoji'),
    servings: number(form, 'servings', 1),
    instructions: steps,
    source_url: optionalText(form, 'source_url'),
    prompt_for_feedback: form.get('prompt_for_feedback') === 'on',
  };
  const recipeResult = recipeId
    ? await client.from('recipes').update(recipeValues).eq('id', recipeId).select('id').single()
    : await client.from('recipes').insert(recipeValues).select('id').single();
  const { data: recipe, error: recipeError } = recipeResult;
  if (recipeError) throw recipeError;

  if (recipeId) {
    const { error } = await client.from('recipe_ingredients').delete().eq('recipe', recipeId);
    if (error) throw error;
  }

  if (ingredients.length) {
    const { error } = await client.from('recipe_ingredients').insert(ingredients.map((ingredient) => ({ ...ingredient, recipe: recipe.id })));
    if (error) {
      if (!recipeId) await client.from('recipes').delete().eq('id', recipe.id);
      throw error;
    }
  }
}

export async function savePanelAction(client: Client, kind: PanelKind, form: FormData): Promise<string> {
  if (kind === 'scan') {
    const barcode = text(form, 'barcode');
    const { data, error } = await client.from('products').select('name,brand').eq('barcode', barcode).maybeSingle();
    if (error) throw error;
    if (!data) throw new Error(`No saved product has barcode ${barcode}.`);
    return `Found ${[data.brand, data.name].filter(Boolean).join(' · ')}.`;
  }

  if (kind === 'lot') {
    const acquiredAt = optionalText(form, 'acquired_at') ? new Date(text(form, 'acquired_at')).toISOString() : new Date().toISOString();
    const { error } = await client.rpc('gpt_add_grocery_lots', {
      p_items: [{
        productId: text(form, 'product'),
        quantity: number(form, 'initial_qty'),
        unit: text(form, 'quantity_unit'),
        totalPrice: number(form, 'total_cost'),
        outOfPocketCost: number(form, 'out_of_pocket_cost'),
        paidBy: text(form, 'paid_by'),
        costIsEstimated: form.get('cost_is_estimated') === 'on',
        priceAsOf: text(form, 'price_as_of'),
        acquiredAt,
        acquiredTimePrecision: text(form, 'time_precision'),
        ...(optionalText(form, 'location') ? { location: optionalText(form, 'location') } : {}),
        ...(optionalText(form, 'use_by') ? { bestBy: optionalText(form, 'use_by') } : {}),
        ...(optionalText(form, 'note') ? { note: optionalText(form, 'note') } : {}),
      }],
      p_source: text(form, 'cost_source'),
      p_request_id: crypto.randomUUID(),
    });
    if (error) throw error;
    return 'Lot added.';
  }

  if (kind === 'product') {
    await createProductAndFood(client, form);
    return 'Food and product created.';
  }

  if (kind === 'recipe' || kind === 'recipe-edit') {
    await saveRecipe(client, form);
    return kind === 'recipe-edit' ? 'Recipe updated.' : 'Recipe saved.';
  }

  if (kind === 'item') {
    const { error } = await client.from('shopping_items').insert({
      free_text: text(form, 'name'),
      quantity_label: optionalText(form, 'quantity_label'),
      source: 'manual',
      note: optionalText(form, 'note'),
    });
    if (error) throw error;
    return 'Grocery item added.';
  }

  if (kind === 'groceries') {
    const rows = text(form, 'groceries').split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
    if (!rows.length) throw new Error('Enter at least one grocery item.');
    const { error } = await client.from('shopping_items').insert(rows.map((line) => ({ free_text: line, source: 'manual' as const })));
    if (error) throw error;
    return `${rows.length} grocery item${rows.length === 1 ? '' : 's'} added.`;
  }

  if (kind === 'log') {
    const occurredAt = optionalText(form, 'occurred_at') ? new Date(text(form, 'occurred_at')).toISOString() : new Date().toISOString();
    const totalPrice = number(form, 'total_cost');
    const { error } = await client.rpc('consume_product_purchase', {
      p_product: text(form, 'product'),
      p_purchased_quantity: number(form, 'purchased_quantity', 1),
      p_consumed_quantity: number(form, 'consumed_quantity', 1),
      p_quantity_unit: text(form, 'quantity_unit'),
      p_acquisition_type: text(form, 'acquisition_type'),
      p_total_price: totalPrice as number,
      p_out_of_pocket_cost: number(form, 'out_of_pocket_cost'),
      p_paid_by: text(form, 'paid_by'),
      p_price_as_of: text(form, 'price_as_of'),
      p_request_id: crypto.randomUUID(),
      ...(optionalText(form, 'location') ? { p_location: optionalText(form, 'location')! } : {}),
      p_occurred_at: occurredAt,
      p_time_precision: text(form, 'time_precision'),
      p_cost_is_estimated: form.get('cost_is_estimated') === 'on',
      p_cost_source: text(form, 'cost_source'),
      ...(optionalText(form, 'label') ? { p_label: optionalText(form, 'label')! } : {}),
      ...(optionalText(form, 'note') ? { p_note: optionalText(form, 'note')! } : {}),
    });
    if (error) throw error;
    return 'Purchase recorded and consumed portion logged.';
  }

  if (kind === 'manual-log') {
    const occurredAt = optionalText(form, 'occurred_at') ? new Date(text(form, 'occurred_at')).toISOString() : new Date().toISOString();
    const nutritionFields = {
      calories: optionalNumber(form, 'kcal'),
      proteinG: optionalNumber(form, 'protein_g'),
      carbsG: optionalNumber(form, 'carbs_g'),
      fatG: optionalNumber(form, 'fat_g'),
      fiberG: optionalNumber(form, 'fiber_g'),
      sugarG: optionalNumber(form, 'sugar_g'),
      sodiumMg: optionalNumber(form, 'sodium_mg'),
    };
    const nutrition = Object.fromEntries(Object.entries(nutritionFields).filter(([, value]) => value !== null)) as Record<string, number | boolean | string>;
    const nutritionSource = optionalText(form, 'nutrition_source');
    if (Object.keys(nutrition).length || nutritionSource || form.get('nutrition_is_estimated') === 'on') {
      nutrition.estimated = form.get('nutrition_is_estimated') === 'on';
      if (nutritionSource) nutrition.source = nutritionSource;
    }
    const totalPrice = optionalNumber(form, 'total_price');
    const portionLabel = optionalText(form, 'portion_label');
    const components = text(form, 'components').split(/\r?\n/).map((line) => line.trim()).filter(Boolean)
      .map((label) => ({ label }));
    const nutritionEstimated = form.get('nutrition_is_estimated') === 'on';
    const nutritionEstimate = nutritionEstimated ? {
      confidence: text(form, 'nutrition_confidence') || 'medium',
      rationale: optionalText(form, 'nutrition_rationale') ?? nutritionSource ?? optionalText(form, 'note') ?? 'User marked this nutrition as estimated.',
    } : null;
    const { error } = await client.rpc('log_manual_consumption', {
      p_label: text(form, 'label'),
      p_portion_label: portionLabel ?? '',
      p_occurred_at: occurredAt,
      p_time_precision: text(form, 'time_precision'),
      p_nutrition: Object.keys(nutrition).length ? nutrition : null,
      p_nutrition_estimate: nutritionEstimate,
      p_components: components.length ? components : [{ label: text(form, 'label'), ...(portionLabel ? { portionLabel } : {}) }],
      p_acquisition_type: text(form, 'acquisition_type'),
      p_total_price: totalPrice as number,
      p_out_of_pocket_cost: number(form, 'out_of_pocket_cost'),
      p_paid_by: text(form, 'paid_by'),
      p_cost_is_estimated: form.get('cost_is_estimated') === 'on',
      p_cost_source: text(form, 'cost_source'),
      p_price_as_of: (totalPrice === null ? null : text(form, 'price_as_of')) as string,
      p_request_id: crypto.randomUUID(),
      ...(optionalText(form, 'note') ? { p_note: optionalText(form, 'note')! } : {}),
    });
    if (error) throw error;
    return 'Food logged without changing inventory.';
  }

  if (kind === 'meal') {
    const intent = text(form, 'intent') || 'prepare';
    const groupId = crypto.randomUUID();
    const plannedServings = number(form, 'planned_servings', 1);
    if (plannedServings <= 0) throw new Error('Planned servings must be positive.');
    if (intent === 'leftover') {
      const sourceGroupId = text(form, 'source_group_id');
      if (!sourceGroupId) throw new Error('Choose the meal that will provide the leftovers.');
      let { data: sourceRows, error: sourceError } = await client.from('meal_plans').select('*').eq('group_id', sourceGroupId);
      if (sourceError) throw sourceError;
      if (!sourceRows?.length) {
        const fallback = await client.from('meal_plans').select('*').eq('id', sourceGroupId);
        sourceRows = fallback.data;
        sourceError = fallback.error;
      }
      if (sourceError) throw sourceError;
      if (!sourceRows?.length) throw new Error('The original meal could not be found.');
      const { data: insertedPlans, error } = await client.from('meal_plans').insert(sourceRows.map((row) => ({
        plan_date: text(form, 'plan_date'),
        daypart: text(form, 'daypart') as Database['public']['Enums']['daypart'],
        meal: row.meal,
        recipe: row.recipe,
        scale_factor: row.scale_factor,
        status: 'planned' as const,
        name: row.name,
        emoji: row.emoji,
        group_id: groupId,
        leftover_of_group_id: sourceGroupId,
        intent: 'leftover',
        preparation_tasks: [],
        note: optionalText(form, 'note'),
      }))).select('id');
      if (error) throw error;
      const { error: consumptionError } = await client.from('planned_consumptions').update({ servings: plannedServings }).in('meal_plan', (insertedPlans ?? []).map((plan) => plan.id));
      if (consumptionError) throw consumptionError;
      return 'Leftovers added to the plan.';
    }
    if (!text(form, 'recipe')) throw new Error('Choose a recipe for the meal.');
    const { data: insertedPlan, error } = await client.from('meal_plans').insert({
      recipe: text(form, 'recipe'),
      plan_date: text(form, 'plan_date'),
      daypart: text(form, 'daypart') as Database['public']['Enums']['daypart'],
      scale_factor: number(form, 'scale_factor', 1),
      status: 'planned',
      group_id: groupId,
      intent: 'prepare',
      note: optionalText(form, 'note'),
    }).select('id').single();
    if (error) throw error;
    const { error: consumptionError } = await client.from('planned_consumptions').update({ servings: plannedServings }).eq('meal_plan', insertedPlan.id);
    if (consumptionError) throw consumptionError;
    return 'Meal added to the plan.';
  }

  if (kind === 'targets') {
    const { error } = await client.from('personal_settings').update({
      nutrition_calories: number(form, 'nutrition_calories'),
      nutrition_protein_g: number(form, 'nutrition_protein_g'),
      nutrition_carbs_g: number(form, 'nutrition_carbs_g'),
      nutrition_fat_g: number(form, 'nutrition_fat_g'),
      nutrition_fiber_g: number(form, 'nutrition_fiber_g'),
      nutrition_sodium_mg: number(form, 'nutrition_sodium_mg'),
      weekly_food_budget: number(form, 'weekly_food_budget'),
    }).eq('singleton', true);
    if (error) throw error;
    return 'Targets and food budget updated.';
  }

  if (kind === 'profile') {
    const timeZone = text(form, 'time_zone');
    try { new Intl.DateTimeFormat('en-US', { timeZone }).format(); }
    catch { throw new Error('Time zone must be a valid IANA name such as America/New_York.'); }
    const { error } = await client.from('personal_settings').update({
      allergies: list(form, 'allergies'),
      dietary_rules: list(form, 'dietary_rules'),
      dislikes: list(form, 'dislikes'),
      favorites: list(form, 'favorites'),
      time_zone: timeZone,
      planning_notes: optionalText(form, 'planning_notes'),
    }).eq('singleton', true);
    if (error) throw error;
    return 'Profile updated.';
  }

  throw new Error(`${kind} is not a database form yet.`);
}
