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
});
