import { describe, expect, it } from 'vitest';
import { parse } from 'yaml';
import instructions from '../docs/PANTRY_GPT_INSTRUCTIONS.md?raw';
import schemaText from '../docs/pantry-gpt-openapi.yaml?raw';
import edgeFunction from '../supabase/functions/pantry-api/index.ts?raw';

describe('Pantry GPT operator pack', () => {
  const schema = parse(schemaText);

  it('fits the Custom GPT instruction limit', () => {
    expect(instructions.length).toBeLessThanOrEqual(8_000);
  });

  it('targets the deployed Supabase function with unique, implemented operations', () => {
    expect(schema.openapi).toBe('3.1.0');
    expect(schema.servers[0].url).toBe('https://xaetuqdtnolzspfvqvja.supabase.co/functions/v1/pantry-api');
    expect(schemaText).not.toContain('cloudfunctions.net');
    expect(schemaText).not.toContain('/v1/calendar/');

    const operationIds: string[] = [];
    for (const [route, methods] of Object.entries(schema.paths as Record<string, Record<string, Record<string, unknown>>>)) {
      expect(edgeFunction.includes(`"${route}"`) || route.endsWith('/{id}')).toBe(true);
      for (const [method, operation] of Object.entries(methods)) {
        operationIds.push(String(operation.operationId));
        if (method !== 'get') expect(operation['x-openai-isConsequential']).toBe(true);
      }
    }
    expect(new Set(operationIds).size).toBe(operationIds.length);
    expect(operationIds.length).toBeLessThanOrEqual(30);
  });

  it('exposes every write body directly without importer-hostile references', () => {
    const writes: Array<{ route: string; method: string; operation: Record<string, unknown> }> = [];
    for (const [route, methods] of Object.entries(schema.paths as Record<string, Record<string, Record<string, unknown>>>)) {
      for (const [method, operation] of Object.entries(methods)) {
        if (method !== 'get') writes.push({ route, method, operation });
      }
    }

    expect(writes).toHaveLength(20);
    for (const { route, method, operation } of writes) {
      const requestBody = operation.requestBody as Record<string, any>;
      expect(requestBody, `${method.toUpperCase()} ${route} must have a request body`).toBeDefined();
      expect(requestBody.$ref, `${method.toUpperCase()} ${route} request body must be inline`).toBeUndefined();
      expect(JSON.stringify(requestBody), `${method.toUpperCase()} ${route} request body must contain no nested refs`).not.toContain('"$ref"');
      const bodySchema = requestBody.content?.['application/json']?.schema;
      expect(bodySchema?.type, `${method.toUpperCase()} ${route} body must be an object`).toBe('object');
      expect(Object.keys(bodySchema?.properties ?? {}).length, `${method.toUpperCase()} ${route} must expose fields`).toBeGreaterThan(0);
      expect((bodySchema?.required?.length ?? 0) > 0 || bodySchema?.minProperties > 0,
        `${method.toUpperCase()} ${route} must reject an empty object`).toBe(true);
    }
    expect(schema.components.requestBodies).toBeUndefined();
  });

  it.each([
    ['/v1/inventory', 'reconcilePantryInventory', ['replacements']],
    ['/v1/groceries', 'addGroceryHaul', ['items']],
    ['/v1/recipes', 'saveRecipe', ['name', 'servings', 'ingredients']],
    ['/v1/plans', 'replaceWeeklyMealPlan', ['weekStart', 'entries']],
    ['/v1/targets', 'saveNutritionTargets', ['calories', 'proteinG', 'carbsG', 'fatG', 'fiberG', 'sodiumMg']],
    ['/v1/preferences', 'saveFoodPreferences', ['allergies', 'dislikes', 'favorites', 'dietaryRules', 'planningNotes']],
    ['/v1/routine', 'savePersonalRoutine', ['timeZone', 'days', 'dinnerWindow', 'commuteMinutes', 'preparationBufferMinutes']],
  ])('exposes all required arguments for %s', (route, operationId, required) => {
    const operation = schema.paths[route].post;
    expect(operation.operationId).toBe(operationId);
    expect(operation.requestBody.content['application/json'].schema.required).toEqual(required);
  });

  it('maps weekly-plan body fields to the parameterized database function', () => {
    expect(edgeFunction).toContain('p_week_start: requiredString(input.weekStart, "weekStart")');
    expect(edgeFunction).toContain('p_entries: requiredArray(input.entries, "entries")');
  });

  it('exposes purchased-product consumption inputs directly to the Action importer', () => {
    const operation = schema.paths['/v1/consume/product'].post;
    const bodySchema = operation.requestBody.content['application/json'].schema;

    expect(operation.requestBody.$ref).toBeUndefined();
    expect(bodySchema.$ref).toBeUndefined();
    expect(bodySchema.type).toBe('object');
    expect(bodySchema.required).toEqual(['productId', 'purchasedQuantity', 'consumedQuantity']);
    expect(Object.keys(bodySchema.properties)).toEqual(
      expect.arrayContaining(['productId', 'purchasedQuantity', 'consumedQuantity', 'location', 'timestamp', 'totalCost', 'costIsEstimated', 'costSource', 'label', 'note']),
    );
  });

  it('supports direct manual consumption without definition or inventory IDs', () => {
    const operation = schema.paths['/v1/consume/manual'].post;
    const bodySchema = operation.requestBody.content['application/json'].schema;

    expect(operation.operationId).toBe('logManualConsumption');
    expect(bodySchema.required).toEqual(['label']);
    expect(Object.keys(bodySchema.properties)).toEqual(
      expect.arrayContaining(['label', 'portionLabel', 'timestamp', 'nutrition', 'cost', 'costIsEstimated', 'costSource', 'note']),
    );
    expect(bodySchema.properties).not.toHaveProperty('productId');
    expect(bodySchema.properties).not.toHaveProperty('foodId');
  });

  it.each([
    ['/v1/foods', ['name', 'measureStyle', 'displayUnit']],
    ['/v1/products', ['foodId', 'name', 'packageQuantity', 'packageUnit']],
  ])('exposes definition inputs directly for %s', (route, required) => {
    const requestBody = schema.paths[route].post.requestBody;
    expect(requestBody.$ref).toBeUndefined();
    expect(requestBody.content['application/json'].schema.type).toBe('object');
    expect(requestBody.content['application/json'].schema.required).toEqual(required);
  });

  it.each([
    ['/v1/foods/{id}', 'editFoodDefinition'],
    ['/v1/products/{id}', 'editProductDefinition'],
    ['/v1/recipes/{id}', 'editRecipe'],
    ['/v1/lots/{id}', 'editInventoryLot'],
    ['/v1/history/{id}', 'editConsumptionEvent'],
  ])('exposes an inline partial-edit contract for %s', (route, operationId) => {
    const operation = schema.paths[route].patch;
    const bodySchema = operation.requestBody.content['application/json'].schema;
    expect(operation.operationId).toBe(operationId);
    expect(operation['x-openai-isConsequential']).toBe(true);
    expect(operation.requestBody.$ref).toBeUndefined();
    expect(bodySchema.type).toBe('object');
    expect(bodySchema.minProperties).toBe(1);
    expect(bodySchema.additionalProperties).toBe(false);
  });

  it('exposes in-place purchase cost correction without a relog operation', () => {
    const properties = schema.paths['/v1/history/{id}'].patch.requestBody.content['application/json'].schema.properties;
    expect(properties).toHaveProperty('purchaseTotalCost');
    expect(properties).toHaveProperty('costIsEstimated');
    expect(properties).toHaveProperty('costSource');
    expect(schemaText).not.toContain('/v1/relog');
  });

  it('contains no legacy outside-food catalog or fake-product log operation', () => {
    expect(schema.paths['/v1/external-foods']).toBeUndefined();
    expect(schema.paths['/v1/meals']).toBeUndefined();
    expect(schemaText).not.toContain('externalFoodId');
    expect(schemaText).not.toContain('saveOutsideFood');
  });
});
