# Kitchen owner OAuth MCP prototype

Status: implemented and tested locally. No live OAuth configuration, client,
credential, grant, deployment or connected ChatGPT read has been performed.

## Accepted authority and scope

Use the existing Supabase owner login. The initial get_inventory tool is a staged
connection test; the eventual product can expose Kitchen owner actions incrementally.
**The OAuth credential has owner authority; it is not read-only.** It can authorize
other operations accepted by Supabase, including possible account/profile updates.
Hiding write tools does not restrict the credential. This broader authority was
explicitly disclosed and accepted for this design.

The adapter exposes exactly one read-only inventory tool. It reuses pantry-api v16
with a fixed GET, using the existing server-only PANTRY_API_TOKEN. That API secret
is distinct from both the OAuth user JWT and the legacy API's server-only
SUPABASE_SERVICE_ROLE_KEY.

No database migrations, roles, owner policy/RPC changes, old GPT changes, or additional
identity provider are included. The existing app login code is unchanged.

## Implemented flow

1. ChatGPT discovers the MCP resource and its Supabase authorization server.
2. Supabase redirects to the new static oauth-consent.html page.
3. Consent shares the existing Supabase client/session and Google sign-in. Before
   showing consent and again before deciding, it checks the immutable owner UUID,
   confirmed nonanonymous live user, and existing is_app_owner RPC.
4. It validates authorization ID, owner, client ID, exact callback and openid scope.
   It explains owner authority and waits for a click. Previously granted consent
   uses Supabase's returned redirect without granting again. Every redirect is
   checked against the configured callback.
5. A signed HTTP Custom Access Token hook rejects unsuitable owner/client claims
   and sets only the target client's aud to the MCP resource. Supabase signs and
   issues the token. The hook does not mint tokens.
6. Before every MCP operation, the adapter checks signature, issuer, exact audience,
   client, immutable owner, authenticated role, issuance/expiry/not-before, openid,
   and nonzero UUID session claim. It additionally performs live Auth user validation
   and the existing owner/live-session RPC. Missing/invalid authentication fails closed.

Ordinary login/refresh claims and unrelated OAuth-client claims pass through the
hook unchanged. The adapter accepts only its pinned client. The hook is nevertheless
project-wide: an HTTP hook outage or timeout can disrupt ordinary login/refresh.
Deploy/configure it before activation and disable it if ordinary login fails.
Never overwrite an existing hook without reviewing and composing its behavior.

## Endpoints

Project: xaetuqdtnolzspfvqvja.

| Purpose | Exact target |
|---|---|
| MCP resource and audience | https://xaetuqdtnolzspfvqvja.supabase.co/functions/v1/kitchen-mcp/mcp |
| Protected-resource metadata | https://xaetuqdtnolzspfvqvja.supabase.co/functions/v1/kitchen-mcp/.well-known/oauth-protected-resource |
| Signed token hook | https://xaetuqdtnolzspfvqvja.supabase.co/functions/v1/kitchen-oauth-hook |
| Issuer | https://xaetuqdtnolzspfvqvja.supabase.co/auth/v1 |
| Authorization endpoint | https://xaetuqdtnolzspfvqvja.supabase.co/auth/v1/oauth/authorize |
| Token endpoint | https://xaetuqdtnolzspfvqvja.supabase.co/auth/v1/oauth/token |
| Authorization-server discovery | https://xaetuqdtnolzspfvqvja.supabase.co/.well-known/oauth-authorization-server/auth/v1 |
| Consent page | https://drewbrandt.github.io/kitchen/oauth-consent.html |

## Exact configuration requiring action-time approval

None of these actions has occurred. Broad design acceptance is not live setup
approval. First confirm the owner UUID, existing hook status, Site URL and signing
configuration through authorized setup surfaces. Do not repeat blocked security
probes or read secret values into tool output.

1. **Supabase Auth > OAuth Server:** enable the OAuth server on this project and
   leave dynamic client registration disabled. With the existing Site URL
   https://drewbrandt.github.io/kitchen/, set authorization_url_path to
   /oauth-consent.html. Supabase appends this to the Site URL. If the real Site URL
   differs, resolve the combined URL first; do not silently change the app's Site URL.
2. **Auth > URL Configuration:** add exactly
   https://drewbrandt.github.io/kitchen/oauth-consent.html as a Google sign-in return
   URL. Preserve existing app redirect entries. This is separate from the OAuth
   client callback.
3. **One OAuth client:** manually register a confidential client named Kitchen
   ChatGPT, with client_secret_basic, authorization-code/refresh flow and S256 PKCE
   from ChatGPT. Register only the exact HTTPS callback displayed by the private
   ChatGPT connection setup. That callback is not known yet; no guessing, wildcards
   or extra callbacks. Enter client ID/secret in ChatGPT's secure OAuth fields.
   Request openid only. This identity scope does not restrict database authority.
4. **Configuration values:** set KITCHEN_MCP_OWNER_ID to the verified existing
   owner's immutable Auth UUID and KITCHEN_MCP_CLIENT_ID to that new client ID.
   Generate the hook signing secret through the approved hook setup and enter the
   matching value securely as KITCHEN_OAUTH_HOOK_SECRET in Edge Function secrets.
   The handler accepts the dashboard's v1,whsec_... format. Reuse existing
   SUPABASE_URL, SUPABASE_ANON_KEY and PANTRY_API_TOKEN in place.
