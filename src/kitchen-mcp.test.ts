// @vitest-environment node
import { generateKeyPairSync, sign } from 'node:crypto';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import { describe, expect, it, vi } from 'vitest';
import { createHandler, type Config } from '../supabase/functions/kitchen-mcp/handler';
import { operationTools } from '../supabase/functions/kitchen-mcp/operations';
import { readTools } from '../supabase/functions/kitchen-mcp/tools';
import { createIdentityProvider } from '../supabase/functions/kitchen-mcp/identity';

const config: Config = {
  supabaseUrl: 'https://synthetic.supabase.co', issuer: 'https://synthetic.supabase.co/auth/v1',
  resource: 'https://synthetic.supabase.co/functions/v1/kitchen-mcp/mcp',
  ownerId: '10000000-0000-4000-8000-000000000001', clientId: '10000000-0000-4000-8000-000000000002', pantryToken: 'synthetic-server-secret',
};
const { publicKey, privateKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const jwk = { ...publicKey.export({ format: 'jwk' }), alg: 'RS256', use: 'sig', kid: 'fixture-key' };
const encode = (value: unknown) => Buffer.from(JSON.stringify(value)).toString('base64url');
function token(overrides: Record<string, unknown> = {}) {
  const data = `${encode({ alg: 'RS256', typ: 'JWT', kid: jwk.kid })}.${encode({
    sub: config.ownerId, iss: config.issuer, aud: config.resource, role: 'authenticated',
    client_id: config.clientId, scope: 'openid', is_anonymous: false,
    session_id: '10000000-0000-4000-8000-000000000003',
    iat: Math.floor(Date.now() / 1000), exp: Math.floor(Date.now() / 1000) + 3600, ...overrides,
  })}`;
  return `${data}.${sign('RSA-SHA256', Buffer.from(data), privateKey).toString('base64url')}`;
}
function fixture(options: { owner?: boolean; anonymous?: boolean; confirmed?: boolean; userId?: string; sessionMissing?: boolean; config?: Partial<Config> } = {}) {
  const authFetch = vi.fn<typeof fetch>(async (input) => {
    const url = String(input);
    if (url.endsWith('/.well-known/jwks.json')) return Response.json({ keys: [jwk] });
    if (url.endsWith('/user')) return options.sessionMissing
      ? Response.json({ code: 'session_not_found', msg: 'Session missing' }, { status: 403 })
      : Response.json({ id: options.userId ?? config.ownerId, is_anonymous: options.anonymous ?? false,
        email_confirmed_at: options.confirmed === false ? null : '2026-10-01T00:00:00Z' });
    if (url.endsWith('/rpc/is_app_owner')) return Response.json(options.owner ?? true);
    throw new Error('Unexpected auth route');
  });
  const upstream = vi.fn<typeof fetch>(async (input) => {
    const url = new URL(String(input));
    const limit = Number(url.searchParams.get('limit')), offset = Number(url.searchParams.get('offset'));
    const lots = Array.from({ length: 53 }, (_, i) => ({ lotId: `fixture-${i}`, food: 'Synthetic rice', quantityBase: 100, baseUnit: 'g' })).slice(offset, offset + limit);
    const hasMore = offset + lots.length < 53;
    return Response.json({ exportedAt: '2026-10-03T00:00:00Z', lots, limit, offset, total: 53, hasMore, nextOffset: hasMore ? offset + lots.length : null });
  });
  const audit = vi.fn();
  const handler = createHandler({ ...config, ...options.config }, {
    identity: createIdentityProvider(config.supabaseUrl, 'synthetic-public-key', authFetch), fetch: upstream, audit,
  });
  const rpc = (method: string, params?: unknown, bearer: string | null = token(), headers = {}) => handler(new Request(config.resource, {
    method: 'POST', headers: { 'content-type': 'application/json', accept: 'application/json, text/event-stream',
      ...(bearer ? { authorization: `Bearer ${bearer}` } : {}), ...headers },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }),
  }));
  return { handler, rpc, upstream, audit, authFetch };
}

