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
const list = (form: FormData, key: string) => text(form, key).split(',').map((item) => item.trim()).filter(Boolean);

async function createProductAndFood(client: Client, form: FormData, external: boolean) {
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
    is_external: external,
  });
  if (productError) {
    await client.from('base_foods').delete().eq('id', food.id);
    throw productError;
  }
}

async function createRecipe(client: Client, form: FormData) {
  const name = text(form, 'name');
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
  const { data: recipe, error: recipeError } = await client.from('recipes').insert({
    name,
    emoji: optionalText(form, 'emoji'),
    servings: number(form, 'servings', 1),
    instructions: steps,
    source_url: optionalText(form, 'source_url'),
    prompt_for_feedback: form.get('prompt_for_feedback') === 'on',
  }).select('id').single();
  if (recipeError) throw recipeError;

  if (ingredients.length) {
    const { error } = await client.from('recipe_ingredients').insert(ingredients.map((ingredient) => ({ ...ingredient, recipe: recipe.id })));
    if (error) {
      await client.from('recipes').delete().eq('id', recipe.id);
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
    const { error } = await client.from('inventory_lots').insert({
      product: text(form, 'product'),
      initial_qty: number(form, 'initial_qty'),
      remaining_qty: number(form, 'initial_qty'),
      total_cost: number(form, 'total_cost', 0),
      cost_is_estimated: form.get('cost_is_estimated') === 'on',
      location: optionalText(form, 'location'),
      use_by: optionalText(form, 'use_by'),
      note: optionalText(form, 'note'),
    });
    if (error) throw error;
    return 'Lot added.';
  }

  if (kind === 'food') {
    await createProductAndFood(client, form, false);
    return 'Food and product created.';
  }

  if (kind === 'external') {
    await createProductAndFood(client, form, true);
    return 'Eating-out product saved.';
  }

  if (kind === 'recipe') {
    await createRecipe(client, form);
    return 'Recipe saved.';
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
    const { error } = await client.from('food_logs').insert({
      label: text(form, 'label'),
      kind: 'custom',
      servings: number(form, 'servings', 1),
      occurred_at: optionalText(form, 'occurred_at') ? new Date(text(form, 'occurred_at')).toISOString() : new Date().toISOString(),
      kcal: number(form, 'kcal', 0),
      protein_g: number(form, 'protein_g', 0),
      carbs_g: number(form, 'carbs_g', 0),
      fat_g: number(form, 'fat_g', 0),
      fiber_g: number(form, 'fiber_g', 0),
      sodium_mg: number(form, 'sodium_mg', 0),
      nutrition_is_estimated: form.get('nutrition_is_estimated') === 'on',
      note: optionalText(form, 'note'),
    });
    if (error) throw error;
    return 'Food logged.';
  }

  if (kind === 'meal') {
    const { error } = await client.from('meal_plans').insert({
      recipe: text(form, 'recipe'),
      plan_date: text(form, 'plan_date'),
      daypart: text(form, 'daypart') as Database['public']['Enums']['daypart'],
      scale_factor: number(form, 'scale_factor', 1),
      status: 'planned',
      note: optionalText(form, 'note'),
    });
    if (error) throw error;
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
    }).eq('singleton', true);
    if (error) throw error;
    return 'Nutrition targets updated.';
  }

  if (kind === 'profile') {
    const { error } = await client.from('personal_settings').update({
      allergies: list(form, 'allergies'),
      dietary_rules: list(form, 'dietary_rules'),
      dislikes: list(form, 'dislikes'),
      favorites: list(form, 'favorites'),
      time_zone: text(form, 'time_zone'),
      planning_notes: optionalText(form, 'planning_notes'),
    }).eq('singleton', true);
    if (error) throw error;
    return 'Profile updated.';
  }

  throw new Error(`${kind} is not a database form yet.`);
}
