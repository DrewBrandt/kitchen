import { timingSafeEqual } from "node:crypto";
import { initializeApp } from "firebase-admin/app";
import { FieldValue, Timestamp, getFirestore } from "firebase-admin/firestore";
import { defineSecret } from "firebase-functions/params";
import { onRequest } from "firebase-functions/v2/https";

initializeApp();

const db = getFirestore();
const pantryApiToken = defineSecret("PANTRY_API_TOKEN");

type JsonObject = Record<string, unknown>;
type ApiResponse = {
  status(code: number): ApiResponse;
  json(body: unknown): void;
};
type Conversion = { unit: string; symbol: string; baseAmount: number };
type FoodRecord = {
  id: string;
  name: string;
  quantityMode: "counted" | "measured";
  baseUnit: string;
  defaultLocation: "pantry" | "fridge" | "freezer";
  emoji: string;
  conversions: Conversion[];
  displayUnit?: string;
  nutrition?: JsonObject;
  aliases: string[];
};
type ProductRecord = {
  id: string;
  foodId: string;
  name: string;
  brand: string;
  aliases: string[];
  barcode?: string;
  conversions: Conversion[];
  nutrition?: JsonObject;
};

export const pantryApi = onRequest(
  {
    region: "us-east4",
    secrets: [pantryApiToken],
    invoker: "public",
    timeoutSeconds: 60,
    maxInstances: 1,
  },
  async (request, response) => {
    response.set("Content-Type", "application/json");
    if (request.method === "OPTIONS") {
      response.status(204).send("");
      return;
    }
    if (!authorized(request.get("authorization"), pantryApiToken.value())) {
      response.status(401).json({ error: "Unauthorized" });
      return;
    }

    try {
      const path = request.path.replace(/\/$/, "");
      if (request.method === "GET" && path === "/v1/inventory") {
        await exportInventory(response);
        return;
      }
      if (request.method === "GET" && path === "/v1/history") {
        await exportHistory(request.query.days, response);
        return;
      }
      if (request.method === "POST" && path === "/v1/history/reconcile") {
        await reconcileHistory(asObject(request.body), response);
        return;
      }
      if (request.method === "GET" && path === "/v1/plans") {
        await exportPlanning(response);
        return;
      }
      if (request.method === "POST" && path === "/v1/plans") {
        await replacePlanning(asObject(request.body), response);
        return;
      }
      if (request.method === "POST" && path === "/v1/grocery-items") {
        await addManualGroceryItem(asObject(request.body), response);
        return;
      }
      if (request.method === "POST" && path === "/v1/inventory") {
        await reconcileInventory(asObject(request.body), response);
        return;
      }
      if (request.method === "POST" && path === "/v1/foods") {
        await createFood(asObject(request.body), response);
        return;
      }
      if (request.method === "POST" && path === "/v1/products") {
        await createProduct(asObject(request.body), response);
        return;
      }
      if (request.method === "POST" && path === "/v1/migrations/canonical-products") {
        await migrateCanonicalProducts(asObject(request.body), response);
        return;
      }
      if (request.method === "POST" && path === "/v1/groceries") {
        await addGroceries(asObject(request.body), response);
        return;
      }
      if (request.method === "POST" && path === "/v1/recipes") {
        await createRecipe(asObject(request.body), response);
        return;
      }
      if (request.method === "POST" && path === "/v1/meals") {
        await logExternalMeal(asObject(request.body), response);
        return;
      }
      if (request.method === "POST" && path === "/v1/consume/recipe") {
        await consumeRecipe(asObject(request.body), response);
        return;
      }
      if (request.method === "POST" && path === "/v1/prepare/recipe") {
        await prepareRecipe(asObject(request.body), response);
        return;
      }
      if (request.method === "POST" && path === "/v1/prepared-batches") {
        await addPreparedBatch(asObject(request.body), response);
        return;
      }
      if (request.method === "POST" && path === "/v1/consume/prepared") {
        await consumePreparedBatch(asObject(request.body), response);
        return;
      }
      if (request.method === "POST" && path === "/v1/consume/meal-template") {
        await consumeMealTemplate(asObject(request.body), response);
        return;
      }
      if (request.method === "POST" && path === "/v1/meal-templates") {
        await saveMealTemplate(asObject(request.body), response);
        return;
      }
      if (request.method === "POST" && path === "/v1/consume/inventory") {
        await consumeInventory(asObject(request.body), response);
        return;
      }
      if (request.method === "POST" && path === "/v1/external-foods") {
        await saveExternalFood(asObject(request.body), response);
        return;
      }
      if (request.method === "POST" && path === "/v1/targets") {
        await saveNutritionTargets(asObject(request.body), response);
        return;
      }
      if (request.method === "POST" && path === "/v1/preferences") {
        await saveFoodPreferences(asObject(request.body), response);
        return;
      }
      if (request.method === "POST" && path === "/v1/access") {
        await grantAccess(asObject(request.body), response);
        return;
      }
      response.status(404).json({ error: "Unknown route" });
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unexpected error";
      response.status(error instanceof ValidationError ? 422 : 500).json({ error: message });
    }
  },
);

function authorized(header: string | undefined, secret: string): boolean {
  if (!header?.startsWith("Bearer ") || secret.length === 0) return false;
  const provided = Buffer.from(header.substring(7));
  const expected = Buffer.from(secret);
  return provided.length === expected.length && timingSafeEqual(provided, expected);
}

async function exportInventory(response: ApiResponse): Promise<void> {
  const [foods, products, lots, recipes, history, nutritionTargets, foodPreferences, externalFoods, plannedMeals, groceryItems, preparedBatches, mealTemplates, recipeFeedback] = await Promise.all([
    db.collection("foods").get(),
    db.collection("products").get(),
    db.collection("inventory_lots").where("quantity_base", ">", 0).get(),
    db.collection("recipes").get(),
    db.collection("consumption_history").orderBy("timestamp", "desc").limit(500).get(),
    db.collection("settings").doc("nutrition").get(),
    db.collection("settings").doc("food_profile").get(),
    db.collection("external_foods").get(),
    db.collection("meal_plan").get(),
    db.collection("grocery_list").get(),
    db.collection("prepared_batches").where("remaining_servings", ">", 0).get(),
    db.collection("meal_templates").get(),
    db.collection("recipe_feedback").get(),
  ]);
  response.status(200).json({
    foods: foods.docs.map((doc) => ({ id: doc.id, ...doc.data() })),
    products: products.docs.map((doc) => ({ id: doc.id, ...doc.data() })),
    lots: lots.docs.map((doc) => ({ id: doc.id, ...serialize(doc.data()) })),
    recipes: recipes.docs.map((doc) => ({ id: doc.id, ...doc.data() })),
    history: history.docs.map((doc) => ({ id: doc.id, ...serialize(doc.data()) })),
    nutritionTargets: nutritionTargets.exists ? serialize(nutritionTargets.data() ?? {}) : null,
    foodPreferences: foodPreferences.exists ? serialize(foodPreferences.data() ?? {}) : null,
    externalFoods: externalFoods.docs.map((doc) => ({ id: doc.id, ...doc.data() })),
    plannedMeals: plannedMeals.docs.map((doc) => ({ id: doc.id, ...serialize(doc.data()) })),
    groceryItems: groceryItems.docs.map((doc) => ({ id: doc.id, ...serialize(doc.data()) })),
    preparedBatches: preparedBatches.docs.map((doc) => ({ id: doc.id, ...serialize(doc.data()) })),
    mealTemplates: mealTemplates.docs.map((doc) => ({ id: doc.id, ...serialize(doc.data()) })),
    recipeFeedback: recipeFeedback.docs.map((doc) => ({ id: doc.id, ...serialize(doc.data()) })),
    exportedAt: new Date().toISOString(),
  });
}

async function exportPlanning(response: ApiResponse): Promise<void> {
  const [meals, groceries] = await Promise.all([
    db.collection("meal_plan").orderBy("date").get(),
    db.collection("grocery_list").get(),
  ]);
  response.status(200).json({
    meals: meals.docs.map((doc) => ({ id: doc.id, ...serialize(doc.data()) })),
    groceries: groceries.docs.map((doc) => ({ id: doc.id, ...serialize(doc.data()) })),
    exportedAt: new Date().toISOString(),
  });
}

