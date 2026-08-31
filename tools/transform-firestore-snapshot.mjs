import crypto from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';

const namespace = '36f07576-8b2e-5bce-a73f-a54c9055f71c';
const estimatesPath = new URL('./firebase-migration-estimates.json', import.meta.url);
const baseFoodGrammar = new Map([
  ['pork-loin', ['Boneless pork loin', 'Boneless pork loins']],
  ['signature-chicken-thighs', ['Boneless skinless chicken thigh', 'Boneless skinless chicken thighs']],
  ['mission-burrito-tortillas', ['Burrito-size flour tortilla', 'Burrito-size flour tortillas']],
  ['carrots', ['Carrot', 'Carrots']],
  ['external:chick-fil-a-chicken-biscuit', ['Chicken Biscuit', 'Chicken Biscuits']],
  ['egg', ['Egg', 'Eggs']],
  ['bubba-burger', ['Frozen beef burger patty', 'Frozen beef burger patties']],
  ['tyson-chicken-twists', ['Frozen breaded chicken twist', 'Frozen breaded chicken twists']],
  ['burger-bun', ['Hamburger bun', 'Hamburger buns']],
  ['hillshire-honey-ham', ['Honey ham slice', 'Honey ham slices']],
  ['sargento-medium-cheddar', ['Medium cheddar slice', 'Medium cheddar slices']],
  ['ny-strip-steak', ['New York strip steak', 'New York strip steaks']],
  ['onion', ['Onion', 'Onions']],
  ['pepperidge-plain-bagels', ['Plain bagel', 'Plain bagels']],
  ['pork-tenderloin', ['Pork tenderloin', 'Pork tenderloins']],
  ['ritz-crackers', ['Round butter cracker', 'Round butter crackers']],
  ['russet-potatoes', ['Russet potato', 'Russet potatoes']],
  ['semisweet-chocolate-chips', ['Semisweet chocolate chip', 'Semisweet chocolate chips']],
  ['unidentified-steak', ['Unidentified steak (identify/weigh later)', 'Unidentified steaks (identify/weigh later)']],
]);

function grammarFor(sourceId, fallbackName) {
  const [name, plural = null] = baseFoodGrammar.get(sourceId) ?? [fallbackName];
  return { name, plural };
}

function argument(name) {
  const index = process.argv.indexOf(name);
  if (index < 0 || !process.argv[index + 1]) throw new Error(`Missing ${name}`);
  return path.resolve(process.argv[index + 1]);
}

function uuidBytes(uuid) {
  return Buffer.from(uuid.replaceAll('-', ''), 'hex');
}

function uuidFor(type, sourceId) {
  const hash = crypto
    .createHash('sha1')
    .update(uuidBytes(namespace))
    .update(`${type}:${sourceId}`)
    .digest()
    .subarray(0, 16);
  hash[6] = (hash[6] & 0x0f) | 0x50;
  hash[8] = (hash[8] & 0x3f) | 0x80;
  const hex = hash.toString('hex');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function sql(value) {
  if (value === null || value === undefined) return 'null';
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) throw new Error(`Invalid number ${value}`);
    return String(value);
  }
  if (typeof value === 'boolean') return value ? 'true' : 'false';
  return `'${String(value).replaceAll("'", "''")}'`;
}

function json(value) {
  return `${sql(JSON.stringify(value ?? null))}::jsonb`;
}

function textArray(values) {
  return `array[${(values ?? []).map(sql).join(', ')}]::text[]`;
}

function unit(shortName) {
  return `(select id from public.measure_conversions where short_name = ${sql(shortName)})`;
}

function insert(table, columns, rows) {
  if (rows.length === 0) return '';
  return `insert into public.${table} (${columns.join(', ')}) values\n${rows
    .map((row) => `  (${row.join(', ')})`)
    .join(',\n')};\n`;
}

function styleFor(food) {
  if (food.base_unit === 'gram') return 'weight';
  if (food.base_unit === 'milliliter' || food.base_unit === 'cup') return 'volume';
  return 'discrete';
}

