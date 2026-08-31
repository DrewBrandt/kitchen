# Private Pantry GPT (planned)

The private Pantry GPT server integration is not currently deployed. Do not
configure the checked-in OpenAPI schema as a live Action yet: its server points
to an intentionally invalid placeholder until an owner-only Supabase-backed API
exists.

The following product assets are retained for that future implementation:

- `PANTRY_GPT_INSTRUCTIONS.md`: conversational behavior and safety rules.
- `pantry-gpt-openapi.yaml`: the proposed deterministic API contract.
- `API.md`: detailed request and transaction semantics.

Before enabling the Action:

1. Implement the API in a server environment that can safely hold credentials.
2. Require owner-only authentication independent of the browser publishable key.
3. Preserve atomic PostgreSQL operations for inventory and cooking writes.
4. Replace the placeholder OpenAPI server URL with the verified endpoint.
5. Test every read operation before testing writes in GPT Preview.
6. Keep all tokens out of Git, GPT instructions, knowledge files, and chats.

Ordinary ChatGPT conversations do not inherit private GPT Actions. Until this
integration is rebuilt, use the web application for live pantry access.