async function replacePlanning(body: JsonObject, response: ApiResponse): Promise<void> {
  const weekStart = dateOnly(requiredString(body.weekStart, "weekStart"), "weekStart");
  const weekEnd = new Date(weekStart);
  weekEnd.setUTCDate(weekEnd.getUTCDate() + 7);
  const [foods, recipeSnapshot, externalSnapshot, lotSnapshot, mealSnapshot, grocerySnapshot, mealTemplateSnapshot, preparedSnapshot] =
    await Promise.all([
      loadFoods(),
      db.collection("recipes").get(),
      db.collection("external_foods").get(),
      db.collection("inventory_lots").where("quantity_base", ">", 0).get(),
      db.collection("meal_plan").get(),
      db.collection("grocery_list").get(),
      db.collection("meal_templates").get(),
      db.collection("prepared_batches").where("remaining_servings", ">", 0).get(),
    ]);
  const recipes = new Map(recipeSnapshot.docs.map((doc) => [doc.id, doc.data()]));
  const externalFoods = new Map(externalSnapshot.docs.map((doc) => [doc.id, doc.data()]));
  const mealTemplates = new Map(mealTemplateSnapshot.docs.map((doc) => [doc.id, doc.data()]));
  const requirements = new Map<string, number>();
  const availablePrepared = new Map<string, number>();
  for (const document of preparedSnapshot.docs) {
    const data = document.data();
    if (data.source !== "recipe" || typeof data.source_id !== "string") continue;
    availablePrepared.set(
      data.source_id,
      (availablePrepared.get(data.source_id) ?? 0) + Number(data.remaining_servings),
    );
  }
  const addRecipeRequirements = (recipeId: string, wantedServings: number): void => {
    const recipe = recipes.get(recipeId);
    if (recipe == null) throw new ValidationError(`Unknown recipe "${recipeId}"`);
    const onHand = availablePrepared.get(recipeId) ?? 0;
    const preparedUsed = Math.min(onHand, wantedServings);
    availablePrepared.set(recipeId, onHand - preparedUsed);
    const servingsToPrepare = wantedServings - preparedUsed;
    if (servingsToPrepare <= 0.000001) return;
    const recipeServings = positiveNumber(recipe.servings, `recipe ${recipeId}.servings`);
    for (const ingredientValue of asArray(recipe.ingredients, `recipe ${recipeId}.ingredients`)) {
      const ingredient = asObject(ingredientValue);
      const foodId = String(ingredient.food_id);
      const food = foods.find((candidate) => candidate.id === foodId);
      if (!food) throw new ValidationError(`Recipe ${recipeId} references an unknown food`);
      const unit = String(ingredient.unit).toLowerCase();
      const conversion = food.conversions.find((candidate) => candidate.unit === unit);
      if (!conversion) throw new ValidationError(`${food.name} does not support unit "${unit}"`);
      const amountBase = Number(ingredient.amount) * conversion.baseAmount * servingsToPrepare / recipeServings;
      requirements.set(foodId, (requirements.get(foodId) ?? 0) + amountBase);
    }
  };
  const entries = asArray(body.entries, "entries").map((value, index) => {
    const item = asObject(value);
    const date = dateOnly(requiredString(item.date, `entries[${index}].date`), `entries[${index}].date`);
    if (date < weekStart || date >= weekEnd) {
      throw new ValidationError(`entries[${index}].date must be inside the requested week`);
    }
    const slot = requiredString(item.slot, `entries[${index}].slot`).toLowerCase();
    if (!["breakfast", "lunch", "dinner", "snack"].includes(slot)) {
      throw new ValidationError(`entries[${index}].slot is invalid`);
    }
    const source = requiredString(item.source, `entries[${index}].source`).toLowerCase();
    if (!["recipe", "meal", "external", "custom"].includes(source)) {
      throw new ValidationError(`entries[${index}].source is invalid`);
    }
    const sourceId = optionalString(item.sourceId);
    const groupId = optionalString(item.groupId);
    const leftoverOfGroupId = optionalString(item.leftoverOfGroupId);
    const intent = (optionalString(item.intent) ?? "prepare").toLowerCase();
    if (!["prepare", "leftover"].includes(intent)) {
      throw new ValidationError(`entries[${index}].intent is invalid`);
    }
    if (leftoverOfGroupId != null && intent !== "leftover") {
      throw new ValidationError(`entries[${index}].leftoverOfGroupId requires intent "leftover"`);
    }
    const servings = item.servings == null ? 1 : positiveNumber(item.servings, `entries[${index}].servings`);
    let name: string;
    let emoji: string;
    if (source === "recipe") {
      if (sourceId == null || !recipes.has(sourceId)) {
        throw new ValidationError(`entries[${index}] references an unknown recipe`);
      }
      const recipe = recipes.get(sourceId) ?? {};
      name = optionalString(item.name) ?? String(recipe.name);
      emoji = optionalString(item.emoji) ?? String(recipe.emoji ?? "🍽️");
      if (intent === "prepare") addRecipeRequirements(sourceId, servings);
    } else if (source === "meal") {
      if (sourceId == null || !mealTemplates.has(sourceId)) {
        throw new ValidationError(`entries[${index}] references an unknown combined meal`);
      }
      const template = mealTemplates.get(sourceId) ?? {};
      name = optionalString(item.name) ?? String(template.name);
      emoji = optionalString(item.emoji) ?? String(template.emoji ?? "🍽️");
      const templateServings = positiveNumber(template.servings, `meal template ${sourceId}.servings`);
      for (const [componentIndex, rawComponent] of asArray(template.components, `meal template ${sourceId}.components`).entries()) {
        const component = asObject(rawComponent);
        const recipeId = requiredString(component.recipe_id, `components[${componentIndex}].recipe_id`);
        const componentServings = positiveNumber(component.servings, `components[${componentIndex}].servings`);
        if (intent === "prepare") {
          addRecipeRequirements(recipeId, componentServings * servings / templateServings);
        }
      }
    } else if (source === "external") {
      if (sourceId == null || !externalFoods.has(sourceId)) {
        throw new ValidationError(`entries[${index}] references an unknown outside food`);
      }
      const food = externalFoods.get(sourceId) ?? {};
      name = optionalString(item.name) ?? String(food.name);
      emoji = optionalString(item.emoji) ?? String(food.emoji ?? "🍽️");
    } else {
      name = requiredString(item.name, `entries[${index}].name`);
      emoji = optionalString(item.emoji) ?? "🍽️";
    }
    return {
      id: optionalString(item.id) ?? `plan-${date.toISOString().slice(0, 10)}-${slot}-${slug(sourceId ?? name)}`,
      data: {
        date: Timestamp.fromDate(date),
        slot,
        source,
        source_id: sourceId ?? null,
        group_id: groupId ?? null,
        leftover_of_group_id: leftoverOfGroupId ?? null,
        intent,
        name,
        emoji,
        servings,
        note: optionalString(item.note) ?? "",
        completed_at: null,
        updated_at: FieldValue.serverTimestamp(),
      },
    };
  });
  if (new Set(entries.map((entry) => entry.id)).size !== entries.length) {
    throw new ValidationError("Plan entry IDs must be unique");
  }
  const sourceGroupDates = new Map<string, Date>();
  for (const document of mealSnapshot.docs) {
    const data = document.data();
    const timestamp = data.date;
    if (
      !(timestamp instanceof Timestamp) ||
      (timestamp.toDate() >= weekStart && timestamp.toDate() < weekEnd)
    ) continue;
    if (typeof data.group_id === "string") sourceGroupDates.set(data.group_id, timestamp.toDate());
  }
  for (const entry of entries) {
    if (entry.data.group_id != null) {
      sourceGroupDates.set(entry.data.group_id, entry.data.date.toDate());
    }
  }
  for (const [index, entry] of entries.entries()) {
    const sourceGroupId = entry.data.leftover_of_group_id;
    if (sourceGroupId == null) continue;
    const sourceDate = sourceGroupDates.get(sourceGroupId);
    if (sourceDate == null || sourceDate >= entry.data.date.toDate()) {
      throw new ValidationError(`entries[${index}].leftoverOfGroupId must reference an earlier planned meal`);
    }
  }

  const available = new Map<string, number>();
  for (const lot of lotSnapshot.docs) {
    const data = lot.data();
    const foodId = String(data.food_id);
    available.set(foodId, (available.get(foodId) ?? 0) + Number(data.quantity_base));
  }
  const checked = new Map<string, boolean>();
  for (const document of grocerySnapshot.docs) {
    const data = document.data();
    if (data.from_plan === true && typeof data.food_id === "string") {
      checked.set(data.food_id, data.checked === true);
    }
  }

  const batch = db.batch();
  for (const document of mealSnapshot.docs) {
    const timestamp = document.data().date;
    if (timestamp instanceof Timestamp) {
      const date = timestamp.toDate();
      if (date >= weekStart && date < weekEnd) batch.delete(document.ref);
    }
  }
  for (const document of grocerySnapshot.docs) {
    if (document.data().from_plan === true) batch.delete(document.ref);
  }
  for (const entry of entries) {
    batch.set(db.collection("meal_plan").doc(entry.id), entry.data);
  }
  let groceryCount = 0;
  for (const [foodId, requiredBase] of requirements) {
    const quantityBase = requiredBase - (available.get(foodId) ?? 0);
    if (quantityBase <= 0.0001) continue;
    const food = foods.find((candidate) => candidate.id === foodId)!;
    batch.set(db.collection("grocery_list").doc(`plan-${foodId}`), {
      name: food.name,
      emoji: food.emoji,
      checked: checked.get(foodId) ?? false,
      from_plan: true,
      food_id: foodId,
      quantity_base: quantityBase,
      quantity_label: "",
      updated_at: FieldValue.serverTimestamp(),
    });
    groceryCount += 1;
  }
  await batch.commit();
  response.status(200).json({
    status: "planned",
    weekStart: weekStart.toISOString().slice(0, 10),
    meals: entries.length,
    groceryItems: groceryCount,
  });
}

async function addManualGroceryItem(body: JsonObject, response: ApiResponse): Promise<void> {
  const name = requiredString(body.name, "name");
  const reference = db.collection("grocery_list").doc();
  await reference.set({
    name,
    emoji: optionalString(body.emoji) ?? "🛒",
    checked: false,
    from_plan: false,
    food_id: null,
    quantity_base: null,
    quantity_label: optionalString(body.quantityLabel) ?? "",
    updated_at: FieldValue.serverTimestamp(),
  });
  response.status(201).json({ id: reference.id, status: "added" });
}

async function exportHistory(rawDays: unknown, response: ApiResponse): Promise<void> {
  const parsedDays = typeof rawDays === "string" ? Number(rawDays) : 30;
  if (!Number.isInteger(parsedDays) || parsedDays < 1 || parsedDays > 365) {
    throw new ValidationError("days must be a whole number between 1 and 365");
  }
  const now = new Date();
  const cutoff = new Date(now);
  cutoff.setHours(0, 0, 0, 0);
  cutoff.setDate(cutoff.getDate() - (parsedDays - 1));
  const snapshot = await db.collection("consumption_history")
    .orderBy("timestamp", "desc")
    .limit(1000)
    .get();
  const events: Array<JsonObject & { id: string }> = snapshot.docs
    .map((doc) => ({ id: doc.id, ...doc.data() } as JsonObject & { id: string }))
    .filter((event) => {
      const timestamp = event.timestamp;
      return timestamp instanceof Timestamp &&
        timestamp.toDate() >= cutoff &&
        event.undone_at == null;
    });
  const meals = new Map<string, { label: string; count: number; lastEaten: Date }>();
  for (const event of events) {
    const label = String(event.label ?? "Unnamed meal");
    const key = label.trim().toLocaleLowerCase();
    const timestamp = (event.timestamp as Timestamp).toDate();
    const current = meals.get(key);
    if (current == null) {
      meals.set(key, { label, count: 1, lastEaten: timestamp });
    } else {
      current.count += 1;
      if (timestamp > current.lastEaten) {
        current.label = label;
        current.lastEaten = timestamp;
      }
    }
  }
  const repeated = [...meals.values()]
    .sort((a, b) => b.count - a.count || b.lastEaten.getTime() - a.lastEaten.getTime())
    .map((meal) => ({
      label: meal.label,
      count: meal.count,
      lastEaten: meal.lastEaten.toISOString(),
    }));
  response.status(200).json({
    rangeDays: parsedDays,
    from: cutoff.toISOString(),
    to: now.toISOString(),
    summary: {
      eventCount: events.length,
      distinctMeals: meals.size,
      repeatedThreeOrMore: repeated.filter((meal) => meal.count >= 3).length,
      mostRepeated: repeated.slice(0, 20),
      recentMealNames: repeated
        .sort((a, b) => Date.parse(b.lastEaten) - Date.parse(a.lastEaten))
        .slice(0, 30)
        .map((meal) => meal.label),
    },
    events: events.map((event) => serialize(event)),
  });
}

