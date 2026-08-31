# Google Calendar integration (planned)

Calendar synchronization remains a planned feature. Its UI is intentionally
visible but disabled until a new server-side implementation exists.

## Product behavior to preserve

- Create grocery reminders from unchecked shortages and their first-needed date.
- Create recipe preparation reminders from explicit lead-time rules.
- Create plan-specific reminders from exact meal times.
- Read selected calendars for schedule-aware planning without modifying them.
- Write only to a dedicated `Pantry Planner` calendar.
- Identify managed events so reconciliation never changes unrelated events.
- Let planning succeed when Google Calendar is unavailable.

## Proposed architecture

Use a Supabase Edge Function or another small owner-only server component. The
browser must never receive the Google OAuth client secret or refresh token.

1. The owner connects Google Calendar through the server endpoint.
2. The server encrypts the refresh token with a deployment secret.
3. Supabase stores the encrypted connection metadata and a planning-sync marker.
4. Meal-plan or grocery changes advance that marker transactionally.
5. A queued/scheduled reconciler reads the committed PostgreSQL state and makes
   idempotent Calendar API changes.
6. Events carry private managed identifiers for safe update and deletion.

## Security requirements

- Require a live Supabase owner session for every connection or manual-sync call.
- Request only the Calendar scopes the feature actually uses.
- Keep OAuth credentials and encryption keys outside browser code and Git.
- Never return refresh tokens or client secrets from status endpoints.
- Bound agenda reads by date and calendar selection.
- Delete only events carrying this app's managed-event identifier.

## Status

Not implemented. The current React UI labels calendar synchronization as paused.
