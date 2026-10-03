export type Claims = Record<string, unknown>;
export type AuthConfig = { ownerId: string; clientId: string; resource: string; issuer: string };
export const isUuid = (value: unknown): value is string => typeof value === 'string' &&
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value) &&
  value !== '00000000-0000-0000-0000-000000000000';
export type IdentityProvider = {
  verifiedClaims(token: string): Promise<Claims | null>;
  liveUser(token: string): Promise<{ id: string; anonymous: boolean; confirmed: boolean } | null>;
  isAppOwner(token: string): Promise<boolean>;
};

// Only verified claims enter this function. Never authorize by email or user_metadata.
export async function authorize(token: string, config: AuthConfig, provider: IdentityProvider): Promise<boolean> {
  if (!token || !isUuid(config.ownerId) || !isUuid(config.clientId)) return false;
  const claims = await provider.verifiedClaims(token);
  const now = Math.floor(Date.now() / 1000);
  if (!claims || claims.sub !== config.ownerId || claims.iss !== config.issuer ||
      claims.aud !== config.resource || claims.client_id !== config.clientId ||
      claims.role !== 'authenticated' || claims.is_anonymous !== false || !isUuid(claims.session_id) ||
      typeof claims.iat !== 'number' || !Number.isFinite(claims.iat) || claims.iat > now ||
      typeof claims.exp !== 'number' || claims.exp <= now ||
      (claims.nbf !== undefined && (typeof claims.nbf !== 'number' || claims.nbf > now)) ||
      typeof claims.scope !== 'string' || !claims.scope.split(' ').includes('openid')) return false;
  const user = await provider.liveUser(token);
  return user?.id === config.ownerId && !user.anonymous && user.confirmed && await provider.isAppOwner(token);
}