async function reconcileInventory(body: JsonObject, response: ApiResponse): Promise<void> {
  const [foods, products] = await Promise.all([loadFoods(), loadProducts()]);
  const replacements = asArray(body.replacements, "replacements").map((value, index) => {
    const replacement = asObject(value);
    const foodId = requiredString(replacement.foodId, `replacements[${index}].foodId`);
    const food = foods.find((entry) => entry.id === foodId);
    if (!food) throw new ValidationError(`replacements[${index}] references an unknown food`);
    const lots = asArray(replacement.lots, `replacements[${index}].lots`).map((lotValue, lotIndex) => {
      const lot = asObject(lotValue);
      const productId = optionalString(lot.productId);
      const product = productId == null
        ? undefined
        : products.find((entry) => entry.id === productId);
      if (productId != null && product == null) {
        throw new ValidationError(`replacements[${index}].lots[${lotIndex}] references an unknown product`);
      }
      if (product != null && product.foodId !== foodId) {
        throw new ValidationError(`replacements[${index}].lots[${lotIndex}] product belongs to another food`);
      }
      const amount = positiveNumber(lot.amount, `replacements[${index}].lots[${lotIndex}].amount`);
      const unit = requiredString(lot.unit, `replacements[${index}].lots[${lotIndex}].unit`).toLowerCase();
      const conversion = product?.conversions.find((entry) => entry.unit === unit) ??
        food.conversions.find((entry) => entry.unit === unit);
      if (!conversion) throw new ValidationError(`${food.name} does not support unit "${unit}"`);
      const location = optionalString(lot.location)?.toLowerCase() ?? food.defaultLocation;
      if (!isLocation(location)) throw new ValidationError(`Unknown location "${location}"`);
      const bestBy = optionalString(lot.bestBy);
      return {
        food_id: foodId,
        product_id: product?.id ?? null,
        quantity_base: amount * conversion.baseAmount,
        original_amount: amount,
        original_unit: unit,
        location,
        best_by: bestBy == null ? null : parseTimestamp(bestBy, `replacements[${index}].lots[${lotIndex}].bestBy`),
        purchased_at: FieldValue.serverTimestamp(),
        source: optionalString(body.source) ?? "inventory reconciliation",
        quantity_estimated: lot.estimated === true,
        quantity_note: optionalString(lot.note) ?? null,
      };
    });
    return { foodId, lots };
  });
  const replacementIds = replacements.map((item) => item.foodId);
  if (new Set(replacementIds).size !== replacementIds.length) {
    throw new ValidationError("replacements cannot contain duplicate food IDs");
  }
  const deleteFoodIds = body.deleteFoodIds == null
    ? []
    : asArray(body.deleteFoodIds, "deleteFoodIds").map((value, index) =>
      requiredString(value, `deleteFoodIds[${index}]`));
  if (new Set(deleteFoodIds).size !== deleteFoodIds.length) {
    throw new ValidationError("deleteFoodIds cannot contain duplicates");
  }
  if (deleteFoodIds.some((id) => replacementIds.includes(id))) {
    throw new ValidationError("A food cannot be replaced and deleted in the same request");
  }
  const displayUnits = body.displayUnits == null ? {} : asObject(body.displayUnits);
  const displayUnitEntries = Object.entries(displayUnits).map(([foodId, value]) => {
    const food = foods.find((entry) => entry.id === foodId);
    if (!food) throw new ValidationError(`displayUnits references unknown food "${foodId}"`);
    const unit = requiredString(value, `displayUnits.${foodId}`).toLowerCase();
    if (!food.conversions.some((conversion) => conversion.unit === unit)) {
      throw new ValidationError(`${food.name} does not support display unit "${unit}"`);
    }
    return { foodId, unit };
  });

  const affectedIds = new Set([...replacementIds, ...deleteFoodIds]);
  const existingLots = await db.collection("inventory_lots").get();
  const batch = db.batch();
  let deletedLots = 0;
  for (const document of existingLots.docs) {
    if (affectedIds.has(String(document.data().food_id))) {
      batch.delete(document.ref);
      deletedLots += 1;
    }
  }
  for (const replacement of replacements) {
    for (const lot of replacement.lots) {
      batch.set(db.collection("inventory_lots").doc(), lot);
    }
  }
  for (const foodId of deleteFoodIds) {
    batch.delete(db.collection("foods").doc(foodId));
  }
  for (const entry of displayUnitEntries) {
    batch.set(db.collection("foods").doc(entry.foodId), {
      display_unit: entry.unit,
      updated_at: FieldValue.serverTimestamp(),
    }, { merge: true });
  }
  await batch.commit();
  response.status(200).json({
    status: "reconciled",
    displayUnitFoodIds: displayUnitEntries.map((entry) => entry.foodId),
    replacedFoodIds: replacementIds,
    deletedFoodIds: deleteFoodIds,
    deletedLots,
    createdLots: replacements.reduce((total, item) => total + item.lots.length, 0),
  });
}

async function reconcileHistory(body: JsonObject, response: ApiResponse): Promise<void> {
  const updates = body.updates == null
    ? []
    : asArray(body.updates, "updates").map((value, index) => {
      const update = asObject(value);
      const kind = requiredString(update.kind, `updates[${index}].kind`);
      if (!["recipe", "inventory", "external"].includes(kind)) {
        throw new ValidationError(`updates[${index}].kind is invalid`);
      }
      return {
        id: requiredString(update.id, `updates[${index}].id`),
        kind,
        recipeId: optionalString(update.recipeId),
        label: optionalString(update.label),
        note: optionalString(update.note),
      };
    });
  const splits = body.splits == null
    ? []
    : asArray(body.splits, "splits").map((value, index) => {
      const split = asObject(value);
      const count = positiveNumber(split.count, `splits[${index}].count`);
      if (!Number.isInteger(count) || count > 100) {
        throw new ValidationError(`splits[${index}].count must be a whole number from 1 to 100`);
      }
      const kind = requiredString(split.kind, `splits[${index}].kind`);
      if (!["recipe", "inventory", "external"].includes(kind)) {
        throw new ValidationError(`splits[${index}].kind is invalid`);
      }
      return {
        id: requiredString(split.id, `splits[${index}].id`),
        count,
        kind,
        recipeId: optionalString(split.recipeId),
        label: requiredString(split.label, `splits[${index}].label`),
        note: optionalString(split.note),
      };
    });
  const ids = [...updates.map((item) => item.id), ...splits.map((item) => item.id)];
  if (new Set(ids).size !== ids.length) {
    throw new ValidationError("History entries cannot be updated and split more than once");
  }

  const [eventSnapshots, recipeSnapshot] = await Promise.all([
    Promise.all(ids.map((id) => db.collection("consumption_history").doc(id).get())),
    db.collection("recipes").get(),
  ]);
  const events = new Map(eventSnapshots.map((snapshot) => [snapshot.id, snapshot]));
  const recipeIds = new Set(recipeSnapshot.docs.map((document) => document.id));
  for (const id of ids) {
    if (!events.get(id)?.exists) throw new ValidationError(`Unknown history entry "${id}"`);
  }
  for (const item of [...updates, ...splits]) {
    if (item.kind === "recipe" && (item.recipeId == null || !recipeIds.has(item.recipeId))) {
      throw new ValidationError(`Recipe history entry "${item.id}" needs a valid recipeId`);
    }
  }

  const batch = db.batch();
  for (const update of updates) {
    const values: JsonObject = {
      kind: update.kind,
      recipe_id: update.kind === "recipe" ? update.recipeId : null,
    };
    if (update.label != null) values.label = update.label;
    if (update.note != null) values.note = update.note;
    batch.update(db.collection("consumption_history").doc(update.id), values);
  }
  const createdIds: string[] = [];
  for (const split of splits) {
    const snapshot = events.get(split.id)!;
    const data = snapshot.data() ?? {};
    const deductions = Array.isArray(data.deductions) ? data.deductions : [];
    if (deductions.length > 0) {
      throw new ValidationError(`Cannot split history entry "${split.id}" because it changed inventory`);
    }
    batch.delete(snapshot.ref);
    const timestamp = data.timestamp instanceof Timestamp
      ? data.timestamp.toDate()
      : new Date(String(data.timestamp));
    for (let index = 0; index < split.count; index += 1) {
      const reference = db.collection("consumption_history").doc();
      createdIds.push(reference.id);
      batch.set(reference, {
        ...data,
        label: split.label,
        kind: split.kind,
        recipe_id: split.kind === "recipe" ? split.recipeId : null,
        timestamp: Timestamp.fromDate(new Date(timestamp.getTime() + index)),
        nutrition: data.nutrition == null
          ? null
          : scaleNutrition(asObject(data.nutrition), 1 / split.count),
        note: split.note ?? data.note ?? "",
        deductions: [],
      });
    }
  }
  await batch.commit();
  response.status(200).json({
    status: "reconciled",
    updatedIds: updates.map((item) => item.id),
    splitIds: splits.map((item) => item.id),
    createdIds,
  });
}

async function createFood(body: JsonObject, response: ApiResponse): Promise<void> {
  const food = parseFood(body);
  const nutrition = body.nutrition == null ? null : parseFoodNutrition(asObject(body.nutrition));
  const reference = db.collection("foods").doc(food.id);
  await reference.set({
    name: food.name,
    quantity_mode: food.quantityMode,
    base_unit: food.baseUnit,
    default_location: food.defaultLocation,
    emoji: food.emoji,
    conversions: food.conversions.map((item) => ({
      unit: item.unit,
      symbol: item.symbol,
      base_amount: item.baseAmount,
    })),
    ...(food.displayUnit == null ? {} : { display_unit: food.displayUnit }),
    ...(nutrition == null ? {} : { nutrition }),
    aliases: food.aliases,
    updated_at: FieldValue.serverTimestamp(),
  }, { merge: true });
  response.status(200).json({ id: reference.id, status: "saved" });
}

