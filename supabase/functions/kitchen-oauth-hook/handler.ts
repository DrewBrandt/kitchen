import { Webhook } from 'standardwebhooks';
import { isUuid } from '../kitchen-mcp/auth.ts';

type Json = Record<string, unknown>;
type Config = { secret: string; ownerId: string; clientId: string; supabaseUrl: string };
const object = (value: unknown): value is Json => Boolean(value) && typeof value === 'object' && !Array.isArray(value);

// This hook never signs a JWT. It returns claims to Supabase Auth, which signs them.
// Request bodies contain identity information and must never be logged.
export function createTokenHook(config: Config) {
  let verifier: Webhook | undefined;
  try { if (config.secret) verifier = new Webhook(config.secret.replace(/^v1,/, '')); } catch { /* fail closed */ }
  const ready = verifier && isUuid(config.ownerId) && isUuid(config.clientId) && /^https:\/\/[a-z0-9.-]+$/.test(config.supabaseUrl);
  return async (request: Request): Promise<Response> => {
    const reply = (body: unknown, status = 200) => Response.json(body, { status, headers: { 'cache-control': 'no-store' } });
    const deny = (status: number, message: string) => reply({ error: { http_code: status, message } }, status);
    if (!ready) return deny(503, 'OAuth hook configuration incomplete');
    if (request.method !== 'POST') return deny(405, 'Method not allowed');
    let event: unknown;
    try {
      const reader = request.body?.getReader();
      if (!reader) return deny(400, 'Invalid hook request');
      const chunks: Uint8Array[] = []; let size = 0;
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        size += value.length;
        if (size > 65536) { await reader.cancel(); return deny(413, 'Hook request too large'); }
        chunks.push(value);
      }
      const bytes = new Uint8Array(size); let offset = 0;
      for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
      event = verifier!.verify(new TextDecoder().decode(bytes), Object.fromEntries(request.headers));
    } catch { return deny(401, 'Invalid hook signature'); }
    if (!object(event) || !object(event.claims)) return deny(400, 'Invalid hook event');
    const claims = event.claims;
    // Ordinary login/refresh and other clients retain exactly their original claims.
    // The adapter separately rejects every client except the pinned Kitchen client.
    if (claims.client_id !== config.clientId) {
      if (event.authentication_method === 'oauth_provider/authorization_code' && !isUuid(claims.client_id))
        return deny(403, 'OAuth client missing');
      return reply({ claims });
    }
    if (event.user_id !== config.ownerId || claims.sub !== config.ownerId ||
        claims.iss !== `${config.supabaseUrl}/auth/v1` || claims.role !== 'authenticated' ||
        claims.is_anonymous !== false || !isUuid(claims.session_id) || claims.scope !== 'openid')
      return deny(403, 'Kitchen OAuth is restricted to its configured owner and scope');
    return reply({ claims: { ...claims, aud: `${config.supabaseUrl}/functions/v1/kitchen-mcp/mcp` } });
  };
}
