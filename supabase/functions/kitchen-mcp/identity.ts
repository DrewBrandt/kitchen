import { createClient } from '@supabase/supabase-js';
import type { IdentityProvider } from './auth.ts';

export function createIdentityProvider(url: string, key: string, fetcher: typeof fetch = fetch): IdentityProvider {
  const client = (token: string) => createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { fetch: fetcher, headers: { Authorization: `Bearer ${token}` } },
  });
  return {
    async verifiedClaims(token) {
      const { data, error } = await client(token).auth.getClaims(token);
      return error ? null : data?.claims ?? null;
    },
    async liveUser(token) {
      const { data, error } = await client(token).auth.getUser(token);
      return error || !data.user ? null : {
        id: data.user.id, anonymous: data.user.is_anonymous !== false,
        confirmed: Boolean(data.user.email_confirmed_at),
      };
    },
    async isAppOwner(token) {
      const { data, error } = await client(token).rpc('is_app_owner');
      return !error && data === true;
    },
  };
}