async function createProduct(body: JsonObject, response: ApiResponse): Promise<void> {
  const foods = await loadFoods();
  const foodId = requiredString(body.foodId, "foodId");
  if (!foods.some((food) => food.id === foodId)) {
    throw new ValidationError(`Unknown canonical food "${foodId}"`);
  }
  const name = requiredString(body.name, "name");
  const id = optionalString(body.id) ?? slug([optionalString(body.brand), name].filter(Boolean).join(" "));
  const conversions = body.conversions == null
    ? []
    : asArray(body.conversions, "conversions").map((value, index) => {
      const conversion = asObject(value);
      return {
        unit: requiredString(conversion.unit, `conversions[${index}].unit`).toLowerCase(),
        symbol: requiredString(conversion.symbol, `conversions[${index}].symbol`),
        base_amount: positiveNumber(conversion.baseAmount, `conversions[${index}].baseAmount`),
      };
    });
  const barcode = optionalString(body.barcode);
  if (barcode != null) {
    const duplicate = await db.collection("products").where("barcode", "==", barcode).get();
    if (duplicate.docs.some((document) => document.id !== id)) {
      throw new ValidationError("Barcode is already assigned to another product");
    }
  }
  const nutrition = body.nutrition == null ? null : parseFoodNutrition(asObject(body.nutrition));
  await db.collection("products").doc(id).set({
    food_id: foodId,
    name,
    brand: optionalString(body.brand) ?? "",
    aliases: body.aliases == null ? [] : stringList(body.aliases, "aliases"),
    barcode: barcode ?? null,
    conversions,
    nutrition,
    updated_at: FieldValue.serverTimestamp(),
  }, { merge: true });
  response.status(200).json({ id, foodId, status: "saved" });
}

async function migrateCanonicalProducts(body: JsonObject, response: ApiResponse): Promise<void> {
  const mappings = asArray(body.mappings, "mappings").map((raw, index) => {
    const mapping = asObject(raw);
    const product = asObject(mapping.product);
    return {
      sourceFoodId: requiredString(mapping.sourceFoodId, `mappings[${index}].sourceFoodId`),
      targetFoodId: optionalString(mapping.targetFoodId) ??
        requiredString(mapping.sourceFoodId, `mappings[${index}].sourceFoodId`),
      canonicalName: optionalString(mapping.canonicalName),
      canonicalAliases: mapping.canonicalAliases == null
        ? []
        : stringList(mapping.canonicalAliases, `mappings[${index}].canonicalAliases`),
      canonicalConversions: mapping.canonicalConversions == null
        ? undefined
        : asArray(mapping.canonicalConversions, `mappings[${index}].canonicalConversions`).map((value, conversionIndex) => {
          const conversion = asObject(value);
          return {
            unit: requiredString(conversion.unit, `mappings[${index}].canonicalConversions[${conversionIndex}].unit`).toLowerCase(),
            symbol: requiredString(conversion.symbol, `mappings[${index}].canonicalConversions[${conversionIndex}].symbol`),
            base_amount: positiveNumber(
              conversion.baseAmount,
              `mappings[${index}].canonicalConversions[${conversionIndex}].baseAmount`,
            ),
          };
        }),
      product: {
        id: optionalString(product.id) ?? slug([
          optionalString(product.brand),
          requiredString(product.name, `mappings[${index}].product.name`),
        ].filter(Boolean).join(" ")),
        name: requiredString(product.name, `mappings[${index}].product.name`),
        brand: optionalString(product.brand) ?? "",
        aliases: product.aliases == null
          ? []
          : stringList(product.aliases, `mappings[${index}].product.aliases`),
        barcode: optionalString(product.barcode),
        conversions: product.conversions == null
          ? []
          : asArray(product.conversions, `mappings[${index}].product.conversions`).map((value, conversionIndex) => {
            const conversion = asObject(value);
            return {
              unit: requiredString(conversion.unit, `mappings[${index}].product.conversions[${conversionIndex}].unit`).toLowerCase(),
              symbol: requiredString(conversion.symbol, `mappings[${index}].product.conversions[${conversionIndex}].symbol`),
              base_amount: positiveNumber(
                conversion.baseAmount,
                `mappings[${index}].product.conversions[${conversionIndex}].baseAmount`,
              ),
            };
          }),
      },
    };
  });
  if (mappings.length === 0) throw new ValidationError("mappings cannot be empty");
  if (new Set(mappings.map((mapping) => mapping.sourceFoodId)).size !== mappings.length) {
    throw new ValidationError("sourceFoodId may only appear once");
  }
  if (new Set(mappings.map((mapping) => mapping.product.id)).size !== mappings.length) {
    throw new ValidationError("Every migrated product needs a unique ID");
  }

  const [foodSnapshot, lotSnapshot, recipeSnapshot, preparedSnapshot, historySnapshot, grocerySnapshot] =
    await Promise.all([
      db.collection("foods").get(),
      db.collection("inventory_lots").get(),
      db.collection("recipes").get(),
      db.collection("prepared_batches").get(),
      db.collection("consumption_history").get(),
      db.collection("grocery_list").get(),
    ]);
  const foods = new Map(foodSnapshot.docs.map((document) => [document.id, document]));
  for (const mapping of mappings) {
    if (!foods.has(mapping.sourceFoodId)) {
      throw new ValidationError(`Unknown source food "${mapping.sourceFoodId}"`);
    }
    if (!foods.has(mapping.targetFoodId)) {
      throw new ValidationError(`Unknown target food "${mapping.targetFoodId}"`);
    }
    const target = foods.get(mapping.targetFoodId)!.data();
    const supportedUnits = new Set(
      (mapping.canonicalConversions ?? asArray(target.conversions, `foods.${mapping.targetFoodId}.conversions`))
        .map((raw) => String(asObject(raw).unit).toLowerCase()),
    );
    for (const recipe of recipeSnapshot.docs) {
      for (const rawIngredient of asArray(recipe.data().ingredients, `recipes.${recipe.id}.ingredients`)) {
        const ingredient = asObject(rawIngredient);
        if (ingredient.food_id === mapping.sourceFoodId &&
            !supportedUnits.has(String(ingredient.unit).toLowerCase())) {
          throw new ValidationError(
            `Recipe "${recipe.id}" unit "${String(ingredient.unit)}" is not supported by target "${mapping.targetFoodId}"`,
          );
        }
      }
    }
  }

  const impact = {
    mappings: mappings.length,
    lots: lotSnapshot.docs.filter((document) =>
      mappings.some((mapping) => mapping.sourceFoodId === document.data().food_id)).length,
    recipes: recipeSnapshot.docs.filter((document) => mappings.some((mapping) =>
      asArray(document.data().ingredients, `recipes.${document.id}.ingredients`)
        .some((raw) => asObject(raw).food_id === mapping.sourceFoodId && mapping.sourceFoodId !== mapping.targetFoodId),
    )).length,
    historyEntries: historySnapshot.docs.filter((document) => mappings.some((mapping) =>
      mapping.sourceFoodId !== mapping.targetFoodId &&
      (Array.isArray(document.data().deductions) ? document.data().deductions : [])
        .some((raw: unknown) => asObject(raw).food_id === mapping.sourceFoodId),
    )).length,
  };
  if (body.dryRun !== false) {
    response.status(200).json({ status: "dry-run", impact });
    return;
  }

  const mappingBySource = new Map(mappings.map((mapping) => [mapping.sourceFoodId, mapping]));
  const rewriteReferences = (values: unknown): unknown[] =>
    (Array.isArray(values) ? values : []).map((raw) => {
      const value = asObject(raw);
      const mapping = mappingBySource.get(String(value.food_id));
      return mapping == null ? value : { ...value, food_id: mapping.targetFoodId };
    });
  const batch = db.batch();
  let writes = 0;
  const countWrite = (): void => {
    writes += 1;
    if (writes > 450) {
      throw new ValidationError("Migration exceeds 450 writes; split the mapping into smaller batches");
    }
  };
  for (const mapping of mappings) {
    const source = foods.get(mapping.sourceFoodId)!.data();
    const targetReference = db.collection("foods").doc(mapping.targetFoodId);
    const existingAliases = Array.isArray(foods.get(mapping.targetFoodId)!.data().aliases)
      ? foods.get(mapping.targetFoodId)!.data().aliases.map(String)
      : [];
    batch.set(targetReference, {
      ...(mapping.canonicalName == null ? {} : { name: mapping.canonicalName }),
      ...(mapping.canonicalConversions == null ? {} : { conversions: mapping.canonicalConversions }),
      aliases: [...new Set([...existingAliases, String(source.name), ...mapping.canonicalAliases])],
      updated_at: FieldValue.serverTimestamp(),
    }, { merge: true });
    countWrite();
    batch.set(db.collection("products").doc(mapping.product.id), {
      food_id: mapping.targetFoodId,
      name: mapping.product.name,
      brand: mapping.product.brand,
      aliases: mapping.product.aliases,
      barcode: mapping.product.barcode ?? null,
      conversions: mapping.product.conversions,
      nutrition: source.nutrition ?? null,
      updated_at: FieldValue.serverTimestamp(),
    }, { merge: true });
    countWrite();
    if (mapping.sourceFoodId !== mapping.targetFoodId) {
      batch.delete(db.collection("foods").doc(mapping.sourceFoodId));
      countWrite();
    }
  }
  for (const document of lotSnapshot.docs) {
    const mapping = mappingBySource.get(String(document.data().food_id));
    if (mapping == null) continue;
    batch.update(document.ref, {
      food_id: mapping.targetFoodId,
      product_id: mapping.product.id,
      updated_at: FieldValue.serverTimestamp(),
    });
    countWrite();
  }
  for (const document of recipeSnapshot.docs) {
    const before = asArray(document.data().ingredients, `recipes.${document.id}.ingredients`);
    if (!before.some((raw) => {
      const mapping = mappingBySource.get(String(asObject(raw).food_id));
      return mapping != null && mapping.sourceFoodId !== mapping.targetFoodId;
    })) continue;
    batch.update(document.ref, {
      ingredients: rewriteReferences(before),
      updated_at: FieldValue.serverTimestamp(),
    });
    countWrite();
  }
  for (const document of preparedSnapshot.docs) {
    const deductions = document.data().ingredient_deductions;
    if (!Array.isArray(deductions) || !deductions.some((raw) => {
      const mapping = mappingBySource.get(String(asObject(raw).food_id));
      return mapping != null && mapping.sourceFoodId !== mapping.targetFoodId;
    })) continue;
    batch.update(document.ref, { ingredient_deductions: rewriteReferences(deductions) });
    countWrite();
  }
  for (const document of historySnapshot.docs) {
    const deductions = document.data().deductions;
    if (!Array.isArray(deductions) || !deductions.some((raw) => {
      const mapping = mappingBySource.get(String(asObject(raw).food_id));
      return mapping != null && mapping.sourceFoodId !== mapping.targetFoodId;
    })) continue;
    batch.update(document.ref, { deductions: rewriteReferences(deductions) });
    countWrite();
  }
  for (const document of grocerySnapshot.docs) {
    const mapping = mappingBySource.get(String(document.data().food_id));
    if (mapping == null) continue;
    if (mapping.sourceFoodId !== mapping.targetFoodId && document.data().from_plan === true) {
      batch.delete(document.ref);
    } else {
      batch.update(document.ref, {
        food_id: mapping.targetFoodId,
        name: mapping.canonicalName ?? foods.get(mapping.targetFoodId)!.data().name,
        updated_at: FieldValue.serverTimestamp(),
      });
    }
    countWrite();
  }
  await batch.commit();
  response.status(200).json({ status: "migrated", impact, writes });
}

