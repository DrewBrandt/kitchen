import { z } from 'zod';
import operations from './operation-schemas.json' with { type: 'json' };
import type { ToolSpec } from './tools.ts';

export const operationTools: ToolSpec[] = operations.map(operation => {
  let schema = z.fromJSONSchema(operation.schema as unknown as Parameters<typeof z.fromJSONSchema>[0]) as z.ZodObject;
  if (operation.method === 'PATCH') schema = schema.refine(args => Object.keys(args).some(key => key !== 'id'), 'Provide at least one changed field; read first.');
  if (operation.name === 'save_meal_plan') schema = schema.refine(args => args.mode !== 'replaceWeek' || Boolean(args.weekStart), 'replaceWeek requires weekStart and the complete seven-day replacement.');
  return { ...operation, method: operation.method as 'POST' | 'PATCH', schema };
});
