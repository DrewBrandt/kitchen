import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { WebStandardStreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/webStandardStreamableHttp.js';
import { z } from 'zod';
import { authorize, isUuid, type AuthConfig, type IdentityProvider } from './auth.ts';
import { operatingRules, readTools, registerTools } from './tools.ts';
import { registerWorkflowTools } from './workflow-tools.ts';
import { operationTools } from './operations.ts';

export type Config = AuthConfig & { supabaseUrl: string; pantryToken: string; anonKey: string };
type Audit = { requestId: string; event: 'inventory_read' | 'request' | 'tool_call'; tool?: string; status: number; count?: number };
type Dependencies = { identity: IdentityProvider; fetch: typeof fetch; audit: (event: Audit) => void };
const argumentsSchema = z.object({
  limit: z.number().int().min(1).max(50).default(20),
  offset: z.number().int().min(0).max(2147483647).default(0),
  includeDepleted: z.boolean().default(false),
}).strict();

export function createHandler(config: Config, deps: Dependencies) {
  const resource = new URL(config.resource);
  const metadataUrl = new URL('./.well-known/oauth-protected-resource', resource).href;
  // Supabase gateways may strip /functions/v1 and/or the function slug.
  // These aliases affect routing only; the signed audience stays the full public URL.
  const routedPaths = (path: string) => [path, path.replace(/^\/functions\/v1/, ''), path.replace(/^\/functions\/v1\/kitchen-mcp/, '')];
  const resourcePaths = routedPaths(resource.pathname);
  const metadataPaths = routedPaths(new URL(metadataUrl).pathname);
  const ready = Boolean(isUuid(config.ownerId) && isUuid(config.clientId) && config.pantryToken && config.anonKey &&
    resource.protocol === 'https:' && config.issuer === `${config.supabaseUrl}/auth/v1` &&
    config.resource === `${config.supabaseUrl}/functions/v1/kitchen-mcp/mcp`);
  return async (request: Request): Promise<Response> => {
    const requestId = crypto.randomUUID();
    const finish = (response: Response) => {
      response.headers.set('cache-control', 'no-store');
      response.headers.set('x-request-id', requestId);
      deps.audit({ requestId, event: 'request', status: response.status });
      return response;
    };
    const json = (body: unknown, status: number, headers = {}) =>
      finish(new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json', ...headers } }));
    if (!ready) return json({ error: 'Prototype setup incomplete' }, 503);
    const url = new URL(request.url);
    if (request.headers.has('origin') && request.headers.get('origin') !== 'https://chatgpt.com')
      return json({ error: 'Forbidden' }, 403);
    if (metadataPaths.includes(url.pathname) && request.method === 'GET') {
      return json({ resource: config.resource, authorization_servers: [config.issuer],
        scopes_supported: ['openid'], bearer_methods_supported: ['header'], resource_name: 'Kitchen' }, 200);
    }
    if (!resourcePaths.includes(url.pathname)) return json({ error: 'Not found' }, 404);
    const challenge = { 'www-authenticate': `Bearer resource_metadata="${metadataUrl}", scope="openid"` };
    const token = /^Bearer ([^\s]+)$/i.exec(request.headers.get('authorization') ?? '')?.[1] ?? '';
    try {
      if (!await authorize(token, config, deps.identity)) return json({ error: 'Unauthorized' }, 401, challenge);
    } catch { return json({ error: 'Unauthorized' }, 401, challenge); }
    if (request.method !== 'POST') return json({ error: 'Method not allowed' }, 405, { allow: 'POST' });

    const server = new McpServer({ name: 'kitchen', version: '0.4.0' }, { instructions: operatingRules });
    registerTools(server, [...readTools, ...operationTools], { ...config, fetch: deps.fetch, requestId, audit: deps.audit });
    registerWorkflowTools(server, { ...config, token, fetch: deps.fetch, requestId, audit: deps.audit });
    server.registerTool('get_inventory', {
      title: 'Read Kitchen inventory',
      description: 'Read product-backed inventory lots, at most 50 per page. Use nextOffset until hasMore is false. Prepared lots are excluded. Pages are live, not a snapshot; restart if inventory changes. Never interpret a partial page as the full inventory.',
      inputSchema: argumentsSchema,
      annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
      _meta: { securitySchemes: [{ type: 'oauth2', scopes: ['openid'] }] },
    }, async (args) => {
      try {
        const page = argumentsSchema.parse(args);
        const upstream = new URL(`${config.supabaseUrl}/functions/v1/pantry-api/v1/inventory`);
        upstream.search = new URLSearchParams({ limit: String(page.limit), offset: String(page.offset), includeDepleted: String(page.includeDepleted) }).toString();
        // Fixed GET only. Never forward the caller's token to the legacy API.
        const response = await deps.fetch(upstream, { method: 'GET', redirect: 'error',
          headers: { authorization: `Bearer ${config.pantryToken}` }, signal: AbortSignal.timeout(15000) });
        if (!response.ok) throw new Error('Inventory unavailable');
        const body = await response.json();
        if (!Array.isArray(body.lots) || body.lots.length > page.limit || body.limit !== page.limit ||
            body.offset !== page.offset || !Number.isSafeInteger(body.total) || body.total < 0 ||
            typeof body.hasMore !== 'boolean' ||
            (body.hasMore ? body.lots.length === 0 || body.nextOffset !== page.offset + body.lots.length : body.nextOffset !== null))
          throw new Error('Invalid inventory page');
        // Do not relay upstream headers, errors or arbitrary top-level fields.
        const result = { exportedAt: body.exportedAt, lots: body.lots, limit: page.limit, offset: page.offset,
          total: body.total, hasMore: body.hasMore, nextOffset: body.nextOffset, requestId };
        deps.audit({ requestId, event: 'inventory_read', status: 200, count: body.lots.length });
        return { content: [{ type: 'text' as const, text: JSON.stringify(result) }], structuredContent: result };
      } catch {
        deps.audit({ requestId, event: 'inventory_read', status: 502 });
        return { isError: true, content: [{ type: 'text' as const, text: `Inventory unavailable. Reference: ${requestId}` }] };
      }
    });
    const transport = new WebStandardStreamableHTTPServerTransport({ sessionIdGenerator: undefined, enableJsonResponse: true, maxRequestBodySize: 16384 });
    try {
      await server.connect(transport);
      return finish(await transport.handleRequest(request));
    } catch { return json({ error: 'MCP request failed' }, 500); }
    finally { await server.close(); }
  };
}