function parseFoodNutrition(value: JsonObject): JsonObject {
  return {
    basis_base_amount: positiveNumber(value.basisBaseAmount, "nutrition.basisBaseAmount"),
    calories: nonNegativeNumber(value.calories, "nutrition.calories"),
    protein_g: nonNegativeNumber(value.proteinG, "nutrition.proteinG"),
    carbs_g: nonNegativeNumber(value.carbsG, "nutrition.carbsG"),
    fat_g: nonNegativeNumber(value.fatG, "nutrition.fatG"),
    fiber_g: nonNegativeNumber(value.fiberG, "nutrition.fiberG"),
    sugar_g: nonNegativeNumber(value.sugarG, "nutrition.sugarG"),
    sodium_mg: nonNegativeNumber(value.sodiumMg, "nutrition.sodiumMg"),
    source: optionalString(value.source) ?? "",
    estimated: value.estimated === true,
  };
}

async function addGroceries(body: JsonObject, response: ApiResponse): Promise<void> {
  const items = asArray(body.items, "items");
  if (items.length === 0) throw new ValidationError("items cannot be empty");
  const [foods, products] = await Promise.all([loadFoods(), loadProducts()]);
  const prepared = items.map((value, index) => {
    const item = asObject(value);
    const selection = resolveFoodSelection(item, foods, products, `items[${index}]`);
    const { food, product } = selection;
    const amount = positiveNumber(item.amount, `items[${index}].amount`);
    const unit = requiredString(item.unit, `items[${index}].unit`).toLowerCase();
    const conversion = product?.conversions.find((entry) => entry.unit === unit) ??
      food.conversions.find((entry) => entry.unit === unit);
    if (!conversion) throw new ValidationError(`${food.name} does not support unit "${unit}"`);
    const location = optionalString(item.location)?.toLowerCase() ?? food.defaultLocation;
    if (!isLocation(location)) throw new ValidationError(`Unknown location "${location}"`);
    const bestBy = optionalString(item.bestBy);
    return {
      food_id: food.id,
      product_id: product?.id ?? null,
      quantity_base: amount * conversion.baseAmount,
      original_amount: amount,
      original_unit: unit,
      location,
      best_by: bestBy == null ? null : parseTimestamp(bestBy, `items[${index}].bestBy`),
      purchased_at: FieldValue.serverTimestamp(),
      source: optionalString(body.source) ?? "api",
    };
  });
  const batch = db.batch();
  const ids: string[] = [];
  for (const lot of prepared) {
    const reference = db.collection("inventory_lots").doc();
    ids.push(reference.id);
    batch.set(reference, lot);
  }
  await batch.commit();
  response.status(201).json({ status: "created", lotIds: ids });
}

async function createRecipe(body: JsonObject, response: ApiResponse): Promise<void> {
  const [foods, products] = await Promise.all([loadFoods(), loadProducts()]);
  const name = requiredString(body.name, "name");
  const ingredients = asArray(body.ingredients, "ingredients").map((value, index) => {
    const ingredient = asObject(value);
    const food = resolveFood(ingredient, foods, `ingredients[${index}]`, products);
    const unit = requiredString(ingredient.unit, `ingredients[${index}].unit`).toLowerCase();
    if (!food.conversions.some((item) => item.unit === unit)) {
      throw new ValidationError(`${food.name} does not support unit "${unit}"`);
    }
    return {
      food_id: food.id,
      amount: positiveNumber(ingredient.amount, `ingredients[${index}].amount`),
      unit,
      optional: ingredient.optional === true,
    };
  });
  if (ingredients.length === 0) throw new ValidationError("ingredients cannot be empty");
  const portions = body.portions == null
    ? []
    : asArray(body.portions, "portions").map((value, index) => {
      const portion = asObject(value);
      return {
        name: requiredString(portion.name, `portions[${index}].name`),
        servings: positiveNumber(portion.servings, `portions[${index}].servings`),
      };
    });
  const id = optionalString(body.id) ?? slug(name);
  const nutritionOverride = body.nutritionOverride == null
    ? null
    : nutritionFromBody(asObject(body.nutritionOverride));
  await db.collection("recipes").doc(id).set({
    name,
    emoji: optionalString(body.emoji) ?? "🍽️",
    servings: positiveNumber(body.servings, "servings"),
    ingredients,
    instructions: asOptionalStringArray(body.instructions),
    nutrition_override: nutritionOverride,
    portions,
    source_url: optionalString(body.sourceUrl) ?? null,
    source_note: optionalString(body.sourceNote) ?? null,
    ...(body.promptForFeedback == null
      ? {}
      : { prompt_for_feedback: requiredBoolean(body.promptForFeedback, "promptForFeedback") }),
    updated_at: FieldValue.serverTimestamp(),
  }, { merge: true });
  response.status(200).json({ id, status: "saved" });
}

async function grantAccess(body: JsonObject, response: ApiResponse): Promise<void> {
  const uid = requiredString(body.uid, "uid");
  if (uid.length > 128 || uid.includes("/")) {
    throw new ValidationError("uid is invalid");
  }
  await db.collection("app_access").doc(uid).set({
    role: "owner",
    updated_at: FieldValue.serverTimestamp(),
  }, { merge: true });
  response.status(200).json({ uid, status: "allowed" });
}

async function logExternalMeal(body: JsonObject, response: ApiResponse): Promise<void> {
  const externalFoodId = optionalString(body.externalFoodId);
  let nutrition: Record<string, number>;
  let label: string;
  let note: string;
  let estimated: boolean;
  if (externalFoodId != null) {
    const saved = await db.collection("external_foods").doc(externalFoodId).get();
    if (!saved.exists) throw new ValidationError("Unknown external food");
    const data = saved.data() ?? {};
    const servings = body.servings == null ? 1 : positiveNumber(body.servings, "servings");
    nutrition = scaleNutrition(asObject(data.nutrition), servings);
    label = optionalString(body.label) ?? (servings === 1
      ? String(data.name)
      : `${servings} servings of ${String(data.name)}`);
    note = optionalString(body.note) ?? [data.brand, data.serving_label].filter(Boolean).join(" · ");
    estimated = typeof body.estimated === "boolean" ? body.estimated : data.estimated === true;
  } else {
    nutrition = nutritionFromBody(body);
    label = requiredString(body.label, "label");
    note = optionalString(body.note) ?? "";
    estimated = body.estimated !== false;
  }
  const timestamp = optionalString(body.timestamp);
  const reference = db.collection("consumption_history").doc();
  await reference.set({
    label,
    kind: "external",
    recipe_id: null,
    timestamp: timestamp == null ? FieldValue.serverTimestamp() : parseTimestamp(timestamp, "timestamp"),
    deductions: [],
    undone_at: null,
    nutrition,
    nutrition_estimated: estimated,
    note,
  });
  response.status(201).json({ id: reference.id, status: "logged" });
}

async function addPreparedBatch(body: JsonObject, response: ApiResponse): Promise<void> {
  const name = requiredString(body.name, "name");
  const servings = positiveNumber(body.servings, "servings");
  const externalFoodId = optionalString(body.externalFoodId);
  let nutrition: JsonObject | null = body.nutrition == null ? null : nutritionFromBody(asObject(body.nutrition));
  let source = "manual";
  let sourceId: string | null = null;
  let emoji = optionalString(body.emoji) ?? "🍽️";
  if (externalFoodId != null) {
    const external = await db.collection("external_foods").doc(externalFoodId).get();
    if (!external.exists) throw new ValidationError(`Unknown external food "${externalFoodId}"`);
    const data = external.data() ?? {};
    nutrition = asObject(data.nutrition);
    source = "external";
    sourceId = externalFoodId;
    emoji = optionalString(body.emoji) ?? String(data.emoji ?? "🍽️");
  }
  const location = (optionalString(body.location) ?? "fridge").toLowerCase();
  if (!["fridge", "freezer", "pantry"].includes(location)) {
    throw new ValidationError("location must be fridge, freezer, or pantry");
  }
  const reference = db.collection("prepared_batches").doc();
  await reference.set({
    name,
    emoji,
    source,
    source_id: sourceId,
    total_servings: servings,
    remaining_servings: servings,
    made_at: body.madeAt == null ? FieldValue.serverTimestamp() : parseTimestamp(requiredString(body.madeAt, "madeAt"), "madeAt"),
    location,
    best_by: body.bestBy == null ? null : parseTimestamp(requiredString(body.bestBy, "bestBy"), "bestBy"),
    nutrition_per_serving: nutrition,
    portions: [],
    ingredient_deductions: [],
    note: optionalString(body.note) ?? "Added through Pantry GPT",
    discarded_at: null,
    updated_at: FieldValue.serverTimestamp(),
  });
  response.status(201).json({ id: reference.id, status: "prepared food added" });
}

