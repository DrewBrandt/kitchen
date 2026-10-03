// @vitest-environment node
import { Webhook } from 'standardwebhooks';
import { describe, expect, it } from 'vitest';
import { createTokenHook } from '../supabase/functions/kitchen-oauth-hook/handler';

const config = {
  secret: `v1,whsec_${Buffer.from('synthetic-hook-signing-key-32bytes').toString('base64')}`,
  ownerId: '10000000-0000-4000-8000-000000000001', clientId: '10000000-0000-4000-8000-000000000002',
  supabaseUrl: 'https://synthetic.supabase.co',
};
const hook = createTokenHook(config);
const signer = new Webhook(config.secret.replace(/^v1,/, ''));
function event(overrides = {}) {
  return { user_id: config.ownerId, authentication_method: 'oauth_provider/authorization_code', claims: {
    sub: config.ownerId, client_id: config.clientId, iss: `${config.supabaseUrl}/auth/v1`, aud: 'authenticated',
    role: 'authenticated', scope: 'openid', is_anonymous: false, session_id: '10000000-0000-4000-8000-000000000003',
    exp: 1800000000, iat: 1790000000, aal: 'aal1', email: 'synthetic@example.test', phone: '', ...overrides,
  } };
}
function request(body: unknown, date = new Date()) {
  const payload = JSON.stringify(body), id = 'synthetic-message';
  return new Request('https://synthetic.supabase.co/functions/v1/kitchen-oauth-hook', {
    method: 'POST', headers: { 'content-type': 'application/json', 'webhook-id': id,
      'webhook-timestamp': String(Math.floor(date.getTime() / 1000)), 'webhook-signature': signer.sign(id, date, payload) }, body: payload,
  });
}
describe('Kitchen Supabase access-token hook', () => {
  it.each(['oauth_provider/authorization_code', 'token_refresh'])('sets only the owner/client audience for %s', async method => {
    const input = { ...event(), authentication_method: method };
    const response = await hook(request(input)); expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ claims: { ...input.claims, aud: `${config.supabaseUrl}/functions/v1/kitchen-mcp/mcp` } });
  });
  it.each(['oauth', 'password', 'token_refresh'])('preserves ordinary app claims exactly for %s', async method => {
    const input = { ...event({ client_id: undefined, scope: undefined }), authentication_method: method };
    const expected = JSON.parse(JSON.stringify(input.claims));
    expect(await (await hook(request(input))).json()).toEqual({ claims: expected });
  });
  it('leaves another OAuth client unchanged rather than changing unrelated authorization', async () => {
    const input = event({ client_id: '10000000-0000-4000-8000-000000000099' });
    expect(await (await hook(request(input))).json()).toEqual({ claims: input.claims });
  });
  it.each([
    { sub: 'other-owner' }, { role: 'service_role' }, { scope: 'openid profile' }, { scope: '' },
    { is_anonymous: true }, { session_id: undefined }, { iss: 'https://other.invalid/auth/v1' },
  ])('rejects unsuitable Kitchen claims (%j)', async claims => {
    const response = await hook(request(event(claims))); expect(response.status).toBe(403);
    expect(await response.text()).not.toContain('synthetic@example.test');
  });
  it('rejects a different event user even with an owner subject', async () => {
    expect((await hook(request({ ...event(), user_id: 'other-owner' }))).status).toBe(403);
  });
  it('rejects an OAuth-code event missing its client ID', async () => {
    expect((await hook(request(event({ client_id: undefined })))).status).toBe(403);
  });
  it('rejects missing, wrong, modified and expired webhook signatures', async () => {
    const missing = request(event()); missing.headers.delete('webhook-signature');
    const wrong = request(event()); wrong.headers.set('webhook-signature', 'v1,incorrect');
    const modified = new Request(request(event()), { body: JSON.stringify(event({ sub: 'modified' })) });
    for (const input of [missing, wrong, modified, request(event(), new Date(Date.now() - 600000))])
      expect((await hook(input)).status).toBe(401);
  });
  it('fails closed before activation if configuration is absent', async () => {
    for (const key of ['secret', 'ownerId', 'clientId', 'supabaseUrl'])
      expect((await createTokenHook({ ...config, [key]: '' })(request(event()))).status).toBe(503);
  });
  it('rejects oversized bodies and non-POST methods', async () => {
    expect((await hook(request('x'.repeat(66000)))).status).toBe(413);
    expect((await hook(new Request('https://synthetic.invalid'))).status).toBe(405);
  });
});
