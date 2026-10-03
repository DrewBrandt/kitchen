# Kitchen private inventory MCP prototype

Status: local prototype only. No deployment, OAuth client, grant, secrets setup,
gateway change, RLS change, or ChatGPT connection was performed. Synthetic success
is not evidence of a connected ChatGPT read.

## Reused services and endpoint

Existing Supabase project: `xaetuqdtnolzspfvqvja`. Existing `pantry-api` v16
provides the inventory projection and bounded pagination. The new adapter calls
only `GET /functions/v1/pantry-api/v1/inventory`, with explicit limit/offset.
It uses the existing server-side `PANTRY_API_TOKEN`; it never accepts that token
as caller authentication or forwards the caller's OAuth token to the legacy API.
No credentials were read or extracted for development/testing.

Proposed MCP resource:
`https://xaetuqdtnolzspfvqvja.supabase.co/functions/v1/kitchen-mcp/mcp`

Protected-resource metadata (advertised by the 401 challenge):
`https://xaetuqdtnolzspfvqvja.supabase.co/functions/v1/kitchen-mcp/.well-known/oauth-protected-resource`

Authorization server: `https://xaetuqdtnolzspfvqvja.supabase.co/auth/v1`.
Supabase's authorization-server discovery is at
`https://xaetuqdtnolzspfvqvja.supabase.co/.well-known/oauth-authorization-server/auth/v1`.

The website remains on GitHub Pages. No Sites service, new paid service, app UI,
database migration, other API action, or old GPT configuration is included.
The existing legacy server token retains its broad authority, but it is only used
behind this adapter's authorization gate and fixed GET route. This prototype does
not revoke that legacy credential or change the old GPT.

## Contract and files

- `supabase/functions/kitchen-mcp/handler.ts`: official SDK stateless Streamable
  HTTP transport, one `get_inventory` tool, metadata/challenge, fixed upstream GET.
- `auth.ts`: immutable owner subject, exact issuer/audience/client, expiry,
  not-before, authenticated nonanonymous identity, and `openid` scope checks.
- `identity.ts`: Supabase signature verification, live user lookup and existing
  `is_app_owner` RPC (including its live-session check). Fail closed on errors.
- `index.ts`: Edge Function composition and server-only environment reads.
- `deno.json`: pinned runtime import map. Root npm lockfile pins test dependencies.
- `src/kitchen-mcp.test.ts`: official MCP client and synthetic signed JWT tests.

Tool arguments: `limit` (1–50, default 20), `offset` (0–2147483647, default 0),
`includeDepleted` (boolean, default false). Unknown properties are rejected.
Only product-backed inventory lots are included, matching the existing API.
Prepared lots are excluded. Use `nextOffset` while `hasMore` is true. Offset pages
are live views, not a snapshot: concurrent inventory changes can shift positions.
Restart pagination if the stock changes during a read.

Every request is authorized, including initialization and tool discovery. Public
metadata contains no inventory. Responses disable caching. Logs contain only a
generated request ID, event, status, and optional row count; no request bodies,
tokens, upstream errors, owner IDs or inventory fields. The same request ID appears
in the HTTP response and successful tool result for later evidence correlation.

## Approval boundary: do not deploy or connect yet

Supabase officially supports OAuth 2.1 with existing users and Edge Functions.
However, OAuth `openid` controls identity information, **not database access**.
Kitchen's existing `is_app_owner` and owner policies grant broad owner access.
Giving ChatGPT an ordinary owner token would therefore exceed this read-only scope.
The adapter's one-tool surface alone does not solve bearer-token access elsewhere.

Required decisions/actions, all still pending separate approval:

1. On project `xaetuqdtnolzspfvqvja`, enable the Supabase OAuth server if disabled.
   Keep public dynamic client registration off; create only one ChatGPT client,
   using the exact redirect URI shown by that connection's management page.
   Do not guess the redirect URI or reuse the Custom GPT API-key configuration.
2. Supply a Supabase authorization/consent endpoint. The repository has no OAuth
   consent implementation; this would require separately approved UI work or an
   approved existing endpoint. It was intentionally excluded from this prototype.