async function prepareRecipe(body: JsonObject, response: ApiResponse): Promise<void> {
  const recipeId = requiredString(body.recipeId, "recipeId");
  const servings = body.servings == null ? 1 : positiveNumber(body.servings, "servings");
  const foods = await loadFoods();
  const foodById = new Map(foods.map((food) => [food.id, food]));
  const preparedId = db.collection("prepared_batches").doc().id;
  const deductions = await db.runTransaction(async (transaction) => {
    const recipeReference = db.collection("recipes").doc(recipeId);
    const recipeSnapshot = await transaction.get(recipeReference);
    if (!recipeSnapshot.exists) throw new ValidationError(`Unknown recipe "${recipeId}"`);
    const recipe = recipeSnapshot.data() ?? {};
    const recipeServings = positiveNumber(recipe.servings, "recipe.servings");
    const requirements = new Map<string, number>();
    for (const [index, rawIngredient] of asArray(recipe.ingredients, "recipe.ingredients").entries()) {
      const ingredient = asObject(rawIngredient);
      const foodId = requiredString(ingredient.food_id, `recipe.ingredients[${index}].food_id`);
      const food = foodById.get(foodId);
      if (food == null) throw new ValidationError(`Recipe references unknown food "${foodId}"`);
      const unit = requiredString(ingredient.unit, `recipe.ingredients[${index}].unit`).toLowerCase();
      const conversion = food.conversions.find((item) => item.unit === unit);
      if (conversion == null) throw new ValidationError(`${food.name} does not support unit "${unit}"`);
      const quantity = positiveNumber(ingredient.amount, `recipe.ingredients[${index}].amount`) *
        conversion.baseAmount * servings / recipeServings;
      requirements.set(foodId, (requirements.get(foodId) ?? 0) + quantity);
    }
    const lotSnapshot = await transaction.get(db.collection("inventory_lots").where("quantity_base", ">", 0));
    const planned = planDeductions(requirements, lotSnapshot.docs);
    for (const deduction of planned) {
      transaction.update(db.collection("inventory_lots").doc(deduction.lot_id), {
        quantity_base: deduction.remaining_base,
        updated_at: FieldValue.serverTimestamp(),
      });
    }
    const override = recipe.nutrition_override == null
      ? null
      : scaleNutrition(asObject(recipe.nutrition_override), 1 / recipeServings);
    const ingredientNutrition = override == null ? nutritionForRequirements(requirements, foodById) : null;
    transaction.set(db.collection("prepared_batches").doc(preparedId), {
      name: String(recipe.name),
      emoji: String(recipe.emoji ?? "🍽️"),
      source: "recipe",
      source_id: recipeId,
      total_servings: servings,
      remaining_servings: servings,
      made_at: FieldValue.serverTimestamp(),
      location: optionalString(body.location) ?? "fridge",
      best_by: body.bestBy == null ? null : parseTimestamp(requiredString(body.bestBy, "bestBy"), "bestBy"),
      nutrition_per_serving: override ?? (ingredientNutrition == null ? null : scaleNutrition(ingredientNutrition.totals, 1 / servings)),
      portions: recipe.portions ?? [],
      ingredient_deductions: planned.map(({ lot_id, food_id, quantity_base }) => ({ lot_id, food_id, quantity_base })),
      note: optionalString(body.note) ?? "Prepared through Pantry GPT",
      discarded_at: null,
      updated_at: FieldValue.serverTimestamp(),
    });
    return planned;
  });
  response.status(201).json({ id: preparedId, status: "prepared", deductions: deductions.length });
}

async function consumePreparedBatch(body: JsonObject, response: ApiResponse): Promise<void> {
  const batchId = requiredString(body.batchId, "batchId");
  const servings = body.servings == null ? 1 : positiveNumber(body.servings, "servings");
  const eventId = db.collection("consumption_history").doc().id;
  await db.runTransaction(async (transaction) => {
    const reference = db.collection("prepared_batches").doc(batchId);
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) throw new ValidationError(`Unknown prepared batch "${batchId}"`);
    const prepared = snapshot.data() ?? {};
    const remaining = nonNegativeNumber(prepared.remaining_servings, "remaining_servings");
    if (servings > remaining + 0.000001) {
      throw new ValidationError(`Only ${formatAmount(remaining)} servings remain`);
    }
    transaction.update(reference, {
      remaining_servings: Math.max(0, remaining - servings),
      updated_at: FieldValue.serverTimestamp(),
    });
    const perServing = prepared.nutrition_per_serving == null ? null : asObject(prepared.nutrition_per_serving);
    transaction.set(db.collection("consumption_history").doc(eventId), {
      label: optionalString(body.label) ?? `${formatAmount(servings)} ${servings === 1 ? "serving" : "servings"} of ${String(prepared.name)}`,
      kind: prepared.source === "external" ? "external" : "recipe",
      recipe_id: prepared.source === "recipe" ? prepared.source_id ?? null : null,
      timestamp: body.timestamp == null ? FieldValue.serverTimestamp() : parseTimestamp(requiredString(body.timestamp, "timestamp"), "timestamp"),
      deductions: [],
      prepared_deductions: [{ batch_id: batchId, servings }],
      undone_at: null,
      nutrition: perServing == null ? null : scaleNutrition(perServing, servings),
      nutrition_estimated: prepared.source === "manual",
      note: optionalString(body.note) ?? "Consumed from prepared food through Pantry GPT",
    });
  });
  response.status(201).json({ id: eventId, status: "consumed prepared food" });
}

async function saveMealTemplate(body: JsonObject, response: ApiResponse): Promise<void> {
  const name = requiredString(body.name, "name");
  const servings = positiveNumber(body.servings, "servings");
  const components = asArray(body.components, "components").map((raw, index) => {
    const component = asObject(raw);
    return {
      recipe_id: requiredString(component.recipeId, `components[${index}].recipeId`),
      servings: positiveNumber(component.servings, `components[${index}].servings`),
    };
  });
  if (components.length < 2) throw new ValidationError("A combined meal needs at least two recipe components");
  const recipes = await Promise.all(components.map((component) => db.collection("recipes").doc(component.recipe_id).get()));
  if (recipes.some((recipe) => !recipe.exists)) throw new ValidationError("A component recipe does not exist");
  const id = optionalString(body.id) ?? slug(name);
  await db.collection("meal_templates").doc(id).set({
    name,
    emoji: optionalString(body.emoji) ?? "🍽️",
    servings,
    components,
    notes: optionalString(body.notes) ?? "",
    updated_at: FieldValue.serverTimestamp(),
  });
  response.status(201).json({ id, status: "combined meal saved" });
}

async function consumeMealTemplate(body: JsonObject, response: ApiResponse): Promise<void> {
  const mealId = requiredString(body.mealId, "mealId");
  const servings = body.servings == null ? 1 : positiveNumber(body.servings, "servings");
  const eventId = db.collection("consumption_history").doc().id;
  const deductionCount = await db.runTransaction(async (transaction) => {
    const mealReference = db.collection("meal_templates").doc(mealId);
    const mealSnapshot = await transaction.get(mealReference);
    if (!mealSnapshot.exists) throw new ValidationError(`Unknown combined meal "${mealId}"`);
    const meal = mealSnapshot.data() ?? {};
    const mealServings = positiveNumber(meal.servings, "meal.servings");
    const preparedSnapshot = await transaction.get(
      db.collection("prepared_batches").where("remaining_servings", ">", 0),
    );
    const updates = new Map<string, { remaining: number; servings: number }>();
    const totals = { calories: 0, protein_g: 0, carbs_g: 0, fat_g: 0, fiber_g: 0, sugar_g: 0, sodium_mg: 0 };
    let hasNutrition = false;
    for (const [componentIndex, rawComponent] of asArray(meal.components, "meal.components").entries()) {
      const component = asObject(rawComponent);
      const recipeId = requiredString(component.recipe_id, `components[${componentIndex}].recipe_id`);
      let needed = positiveNumber(component.servings, `components[${componentIndex}].servings`) * servings / mealServings;
      const candidates = preparedSnapshot.docs
        .filter((document) => {
          const data = document.data();
          return data.source === "recipe" && data.source_id === recipeId && data.discarded_at == null;
        })
        .sort((left, right) => {
          const leftDate = left.data().made_at instanceof Timestamp ? left.data().made_at.toMillis() : 0;
          const rightDate = right.data().made_at instanceof Timestamp ? right.data().made_at.toMillis() : 0;
          return leftDate - rightDate;
        });
      for (const candidate of candidates) {
        if (needed <= 0.000001) break;
        const data = candidate.data();
        const priorUpdate = updates.get(candidate.id);
        const remaining = priorUpdate?.remaining ?? Number(data.remaining_servings);
        const take = Math.min(remaining, needed);
        if (take <= 0) continue;
        updates.set(candidate.id, {
          remaining: remaining - take,
          servings: (priorUpdate?.servings ?? 0) + take,
        });
        if (data.nutrition_per_serving != null) {
          hasNutrition = true;
          const scaled = scaleNutrition(asObject(data.nutrition_per_serving), take);
          for (const key of Object.keys(totals) as Array<keyof typeof totals>) {
            totals[key] += Number(scaled[key] ?? 0);
          }
        }
        needed -= take;
      }
      if (needed > 0.000001) {
        const recipe = await transaction.get(db.collection("recipes").doc(recipeId));
        throw new ValidationError(
          `Prepare ${formatAmount(needed)} more servings of ${String(recipe.data()?.name ?? recipeId)}`,
        );
      }
    }
    for (const [batchId, update] of updates) {
      transaction.update(db.collection("prepared_batches").doc(batchId), {
        remaining_servings: Math.max(0, update.remaining),
        updated_at: FieldValue.serverTimestamp(),
      });
    }
    transaction.set(db.collection("consumption_history").doc(eventId), {
      label: optionalString(body.label) ?? `${formatAmount(servings)} ${servings === 1 ? "serving" : "servings"} of ${String(meal.name)}`,
      kind: "recipe",
      recipe_id: null,
      timestamp: body.timestamp == null ? FieldValue.serverTimestamp() : parseTimestamp(requiredString(body.timestamp, "timestamp"), "timestamp"),
      deductions: [],
      prepared_deductions: [...updates].map(([batchId, update]) => ({ batch_id: batchId, servings: update.servings })),
      undone_at: null,
      nutrition: hasNutrition ? totals : null,
      nutrition_estimated: false,
      note: optionalString(body.note) ?? `Combined meal ${mealId} consumed through Pantry GPT`,
    });
    return updates.size;
  });
  response.status(201).json({ id: eventId, status: "combined meal consumed", preparedBatches: deductionCount });
}

