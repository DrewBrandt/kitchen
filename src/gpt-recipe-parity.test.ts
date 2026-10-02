/// <reference types="node" />
// @vitest-environment node
import { createContext, runInContext } from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import Ajv2020 from 'ajv/dist/2020';
import { parse } from 'yaml';
import { describe, expect, it, vi } from 'vitest';
import schemaText from '../docs/pantry-gpt-openapi.yaml?raw';
import edgeSource from '../supabase/functions/pantry-api/index.ts?raw';

const schema = parse(schemaText);
const patchSchema = schema.paths['/v1/recipes/{id}'].patch.requestBody.content['application/json'].schema;
const ajv = new Ajv2020({ strict: false, allErrors: true });
ajv.addFormat('uuid', /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i);
ajv.addFormat('uri', { type: 'string', validate: (value: string) => { try { new URL(value); return true; } catch { return false; } } });
const validate = ajv.compile(patchSchema);
const uuid = (n: number) => `98600000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const base = { foodId: uuid(3), quantity: 10, unit: uuid(4), sortOrder: 0 };
const batchNutrition = { calories: 800, proteinG: 30, carbsG: 100, fatG: 30, fiberG: 10, sugarG: 5, sodiumMg: 600 };

function fixture() {
  // Run actual route/serializer source with a stub database. No Deno listener,
  // credentials, external client, or HTTP connection is created by this test.
  const source = edgeSource.replace(/^import .*\r?\n/, '').split('Deno.serve(')[0];
  const context = createContext({ Request, Response, URL });
  // Node supports transform mode; the locked Node typings currently expose only strip.
  const transform = stripTypeScriptTypes as unknown as (code: string, options: { mode: 'transform' }) => string;
  runInContext(transform(source, { mode: 'transform' }), context);
  const rows = [
    { id: uuid(10), recipe: uuid(1), ingredient: uuid(3), qty: 10, unit: uuid(4), sort_order: 0, note: 'Sauce', pinned_product: uuid(5) },
    { id: uuid(11), recipe: uuid(1), ingredient: uuid(3), qty: 10, unit: uuid(4), sort_order: 1, note: 'Topping', pinned_product: null },
  ];
  const tables: Record<string, unknown[]> = {
    recipes: [{ id: uuid(1), name: 'Duplicate recipe', servings: 2 }], recipe_ingredients: rows,
    base_foods: [{ id: uuid(3), name: 'Flour' }], measure_conversions: [{ id: uuid(4), short_name: 'g', full_name: 'grams' }],
  };
  const rpc = vi.fn(async (_name: string, _args: unknown): Promise<{ data: unknown; error: { message: string } | null }> => ({ data: { status: 'updated' }, error: null }));
  const db = { rpc, from: (table: string) => ({ select: () => {
    const result = { data: tables[table], error: null };
    return { ...result, order: () => result };
  } }) };
  const request = async (method: string, body?: unknown, path = `/v1/recipes/${uuid(1)}`) => context.route(
    new Request(`https://local.invalid${path}`, { method, ...(body === undefined ? {} : { body: JSON.stringify(body) }) }), db,
  ) as Promise<Response>;
  return { rows, rpc, request };
}

