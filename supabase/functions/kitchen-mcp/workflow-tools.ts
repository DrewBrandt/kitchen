import { intentDescription } from './intent-guidance.ts';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';
import { correctionTools } from './corrections.ts';
import { plannedPreparationTool } from './preparation.ts';

const uuid = z.string().uuid();
type Args = Record<string, unknown>;
export const workflowTools = [
  plannedPreparationTool,
  ...correctionTools,
  {
    name: 'fulfill_planned_entry', rpc: 'consume_planned_meals',
    description: 'Log eating one exact saved plan entry and mark its planned consumption fulfilled, using the app transaction and its stock rules. Read get_plan first and use the entry ID, not its consumption ID. Does not cook a recipe: its batch must already be prepared. Requires actual eaten servings and an offset-bearing timestamp. Reuse requestId and identical arguments after an ambiguous failure; never also call generic consumption for this eating event.',
    schema: z.object({ requestId: uuid, planEntryId: uuid, servings: z.number().positive(), timestamp: z.string().datetime({ offset: true }) }).strict(),
    params: (a: Args) => ({ p_request_id: a.requestId, p_meal_plans: [a.planEntryId], p_servings: [a.servings], p_occurred_at: a.timestamp }),
    result: (data: unknown) => ({ foodLogIds: z.array(uuid).length(1).parse(data), status: 'fulfilled' }),
  },
  {
    name: 'discard_inventory_lot', rpc: 'set_inventory_lot_quantity',
    description: 'Discard some or all of one prepared-food or product inventory lot as waste, without logging eating. Read its current quantity first; remainingQuantity is the amount LEFT after discard, in the returned lot units (servings for prepared food), not the discarded amount. Zero discards all. Returns adjustmentEventId for undo. Reuse requestId with identical arguments after ambiguous failure. Does not undo preparation or restore its ingredients.',
    schema: z.object({ requestId: uuid, lotId: uuid, remainingQuantity: z.number().nonnegative(), reason: z.string().trim().min(1).max(1000) }).strict(),
    params: (a: Args) => ({ p_request_id: a.requestId, p_lot: a.lotId, p_remaining: a.remainingQuantity, p_discard: true, p_note: a.reason }),
    result: (data: unknown) => ({ adjustmentEventId: uuid.nullable().parse(data), status: data === null ? 'unchanged' : 'discarded' }),
  },
  {
    name: 'undo_inventory_adjustment', rpc: 'undo_inventory_adjustment',
    description: 'Undo one exact discard/waste or manual stock-adjustment event, restoring its stock effect through the app transaction. Use adjustmentEventId returned by discard_inventory_lot, not a lot, food-log or preparation ID. Repeated undo of that event has no additional effect. Cannot undo a receipt, consumption, or preparation. Read the affected lot back after success.',
    schema: z.object({ adjustmentEventId: uuid }).strict(),
    params: (a: Args) => ({ p_event: a.adjustmentEventId }),
    result: (data: unknown) => { z.union([z.null(), z.literal('')]).parse(data); return { status: 'undone' }; },
  },
];

export function registerWorkflowTools(server: McpServer, options: {
  supabaseUrl: string; anonKey: string; token: string; requestId: string; fetch: typeof fetch;
  audit: (event: { requestId: string; event: 'tool_call'; tool: string; status: number }) => void;
}) {
  for (const spec of workflowTools) server.registerTool(spec.name, {
    description: intentDescription(spec.name, spec.description), inputSchema: spec.schema,
    annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false },
    _meta: { securitySchemes: [{ type: 'oauth2', scopes: ['openid'] }] },
  }, async (input: unknown) => {
    let status = 502;
    try {
      const args = spec.schema.parse(input);
      // Same project and authenticated owner session used by is_app_owner. Never
      // send the OAuth token to pantry-api, arbitrary URLs, or through redirects.
      const response = await options.fetch(`${options.supabaseUrl}/rest/v1/rpc/${spec.rpc}`, {
        method: 'POST', redirect: 'error', signal: AbortSignal.timeout(20000),
        headers: { apikey: options.anonKey, authorization: `Bearer ${options.token}`, 'content-type': 'application/json' },
        body: JSON.stringify(spec.params(args)),
      });
      status = response.status;
      if (!response.ok) throw new Error('Transaction rejected');
      const data = response.status === 204 ? null : await response.json();
      const result = { ...spec.result(data), auditRequestId: options.requestId };
      options.audit({ requestId: options.requestId, event: 'tool_call', tool: spec.name, status });
      return { content: [{ type: 'text' as const, text: JSON.stringify(result) }], structuredContent: result };
    } catch {
      options.audit({ requestId: options.requestId, event: 'tool_call', tool: spec.name, status: status >= 400 ? status : 502 });
      const hint = 'failureHint' in spec ? spec.failureHint : '';
      return { isError: true, content: [{ type: 'text' as const, text: `Mise transaction was not confirmed. ${hint} Read back the affected plan/lot before retrying; check the exact ID, available stock and current status. Preserve the requestId and arguments for the same action. Reference: ${options.requestId}` }] };
    }
  });
}