async function consumeRecipe(body: JsonObject, response: ApiResponse): Promise<void> {
  const recipeId = requiredString(body.recipeId, "recipeId");
  const servings = body.servings == null ? 1 : positiveNumber(body.servings, "servings");
  const foods = await loadFoods();
  const foodById = new Map(foods.map((food) => [food.id, food]));
  const eventId = db.collection("consumption_history").doc().id;
  const result = await db.runTransaction(async (transaction) => {
    const recipeReference = db.collection("recipes").doc(recipeId);
    const recipeSnapshot = await transaction.get(recipeReference);
    if (!recipeSnapshot.exists) throw new ValidationError(`Unknown recipe "${recipeId}"`);
    const recipe = recipeSnapshot.data() ?? {};
    const recipeServings = positiveNumber(recipe.servings, "recipe.servings");
    const requirements = new Map<string, number>();
    for (const [index, rawIngredient] of asArray(recipe.ingredients, "recipe.ingredients").entries()) {
      const ingredient = asObject(rawIngredient);
      const foodId = requiredString(ingredient.food_id, `recipe.ingredients[${index}].food_id`);
      const food = foodById.get(foodId);
      if (food == null) throw new ValidationError(`Recipe references unknown food "${foodId}"`);
      const unit = requiredString(ingredient.unit, `recipe.ingredients[${index}].unit`).toLowerCase();
      const conversion = food.conversions.find((item) => item.unit === unit);
      if (conversion == null) throw new ValidationError(`${food.name} does not support unit "${unit}"`);
      const quantityBase = positiveNumber(ingredient.amount, `recipe.ingredients[${index}].amount`) *
        conversion.baseAmount * servings / recipeServings;
      requirements.set(foodId, (requirements.get(foodId) ?? 0) + quantityBase);
    }
    const lotSnapshot = await transaction.get(
      db.collection("inventory_lots").where("quantity_base", ">", 0),
    );
    const deductions = planDeductions(requirements, lotSnapshot.docs);
    for (const deduction of deductions) {
      transaction.update(db.collection("inventory_lots").doc(deduction.lot_id), {
        quantity_base: deduction.remaining_base,
        updated_at: FieldValue.serverTimestamp(),
      });
    }
    const nutritionOverride = recipe.nutrition_override == null
      ? null
      : scaleNutrition(asObject(recipe.nutrition_override), servings / recipeServings);
    const ingredientNutrition = nutritionOverride == null
      ? nutritionForRequirements(requirements, foodById)
      : null;
    transaction.set(db.collection("consumption_history").doc(eventId), {
      label: optionalString(body.label) ?? `${formatAmount(servings)} ${servings === 1 ? "serving" : "servings"} of ${String(recipe.name)}`,
      kind: "recipe",
      recipe_id: recipeId,
      timestamp: body.timestamp == null
        ? FieldValue.serverTimestamp()
        : parseTimestamp(requiredString(body.timestamp, "timestamp"), "timestamp"),
      deductions: deductions.map(({ lot_id, food_id, quantity_base }) => ({ lot_id, food_id, quantity_base })),
      undone_at: null,
      nutrition: nutritionOverride ?? ingredientNutrition?.totals ?? null,
      nutrition_estimated: nutritionOverride == null
        ? ingredientNutrition?.estimated ?? true
        : false,
      note: optionalString(body.note) ?? "Logged through Pantry GPT",
    });
    return deductions;
  });
  response.status(201).json({ id: eventId, status: "consumed", deductions: result.length });
}

async function consumeInventory(body: JsonObject, response: ApiResponse): Promise<void> {
  const [foods, products] = await Promise.all([loadFoods(), loadProducts()]);
  const selection = resolveFoodSelection(body, foods, products, "food");
  const { food, product } = selection;
  const amount = positiveNumber(body.amount, "amount");
  const unit = requiredString(body.unit, "unit").toLowerCase();
  const conversion = product?.conversions.find((item) => item.unit === unit) ??
    food.conversions.find((item) => item.unit === unit);
  if (conversion == null) throw new ValidationError(`${food.name} does not support unit "${unit}"`);
  const requirement = amount * conversion.baseAmount;
  const eventId = db.collection("consumption_history").doc().id;
  const deductions = await db.runTransaction(async (transaction) => {
    const lotSnapshot = await transaction.get(
      db.collection("inventory_lots").where("quantity_base", ">", 0),
    );
    const planned = planDeductions(new Map([[food.id, requirement]]), lotSnapshot.docs);
    for (const deduction of planned) {
      transaction.update(db.collection("inventory_lots").doc(deduction.lot_id), {
        quantity_base: deduction.remaining_base,
        updated_at: FieldValue.serverTimestamp(),
      });
    }
    const nutrition = nutritionForRequirements(new Map([[food.id, requirement]]), new Map([[food.id, food]]));
    transaction.set(db.collection("consumption_history").doc(eventId), {
      label: optionalString(body.label) ?? `${formatAmount(amount)} ${unit} ${food.name.toLowerCase()}`,
      kind: "inventory",
      recipe_id: null,
      timestamp: body.timestamp == null
        ? FieldValue.serverTimestamp()
        : parseTimestamp(requiredString(body.timestamp, "timestamp"), "timestamp"),
      deductions: planned.map(({ lot_id, food_id, quantity_base }) => ({ lot_id, food_id, quantity_base })),
      undone_at: null,
      nutrition: nutrition?.totals ?? null,
      nutrition_estimated: nutrition?.estimated ?? true,
      note: optionalString(body.note) ?? "Logged through Pantry GPT",
    });
    return planned;
  });
  response.status(201).json({ id: eventId, status: "consumed", deductions: deductions.length });
}

type PlannedDeduction = {
  lot_id: string;
  food_id: string;
  quantity_base: number;
  remaining_base: number;
};

function planDeductions(
  requirements: Map<string, number>,
  lots: Array<{ id: string; data(): JsonObject }>,
): PlannedDeduction[] {
  const deductions: PlannedDeduction[] = [];
  for (const [foodId, required] of requirements) {
    let remaining = required;
    const candidates = lots
      .filter((lot) => String(lot.data().food_id) === foodId && Number(lot.data().quantity_base) > 0)
      .sort((left, right) => lotSortValue(left.data()) - lotSortValue(right.data()));
    for (const lot of candidates) {
      if (remaining <= 0.000001) break;
      const quantity = Number(lot.data().quantity_base);
      const amount = Math.min(quantity, remaining);
      deductions.push({
        lot_id: lot.id,
        food_id: foodId,
        quantity_base: amount,
        remaining_base: quantity - amount,
      });
      remaining -= amount;
    }
    if (remaining > 0.000001) {
      throw new ValidationError(`Insufficient inventory for "${foodId}"; missing ${formatAmount(remaining)} base units`);
    }
  }
  return deductions;
}

function lotSortValue(data: JsonObject): number {
  const bestBy = data.best_by instanceof Timestamp ? data.best_by.toMillis() : Number.MAX_SAFE_INTEGER;
  const purchasedAt = data.purchased_at instanceof Timestamp ? data.purchased_at.toMillis() : Number.MAX_SAFE_INTEGER;
  return bestBy * 2 + purchasedAt / Number.MAX_SAFE_INTEGER;
}

function nutritionForRequirements(
  requirements: Map<string, number>,
  foods: Map<string, FoodRecord>,
): { totals: Record<string, number>; estimated: boolean } | null {
  const totals = { calories: 0, protein_g: 0, carbs_g: 0, fat_g: 0, fiber_g: 0, sugar_g: 0, sodium_mg: 0 };
  let estimated = false;
  for (const [foodId, quantityBase] of requirements) {
    const nutrition = foods.get(foodId)?.nutrition;
    if (nutrition == null) return null;
    const basis = positiveNumber(nutrition.basis_base_amount, `nutrition for ${foodId}`);
    const factor = quantityBase / basis;
    for (const key of Object.keys(totals) as Array<keyof typeof totals>) {
      totals[key] += nonNegativeNumber(nutrition[key], `nutrition.${key}`) * factor;
    }
    estimated ||= nutrition.estimated === true;
  }
  return { totals, estimated };
}

function formatAmount(value: number): string {
  return Number.isInteger(value) ? String(value) : String(Number(value.toFixed(2)));
}

async function saveExternalFood(body: JsonObject, response: ApiResponse): Promise<void> {
  const name = requiredString(body.name, "name");
  const brand = optionalString(body.brand) ?? "";
  const id = optionalString(body.id) ?? slug(`${brand}-${name}`);
  const nutrition = nutritionFromBody(body);
  await db.collection("external_foods").doc(id).set({
    name,
    brand,
    emoji: optionalString(body.emoji) ?? "🍽️",
    serving_label: requiredString(body.servingLabel, "servingLabel"),
    nutrition,
    source: optionalString(body.source) ?? "",
    estimated: body.estimated === true,
    updated_at: FieldValue.serverTimestamp(),
  }, { merge: true });
  response.status(200).json({ id, status: "saved" });
}

async function saveNutritionTargets(body: JsonObject, response: ApiResponse): Promise<void> {
  const targets = {
    calories: positiveNumber(body.calories, "calories"),
    protein_g: positiveNumber(body.proteinG, "proteinG"),
    carbs_g: positiveNumber(body.carbsG, "carbsG"),
    fat_g: positiveNumber(body.fatG, "fatG"),
    fiber_g: positiveNumber(body.fiberG, "fiberG"),
    sodium_mg: positiveNumber(body.sodiumMg, "sodiumMg"),
    label: optionalString(body.label) ?? "Personalized targets",
    updated_at: FieldValue.serverTimestamp(),
  };
  await db.collection("settings").doc("nutrition").set(targets);
  response.status(200).json({ status: "saved" });
}

