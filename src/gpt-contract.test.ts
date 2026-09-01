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

  it('contains no legacy outside-food or direct custom-log operations', () => {
    expect(schema.paths['/v1/external-foods']).toBeUndefined();
    expect(schema.paths['/v1/meals']).toBeUndefined();
    expect(schemaText).not.toContain('externalFoodId');
    expect(schemaText).not.toContain('saveOutsideFood');
    expect(schemaText).not.toContain('logMealWithoutInventoryDeduction');
  });
});