function baseUnitFor(food) {
  return styleFor(food) === 'weight' ? 'g' : styleFor(food) === 'volume' ? 'fl oz' : 'ct';
}

function canonicalFactor(food) {
  if (food.base_unit === 'milliliter') return 1 / 29.5735295625;
  if (food.base_unit === 'cup') return 8;
  return 1;
}

function canonicalQuantity(food, legacyBaseQuantity) {
  return Number(legacyBaseQuantity) * canonicalFactor(food);
}

function normalizedBaseQuantity(food, amount, legacyUnit) {
  const conversion = (food.conversions ?? []).find(
    (item) => item.unit.toLowerCase() === legacyUnit.toLowerCase(),
  );
  if (!conversion) {
    throw new Error(`No ${legacyUnit} conversion for ${food.id}`);
  }
  const legacyBase = Number(amount) * Number(conversion.base_amount);
  return canonicalQuantity(food, legacyBase);
}

const categoryMap = {
  produceDeli: 'Produce & deli meats',
  seafoodBreadInternational: 'Seafood, bread & international',
  bakingMeat: 'Baking & fresh meats',
  snacksDrinks: 'Snacks, chips & sports drinks',
  seasonalCards: 'Seasonal & cards',
  householdPets: 'Laundry, cleaning & pets',
  dairyFrozenDinner: 'Dairy & frozen dinners',
  frozenTreats: 'Frozen foods & treats',
  eggsYogurtCheese: 'Eggs, yogurt, cheese & dough',
  deliBakeryDessert: 'Deli, bakery & desserts',
};

function categoryFor(food) {
  return categoryMap[food.grocery_section] ?? 'Pantry & other';
}

function nutritionFor(food, estimates) {
  const legacy = food.nutrition;
  if (legacy) {
    return {
      basis: legacy.basis_base_amount,
      kcal: legacy.calories,
      protein_g: legacy.protein_g,
      carbs_g: legacy.carbs_g,
      fat_g: legacy.fat_g,
      fiber_g: legacy.fiber_g,
      sugar_g: legacy.sugar_g,
      sodium_mg: legacy.sodium_mg,
      source: legacy.source || 'Migrated Firebase nutrition',
      estimated: Boolean(legacy.estimated),
    };
  }
  const estimate = estimates.nutrition[food.id];
  if (!estimate) throw new Error(`Missing nutrition estimate for ${food.id}`);
  return { ...estimate, estimated: true };
}

function timestampDate(value) {
  return value ? value.slice(0, 10) : null;
}

