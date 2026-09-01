import { createClient } from "npm:@supabase/supabase-js@2.112.4";

type Json = Record<string, unknown>;
type Supabase = ReturnType<typeof createClient>;
const headers = {
  "access-control-allow-origin": "https://chatgpt.com",
  "access-control-allow-headers": "authorization, content-type",
  "access-control-allow-methods": "GET, POST, PATCH, OPTIONS",
  "content-type": "application/json; charset=utf-8",
};
class ApiError extends Error { constructor(message: string, readonly status = 422) { super(message); } }
const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers });
const requiredString = (value: unknown, name: string) => {
  if (typeof value !== "string" || !value.trim()) throw new ApiError(`${name} is required`);
  return value.trim();
};
const positiveNumber = (value: unknown, name: string) => {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) throw new ApiError(`${name} must be positive`);
  return parsed;
};
const nonnegativeNumber = (value: unknown, name: string) => {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0) throw new ApiError(`${name} must be nonnegative`);
  return parsed;
};
const requiredArray = (value: unknown, name: string) => {
  if (!Array.isArray(value)) throw new ApiError(`${name} must be an array`);
  return value;
};
const requiredObject = (value: unknown, name: string): Json => {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new ApiError(`${name} must be an object`);
  return value as Json;
};
const requiredText = (value: unknown, name: string) => {
  if (typeof value !== "string") throw new ApiError(`${name} must be a string`);
  return value;
};
const bodyObject = async (request: Request): Promise<Json> => {
  try {
    const value = await request.json();
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error();
    return value as Json;
  } catch { throw new ApiError("Request body must be a JSON object"); }
};
const unwrap = <T>(result: { data: T; error: { message: string } | null }): T => {
  if (result.error) throw new ApiError(result.error.message);
  return result.data;
};

async function tokenMatches(header: string | null, expected: string) {
  const supplied = header?.startsWith("Bearer ") ? header.slice(7) : "";
  const encoder = new TextEncoder();
  const [left, right] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(supplied)),
    crypto.subtle.digest("SHA-256", encoder.encode(expected)),
  ]);
  const a = new Uint8Array(left); const b = new Uint8Array(right);
  let difference = a.length ^ b.length;
  for (let index = 0; index < Math.max(a.length, b.length); index += 1) difference |= (a[index] ?? 0) ^ (b[index] ?? 0);
  return difference === 0 && supplied.length > 0;
}

async function resolveUnitId(db: Supabase, input: unknown) {
  const value = requiredString(input, "unit");
  const all = unwrap(await db.from("measure_conversions").select("id,full_name,short_name")) as Json[];
  const unit = all.find((candidate) => candidate.id === value ||
    [candidate.full_name, candidate.short_name].some((name) => String(name).toLowerCase() === value.toLowerCase()));
  if (!unit) throw new ApiError(`Unknown unit: ${value}`);
  return unit.id;
}

async function foods(db: Supabase, query?: string, id?: string) {
  const [foodResult, productResult, unitResult] = await Promise.all([
    db.from("base_foods").select("*").order("name"),
    db.from("products").select("*").order("name"),
    db.from("measure_conversions").select("*").order("full_name"),
  ]);
  let foodRows = unwrap(foodResult) as Json[];
  const products = unwrap(productResult) as Json[]; const units = unwrap(unitResult) as Json[];
  if (id) foodRows = foodRows.filter((food) => food.id === id);
  if (query) {
    const needle = query.toLowerCase();
    foodRows = foodRows.filter((food) => String(food.name).toLowerCase().includes(needle) ||
      ((food.aliases as string[] | null) ?? []).some((alias) => alias.toLowerCase().includes(needle)));
  }
  return foodRows.map((food) => ({ ...food,
    displayUnit: units.find((unit) => unit.id === food.display_unit),
    products: products.filter((product) => product.food === food.id),
  }));
}

