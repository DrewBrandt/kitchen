export type Claims = Record<string, unknown>;
export type AuthConfig = { ownerId: string; clientId: string; resource: string; issuer: string };
export type IdentityProvider = {
  verifiedClaims(token: string): Promise<Claims | null>;
  liveUser(token: string): Promise<{ id: string; anonymous: boolean } | null>;
  isAppOwner(token: string): Promise<boolean>;
};

// Only verified claims enter this function. Never authorize by email or user_metadata.
export async function authorize(token: string, config: AuthConfig, provider: IdentityProvider): Promise<boolean> {
  if (!token || !config.ownerId || !config.clientId) return false;
  const claims = await provider.verifiedClaims(token);
  const now = Math.floor(Date.now() / 1000);
  if (!claims || claims.sub !== config.ownerId || claims.iss !== config.issuer ||
      claims.aud !== config.resource || claims.client_id !== config.clientId ||
      claims.role !== 'authenticated' || claims.is_anonymous === true ||
      typeof claims.exp !== 'number' || claims.exp <= now ||
      (claims.nbf !== undefined && (typeof claims.nbf !== 'number' || claims.nbf > now)) ||
      typeof claims.scope !== 'string' || !claims.scope.split(' ').includes('openid')) return false;
  const user = await provider.liveUser(token);
  return user?.id === config.ownerId && !user.anonymous && await provider.isAppOwner(token);
}