async function main() {
  const input = argument('--input');
  const output = argument('--output');
  const rollback = process.argv.includes('--rollback');
  const replace = process.argv.includes('--replace');
  const snapshot = JSON.parse(await readFile(input, 'utf8'));
  const estimates = JSON.parse(await readFile(estimatesPath, 'utf8'));
  const c = snapshot.collections;
  const foodsById = new Map(c.foods.map((food) => [food.id, food]));
  const productsById = new Map(c.products.map((product) => [product.id, product]));
  const lotsById = new Map(c.inventory_lots.map((lot) => [lot.id, lot]));
  const activeDeductions = c.consumption_history
    .filter((event) => !event.undone_at)
    .flatMap((event) => event.deductions ?? []);

  const initialQuantity = new Map(
    c.inventory_lots.map((lot) => [
      lot.id,
      Number(lot.quantity_base) +
        activeDeductions
          .filter((deduction) => deduction.lot_id === lot.id)
          .reduce((sum, deduction) => sum + Number(deduction.quantity_base), 0),
    ]),
  );

  const genericFoodIds = new Set(
    c.inventory_lots.filter((lot) => !lot.product_id).map((lot) => lot.food_id),
  );
  const externalFoodIds = new Set(c.external_foods.map((food) => food.id));
  for (const id of externalFoodIds) {
    if (foodsById.has(id)) throw new Error(`External food ID collides with food ${id}`);
  }

  const preparedFoodKey = (batch) =>
    c.foods.find((food) => food.name.toLowerCase() === batch.name.toLowerCase())?.id ??
    `prepared-${batch.id}`;
  const preparedFoods = c.prepared_batches
    .filter((batch) => preparedFoodKey(batch).startsWith('prepared-'))
    .map((batch) => ({
      id: preparedFoodKey(batch),
      name: batch.name,
      emoji: batch.emoji,
      nutrition: batch.nutrition_per_serving,
    }));

  const baseFoodRows = [];
  for (const food of c.foods) {
    const nutrition = nutritionFor(food, estimates);
    const grammar = grammarFor(food.id, food.name);
    baseFoodRows.push([
      sql(uuidFor('food', food.id)), sql(grammar.name), sql(grammar.plural), sql(styleFor(food)),
      sql(food.emoji), sql(categoryFor(food)), unit(baseUnitFor(food)), 'null',
      styleFor(food) === 'discrete' && food.id === 'unidentified-steak' ? '340.194' : 'null',
      sql(canonicalQuantity(food, nutrition.basis)), sql(nutrition.kcal), sql(nutrition.protein_g),
      sql(nutrition.carbs_g), sql(nutrition.fat_g), sql(nutrition.fiber_g),
      sql(nutrition.sugar_g), sql(nutrition.sodium_mg), textArray(food.aliases),
      sql(food.ingredient_role), sql(food.store_aisle), sql(nutrition.source),
      sql(nutrition.estimated), sql(food.id), sql(food.createTime), sql(food.updateTime),
    ]);
  }
  for (const food of c.external_foods) {
    const n = food.nutrition ?? {};
    const sourceId = `external:${food.id}`;
    const grammar = grammarFor(sourceId, food.name);
    baseFoodRows.push([
      sql(uuidFor('food', sourceId)), sql(grammar.name), sql(grammar.plural), sql('discrete'),
      sql(food.emoji), sql('Pantry & other'), unit('ct'), 'null', 'null', '1',
      sql(n.calories), sql(n.protein_g), sql(n.carbs_g), sql(n.fat_g), sql(n.fiber_g),
      sql(n.sugar_g), sql(n.sodium_mg), textArray([]), 'null', 'null', sql(food.source),
      sql(Boolean(food.estimated)), sql(`external:${food.id}`), sql(food.createTime), sql(food.updateTime),
    ]);
  }
  for (const food of preparedFoods) {
    const n = food.nutrition ?? {};
    const grammar = grammarFor(food.id, food.name);
    baseFoodRows.push([
      sql(uuidFor('food', food.id)), sql(grammar.name), sql(grammar.plural), sql('discrete'), sql(food.emoji),
      sql('Pantry & other'), unit('ct'), 'null', 'null', '1', sql(n.calories),
      sql(n.protein_g), sql(n.carbs_g), sql(n.fat_g), sql(n.fiber_g), sql(n.sugar_g),
      sql(n.sodium_mg), textArray([]), 'null', 'null', sql('Migrated prepared-batch snapshot'),
      'true', sql(food.id), sql(snapshot.exportedAt), sql(snapshot.exportedAt),
    ]);
  }

  const productRows = [];
  for (const product of c.products) {
    const food = foodsById.get(product.food_id);
    if (!food) throw new Error(`Product ${product.id} has unknown food ${product.food_id}`);
    const relatedLots = c.inventory_lots.filter((lot) => lot.product_id === product.id);
    const inferredPackage = Math.max(
      0,
      ...(product.conversions ?? []).map((item) => Number(item.base_amount)),
      ...relatedLots.map((lot) => initialQuantity.get(lot.id)),
      Number(product.nutrition?.basis_base_amount ?? 0),
    );
    const packageQtyLegacy = estimates.packageCosts[product.id]?.[1] ?? inferredPackage;
    if (!(packageQtyLegacy > 0)) throw new Error(`Cannot infer package quantity for ${product.id}`);
    const packageQty = canonicalQuantity(food, packageQtyLegacy);
    const n = product.nutrition;
    productRows.push([
      sql(uuidFor('product', product.id)), sql(uuidFor('food', product.food_id)), sql(product.barcode),
      sql(product.name), sql(product.brand), sql(packageQty), unit(baseUnitFor(food)),
      sql(n ? canonicalQuantity(food, n.basis_base_amount) : null),
      sql(n ? canonicalQuantity(food, n.basis_base_amount) : null), sql(n?.calories), sql(n?.protein_g),
      sql(n?.carbs_g), sql(n?.fat_g), sql(n?.fiber_g), sql(n?.sugar_g), sql(n?.sodium_mg),
      sql(food.emoji), 'false', 'null', '0', textArray(product.aliases), sql(n?.source),
      sql(Boolean(n?.estimated)), sql(product.id), sql(product.createTime), sql(product.updateTime),
    ]);
  }
  for (const foodId of genericFoodIds) {
    const food = foodsById.get(foodId);
    const qty = Math.max(...c.inventory_lots.filter((lot) => !lot.product_id && lot.food_id === foodId).map((lot) => initialQuantity.get(lot.id)));
    productRows.push([
      sql(uuidFor('product', `generic:${foodId}`)), sql(uuidFor('food', foodId)), 'null',
      sql(`${food.name} (legacy unbranded)`), 'null', sql(canonicalQuantity(food, qty)), unit(baseUnitFor(food)),
      'null', 'null', 'null', 'null', 'null', 'null', 'null', 'null', 'null', sql(food.emoji),
      'false', 'null', '0', textArray([]), 'null', 'false', sql(`generic:${foodId}`),
      sql(snapshot.exportedAt), sql(snapshot.exportedAt),
    ]);
  }
  for (const food of c.external_foods) {
    productRows.push([
      sql(uuidFor('product', `external:${food.id}`)), sql(uuidFor('food', `external:${food.id}`)),
      sql(food.barcode), sql(food.name), sql(food.brand), '1', unit('ct'), '1', '1',
      sql(food.nutrition?.calories), sql(food.nutrition?.protein_g), sql(food.nutrition?.carbs_g),
      sql(food.nutrition?.fat_g), sql(food.nutrition?.fiber_g), sql(food.nutrition?.sugar_g),
      sql(food.nutrition?.sodium_mg), sql(food.emoji), 'true', 'null', '0', textArray([]),
      sql(food.source), sql(Boolean(food.estimated)), sql(`external:${food.id}`),
      sql(food.createTime), sql(food.updateTime),
    ]);
  }
  for (const batch of c.prepared_batches) {
    productRows.push([
      sql(uuidFor('product', `prepared:${batch.id}`)), sql(uuidFor('food', preparedFoodKey(batch))),
      'null', sql(batch.name), sql('Prepared food'), '1', unit('ct'), '1', '1',
      sql(batch.nutrition_per_serving?.calories), sql(batch.nutrition_per_serving?.protein_g),
      sql(batch.nutrition_per_serving?.carbs_g), sql(batch.nutrition_per_serving?.fat_g),
      sql(batch.nutrition_per_serving?.fiber_g), sql(batch.nutrition_per_serving?.sugar_g),
      sql(batch.nutrition_per_serving?.sodium_mg), sql(batch.emoji), 'false', 'null', '0',
      textArray([]), sql('Migrated prepared-batch snapshot'), 'true',
      sql(`prepared:${batch.id}`), sql(batch.createTime), sql(batch.updateTime),
    ]);
  }

  const recipeRows = c.recipes.map((recipe) => [
    sql(uuidFor('recipe', recipe.id)), sql(recipe.name), sql(recipe.emoji), sql(recipe.servings),
    'null', 'null', json(recipe.instructions ?? []), 'null', 'null', 'null', 'null', 'null',
    'null', 'null', 'null', json(recipe.portions ?? []), json(recipe.preparation_rules ?? []),
    sql(recipe.source_url), sql(recipe.source_note), sql(recipe.prompt_for_feedback ?? true),
    sql(recipe.id), sql(recipe.createTime), sql(recipe.updateTime),
  ]);
  const ingredientRows = [];
  for (const recipe of c.recipes) {
    for (const [index, ingredient] of (recipe.ingredients ?? []).entries()) {
      const food = foodsById.get(ingredient.food_id);
      if (!food) throw new Error(`Recipe ${recipe.id} has unknown food ${ingredient.food_id}`);
      ingredientRows.push([
        sql(uuidFor('recipe-ingredient', `${recipe.id}:${index}`)), sql(uuidFor('recipe', recipe.id)),
        sql(uuidFor('food', ingredient.food_id)), 'null',
        sql(normalizedBaseQuantity(food, ingredient.amount, ingredient.unit)),
        unit(baseUnitFor(food)), sql(index), 'null',
      ]);
    }
  }

  const foodLogRows = c.consumption_history.map((event) => {
    const n = event.nutrition ?? {};
    const externalProduct = event.external_food_id
      ? uuidFor('product', `external:${event.external_food_id}`)
      : null;
    return [
      sql(uuidFor('food-log', event.id)), sql(event.label), sql(event.kind ?? 'custom'),
      sql(event.recipe_id ? uuidFor('recipe', event.recipe_id) : null), sql(externalProduct),
      sql(event.servings), sql(event.timestamp), sql(event.undone_at), sql(n.calories),
      sql(n.protein_g), sql(n.carbs_g), sql(n.fat_g), sql(n.fiber_g), sql(n.sugar_g),
      sql(n.sodium_mg), sql(Boolean(event.nutrition_estimated)), sql(event.note),
      sql(event.id), sql(event.createTime),
    ];
  });

  const lotRows = [];
  for (const lot of c.inventory_lots) {
    const productKey = lot.product_id ?? `generic:${lot.food_id}`;
    const price = lot.product_id
      ? estimates.packageCosts[lot.product_id]
      : [estimates.genericCosts[lot.food_id], 1];
    if (!price || !(price[0] >= 0) || !(price[1] > 0)) {
      throw new Error(`Missing cost estimate for lot ${lot.id} (${productKey})`);
    }
    const legacyQty = initialQuantity.get(lot.id);
    const qty = canonicalQuantity(foodsById.get(lot.food_id), legacyQty);
    const cost = Math.round((legacyQty * price[0] / price[1]) * 100) / 100;
    lotRows.push([
      sql(uuidFor('lot', lot.id)), sql(uuidFor('product', productKey)), 'null', sql(qty),
      sql(qty), sql(cost), sql(timestampDate(lot.best_by)), sql(lot.location),
      sql(lot.purchased_at ?? lot.createTime), sql('Migrated from Firebase inventory snapshot'),
      sql(lot.createTime), 'true', sql(estimates.costSource), sql(lot.id),
    ]);
  }
  for (const batch of c.prepared_batches) {
    lotRows.push([
      sql(uuidFor('lot', `prepared:${batch.id}`)), sql(uuidFor('product', `prepared:${batch.id}`)),
      'null', sql(batch.total_servings), sql(batch.total_servings), sql(6.99 * batch.total_servings),
      sql(timestampDate(batch.best_by)), sql(batch.location), sql(batch.made_at), sql(batch.note),
      sql(batch.createTime), 'true', sql(estimates.costSource), sql(`prepared:${batch.id}`),
    ]);
  }

  const eventRows = [];
  const skippedDeductions = [];
  for (const event of c.consumption_history) {
    for (const [index, deduction] of (event.deductions ?? []).entries()) {
      if (!lotsById.has(deduction.lot_id)) {
        skippedDeductions.push(`${event.id}:${deduction.lot_id}`);
        continue;
      }
      eventRows.push([
        sql(uuidFor('inventory-event', `${event.id}:${index}`)), sql(uuidFor('lot', deduction.lot_id)),
        sql(-canonicalQuantity(foodsById.get(deduction.food_id), deduction.quantity_base)),
        sql('eaten'), 'null', 'null', sql(event.timestamp),
        sql(event.undone_at), sql(event.note), sql(event.createTime), sql(uuidFor('food-log', event.id)),
      ]);
    }
  }

  const planRows = c.meal_plan.map((plan) => [
    sql(uuidFor('meal-plan', plan.id)), sql(timestampDate(plan.date)), sql(plan.slot), sql(plan.scheduled_time),
    'null', sql(plan.source_id ? uuidFor('recipe', plan.source_id) : null), sql(plan.servings ?? 1),
    sql('planned'), 'null', sql(plan.note), sql(plan.createTime), sql(plan.updateTime), sql(plan.name),
    sql(plan.emoji), sql(plan.group_id), sql(plan.leftover_of_group_id), sql(plan.intent ?? 'prepare'),
    json(plan.preparation_tasks ?? []), sql(plan.id),
  ]);

  const shoppingRows = c.grocery_list.map((item) => {
    const food = item.food_id ? foodsById.get(item.food_id) : null;
    return [
      sql(uuidFor('shopping', item.id)), sql(item.food_id ? uuidFor('food', item.food_id) : null),
      'null', sql(item.food_id ? null : item.name), sql(item.quantity_base),
      food ? unit(baseUnitFor(food)) : 'null', sql(item.from_plan ? 'generated' : 'manual'),
      sql(item.checked ? item.updateTime : null), 'null', sql(item.name), sql(item.createTime),
      sql(timestampDate(item.first_needed_date)), sql(item.quantity_label), sql(item.id),
    ];
  });

  const settings = Object.fromEntries(c.settings.map((item) => [item.id, item]));
  const nutrition = settings.nutrition ?? {};
  const profile = settings.food_profile ?? {};
  const routine = settings.personal_routine ?? {};
  const calendar = settings.calendar_sync ?? {};
  const lotExpectations = [
    ...c.inventory_lots.map((lot) => [
      lot.id,
      canonicalQuantity(foodsById.get(lot.food_id), lot.quantity_base),
    ]),
    ...c.prepared_batches.map((batch) => [
      `prepared:${batch.id}`,
      Number(batch.remaining_servings),
    ]),
  ];
  const activeNutrition = c.consumption_history
    .filter((event) => !event.undone_at)
    .reduce(
      (total, event) => {
        const n = event.nutrition ?? {};
        for (const key of Object.keys(total)) total[key] += Number(n[key] ?? 0);
        return total;
      },
      { calories: 0, protein_g: 0, carbs_g: 0, fat_g: 0, fiber_g: 0, sugar_g: 0, sodium_mg: 0 },
    );
  const expectedLotsSql = lotExpectations
    .map(([id, quantity]) => `(${sql(id)}, ${sql(quantity)}::numeric)`)
    .join(', ');

  const replaceSql = replace
    ? [
        'delete from public.inventory_events where food_log in (select id from public.food_logs where legacy_firebase_id is not null);',
        'delete from public.shopping_items where legacy_firebase_id is not null;',
        'delete from public.meal_plans where legacy_firebase_id is not null;',
        'delete from public.inventory_lots where legacy_firebase_id is not null;',
        'delete from public.food_logs where legacy_firebase_id is not null;',
        'delete from public.recipes where legacy_firebase_id is not null;',
        'delete from public.products where legacy_firebase_id is not null;',
        'delete from public.base_foods where legacy_firebase_id is not null;',
      ].join('\n') + '\n'
    : '';
  const statements = [
    'begin;\nset constraints all deferred;\n',
    replaceSql,
    insert('base_foods', ['id','name','plural','measure_style','emoji','grocery_category','display_unit','g_per_fl_oz','g_per_count','nutrition_basis_qty','kcal','protein_g','carbs_g','fat_g','fiber_g','sugar_g','sodium_mg','aliases','ingredient_role','store_aisle','nutrition_source','nutrition_is_estimated','legacy_firebase_id','created_at','updated_at'], baseFoodRows),
    insert('products', ['id','food','barcode','name','brand','package_qty_base','package_unit','serving_qty_base','nutrition_basis_qty','kcal','protein_g','carbs_g','fat_g','fiber_g','sugar_g','sodium_mg','emoji','is_external','last_used_at','use_count','aliases','nutrition_source','nutrition_is_estimated','legacy_firebase_id','created_at','updated_at'], productRows),
    insert('recipes', ['id','name','emoji','servings','output_food','yield_qty','instructions','override_basis_qty','override_kcal','override_protein_g','override_carbs_g','override_fat_g','override_fiber_g','override_sodium_mg','override_sugar_g','portions','preparation_rules','source_url','source_note','prompt_for_feedback','legacy_firebase_id','created_at','updated_at'], recipeRows),
    insert('recipe_ingredients', ['id','recipe','ingredient','pinned_product','qty','unit','sort_order','note'], ingredientRows),
    insert('food_logs', ['id','label','kind','recipe','product','servings','occurred_at','voided_at','kcal','protein_g','carbs_g','fat_g','fiber_g','sugar_g','sodium_mg','nutrition_is_estimated','note','legacy_firebase_id','created_at'], foodLogRows),
    insert('inventory_lots', ['id','product','prep','initial_qty','remaining_qty','total_cost','use_by','location','acquired_at','note','created_at','cost_is_estimated','cost_source','legacy_firebase_id'], lotRows),
    insert('inventory_events', ['id','lot','quantity_delta','reason','prep','cook_session','occurred_at','voided_at','note','created_at','food_log'], eventRows),
    insert('meal_plans', ['id','plan_date','daypart','scheduled_time','meal','recipe','scale_factor','status','cook_session','note','created_at','updated_at','name','emoji','group_id','leftover_of_group_id','intent','preparation_tasks','legacy_firebase_id'], planRows),
    insert('shopping_items', ['id','food','pinned_product','free_text','qty_needed','unit','source','checked_at','lot','note','created_at','first_needed_date','quantity_label','legacy_firebase_id'], shoppingRows),
    `update public.app_settings set time_zone = ${sql(routine.time_zone ?? 'America/New_York')} where singleton;\n`,
    `update public.personal_settings set\n  nutrition_calories = ${sql(nutrition.calories ?? 2000)},\n  nutrition_protein_g = ${sql(nutrition.protein_g ?? 50)},\n  nutrition_carbs_g = ${sql(nutrition.carbs_g ?? 275)},\n  nutrition_fat_g = ${sql(nutrition.fat_g ?? 78)},\n  nutrition_fiber_g = ${sql(nutrition.fiber_g ?? 28)},\n  nutrition_sodium_mg = ${sql(nutrition.sodium_mg ?? 2300)},\n  nutrition_label = ${sql(nutrition.label)},\n  allergies = ${textArray(profile.allergies)},\n  dislikes = ${textArray(profile.dislikes)},\n  favorites = ${textArray(profile.favorites)},\n  dietary_rules = ${textArray(profile.dietary_rules)},\n  planning_notes = ${sql(profile.planning_notes)},\n  time_zone = ${sql(routine.time_zone ?? 'America/New_York')},\n  routine_days = ${json(routine.days ?? {})},\n  dinner_start = ${sql(routine.dinner_window?.start ?? '18:00')},\n  dinner_end = ${sql(routine.dinner_window?.end ?? '20:30')},\n  commute_minutes = ${sql(routine.commute_minutes ?? 0)},\n  preparation_buffer_minutes = ${sql(routine.preparation_buffer_minutes ?? 30)},\n  default_thaw_hours = ${sql(routine.default_thaw_hours ?? 24)},\n  routine_notes = ${sql(routine.notes)},\n  calendar_settings = ${json(calendar)}\nwhere singleton;\n`,
    `do $$\nbegin\n  if (select count(*) from public.base_foods where legacy_firebase_id is not null) <> ${baseFoodRows.length} then raise exception 'base food count mismatch'; end if;\n  if (select count(*) from public.products where legacy_firebase_id is not null) <> ${productRows.length} then raise exception 'product count mismatch'; end if;\n  if (select count(*) from public.recipes where legacy_firebase_id is not null) <> ${recipeRows.length} then raise exception 'recipe count mismatch'; end if;\n  if (select count(*) from public.recipe_ingredients) <> ${ingredientRows.length} then raise exception 'recipe ingredient count mismatch'; end if;\n  if (select count(*) from public.food_logs where legacy_firebase_id is not null) <> ${foodLogRows.length} then raise exception 'food log count mismatch'; end if;\n  if (select count(*) from public.inventory_lots where legacy_firebase_id is not null) <> ${lotRows.length} then raise exception 'lot count mismatch'; end if;\n  if (select count(*) from public.meal_plans where legacy_firebase_id is not null) <> ${planRows.length} then raise exception 'meal-plan count mismatch'; end if;\n  if (select count(*) from public.shopping_items where legacy_firebase_id is not null) <> ${shoppingRows.length} then raise exception 'shopping count mismatch'; end if;\n  if exists (\n    select 1\n    from (values ${expectedLotsSql}) expected(legacy_id, remaining_qty)\n    left join public.inventory_lots lot on lot.legacy_firebase_id = expected.legacy_id\n    where lot.id is null or abs(lot.remaining_qty - expected.remaining_qty) > 0.000001\n  ) then raise exception 'inventory remaining quantity mismatch'; end if;\n  if exists (select 1 from public.inventory_lots where legacy_firebase_id is not null and total_cost is null) then raise exception 'migrated lot missing cost'; end if;\n  if abs((select coalesce(sum(kcal), 0) from public.food_logs where voided_at is null) - ${activeNutrition.calories}) > 0.001 then raise exception 'food-log calorie mismatch'; end if;\n  if abs((select coalesce(sum(protein_g), 0) from public.food_logs where voided_at is null) - ${activeNutrition.protein_g}) > 0.001 then raise exception 'food-log protein mismatch'; end if;\n  if abs((select coalesce(sum(carbs_g), 0) from public.food_logs where voided_at is null) - ${activeNutrition.carbs_g}) > 0.001 then raise exception 'food-log carbs mismatch'; end if;\n  if abs((select coalesce(sum(fat_g), 0) from public.food_logs where voided_at is null) - ${activeNutrition.fat_g}) > 0.001 then raise exception 'food-log fat mismatch'; end if;\n  if abs((select coalesce(sum(fiber_g), 0) from public.food_logs where voided_at is null) - ${activeNutrition.fiber_g}) > 0.001 then raise exception 'food-log fiber mismatch'; end if;\n  if abs((select coalesce(sum(sugar_g), 0) from public.food_logs where voided_at is null) - ${activeNutrition.sugar_g}) > 0.001 then raise exception 'food-log sugar mismatch'; end if;\n  if abs((select coalesce(sum(sodium_mg), 0) from public.food_logs where voided_at is null) - ${activeNutrition.sodium_mg}) > 0.001 then raise exception 'food-log sodium mismatch'; end if;\nend $$;\n`,
    rollback ? 'rollback;\n' : 'commit;\n',
  ];
  await writeFile(output, statements.join('\n'), { encoding: 'utf8', flag: 'wx' });
  console.log(JSON.stringify({
    baseFoods: baseFoodRows.length,
    products: productRows.length,
    recipes: recipeRows.length,
    recipeIngredients: ingredientRows.length,
    foodLogs: foodLogRows.length,
    lots: lotRows.length,
    inventoryEvents: eventRows.length,
    mealPlans: planRows.length,
    shoppingItems: shoppingRows.length,
    transaction: rollback ? 'rollback' : 'commit',
    replace,
    skippedOrphanDeductions: skippedDeductions,
  }, null, 2));
  console.log(`SQL written to ${output}`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.stack : String(error));
  process.exitCode = 1;
});
