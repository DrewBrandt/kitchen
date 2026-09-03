import { describe, expect, it } from 'vitest';
import { parse } from 'yaml';
import instructions from '../docs/PANTRY_GPT_INSTRUCTIONS.md?raw';
import schemaText from '../docs/pantry-gpt-openapi.yaml?raw';
import edgeFunction from '../supabase/functions/pantry-api/index.ts?raw';

describe('Pantry GPT operator pack', () => {
  const schema = parse(schemaText);

  it('fits the Custom GPT instruction limit', () => {
    expect(instructions.replace(/\r\n/g, '\n').length).toBeLessThanOrEqual(8_000);
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
        if (method !== 'get' && route !== '/v1/plans/preview') expect(operation['x-openai-isConsequential']).toBe(true);
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

    expect(writes).toHaveLength(21);
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
    ['/v1/inventory', 'reconcilePantryInventory', ['requestId', 'replacements']],
    ['/v1/groceries', 'addGroceryHaul', ['requestId', 'source', 'items']],
    ['/v1/recipes', 'saveRecipe', ['name', 'servings', 'ingredients']],
    ['/v1/plans', 'saveMealPlan', ['mode', 'entries']],
    ['/v1/targets', 'saveNutritionTargets', ['calories', 'proteinG', 'carbsG', 'fatG', 'fiberG', 'sodiumMg']],
    ['/v1/preferences', 'saveFoodPreferences', ['allergies', 'dislikes', 'favorites', 'dietaryRules', 'planningNotes']],
  ])('exposes all required arguments for %s', (route, operationId, required) => {
    const operation = schema.paths[route].post;
    expect(operation.operationId).toBe(operationId);
    expect(operation.requestBody.content['application/json'].schema.required).toEqual(required);
  });

  it('maps additive and replacement plan writes to one parameterized database function', () => {
    expect(edgeFunction).toContain('db.rpc("gpt_save_plan"');
    expect(edgeFunction).toContain('p_mode: mode');
    expect(edgeFunction).toContain('mode === "replaceWeek" ? requiredString(input.weekStart, "weekStart") : null');
    expect(edgeFunction).toContain('p_entries: requiredArray(input.entries, "entries")');
    const planSchema = schema.paths['/v1/plans'].post.requestBody.content['application/json'].schema;
    expect(planSchema.properties.mode.enum).toEqual(['append', 'replaceWeek']);
    expect(planSchema.properties.entries.items.required).toContain('plannedServings');
    expect(planSchema.properties.entries.items.properties.source.enum)
      .toEqual(['recipe', 'meal', 'product', 'inventoryLot']);
    expect(planSchema.properties.entries.items.properties).toHaveProperty('consumeFromInventory');
  });

  it('previews any date without marking the read-only POST consequential', () => {
    const operation = schema.paths['/v1/plans/preview'].post;
    const candidate = operation.requestBody.content['application/json'].schema.properties.candidate;
    expect(operation.operationId).toBe('previewDailyNutrition');
    expect(operation['x-openai-isConsequential']).toBeUndefined();
    expect(candidate.required).toEqual(['label', 'sourceType', 'servings']);
    expect(candidate.properties.sourceType.enum).toEqual(['product', 'recipe', 'custom']);
    expect(candidate.properties.nutritionPerServing.properties).toHaveProperty('source');
    expect(edgeFunction).toContain('db.rpc("gpt_preview_daily_nutrition"');
    expect(edgeFunction).toContain('readableNumbers(unwrap(await db.rpc("gpt_preview_daily_nutrition"');
  });

  it('keeps routine read-only in the GPT to stay within the 30-operation importer limit', () => {
    expect(schema.paths['/v1/routine'].get.operationId).toBe('getPersonalRoutine');
    expect(schema.paths['/v1/routine'].post).toBeUndefined();
  });

  it('exposes purchased-product consumption inputs directly to the Action importer', () => {
    const operation = schema.paths['/v1/consume/product'].post;
    const bodySchema = operation.requestBody.content['application/json'].schema;

    expect(operation.requestBody.$ref).toBeUndefined();
    expect(bodySchema.$ref).toBeUndefined();
    expect(bodySchema.type).toBe('object');
    expect(bodySchema.required).toEqual([
      'requestId', 'productId', 'purchasedQuantity', 'consumedQuantity', 'quantityUnit', 'acquisitionType',
      'totalPrice', 'outOfPocketCost', 'paidBy', 'costIsEstimated', 'costSource',
      'priceAsOf', 'timestamp', 'timePrecision',
    ]);
    expect(Object.keys(bodySchema.properties)).toEqual(
      expect.arrayContaining(['requestId', 'productId', 'purchasedQuantity', 'consumedQuantity', 'quantityUnit', 'acquisitionType', 'location', 'timestamp', 'totalPrice', 'outOfPocketCost', 'paidBy', 'costIsEstimated', 'costSource', 'priceAsOf', 'label', 'note']),
    );
    expect(bodySchema.properties.acquisitionType.enum).toEqual(['grocery', 'restaurant', 'takeout', 'office', 'gift', 'home', 'other']);
    expect(edgeFunction).toContain('const acquisitionType = requiredString(input.acquisitionType, "acquisitionType")');
    expect(edgeFunction).toContain('p_acquisition_type: acquisitionType');
    expect(edgeFunction).toContain('p_quantity_unit: requiredString(input.quantityUnit, "quantityUnit")');
    expect(edgeFunction).toContain('const totalPrice = requiredNullableNonnegativeNumber(input, "totalPrice")');
    expect(edgeFunction).toContain('p_total_price: totalPrice');
    expect(edgeFunction).toContain('p_request_id: requiredString(input.requestId, "requestId")');
  });

  it('can target an exact inventory lot instead of silently choosing FEFO', () => {
    const properties = schema.paths['/v1/consume/inventory'].post.requestBody
      .content['application/json'].schema.properties;
    expect(properties.lotId).toMatchObject({ type: 'string', format: 'uuid' });
    expect(edgeFunction).toContain('p_lot: input.lotId ?? null');
    expect(instructions).toMatch(/pass `lotId`\s+for a known package/);
  });

  it('requires grocery price provenance instead of silently creating unpriced lots', () => {
    const bodySchema = schema.paths['/v1/groceries'].post.requestBody.content['application/json'].schema;
    const itemSchema = bodySchema.properties.items.items;

    expect(bodySchema.required).toEqual(['requestId', 'source', 'items']);
    expect(itemSchema.required).toEqual(['productId', 'quantity', 'unit', 'totalPrice', 'outOfPocketCost', 'paidBy', 'costIsEstimated', 'priceAsOf', 'acquiredAt', 'acquiredTimePrecision']);
    expect(edgeFunction).toContain('const source = requiredString(input.source, "source")');
    expect(edgeFunction).toContain('requiredBoolean(row.costIsEstimated');
  });

  it('supports direct manual consumption without definition or inventory IDs', () => {
    const operation = schema.paths['/v1/consume/manual'].post;
    const bodySchema = operation.requestBody.content['application/json'].schema;

    expect(operation.operationId).toBe('logManualConsumption');
    expect(bodySchema.required).toEqual(['requestId', 'label', 'timestamp', 'timePrecision', 'components', 'acquisitionType', 'totalPrice', 'outOfPocketCost', 'paidBy', 'costIsEstimated', 'costSource', 'priceAsOf']);
    expect(Object.keys(bodySchema.properties)).toEqual(
      expect.arrayContaining(['requestId', 'label', 'portionLabel', 'timestamp', 'timePrecision', 'nutrition', 'nutritionEstimate', 'components', 'acquisitionType', 'totalPrice', 'outOfPocketCost', 'paidBy', 'priceAsOf', 'costIsEstimated', 'costSource', 'note']),
    );
    expect(bodySchema.properties).not.toHaveProperty('productId');
    expect(bodySchema.properties).not.toHaveProperty('foodId');
    expect(bodySchema.properties.components.minItems).toBe(1);
    expect(edgeFunction).toContain('requiredNonemptyArray(input.components, "components")');
    expect(edgeFunction).toContain('requireEstimateMetadata(nutrition, nutritionEstimate)');
    expect(edgeFunction).toContain('requirePurchasedPrice(acquisitionType, totalPrice)');
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

  it('saves researched product cost metadata during product creation', () => {
    const properties = schema.paths['/v1/products'].post.requestBody.content['application/json'].schema.properties;
    expect(properties).toHaveProperty('estimatedCost');
    expect(properties).toHaveProperty('costSource');
    expect(properties).toHaveProperty('costAsOf');
    expect(edgeFunction).toContain('const costFields = estimatedCost === null ? {}');
    expect(edgeFunction).toContain('estimated_cost: estimatedCost');
    expect(edgeFunction).toContain('cost_as_of: input.costAsOf');
  });

  it('exposes always-available food status for creation and partial edits', () => {
    expect(schema.paths['/v1/foods'].post.requestBody.content['application/json'].schema.properties)
      .toHaveProperty('alwaysAvailable');
    expect(schema.paths['/v1/foods/{id}'].patch.requestBody.content['application/json'].schema.properties)
      .toHaveProperty('alwaysAvailable');
    expect(edgeFunction).toContain('always_available: Boolean(input.alwaysAvailable)');
  });

  it('requires recipe-friendly volume measures for convertible staples', () => {
    expect(instructions).toContain('Write weight-stocked staples in practical kitchen volume units');
    expect(instructions).toContain('Do not save tiny gram quantities');
    expect(instructions).toContain('supported conversion allows `1/2 tsp`');
  });

  it('requires source-backed research before reusable-product nutrition is omitted', () => {
    expect(instructions).toContain('web research is required: use its barcode');
    expect(instructions).toMatch(/Do this before\s+asking Drew or leaving it unresolved/);
    expect(instructions).toContain('preserve the source URL or citation in `nutrition.source`');
    expect(instructions).toContain('Omit reusable-product nutrition only after a');
    expect(instructions).toContain('“do not guess” is not permission to leave it empty');
  });

  it('requires price research or a user question before a paid write', () => {
    expect(instructions).toContain('Cost is mandatory for a purchase or paid meal');
    expect(instructions).toContain('research');
    expect(instructions).toContain('the exact product and store/current retailer price');
    expect(instructions).toContain('never silently omit cost because a field is');
    expect(instructions).toContain('Record full `totalPrice`');
    expect(instructions).toContain("Drew's `outOfPocketCost`, `paidBy`");
    expect(instructions).toContain('`costIsEstimated`, source, and `priceAsOf`');
  });

  it('supports historical preparation timestamps', () => {
    const properties = schema.paths['/v1/prepare/recipe'].post.requestBody.content['application/json'].schema.properties;
    expect(properties).toHaveProperty('preparedAt');
    expect(properties).toHaveProperty('sourceType');
    expect(properties).toHaveProperty('requestId');
    expect(edgeFunction).toContain('p_prepared_at: requiredString(input.preparedAt, "preparedAt")');
    expect(instructions).toContain('For a backfill, send the actual `preparedAt`');
  });

  it('searches exact product identity fields and aliases as part of food lookup', () => {
    expect(edgeFunction).toContain('const normalizeSearch');
    expect(edgeFunction).toContain('product.name, product.brand, product.barcode');
    expect(edgeFunction).toContain('...((product.aliases as string[] | null) ?? [])');
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
    expect(properties).toHaveProperty('purchaseTotalPrice');
    expect(properties).toHaveProperty('purchaseOutOfPocketCost');
    expect(properties).toHaveProperty('purchasePaidBy');
    expect(properties).toHaveProperty('purchasePriceAsOf');
    expect(properties).toHaveProperty('costIsEstimated');
    expect(properties).toHaveProperty('costSource');
    expect(schemaText).not.toContain('/v1/relog');
  });

  it('exposes an auditable consumption void that reverses inventory effects', () => {
    const operation = schema.paths['/v1/history/void'].post;
    const bodySchema = operation.requestBody.content['application/json'].schema;
    expect(operation.operationId).toBe('voidConsumptionEvent');
    expect(operation['x-openai-isConsequential']).toBe(true);
    expect(bodySchema.required).toEqual(['id', 'reason']);
    expect(edgeFunction).toContain('db.rpc("gpt_void_consumption"');
    expect(instructions).toContain('call void-consumption with its');
  });

  it('contains no legacy outside-food catalog or fake-product log operation', () => {
    expect(schema.paths['/v1/external-foods']).toBeUndefined();
    expect(schema.paths['/v1/meals']).toBeUndefined();
    expect(schemaText).not.toContain('externalFoodId');
    expect(schemaText).not.toContain('saveOutsideFood');
  });
});
