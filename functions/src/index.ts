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
};

export const pantryApi = onRequest(
  { region: "us-east1", secrets: [pantryApiToken], timeoutSeconds: 60 },
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
      if (request.method === "POST" && path === "/v1/foods") {
        await createFood(asObject(request.body), response);
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
  const [foods, lots, recipes] = await Promise.all([
    db.collection("foods").get(),
    db.collection("inventory_lots").where("quantity_base", ">", 0).get(),
    db.collection("recipes").get(),
  ]);
  response.status(200).json({
    foods: foods.docs.map((doc) => ({ id: doc.id, ...doc.data() })),
    lots: lots.docs.map((doc) => ({ id: doc.id, ...serialize(doc.data()) })),
    recipes: recipes.docs.map((doc) => ({ id: doc.id, ...doc.data() })),
    exportedAt: new Date().toISOString(),
  });
}

async function createFood(body: JsonObject, response: ApiResponse): Promise<void> {
  const food = parseFood(body);
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
    updated_at: FieldValue.serverTimestamp(),
  }, { merge: true });
  response.status(200).json({ id: reference.id, status: "saved" });
}

async function addGroceries(body: JsonObject, response: ApiResponse): Promise<void> {
  const items = asArray(body.items, "items");
  if (items.length === 0) throw new ValidationError("items cannot be empty");
  const foods = await loadFoods();
  const prepared = items.map((value, index) => {
    const item = asObject(value);
    const food = resolveFood(item, foods, `items[${index}]`);
    const amount = positiveNumber(item.amount, `items[${index}].amount`);
    const unit = requiredString(item.unit, `items[${index}].unit`).toLowerCase();
    const conversion = food.conversions.find((entry) => entry.unit === unit);
    if (!conversion) throw new ValidationError(`${food.name} does not support unit "${unit}"`);
    const location = optionalString(item.location)?.toLowerCase() ?? food.defaultLocation;
    if (!isLocation(location)) throw new ValidationError(`Unknown location "${location}"`);
    const bestBy = optionalString(item.bestBy);
    return {
      food_id: food.id,
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
  const foods = await loadFoods();
  const name = requiredString(body.name, "name");
  const ingredients = asArray(body.ingredients, "ingredients").map((value, index) => {
    const ingredient = asObject(value);
    const food = resolveFood(ingredient, foods, `ingredients[${index}]`);
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
  const id = optionalString(body.id) ?? slug(name);
  await db.collection("recipes").doc(id).set({
    name,
    emoji: optionalString(body.emoji) ?? "🍽️",
    servings: positiveNumber(body.servings, "servings"),
    ingredients,
    instructions: asOptionalStringArray(body.instructions),
    source_url: optionalString(body.sourceUrl) ?? null,
    source_note: optionalString(body.sourceNote) ?? null,
    updated_at: FieldValue.serverTimestamp(),
  }, { merge: true });
  response.status(200).json({ id, status: "saved" });
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
    };
  });
}

function resolveFood(item: JsonObject, foods: FoodRecord[], path: string): FoodRecord {
  const id = optionalString(item.foodId);
  const name = optionalString(item.food);
  const food = id != null
    ? foods.find((entry) => entry.id === id)
    : foods.find((entry) => singular(normalize(entry.name)) === singular(normalize(name ?? "")));
  if (!food) throw new ValidationError(`${path} references an unknown food`);
  return food;
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
  return {
    id: optionalString(body.id) ?? slug(name),
    name,
    quantityMode: mode,
    baseUnit,
    defaultLocation: location,
    emoji: optionalString(body.emoji) ?? "🥫",
    conversions,
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
function positiveNumber(value: unknown, name: string): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) throw new ValidationError(`${name} must be a positive number`);
  return value;
}
function asOptionalStringArray(value: unknown): string[] {
  if (value == null) return [];
  return asArray(value, "instructions").map((item, index) => requiredString(item, `instructions[${index}]`));
}
function parseTimestamp(value: string, name: string): Timestamp {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) throw new ValidationError(`${name} must be an ISO date`);
  return Timestamp.fromDate(date);
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