async function inventory(db: Supabase) {
  const [lotResult, productResult, foodResult, unitResult] = await Promise.all([
    db.from("inventory_lots").select("*").gt("remaining_qty", 0).order("use_by"),
    db.from("products").select("*"),
    db.from("base_foods").select("*"), db.from("measure_conversions").select("*"),
  ]);
  const lots = unwrap(lotResult) as Json[]; const products = unwrap(productResult) as Json[];
  const foodRows = unwrap(foodResult) as Json[]; const units = unwrap(unitResult) as Json[];
  return { exportedAt: new Date().toISOString(), lots: lots.map((lot) => {
    const product = products.find((row) => row.id === lot.product);
    const food = foodRows.find((row) => row.id === product?.food);
    const unit = units.find((row) => row.id === food?.display_unit);
    return { lotId: lot.id, productId: product?.id,
      product: product ? [product.brand, product.name].filter(Boolean).join(" · ") : null,
      foodId: food?.id, food: food?.name, quantityBase: Number(lot.remaining_qty), displayUnit: unit?.short_name,
      location: lot.location, bestBy: lot.use_by, acquiredAt: lot.acquired_at, note: lot.note };
  }).filter((row) => row.foodId) };
}

async function recipes(db: Supabase, query?: string, id?: string) {
  const [recipeResult, ingredientResult, foodResult, unitResult] = await Promise.all([
    db.from("recipes").select("*").order("name"), db.from("recipe_ingredients").select("*").order("sort_order"),
    db.from("base_foods").select("id,name"), db.from("measure_conversions").select("id,full_name,short_name"),
  ]);
  let rows = unwrap(recipeResult) as Json[]; const ingredients = unwrap(ingredientResult) as Json[];
  const foodRows = unwrap(foodResult) as Json[]; const units = unwrap(unitResult) as Json[];
  if (id) rows = rows.filter((recipe) => recipe.id === id);
  if (query) rows = rows.filter((recipe) => String(recipe.name).toLowerCase().includes(query.toLowerCase()));
  return rows.map((recipe) => ({ ...recipe, ingredients: ingredients.filter((item) => item.recipe === recipe.id).map((item) => ({
    ...item, food: foodRows.find((food) => food.id === item.ingredient)?.name,
    unit: units.find((unit) => unit.id === item.unit),
  })) }));
}

async function prepared(db: Supabase) {
  const [lotResult, prepResult, recipeResult] = await Promise.all([
    db.from("inventory_lots").select("*").not("prep", "is", null).gt("remaining_qty", 0).order("use_by"),
    db.from("preps").select("*").is("voided_at", null), db.from("recipes").select("id,name,emoji,servings"),
  ]);
  const lots = unwrap(lotResult) as Json[]; const preps = unwrap(prepResult) as Json[]; const recipeRows = unwrap(recipeResult) as Json[];
  return lots.map((lot) => {
    const prep = preps.find((row) => row.id === lot.prep); const recipe = recipeRows.find((row) => row.id === prep?.recipe);
    return { batchId: lot.id, prepId: prep?.id, recipeId: recipe?.id, name: recipe?.name, emoji: recipe?.emoji,
      servingsRemaining: Number(lot.remaining_qty), servingsPrepared: Number(lot.initial_qty), location: lot.location,
      bestBy: lot.use_by, preparedAt: prep?.prepped_at, note: lot.note ?? prep?.note };
  }).filter((row) => row.recipeId);
}

async function planning(db: Supabase) {
  const [planResult, consumptionResult, groceryResult, recipeResult, mealResult] = await Promise.all([
    db.from("meal_plans").select("*").order("plan_date").order("scheduled_time"),
    db.from("planned_consumptions").select("*"),
    db.from("shopping_items").select("*").is("lot", null).order("created_at"),
    db.from("recipes").select("id,name,emoji"), db.from("meals").select("id,name,emoji"),
  ]);
  const recipeRows = unwrap(recipeResult) as Json[]; const meals = unwrap(mealResult) as Json[];
  const consumptions = unwrap(consumptionResult) as Json[];
  return { entries: (unwrap(planResult) as Json[]).map((entry) => ({ ...entry,
    source: entry.recipe ? "recipe" : "meal", sourceId: entry.recipe ?? entry.meal,
    sourceName: entry.recipe ? recipeRows.find((row) => row.id === entry.recipe)?.name : meals.find((row) => row.id === entry.meal)?.name,
    plannedConsumption: consumptions.find((consumption) => consumption.meal_plan === entry.id) ?? null,
  })), groceries: unwrap(groceryResult) };
}