describe('recipe Action schema and actual HTTP handler parity', () => {
  it.each([
    ['legacy no-ID matching', { ingredients: [base] }],
    ['stable existing identity', { ingredients: [{ ...base, id: uuid(10) }] }],
    ['saved piece estimate', { ingredients: [{ ...base, pieceBasis: { count: 1, grams: 10, label: 'piece', sourceQuantity: 10, sourceUnit: 'g', provenance: 'importer estimate', anchor: true } }] }],
    ['clear piece estimate', { ingredients: [{ ...base, pieceBasis: null }] }],
    ['clear an existing note', { ingredients: [{ ...base, id: uuid(10), note: null }] }],
    ['explicit new row', { ingredients: [{ ...base, id: null, note: null }] }],
    ['clear nutrition', { nutrition: null }],
    ['whole-recipe nutrition without legacy basis', { servings: 4, nutrition: batchNutrition }],
    ['whole-recipe nutrition with ignored legacy basis', { servings: 4, nutrition: { ...batchNutrition, basisQuantity: 99 } }],
    ['metadata-only edit', { name: 'Renamed' }],
  ])('validates and forwards %s without rewriting the payload', async (_label, payload) => {
    expect(validate(payload), JSON.stringify(validate.errors)).toBe(true);
    const { request, rpc } = fixture();
    expect((await request('PATCH', payload)).status).toBe(200);
    expect(rpc).toHaveBeenCalledExactlyOnceWith('gpt_update_recipe', { p_recipe: uuid(1), p_patch: payload });
  });

  it.each([
    { ingredients: [{ ...base, id: 'not-a-uuid' }] },
    { ingredients: [{ ...base, id: 42 }] },
    { ingredients: [{ ...base, pinned_product: uuid(5) }] },
    { ingredients: [{ ...base, note: 42 }] },
    { ingredients: [{ id: uuid(10) }] },
    { ingredients: [] },
    { nutrition: 'clear' },
    { nutrition: { ...batchNutrition, basisQuantity: 0 } },
    { nutrition: { calories: 800 } },
    {},
  ])('rejects invalid or unsupported contract input %#', (payload) => {
    expect(validate(payload)).toBe(false);
  });

  it('maps actual GET rows into a valid duplicate reorder/edit while preserving distinct IDs', async () => {
    const { rows, request, rpc } = fixture();
    const single = await (await request('GET')).json();
    const list = await (await request('GET', undefined, '/v1/recipes')).json();
    expect(list.recipes[0]).toEqual(single.recipe);
    for (const [i, row] of single.recipe.ingredients.entries()) {
      expect(row).toMatchObject({ id: rows[i].id, note: rows[i].note, pinned_product: rows[i].pinned_product });
      expect(row.unit.id).toBe(uuid(4));
    }
    const payload = { ingredients: single.recipe.ingredients.toReversed().map((row: Omit<typeof rows[number], 'unit'> & { unit: { id: string } }, i: number) => ({
      id: row.id, foodId: row.ingredient, quantity: 20, unit: row.unit.id, sortOrder: i,
      // Deliberately omit notes/pins: SQL preserves each matched row's metadata.
    })) };
    expect(validate(payload), JSON.stringify(validate.errors)).toBe(true);
    expect(payload.ingredients.map((row: { id: string }) => row.id)).toEqual([uuid(11), uuid(10)]);
    await request('PATCH', payload);
    expect(rpc).toHaveBeenCalledExactlyOnceWith('gpt_update_recipe', { p_recipe: uuid(1), p_patch: payload });
  });

  it('permits mixing identified duplicates and an explicitly new row of the same food', async () => {
    const payload = { ingredients: [{ ...base, id: uuid(10) }, { ...base, id: uuid(11), sortOrder: 1 }, { ...base, id: null, sortOrder: 2 }] };
    expect(validate(payload), JSON.stringify(validate.errors)).toBe(true);
    const { request, rpc } = fixture();
    await request('PATCH', payload);
    expect(rpc.mock.calls[0][1]).toEqual({ p_recipe: uuid(1), p_patch: payload });
  });

  it('documents safe POST narrowing and PATCH identity without adding operations', () => {
    expect(Object.values(schema.paths).flatMap((methods) => Object.values(methods as object))).toHaveLength(30);
    expect(schema.paths['/v1/recipes/{id}'].patch.description).toContain('may reject ambiguous duplicates');
    expect(schema.paths['/v1/recipes/{id}'].patch.description).toContain('unit.id to unit');
    expect(schema.paths['/v1/recipes'].post.description).toContain('deliberately narrows legacy destructive upsert behavior');
    expect(schema.paths['/v1/recipes'].post.description).toContain('use editRecipe (PATCH)');
    expect(schema.paths['/v1/recipes'].post.requestBody.content['application/json'].schema.properties.ingredients.items.properties.id).toBeUndefined();
  });

  it('keeps POST routing and saved/id responses for new and existing recipe IDs', async () => {
    const { request, rpc } = fixture();
    const payload = { id: uuid(1), name: 'Saved recipe', servings: 2, ingredients: [base] };
    const result = { status: 'saved', id: uuid(1) };
    rpc.mockResolvedValueOnce({ data: result, error: null });
    const response = await request('POST', payload, '/v1/recipes');
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual(result);
    expect(rpc).toHaveBeenCalledExactlyOnceWith('gpt_save_recipe', { p_recipe: payload });
  });

  it('deprecates basisQuantity only for recipe PATCH while retaining legacy input', () => {
    const nutrition = patchSchema.properties.nutrition;
    expect(nutrition.required).not.toContain('basisQuantity');
    expect(nutrition.properties.basisQuantity.deprecated).toBe(true);
    expect(nutrition.properties.basisQuantity.description).toContain('whole-recipe nutrient totals');
    for (const [path, method] of [['/v1/foods', 'post'], ['/v1/foods/{id}', 'patch'], ['/v1/products', 'post'], ['/v1/products/{id}', 'patch'], ['/v1/recipes', 'post']]) {
      const other = schema.paths[path][method].requestBody.content['application/json'].schema.properties.nutrition;
      expect(other.required).toContain('basisQuantity');
      expect(other.properties.basisQuantity.deprecated).toBeUndefined();
    }
    expect(schema.components.schemas.Nutrition.required).toContain('basisQuantity');
    expect(schema.components.schemas.Nutrition.properties.basisQuantity.deprecated).toBeUndefined();
  });

  it('surfaces SQL ambiguity without retrying through destructive POST', async () => {
    const { request, rpc } = fixture();
    const message = 'Ambiguous duplicate ingredients; provide ingredient IDs or use the recipe editor';
    rpc.mockResolvedValueOnce({ data: null, error: { message } });
    const payload = { ingredients: [{ ...base, quantity: 30 }] };
    expect(validate(payload)).toBe(true); // Legacy shape remains compatible; SQL decides identity.
    await expect(request('PATCH', payload)).rejects.toMatchObject({ status: 422, message });
    expect(rpc).toHaveBeenCalledExactlyOnceWith('gpt_update_recipe', { p_recipe: uuid(1), p_patch: payload });
  });
});