5. **GitHub repository variables:** set KITCHEN_MCP_OWNER_ID,
   KITCHEN_MCP_CLIENT_ID and KITCHEN_MCP_REDIRECT_URI. The Pages workflow exposes
   these public identifiers under VITE_ prefixes to the consent page. Missing values
   disable consent without disabling the ordinary app. Never put secrets here.
6. **Signing prerequisite:** verify asymmetric JWT signing is already active;
   Supabase openid ID tokens require it. If a signing-key change is required, stop
   for its own exact change review. Do not silently rotate keys.
7. **Deploy two Edge Functions:** kitchen-mcp and kitchen-oauth-hook, with gateway
   JWT verification disabled only for these two functions. MCP validates user JWTs
   itself; unauthenticated discovery must reach it. The hook validates signed
   Standard Webhooks requests/timestamps, not user JWTs. Neither provides
   unauthenticated inventory. supabase/config.toml remains unchanged pending approval.
8. **Custom Access Token hook:** configure the project-wide HTTP hook to the exact
   hook URL above, using the matching signing secret. Activate only after deployment
   and configuration are ready. If another hook exists, compose and review first;
   replacement is not authorized. Verify ordinary owner login/refresh immediately.
   Ordinary claims stay unchanged, but token issuance gains an availability dependency.
9. **Publish and connect:** integrate/push with the repository's merge lock and Pages
   deployment process. Finish the private ChatGPT OAuth MCP connection at the exact
   resource URL. Use the existing owner account and explicitly approve the disclosed
   owner-access grant. No other users or grants are included.

Application order after approval: resolve prerequisites/callback/owner; create the
single client and configure values; publish consent and deploy both functions;
activate the hook; verify ordinary login; finally grant access and read inventory.
Do not consent before the hook is active.

Before approved Supabase deployment, link this worktree normally with
npx.cmd supabase link --project-ref xaetuqdtnolzspfvqvja. Never copy ignored link state.
Do not deploy the synthetic build used for local validation.

Public configuration: owner UUID, client ID, URLs, scope, and existing Supabase
publishable/anon key. Secrets: client secret, hook signing secret, API/service-role
secrets, authorization codes, access/refresh tokens. Keep secrets out of browser
bundles, repository variables, tool metadata/results, logs, screenshots and chat.
Never extract credentials to bridge a test.

Rollback: block MCP immediately by removing its configured client ID or disabling
the function; revoke the new client/grant; disable/restore the new hook. Disabling
the hook alone does not invalidate already issued access tokens. Preserve the
existing app login and old GPT.

## Smallest real connection test after approval

1. Verify public metadata and a missing-token MCP POST returning 401.
2. Complete private OAuth as the existing owner. Verify MCP initialization and
   discovery of exactly get_inventory.
3. Ask ChatGPT for limit: 2. If hasMore, request one continuation using nextOffset.
   Record the tool name, pagination and requestId.
4. Match requestId to the function's inventory_read event, timestamp and row count.
   Do not record inventory contents or credentials. Verify ordinary Kitchen login
   still works. Check an OAuth refresh/reconnect retains client/audience/session
   validation before claiming the connection durable.

Wrong-owner, malformed-token and revoked-session cases have synthetic coverage.
Do not create users or obtain another person's credentials for a live negative test.

## Local evidence and limits

Focused command:
npm test -- src/kitchen-mcp.test.ts src/kitchen-oauth-hook.test.ts src/OAuthConsent.test.tsx src/Root.test.tsx src/inventory-api-parity.test.ts

Result: **113 tests passed**. npm run check passed. The production build passed with
nonempty synthetic Supabase values plus synthetic owner/client/callback values,
producing both index.html and oauth-consent.html. That output is validation-only.
No repeated full regression suite was run for this local stage; integration still
requires the repository's integration checks.

Tests exercise the official MCP client, ephemeral signed JWTs/synthetic JWKS,
live-user/session responses, signed/invalid/expired HTTP hook requests, ordinary
claim preservation, consent and Google callback recovery. No live credentials are
used. They do not prove hosted OAuth issuance, Deno/gateway deployment, actual
signing configuration, hook availability or connected ChatGPT success.

The prior audit reported existing ajv@8.17.1 (moderate) and undici@7.29.0 (high)
advisories. Both remain at base lockfile versions; no unrelated dependency upgrade
was included. Review runtime applicability before deployment. The new hook verifier
is pinned to standardwebhooks@1.1.1 in npm and the Edge Function import map.

## Official references checked 2026-10-03

- [OpenAI MCP auth](https://developers.openai.com/plugins/build/auth)
- [Supabase OAuth setup/consent](https://supabase.com/docs/guides/auth/oauth-server/getting-started)
- [Custom Access Token hook](https://supabase.com/docs/guides/auth/auth-hooks/custom-access-token-hook)
- [HTTP hooks and availability](https://supabase.com/docs/guides/auth/auth-hooks)
- [Scope meaning](https://supabase.com/docs/guides/auth/oauth-server/token-security)
- [Token issuance/refresh source](https://github.com/supabase/auth/blob/master/internal/tokens/service.go)
- [Consent routing source](https://github.com/supabase/auth/blob/master/internal/api/oauthserver/authorize.go)