async function history(db: Supabase, days: number) {
  const cutoff = new Date(Date.now() - days * 86_400_000).toISOString();
  const logs = unwrap(await db.from("food_logs").select("*").is("voided_at", null)
    .gte("occurred_at", cutoff).order("occurred_at", { ascending: false })) as Json[];
  if (!logs.length) return { exportedAt: new Date().toISOString(), days, events: [] };
  const logIds = logs.map((log) => String(log.id));
  const inventoryEvents = unwrap(await db.from("inventory_events").select("*").in("food_log", logIds)) as Json[];
  const lotIds = [...new Set(inventoryEvents.map((event) => String(event.lot)))];
  const [lotResult, costResult] = await Promise.all([
    lotIds.length ? db.from("inventory_lots").select("*").in("id", lotIds) : Promise.resolve({ data: [], error: null }),
    lotIds.length ? db.from("inventory_event_costs").select("*").in("inventory_event_id", inventoryEvents.map((event) => String(event.id))) : Promise.resolve({ data: [], error: null }),
  ]);
  const lots = unwrap(lotResult) as Json[];
  const costs = unwrap(costResult) as Json[];
  return { exportedAt: new Date().toISOString(), days, events: logs.map((log) => {
    const deductions = inventoryEvents.filter((event) => event.food_log === log.id).map((event) => ({
      ...event,
      cost: costs.find((cost) => cost.inventory_event_id === event.id)?.cost ?? null,
      lot: lots.find((lot) => lot.id === event.lot) ?? null,
    }));
    const cost = deductions.length > 0 && deductions.every((event) => event.cost !== null)
      ? deductions.reduce((total, event) => total + Number(event.cost), 0)
      : null;
    return { ...log, cost, inventoryEvents: deductions };
  }) };
}

async function saveFood(db: Supabase, input: Json) {
  const nutrition = (input.nutrition as Json | undefined) ?? {};
  let id = typeof input.id === "string" ? input.id : undefined;
  if (!id) {
    const existing = await db.from("base_foods").select("id").ilike("name", requiredString(input.name, "name")).maybeSingle();
    if (!existing.error && existing.data) id = existing.data.id;
  }
  const row = { ...(id ? { id } : {}), name: requiredString(input.name, "name"), plural: input.plural ?? null,
    measure_style: requiredString(input.measureStyle, "measureStyle"), emoji: input.emoji ?? null,
    grocery_category: input.groceryCategory ?? null, display_unit: await resolveUnitId(db, input.displayUnit),
    g_per_fl_oz: input.gPerFlOz == null ? null : positiveNumber(input.gPerFlOz, "gPerFlOz"),
    g_per_count: input.gPerCount == null ? null : positiveNumber(input.gPerCount, "gPerCount"),
    ingredient_role: input.ingredientRole ?? null, store_aisle: input.storeAisle ?? null,
    aliases: Array.isArray(input.aliases) ? input.aliases : [], nutrition_basis_qty: Number(nutrition.basisQuantity ?? 100),
    kcal: Number(nutrition.calories ?? 0), protein_g: Number(nutrition.proteinG ?? 0), carbs_g: Number(nutrition.carbsG ?? 0),
    fat_g: Number(nutrition.fatG ?? 0), fiber_g: Number(nutrition.fiberG ?? 0), sugar_g: Number(nutrition.sugarG ?? 0),
    sodium_mg: Number(nutrition.sodiumMg ?? 0), nutrition_source: nutrition.source ?? null,
    nutrition_is_estimated: Boolean(nutrition.estimated) };
  const result = await db.from("base_foods").upsert(row).select("id").single();
  return { status: "saved", id: unwrap(result).id };
}