describe('Kitchen MCP synthetic contract', () => {
  it('requires owner authentication for writes and preserves the domain retry ID', async () => {
    const f=fixture(); const args={requestId:'10000000-0000-4000-8000-000000000011',batchId:'10000000-0000-4000-8000-000000000012',servings:1,timestamp:'2026-10-04T12:30:00-04:00',timePrecision:'exact'};
    const params={name:'consume_prepared',arguments:args};
    expect((await f.rpc('tools/call',params,null)).status).toBe(401);
    expect((await f.rpc('tools/call',params,token({sub:'10000000-0000-4000-8000-000000000099'}))).status).toBe(401);
    expect(f.upstream).not.toHaveBeenCalled();
    f.upstream.mockResolvedValue(Response.json({status:'consumed',id:'synthetic-event'}));
    const reply=await f.rpc('tools/call',params);expect(reply.status).toBe(200);
    expect((await reply.json()).result.structuredContent.result.status).toBe('consumed');
    expect(f.upstream).toHaveBeenCalledTimes(1);
    expect(JSON.parse(String(f.upstream.mock.calls[0][1]?.body))).toEqual(args);
  });
  it.each(['/functions/v1/kitchen-mcp', '/kitchen-mcp', ''])('routes gateway prefix %s without changing the public audience', async prefix => {
    const f = fixture();
    const metadata = await f.handler(new Request(`https://synthetic.supabase.co${prefix}/.well-known/oauth-protected-resource`));
    expect(metadata.status).toBe(200);
    expect(await metadata.json()).toMatchObject({ resource: config.resource });
    const request = (bearer?: string) => new Request(`https://synthetic.supabase.co${prefix}/mcp`, { method: 'POST', headers: {
      'content-type': 'application/json', accept: 'application/json, text/event-stream', ...(bearer ? { authorization: `Bearer ${bearer}` } : {}),
    }, body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/list' }) });
    expect((await f.handler(request())).status).toBe(401);
    expect((await f.handler(request(token({ aud: `https://synthetic.supabase.co${prefix}/mcp?wrong` })))).status).toBe(401);
    const result = await f.handler(request(token()));
    expect(result.status).toBe(200);
    expect((await result.json()).result.tools.map((t: { name: string }) => t.name)).toEqual([...readTools.map(t => t.name), ...operationTools.map(t => t.name), 'get_inventory']);
  });
  it('interoperates with the official client: initialize, discovery, bounded pages and continuation', async () => {
    const f = fixture();
    const client = new Client({ name: 'synthetic-test', version: '1' });
    const transport = new StreamableHTTPClientTransport(new URL(config.resource), {
      requestInit: { headers: { authorization: `Bearer ${token()}` } },
      fetch: (input, init) => f.handler(new Request(input, init)),
    });
    await client.connect(transport);
    try {
      const tools = await client.listTools();
      expect(tools.tools.map(t => t.name)).toEqual([...readTools.map(t => t.name), ...operationTools.map(t => t.name), 'get_inventory']);
      expect(tools.tools[0].annotations).toMatchObject({ readOnlyHint: true, destructiveHint: false });
      const first = await client.callTool({ name: 'get_inventory', arguments: { limit: 50 } });
      const firstPage = first.structuredContent as Record<string, unknown>;
      expect(first.isError).not.toBe(true);
      expect(first.structuredContent).toMatchObject({ limit: 50, offset: 0, total: 53, hasMore: true, nextOffset: 50 });
      expect(firstPage.lots).toHaveLength(50);
      const last = await client.callTool({ name: 'get_inventory', arguments: { limit: 50, offset: 50 } });
      expect(last.structuredContent).toMatchObject({ hasMore: false, nextOffset: null });
      expect((last.structuredContent as Record<string, unknown>).lots).toHaveLength(3);
      for (const [url, init] of f.upstream.mock.calls) {
        expect(String(url)).toContain('/pantry-api/v1/inventory?');
        expect(init).toMatchObject({ method: 'GET', redirect: 'error', headers: { authorization: 'Bearer synthetic-server-secret' } });
      }
      expect(f.audit).toHaveBeenCalledWith(expect.objectContaining({ requestId: firstPage.requestId, event: 'inventory_read', count: 50 }));
    } finally { await client.close(); }
  });

  it.each([
    ['other owner', { sub: 'other-user' }], ['wrong issuer', { iss: 'https://other.invalid' }],
    ['ordinary app token', { aud: 'authenticated' }], ['other client', { client_id: 'other-client' }],
    ['expired', { exp: 1 }], ['future token', { nbf: 9999999999 }],
    ['anonymous identity', { is_anonymous: true }], ['privileged role', { role: 'service_role' }],
    ['missing scope', { scope: '' }],
    ['missing session', { session_id: undefined }], ['invalid session', { session_id: 'not-a-session' }],
    ['nil session', { session_id: '00000000-0000-0000-0000-000000000000' }],
    ['future issuance', { iat: 9999999999 }], ['missing anonymous claim', { is_anonymous: undefined }],
  ])('rejects %s before reading inventory', async (_name, claims) => {
    const f = fixture(); const response = await f.rpc('tools/list', {}, token(claims));
    expect(response.status).toBe(401); expect(f.upstream).not.toHaveBeenCalled();
  });
  it('rejects missing and forged signatures, with protected resource discovery', async () => {
    const f = fixture();
    for (const bearer of [null, `${token().split('.').slice(0, 2).join('.')}.AAAA`]) {
      const response = await f.rpc('tools/list', {}, bearer);
      expect(response.status).toBe(401);
      expect(response.headers.get('www-authenticate')).toContain('resource_metadata=');
    }
    const metadata = await f.handler(new Request('https://synthetic.supabase.co/functions/v1/kitchen-mcp/.well-known/oauth-protected-resource'));
    expect(await metadata.json()).toMatchObject({ resource: config.resource, scopes_supported: ['openid'] });
    expect(f.upstream).not.toHaveBeenCalled();
  });
  it.each([{ owner: false }, { anonymous: true }, { confirmed: false }, { userId: 'other-user' }, { sessionMissing: true }])('preserves live owner checks (%j)', async (options) => {
    const f = fixture(options); expect((await f.rpc('tools/list')).status).toBe(401);
    expect(f.upstream).not.toHaveBeenCalled();
  });
  it.each([{ limit: 0 }, { limit: 51 }, { limit: 1.5 }, { offset: -1 }, { offset: 2147483648 }, { includeDepleted: 'true' }, { url: 'https://other.invalid' }])('rejects invalid tool arguments (%j)', async (args) => {
    const f = fixture(); const response = await f.rpc('tools/call', { name: 'get_inventory', arguments: args });
    const body = await response.json(); expect(body.error || body.result?.isError).toBeTruthy();
    expect(f.upstream).not.toHaveBeenCalled();
  });
  it('rejects unknown tools and defaults inventory to a bounded active page', async () => {
    const f = fixture(); const unknown = await f.rpc('tools/call', { name: 'update_inventory', arguments: {} });
    const body = await unknown.json(); expect(body.error || body.result?.isError).toBeTruthy();
    expect(f.upstream).not.toHaveBeenCalled();
    const response = await f.rpc('tools/call', { name: 'get_inventory', arguments: {} });
    expect((await response.json()).result.structuredContent).toMatchObject({ limit: 20, offset: 0 });
    expect(String(f.upstream.mock.calls[0][0])).toContain('includeDepleted=false');
  });
  it('fails closed when configuration is missing', async () => {
    for (const missing of ['ownerId', 'clientId', 'pantryToken']) {
      const f = fixture({ config: { [missing]: '' } }); expect((await f.rpc('tools/list')).status).toBe(503);
      expect(f.authFetch).not.toHaveBeenCalled(); expect(f.upstream).not.toHaveBeenCalled();
    }
  });
  it('sanitizes upstream errors and never logs credentials or inventory content', async () => {
    const f = fixture(); f.upstream.mockResolvedValueOnce(new Response('synthetic-server-secret', { status: 500 }));
    const response = await f.rpc('tools/call', { name: 'get_inventory', arguments: {} });
    const body = await response.json(); expect(body.result.isError).toBe(true);
    expect(JSON.stringify(body)).not.toContain(config.pantryToken);
    expect(JSON.stringify(f.audit.mock.calls)).not.toMatch(/secret|Bearer|Synthetic rice/);
  });
  it('rejects oversized or nonadvancing upstream pages', async () => {
    const f = fixture(); f.upstream.mockResolvedValueOnce(Response.json({ lots: [], limit: 20, offset: 0, total: 5, hasMore: true, nextOffset: 0 }));
    expect((await (await f.rpc('tools/call', { name: 'get_inventory', arguments: {} })).json()).result.isError).toBe(true);
  });
  it('rejects an unapproved browser origin', async () => {
    const f = fixture(); expect((await f.rpc('tools/list', {}, token(), { origin: 'https://other.invalid' })).status).toBe(403);
    expect(f.authFetch).not.toHaveBeenCalled();
  });
  it('bounds request bodies and rejects malformed protocol messages', async () => {
    const f = fixture();
    for (const [body, status] of [['{', 400], [' '.repeat(17000), 413]] as const) {
      const response = await f.handler(new Request(config.resource, { method: 'POST',
        headers: { authorization: `Bearer ${token()}`, 'content-type': 'application/json', accept: 'application/json, text/event-stream' }, body }));
      expect(response.status).toBe(status);
    }
    expect(f.upstream).not.toHaveBeenCalled();
  });
  it('fails closed when the identity provider is unavailable', async () => {
    const f = fixture(); f.authFetch.mockRejectedValue(new Error('synthetic private auth failure'));
    const response = await f.rpc('tools/list');
    expect(response.status).toBe(401); expect(await response.text()).not.toContain('private auth failure');
    expect(f.upstream).not.toHaveBeenCalled();
  });
});
