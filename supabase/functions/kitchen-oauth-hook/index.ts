import { createTokenHook } from './handler.ts';

Deno.serve(createTokenHook({
  secret: Deno.env.get('KITCHEN_OAUTH_HOOK_SECRET') ?? '',
  ownerId: Deno.env.get('KITCHEN_MCP_OWNER_ID') ?? '',
  clientId: Deno.env.get('KITCHEN_MCP_CLIENT_ID') ?? '',
  supabaseUrl: Deno.env.get('SUPABASE_URL') ?? '',
}));