async function saveProduct(db: Supabase, input: Json) {
  const nutrition = (input.nutrition as Json | undefined) ?? {};
  const foodId = requiredString(input.foodId, "foodId");
  const packageUnit = await resolveUnitId(db, input.packageUnit);
  const packageQuantity = positiveNumber(input.packageQuantity, "packageQuantity");
  const packageBase = unwrap(await db.rpc("to_base_quantity", { p_food: foodId, p_amount: packageQuantity, p_unit: packageUnit }));
  const servingBase = input.servingQuantity == null ? null : unwrap(await db.rpc("to_base_quantity", {
    p_food: foodId, p_amount: positiveNumber(input.servingQuantity, "servingQuantity"), p_unit: packageUnit,
  }));
  const row = { ...(typeof input.id === "string" ? { id: input.id } : {}), food: foodId,
    name: requiredString(input.name, "name"), brand: input.brand ?? null, aliases: Array.isArray(input.aliases) ? input.aliases : [],
    barcode: input.barcode ?? null, package_qty_base: packageBase, package_unit: packageUnit, serving_qty_base: servingBase,
    nutrition_basis_qty: Number(nutrition.basisQuantity ?? 1), kcal: Number(nutrition.calories ?? 0),
    protein_g: Number(nutrition.proteinG ?? 0), carbs_g: Number(nutrition.carbsG ?? 0), fat_g: Number(nutrition.fatG ?? 0),
    fiber_g: Number(nutrition.fiberG ?? 0), sugar_g: Number(nutrition.sugarG ?? 0), sodium_mg: Number(nutrition.sodiumMg ?? 0),
    nutrition_source: nutrition.source ?? null, nutrition_is_estimated: Boolean(nutrition.estimated) };
  const result = await db.from("products").upsert(row).select("id").single();
  return { status: "saved", id: unwrap(result).id };
}

