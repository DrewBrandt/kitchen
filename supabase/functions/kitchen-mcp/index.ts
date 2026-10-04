import { createHandler } from './handler.ts';
import { createIdentityProvider } from './identity.ts';

const url = Deno.env.get('SUPABASE_URL') ?? '';
const key = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
// No defaults for identity/client allowlists, and no legacy-token fallback for callers.
const handler = createHandler({
  anonKey: key, supabaseUrl: url, issuer: `${url}/auth/v1`,
  resource: `${url || 'https://unconfigured.invalid'}/functions/v1/kitchen-mcp/mcp`,
  ownerId: Deno.env.get('KITCHEN_MCP_OWNER_ID') ?? '',
  clientId: Deno.env.get('KITCHEN_MCP_CLIENT_ID') ?? '',
  pantryToken: Deno.env.get('PANTRY_API_TOKEN') ?? '',
}, {
  identity: createIdentityProvider(url || 'https://unconfigured.invalid', key || 'unconfigured'),
  fetch,
  audit: (event) => console.info(JSON.stringify(event)),
});
Deno.serve(handler);
