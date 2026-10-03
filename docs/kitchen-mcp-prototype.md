# Kitchen owner OAuth MCP prototype

Setup approved on 2026-10-03. OAuth/public client and consent redirect are configured;
the concrete hook migration is installed, awaiting dashboard activation. MCP and
Pages publication are in progress. No owner grant or connected inventory read yet.

Verified public owner UUID: `d075c538-3eca-4b08-bf5f-525f4947b3f3`.
Public client ID: `555528c5-3333-4ec1-91d6-7fd18e9000f3`.
Exact ChatGPT callback: `https://chatgpt.com/connector/oauth/_fJUf8WQ-Qg6`.
Site URL unchanged; active signing is ECC P-256; no previous hook was configured.
Migration `202610030001_kitchen_oauth_audience.sql` passed deployed logic and ACL
assertions through the management role. The hosted interface disallowed SET ROLE;
execution as supabase_auth_admin was verified in isolated Postgres instead.

## Recommended configuration

Reuse existing Supabase Auth and hosting on project `xaetuqdtnolzspfvqvja`, the
existing Kitchen Google owner login, GitHub Pages consent, and pantry-api v16.
Register one **public** OAuth client manually (`token_endpoint_auth_method: none`),
with authorization code + S256 PKCE, refresh, and the exact HTTPS callback shown
by ChatGPT. Disable dynamic registration. No client secret or separate provider.

The single MCP tool `get_inventory` is read-only, bounded to 1–50 rows, with
`nextOffset` continuation. Its OAuth credential has the broader Supabase owner
authority already accepted by the user, including possible profile updates.
It is not a read-only credential. Existing owner policies and old GPT stay unchanged.

Require `openid`; allow its standard identity companions `email`, `profile`, and
`phone`, plus `offline_access` for refresh, in any order. ChatGPT requests advertised OIDC scopes by default. Consent
shows the actual requested scopes and rejects unknown scopes or missing openid.
MCP still requires openid and exact issuer, audience, client, immutable owner,
nonanonymous authenticated role, signature/time/session checks and live owner RPC.
Identity scopes do not restrict database authority.

Use the supported **Postgres Custom Access Token hook**, not an HTTP function.
The approval-only SQL template is `supabase/oauth/kitchen_access_token.sql`.
It creates one private schema/function, runs as security invoker, reads no tables,
makes no network calls, and grants schema usage/function execution only to
`supabase_auth_admin` (apart from the database owner). It returns ordinary and
unrelated-client claims unchanged. For the pinned client it verifies the owner,
issuer, session, role and identity scopes, then changes only `aud` to the MCP URL.
Supabase signs the result. There is no hook signing secret or extra Edge Function.
The hook still executes during all token issuance: a SQL/configuration failure
can disrupt sign-in. The database is already an Auth dependency; this adds no
independent service/network dependency. Preserve/compose any existing hook first.

## Resource-binding finding (official sources, 2026-10-03)

Supabase's setup docs explicitly recommend Custom Access Token Hooks for a
client-specific audience. Current upstream `internal/tokens/service.go` builds
access-token audience from `params.User.Aud`, obtains scopes from the session,
and invokes the configured hook before signing. The source does not establish
native request-resource-to-access-token audience binding. Accepting/storing a
resource parameter alone does not prove that binding. Hosted version is not
claimed verified. The supported hook is therefore the recommended path; exact
MCP audience validation remains mandatory.

References:
- https://developers.openai.com/plugins/build/auth (resource audience, public clients, S256, default OIDC scopes)
- https://supabase.com/docs/guides/auth/oauth-server/getting-started (public none clients, exact callbacks, custom audiences)
- https://supabase.com/docs/guides/auth/auth-hooks (Postgres hooks, invoker permissions)
- https://supabase.com/docs/guides/auth/auth-hooks/custom-access-token-hook (claims contract)
- https://github.com/supabase/auth/blob/master/internal/tokens/service.go (current upstream issuance, not hosted-version proof)

## Exact targets

- MCP resource/audience: `https://xaetuqdtnolzspfvqvja.supabase.co/functions/v1/kitchen-mcp/mcp`
- Resource metadata: `https://xaetuqdtnolzspfvqvja.supabase.co/functions/v1/kitchen-mcp/.well-known/oauth-protected-resource`
- Issuer: `https://xaetuqdtnolzspfvqvja.supabase.co/auth/v1`
- Discovery: `https://xaetuqdtnolzspfvqvja.supabase.co/.well-known/oauth-authorization-server/auth/v1`
- Authorization/token: issuer + `/oauth/authorize` and `/oauth/token`
- Consent: `https://drewbrandt.github.io/kitchen/oauth-consent.html`
- Database hook: `pg-functions://postgres/kitchen_oauth/custom_access_token`