async function route(request: Request, db: Supabase) {
  const url = new URL(request.url); const marker = "/pantry-api"; const offset = url.pathname.indexOf(marker);
  const path = (offset >= 0 ? url.pathname.slice(offset + marker.length) : url.pathname).replace(/\/$/, "") || "/";
  const method = request.method;
  if (method === "GET" && path === "/v1/inventory") return reply(await inventory(db));
  if (method === "POST" && path === "/v1/inventory") { const input = await bodyObject(request);
    return reply(unwrap(await db.rpc("gpt_reconcile_inventory", {
      p_replacements: requiredArray(input.replacements, "replacements"), p_source: input.source ?? null,
    }))); }
  if (method === "GET" && path === "/v1/foods") return reply({ foods: await foods(db, url.searchParams.get("q") ?? undefined) });
  if (method === "GET" && path.startsWith("/v1/foods/")) { const rows = await foods(db, undefined, decodeURIComponent(path.slice(10)));
    if (!rows.length) throw new ApiError("Food does not exist", 404); return reply({ food: rows[0] }); }
  if (method === "POST" && path === "/v1/foods") return reply(await saveFood(db, await bodyObject(request)));
  if (method === "PATCH" && path.startsWith("/v1/foods/")) return reply(unwrap(await db.rpc("gpt_update_food", {
    p_food: decodeURIComponent(path.slice(10)), p_patch: await bodyObject(request),
  })));
  if (method === "POST" && path === "/v1/products") return reply(await saveProduct(db, await bodyObject(request)));
  if (method === "PATCH" && path.startsWith("/v1/products/")) return reply(unwrap(await db.rpc("gpt_update_product", {
    p_product: decodeURIComponent(path.slice(13)), p_patch: await bodyObject(request),
  })));
  if (method === "POST" && path === "/v1/groceries") { const input = await bodyObject(request);
    return reply(unwrap(await db.rpc("gpt_add_grocery_lots", {
      p_items: requiredArray(input.items, "items"), p_source: input.source ?? null,
    })), 201); }
  if (method === "GET" && path === "/v1/recipes") return reply({ recipes: await recipes(db, url.searchParams.get("q") ?? undefined) });
  if (method === "GET" && path.startsWith("/v1/recipes/")) { const rows = await recipes(db, undefined, decodeURIComponent(path.slice(12)));
    if (!rows.length) throw new ApiError("Recipe does not exist", 404); return reply({ recipe: rows[0] }); }
  if (method === "POST" && path === "/v1/recipes") return reply(unwrap(await db.rpc("gpt_save_recipe", { p_recipe: await bodyObject(request) })));
  if (method === "PATCH" && path.startsWith("/v1/recipes/")) return reply(unwrap(await db.rpc("gpt_update_recipe", {
    p_recipe: decodeURIComponent(path.slice(12)), p_patch: await bodyObject(request),
  })));
  if (method === "PATCH" && path.startsWith("/v1/lots/")) return reply(unwrap(await db.rpc("gpt_update_inventory_lot", {
    p_lot: decodeURIComponent(path.slice(9)), p_patch: await bodyObject(request),
  })));
  if (method === "POST" && path === "/v1/consume/product") { const input = await bodyObject(request);
    return reply(unwrap(await db.rpc("consume_product_purchase", {
      p_product: requiredString(input.productId, "productId"),
      p_purchased_quantity: positiveNumber(input.purchasedQuantity, "purchasedQuantity"),
      p_consumed_quantity: nonnegativeNumber(input.consumedQuantity, "consumedQuantity"),
      p_location: input.location ?? null,
      p_occurred_at: input.timestamp ?? new Date().toISOString(),
      p_total_cost: input.totalCost ?? null,
      p_cost_is_estimated: Boolean(input.costIsEstimated),
      p_cost_source: input.costSource ?? null,
      p_label: input.label ?? null,
      p_note: input.note ?? null,
    })), 201); }
  if (method === "POST" && path === "/v1/consume/manual") { const input = await bodyObject(request);
    if (input.nutrition !== undefined && input.nutrition !== null && (typeof input.nutrition !== "object" || Array.isArray(input.nutrition))) {
      throw new ApiError("nutrition must be an object or null");
    }
    return reply(unwrap(await db.rpc("log_manual_consumption", {
      p_label: requiredString(input.label, "label"),
      p_portion_label: input.portionLabel ?? null,
      p_occurred_at: input.timestamp ?? new Date().toISOString(),
      p_nutrition: input.nutrition ?? null,
      p_cost: input.cost === undefined || input.cost === null ? null : nonnegativeNumber(input.cost, "cost"),
      p_cost_is_estimated: Boolean(input.costIsEstimated),
      p_cost_source: input.costSource ?? null,
      p_note: input.note ?? null,
    })), 201); }
  if (method === "POST" && path === "/v1/prepare/recipe") { const input = await bodyObject(request);
    return reply(unwrap(await db.rpc("gpt_prepare_recipe", { p_recipe: requiredString(input.recipeId, "recipeId"),
      p_servings: positiveNumber(input.servings, "servings"), p_location: input.location ?? "fridge",
      p_use_by: input.bestBy ?? null, p_note: input.note ?? null })), 201); }
  if (method === "GET" && path === "/v1/prepared-batches") return reply({ batches: await prepared(db) });
  if (method === "POST" && path === "/v1/consume/prepared") { const input = await bodyObject(request);
    return reply(unwrap(await db.rpc("gpt_consume_prepared", { p_lot: requiredString(input.batchId, "batchId"),
      p_quantity: positiveNumber(input.servings, "servings"), p_occurred_at: input.timestamp ?? new Date().toISOString(),
      p_label: input.label ?? null, p_note: input.note ?? null })), 201); }
  if (method === "POST" && path === "/v1/consume/inventory") { const input = await bodyObject(request);
    return reply(unwrap(await db.rpc("gpt_consume_inventory", { p_food: requiredString(input.foodId, "foodId"),
      p_quantity: positiveNumber(input.quantity, "quantity"), p_unit: requiredString(input.unit, "unit"),
      p_occurred_at: input.timestamp ?? new Date().toISOString(), p_label: input.label ?? null, p_note: input.note ?? null })), 201); }
  if (method === "GET" && path === "/v1/history") { const days = Math.min(365, Math.max(1, Number(url.searchParams.get("days") ?? 30)));
    return reply(await history(db, days)); }
  if (method === "PATCH" && path.startsWith("/v1/history/")) return reply(unwrap(await db.rpc("gpt_update_consumption", {
    p_food_log: decodeURIComponent(path.slice(12)), p_patch: await bodyObject(request),
  })));
  if (method === "GET" && path === "/v1/plans") return reply(await planning(db));
  if (method === "POST" && path === "/v1/plans") { const input = await bodyObject(request);
    return reply(unwrap(await db.rpc("gpt_replace_weekly_plan", {
      p_week_start: requiredString(input.weekStart, "weekStart"), p_entries: requiredArray(input.entries, "entries"),
    }))); }
  if (method === "POST" && path === "/v1/grocery-items") { const input = await bodyObject(request);
    const result = await db.from("shopping_items").insert({ free_text: requiredString(input.name, "name"),
      quantity_label: input.quantityLabel ?? null, source: "manual", note: input.note ?? null }).select("id").single();
    return reply({ status: "created", id: unwrap(result).id }, 201); }
  if (method === "GET" && ["/v1/targets", "/v1/preferences", "/v1/routine"].includes(path)) {
    const settings = unwrap(await db.from("personal_settings").select("*").eq("singleton", true).single()) as Json;
    if (path === "/v1/targets") return reply({ calories: settings.nutrition_calories, proteinG: settings.nutrition_protein_g,
      carbsG: settings.nutrition_carbs_g, fatG: settings.nutrition_fat_g, fiberG: settings.nutrition_fiber_g,
      sodiumMg: settings.nutrition_sodium_mg, label: settings.nutrition_label });
    if (path === "/v1/preferences") return reply({ allergies: settings.allergies, dislikes: settings.dislikes,
      favorites: settings.favorites, dietaryRules: settings.dietary_rules, planningNotes: settings.planning_notes });
    return reply({ timeZone: settings.time_zone, days: settings.routine_days,
      dinnerWindow: { start: settings.dinner_start, end: settings.dinner_end }, commuteMinutes: settings.commute_minutes,
      preparationBufferMinutes: settings.preparation_buffer_minutes, defaultThawHours: settings.default_thaw_hours,
      notes: settings.routine_notes });
  }
  if (method === "POST" && ["/v1/targets", "/v1/preferences", "/v1/routine"].includes(path)) {
    const input = await bodyObject(request);
    const update = path === "/v1/targets" ? { nutrition_calories: positiveNumber(input.calories, "calories"), nutrition_protein_g: nonnegativeNumber(input.proteinG, "proteinG"),
      nutrition_carbs_g: nonnegativeNumber(input.carbsG, "carbsG"), nutrition_fat_g: nonnegativeNumber(input.fatG, "fatG"), nutrition_fiber_g: nonnegativeNumber(input.fiberG, "fiberG"),
      nutrition_sodium_mg: nonnegativeNumber(input.sodiumMg, "sodiumMg"), nutrition_label: input.label ?? null }
      : path === "/v1/preferences" ? { allergies: requiredArray(input.allergies, "allergies"), dislikes: requiredArray(input.dislikes, "dislikes"), favorites: requiredArray(input.favorites, "favorites"),
        dietary_rules: requiredArray(input.dietaryRules, "dietaryRules"), planning_notes: requiredText(input.planningNotes, "planningNotes") }
      : { time_zone: requiredString(input.timeZone, "timeZone"), routine_days: requiredObject(input.days, "days"),
        dinner_start: requiredString(requiredObject(input.dinnerWindow, "dinnerWindow").start, "dinnerWindow.start"),
        dinner_end: requiredString(requiredObject(input.dinnerWindow, "dinnerWindow").end, "dinnerWindow.end"),
        commute_minutes: nonnegativeNumber(input.commuteMinutes, "commuteMinutes"), preparation_buffer_minutes: nonnegativeNumber(input.preparationBufferMinutes, "preparationBufferMinutes"),
        default_thaw_hours: input.defaultThawHours ?? 24, routine_notes: input.notes ?? null };
    unwrap(await db.from("personal_settings").update(update).eq("singleton", true)); return reply({ status: "saved" });
  }
  throw new ApiError("Route does not exist", 404);
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers });
  const token = Deno.env.get("PANTRY_API_TOKEN") ?? "";
  if (!token || !(await tokenMatches(request.headers.get("authorization"), token))) return reply({ error: "Unauthorized" }, 401);
  try {
    const url = Deno.env.get("SUPABASE_URL"); const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !serviceKey) throw new Error("Supabase function environment is incomplete");
    return await route(request, createClient(url, serviceKey, { auth: { persistSession: false } }));
  } catch (error) {
    const status = error instanceof ApiError ? error.status : 500;
    const message = error instanceof Error ? error.message : "Unexpected error";
    console.error(JSON.stringify({ status, message })); return reply({ error: message }, status);
  }
});
