import type { OAuthAuthorizationDetails } from '@supabase/supabase-js';

export type ConsentConfig = { ownerId: string; clientId: string; redirectUri: string };
export const pendingConsentKey = 'kitchen.oauth.pending-consent';
const identifier = (value: unknown): value is string => typeof value === 'string' && /^[A-Za-z0-9_-]{16,256}$/.test(value);
const uuid = (value: string) => /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(value) && value !== '00000000-0000-0000-0000-000000000000';
const callbackParams = new Set(['code', 'state', 'error', 'error_description', 'error_uri']);

export function configuredConsent(config: ConsentConfig) {
  try {
    const url = new URL(config.redirectUri);
    return uuid(config.ownerId) && uuid(config.clientId) && url.protocol === 'https:' &&
      !url.username && !url.password && !url.hash &&
      ![...url.searchParams.keys()].some(key => callbackParams.has(key));
  } catch { return false; }
}

// Authorization IDs are short-lived references, not access/refresh tokens.
export function pendingConsent(url: URL, storage: Storage): string {
  if (url.searchParams.has('authorization_id')) {
    const id = url.searchParams.get('authorization_id');
    storage.removeItem(pendingConsentKey);
    if (!identifier(id)) throw new Error('Invalid authorization request. Restart the connection in ChatGPT.');
    storage.setItem(pendingConsentKey, JSON.stringify({ id, createdAt: Date.now() }));
    return id;
  }
  try {
    const saved = JSON.parse(storage.getItem(pendingConsentKey) ?? 'null');
    if (identifier(saved?.id) && typeof saved.createdAt === 'number' &&
        Date.now() >= saved.createdAt && Date.now() - saved.createdAt < 15 * 60 * 1000) return saved.id;
  } catch { /* never display stored data */ }
  storage.removeItem(pendingConsentKey);
  throw new Error('Authorization request expired or missing. Restart the connection in ChatGPT.');
}

export function approvedRedirect(value: string, expected: string): boolean {
  try {
    const target = new URL(value), base = new URL(expected);
    if (target.origin !== base.origin || target.pathname !== base.pathname || target.hash ||
        target.username || target.password || target.protocol !== 'https:') return false;
    for (const [key, val] of base.searchParams) if (target.searchParams.get(key) !== val) return false;
    return [...target.searchParams.keys()].every(key => base.searchParams.has(key) || callbackParams.has(key));
  } catch { return false; }
}

export function validConsentDetails(details: OAuthAuthorizationDetails, authorizationId: string, config: ConsentConfig) {
  return details.authorization_id === authorizationId && details.client.id === config.clientId &&
    details.user.id === config.ownerId && details.redirect_uri === config.redirectUri && details.scope === 'openid';
}