## Concrete approval items before live setup

The user separately approved the following setup; final ChatGPT consent remains theirs.

1. Verify the existing immutable owner UUID, current hook, Site URL, asymmetric
   signing configuration, and ChatGPT's exact callback through approved setup
   surfaces. No credential extraction or blocked probes. If signing-key rotation
   or replacing an existing hook is necessary, present that exact change first.
2. Enable Supabase OAuth Server, leave dynamic registration disabled, and set
   authorization path `/oauth-consent.html`, provided the existing Site URL is
   `https://drewbrandt.github.io/kitchen/`. Resolve the combined URL if different;
   do not silently change Site URL. Add the exact consent URL to allowed app
   sign-in redirects while preserving existing entries.
3. Register one public Kitchen ChatGPT client, authentication method `none`, exact
   callback only, using S256 PKCE. Enable the advertised standard OIDC scopes
   (openid/email/profile/phone/offline_access); no unknown/custom action scopes. Enter only its
   public client ID in ChatGPT's OAuth configuration. No client secret to create.
4. Replace the SQL template's `__OWNER_UUID__` and `__CLIENT_UUID__` with those
   verified public IDs, review the concrete SQL, and install/version it as a
   migration. It is intentionally outside automatic migrations until this step.
   Install only the new schema/function and their narrow grants. Do not change
   existing roles, RLS, owner RPC, tables, or API access rules.
5. Configure Edge Function `KITCHEN_MCP_OWNER_ID` and `KITCHEN_MCP_CLIENT_ID`.
   Reuse existing `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `PANTRY_API_TOKEN` in place.
   Set GitHub public repository variables `KITCHEN_MCP_OWNER_ID`,
   `KITCHEN_MCP_CLIENT_ID`, `KITCHEN_MCP_REDIRECT_URI` for the Pages build.
6. Integrate/publish consent via the repository merge-lock/Pages process and deploy
   **only kitchen-mcp**, with gateway JWT verification disabled for this function
   so application OAuth checks and public metadata can run. No unauthenticated
   inventory access. Link the worktree normally before approved Supabase deploy;
   never copy ignored link state or deploy synthetic build output.
7. Activate the project's Custom Access Token Postgres hook at the exact URI above,
   after installation/configuration. Verify ordinary app sign-in/refresh at once.
8. Connect the private ChatGPT MCP URL as the existing owner and explicitly grant
   the disclosed owner authority. Verify initialization, singleton tool discovery,
   a limit-2 page and continuation. Correlate returned requestId with server
   inventory_read timestamp/count. Verify OAuth refresh/reconnect too.

Public configuration includes owner/client UUIDs and callback URL. No secrets in
repository variables, browser code, MCP schemas/results, logs, screenshots or chat.
Rollback: block MCP by removing configured client ID or disabling its function;
revoke client/grant; restore/disable the new hook. Disabling a hook alone does not
invalidate issued tokens. Preserve ordinary login and the old GPT.

## Local validation

- `npm test -- src/OAuthConsent.test.tsx src/kitchen-mcp.test.ts`: 62 passed.
- `npm run check`: passed.
- `npm run build` with nonempty synthetic Supabase/owner/client/callback values: passed; output not deployed.
- `sh supabase/tests/run_oauth_isolated.sh`: passed (cached postgres:17, Docker; no live link).

On Windows run the SQL harness via WSL Ubuntu root with scoped elevation. It
creates a disposable network-disabled Postgres container, substitutes synthetic
IDs, tests the real SQL as supabase_auth_admin, checks unchanged ordinary claims,
owner/client audience on issuance/refresh, rejected identities/scopes and ACLs,
and removes only its own container. No hosted credentials are used.

Earlier adapter/consent/base integration checks passed 113 tests plus typecheck
and a production build with synthetic nonempty settings. The obsolete HTTP-hook
tests from that count have been removed. Current focused results are recorded in
the implementation handoff. Local tests do not prove hosted OAuth issuance,
Deno/gateway deployment, actual signing configuration or connected ChatGPT success.
The actual connected test remains gated on the setup approvals above.