async function saveFoodPreferences(body: JsonObject, response: ApiResponse): Promise<void> {
  const preferences = {
    allergies: stringList(body.allergies, "allergies"),
    dislikes: stringList(body.dislikes, "dislikes"),
    favorites: stringList(body.favorites, "favorites"),
    dietary_rules: stringList(body.dietaryRules, "dietaryRules"),
    planning_notes: optionalString(body.planningNotes) ?? "",
    updated_at: FieldValue.serverTimestamp(),
  };
  await db.collection("settings").doc("food_profile").set(preferences);
  response.status(200).json({ status: "saved" });
}

async function loadFoods(): Promise<FoodRecord[]> {
  const snapshot = await db.collection("foods").get();
  return snapshot.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      name: String(data.name),
      quantityMode: data.quantity_mode as "counted" | "measured",
      baseUnit: String(data.base_unit),
      defaultLocation: data.default_location as "pantry" | "fridge" | "freezer",
      emoji: String(data.emoji ?? "🥫"),
      conversions: (data.conversions as JsonObject[]).map((item) => ({
        unit: String(item.unit).toLowerCase(),
        symbol: String(item.symbol),
        baseAmount: Number(item.base_amount),
      })),
      displayUnit: optionalString(data.display_unit),
      nutrition: data.nutrition == null ? undefined : asObject(data.nutrition),
      aliases: Array.isArray(data.aliases) ? data.aliases.map(String) : [],
    };
  });
}

async function loadProducts(): Promise<ProductRecord[]> {
  const snapshot = await db.collection("products").get();
  return snapshot.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      foodId: String(data.food_id),
      name: String(data.name),
      brand: String(data.brand ?? ""),
      aliases: Array.isArray(data.aliases) ? data.aliases.map(String) : [],
      barcode: optionalString(data.barcode),
      conversions: (Array.isArray(data.conversions) ? data.conversions : []).map((raw) => {
        const item = asObject(raw);
        return {
          unit: String(item.unit).toLowerCase(),
          symbol: String(item.symbol),
          baseAmount: Number(item.base_amount),
        };
      }),
      nutrition: data.nutrition == null ? undefined : asObject(data.nutrition),
    };
  });
}

type FoodSelection = { food: FoodRecord; product?: ProductRecord };

function resolveFoodSelection(
  item: JsonObject,
  foods: FoodRecord[],
  products: ProductRecord[],
  path: string,
): FoodSelection {
  const id = optionalString(item.foodId);
  const productId = optionalString(item.productId);
  const barcode = optionalString(item.barcode);
  const name = optionalString(item.product) ?? optionalString(item.food);
  let product = productId == null ? undefined : products.find((entry) => entry.id === productId);
  if (productId != null && product == null) {
    throw new ValidationError(`${path} references unknown product "${productId}"`);
  }
  if (product == null && barcode != null) {
    product = products.find((entry) => entry.barcode === barcode);
  }
  if (product == null && id == null && name != null) {
    const wanted = singular(normalize(name));
    const productMatches = products.filter((entry) =>
      [entry.name, `${entry.brand} ${entry.name}`, ...entry.aliases]
        .some((candidate) => singular(normalize(candidate)) === wanted),
    );
    if (productMatches.length > 1) {
      throw new ValidationError(`${path} matches more than one product; send productId or barcode`);
    }
    product = productMatches[0];
  }
  const resolvedFoodId = id ?? product?.foodId;
  let food = resolvedFoodId == null ? undefined : foods.find((entry) => entry.id === resolvedFoodId);
  if (food == null && id == null && name != null) {
    const wanted = singular(normalize(name));
    const foodMatches = foods.filter((entry) =>
      [entry.name, ...entry.aliases].some((candidate) => singular(normalize(candidate)) === wanted),
    );
    if (foodMatches.length > 1) {
      throw new ValidationError(`${path} matches more than one canonical food; send foodId`);
    }
    food = foodMatches[0];
  }
  if (!food) throw new ValidationError(`${path} references an unknown canonical food or product`);
  if (product != null && product.foodId !== food.id) {
    throw new ValidationError(`${path} product does not belong to canonical food "${food.id}"`);
  }
  return { food, product };
}

function resolveFood(
  item: JsonObject,
  foods: FoodRecord[],
  path: string,
  products: ProductRecord[] = [],
): FoodRecord {
  return resolveFoodSelection(item, foods, products, path).food;
}

function parseFood(body: JsonObject): FoodRecord {
  const name = requiredString(body.name, "name");
  const mode = requiredString(body.quantityMode, "quantityMode");
  if (mode !== "counted" && mode !== "measured") throw new ValidationError("quantityMode must be counted or measured");
  const location = optionalString(body.defaultLocation) ?? "pantry";
  if (!isLocation(location)) throw new ValidationError("defaultLocation is invalid");
  const conversions = asArray(body.conversions, "conversions").map((value, index) => {
    const item = asObject(value);
    return {
      unit: requiredString(item.unit, `conversions[${index}].unit`).toLowerCase(),
      symbol: requiredString(item.symbol, `conversions[${index}].symbol`),
      baseAmount: positiveNumber(item.baseAmount, `conversions[${index}].baseAmount`),
    };
  });
  const baseUnit = requiredString(body.baseUnit, "baseUnit").toLowerCase();
  if (!conversions.some((item) => item.unit === baseUnit && item.baseAmount === 1)) {
    throw new ValidationError("baseUnit needs a conversion with baseAmount 1");
  }
  const displayUnit = optionalString(body.displayUnit)?.toLowerCase();
  if (displayUnit != null && !conversions.some((item) => item.unit === displayUnit)) {
    throw new ValidationError("displayUnit must match a conversion unit");
  }
  return {
    id: optionalString(body.id) ?? slug(name),
    name,
    quantityMode: mode,
    baseUnit,
    defaultLocation: location,
    emoji: optionalString(body.emoji) ?? "🥫",
    conversions,
    displayUnit,
    aliases: body.aliases == null ? [] : stringList(body.aliases, "aliases"),
  };
}

class ValidationError extends Error {}

function asObject(value: unknown): JsonObject {
  if (value == null || typeof value !== "object" || Array.isArray(value)) throw new ValidationError("Expected a JSON object");
  return value as JsonObject;
}
function asArray(value: unknown, name: string): unknown[] {
  if (!Array.isArray(value)) throw new ValidationError(`${name} must be an array`);
  return value;
}
function requiredString(value: unknown, name: string): string {
  if (typeof value !== "string" || value.trim() === "") throw new ValidationError(`${name} is required`);
  return value.trim();
}
function optionalString(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() !== "" ? value.trim() : undefined;
}
function requiredBoolean(value: unknown, name: string): boolean {
  if (typeof value !== "boolean") throw new ValidationError(`${name} must be true or false`);
  return value;
}
function positiveNumber(value: unknown, name: string): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) throw new ValidationError(`${name} must be a positive number`);
  return value;
}
function nonNegativeNumber(value: unknown, name: string): number {
  if (value == null) return 0;
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
    throw new ValidationError(`${name} must be a non-negative number`);
  }
  return value;
}
function nutritionFromBody(body: JsonObject): Record<string, number> {
  const nutrition = {
    calories: nonNegativeNumber(body.calories, "calories"),
    protein_g: nonNegativeNumber(body.proteinG, "proteinG"),
    carbs_g: nonNegativeNumber(body.carbsG, "carbsG"),
    fat_g: nonNegativeNumber(body.fatG, "fatG"),
    fiber_g: nonNegativeNumber(body.fiberG, "fiberG"),
    sugar_g: nonNegativeNumber(body.sugarG, "sugarG"),
    sodium_mg: nonNegativeNumber(body.sodiumMg, "sodiumMg"),
  };
  if (!Object.values(nutrition).some((value) => value > 0)) {
    throw new ValidationError("At least one nutrition value must be positive");
  }
  return nutrition;
}
function scaleNutrition(nutrition: JsonObject, factor: number): Record<string, number> {
  return {
    calories: nonNegativeNumber(nutrition.calories, "nutrition.calories") * factor,
    protein_g: nonNegativeNumber(nutrition.protein_g, "nutrition.protein_g") * factor,
    carbs_g: nonNegativeNumber(nutrition.carbs_g, "nutrition.carbs_g") * factor,
    fat_g: nonNegativeNumber(nutrition.fat_g, "nutrition.fat_g") * factor,
    fiber_g: nonNegativeNumber(nutrition.fiber_g, "nutrition.fiber_g") * factor,
    sugar_g: nonNegativeNumber(nutrition.sugar_g, "nutrition.sugar_g") * factor,
    sodium_mg: nonNegativeNumber(nutrition.sodium_mg, "nutrition.sodium_mg") * factor,
  };
}
function asOptionalStringArray(value: unknown): string[] {
  if (value == null) return [];
  return asArray(value, "instructions").map((item, index) => requiredString(item, `instructions[${index}]`));
}
function stringList(value: unknown, name: string): string[] {
  if (value == null) return [];
  const seen = new Set<string>();
  return asArray(value, name).map((item, index) => requiredString(item, `${name}[${index}]`))
    .filter((item) => {
      const key = item.toLocaleLowerCase();
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
}
function parseTimestamp(value: string, name: string): Timestamp {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) throw new ValidationError(`${name} must be an ISO date`);
  return Timestamp.fromDate(date);
}
function dateOnly(value: string, name: string): Date {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new ValidationError(`${name} must use YYYY-MM-DD`);
  }
  const date = new Date(`${value}T00:00:00.000Z`);
  if (Number.isNaN(date.getTime()) || date.toISOString().slice(0, 10) !== value) {
    throw new ValidationError(`${name} is not a valid date`);
  }
  return date;
}
function isLocation(value: string): value is "pantry" | "fridge" | "freezer" {
  return value === "pantry" || value === "fridge" || value === "freezer";
}
function normalize(value: string): string { return value.toLowerCase().replace(/[^a-z0-9]/g, ""); }
function singular(value: string): string { return value.endsWith("s") ? value.slice(0, -1) : value; }
function slug(value: string): string { return value.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, ""); }
function serialize(value: JsonObject): JsonObject {
  return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, item instanceof Timestamp ? item.toDate().toISOString() : item]));
}