3. Before issuing a grant, review and implement client-specific token/access
   restrictions: MCP-only `aud` equal to the resource URL; verified client ID;
   identity scope `openid`; and prevention of that client's direct database writes,
   noninventory reads, and write RPCs. Preserve the existing owner/live-session
   check. Do not assume a custom audience alone prevents PostgREST access.
   Policy/hook changes and their tests must be a separate concrete review; no
   proposed policy has been silently installed here. Verify Supabase's issued
   `scope`, audience and live-session behavior without weakening checks if it differs.
4. Configure server-side `KITCHEN_MCP_OWNER_ID` with the existing owner's immutable
   auth UUID and `KITCHEN_MCP_CLIENT_ID` with that single approved OAuth client ID.
   Standard Supabase runtime values `SUPABASE_URL`/`SUPABASE_ANON_KEY` and the
   existing project secret `PANTRY_API_TOKEN` are reused. Do not put these into
   browser bundles, plugin schemas, examples, logs or chat, or extract them to test.
5. Approve deployment of only `kitchen-mcp` and the function-specific gateway
   `verify_jwt = false` setting needed for OAuth metadata/challenges. Application
   verification stays mandatory. This setting is NOT added to `config.toml` yet.
   Link this feature worktree normally before any approved Supabase deployment;
   never copy another worktree's ignored link state. Verify both metadata and
   unauthenticated rejection immediately after deployment, before connecting.
6. Create the private ChatGPT MCP connection at the resource URL, select OAuth,
   and authorize with the existing owner account. Grant only after step 3's
   restrictions are verified. Private visibility is not an authorization control.

The next approval is for the exact OAuth/consent/access setup above, not for a
general expansion of the existing API. Do not enable OAuth first and defer the
token restrictions until after connecting. Custom GPT Actions do not transfer
automatically; leave the existing GPT unchanged.

## Local proof and next live proof

From a freshly restored worktree:

```powershell
npm ci
npm test -- src/kitchen-mcp.test.ts src/inventory-api-parity.test.ts
npm run check
$env:VITE_SUPABASE_URL = 'https://example.supabase.co'
$env:VITE_SUPABASE_PUBLISHABLE_KEY = 'build-validation-placeholder'
npm run build
```

Tests generate an ephemeral RSA key and signed fixture tokens, serve only synthetic
JWKS/user/owner responses, and route the official MCP client in-process. No real
network, existing user token or credential is used. They exercise token signature
validation through the same Supabase client implementation used at runtime.
The unchanged inventory parity tests cover the upstream API's actual projection.
They do not prove live Supabase OAuth issuance, gateway routing, Deno bundling,
revocation semantics, or ChatGPT compatibility after the pending configuration.

The placeholder-auth production build passed. A dependency audit reported existing
`ajv@8.17.1` (moderate) and `undici@7.29.0` (high) advisories; both versions were
already in the base lockfile and remain unchanged. No unrelated dependency update
was included. Assess those advisories before a live deployment.

After approval and setup: connect ChatGPT privately, ask for inventory with a small
limit, continue to the next page, and correlate the returned request IDs with
`inventory_read` server log entries and counts. Record timestamps and IDs only.
Verify rejection of an absent credential and a separately authorized nonowner
fixture/account without extracting existing credentials or reviving blocked probes.
Only then report connected success.

## Official references (checked 2026-10-03)

- [OpenAI MCP server](https://developers.openai.com/plugins/build/mcp-server)
- [OpenAI OAuth requirements](https://developers.openai.com/plugins/build/auth)
- [Connect and test](https://developers.openai.com/plugins/deploy/connect-chatgpt)
- [Custom GPT migration](https://learn.chatgpt.com/docs/migrate-custom-gpts)
- [Supabase OAuth server](https://supabase.com/docs/guides/auth/oauth-server)
- [Supabase MCP authentication](https://supabase.com/docs/guides/auth/oauth-server/mcp-authentication)
- [Supabase token security](https://supabase.com/docs/guides/auth/oauth-server/token-security)
- [Supabase MCP hosting](https://supabase.com/docs/guides/ai-tools/byo-mcp)
