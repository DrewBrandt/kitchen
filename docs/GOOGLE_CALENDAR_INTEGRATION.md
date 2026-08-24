# Google Calendar integration

## Implementation status

Implemented in the application and Cloud Functions:

- chronological `first_needed_date` grocery derivation
- atomic planning-sync markers from Flutter and Pantry GPT writes
- disabled-by-default settings and connection controls in the Planning page
- owner-authenticated OAuth connection using the narrow
  `calendar.app.created` scope
- encrypted server-only refresh-token storage
- creation and reuse of the `Pantry Planner` secondary calendar
- idempotent grocery and explicit recipe-preparation event reconciliation
- retry handling, sanitized status, manual sync, and managed-event cleanup

Production activation requires the one-time Google OAuth setup below. Live
end-to-end verification must use a test Google Calendar after those credentials
are configured.

## One-time production setup

1. Enable Google Calendar API in Firebase project `pantry-tracker-4bc45`.
2. Configure the Google Auth consent screen for the private owner account.
3. Create a **Web application** OAuth client and register this exact redirect:

   ```text
   https://us-east4-pantry-tracker-4bc45.cloudfunctions.net/calendarAuth
   ```

4. Store the client ID and client secret without printing or committing them:

   ```powershell
   firebase functions:secrets:set GOOGLE_CALENDAR_CLIENT_ID
   firebase functions:secrets:set GOOGLE_CALENDAR_CLIENT_SECRET
   firebase functions:secrets:set CALENDAR_TOKEN_KEY
   ```

   `CALENDAR_TOKEN_KEY` must be a randomly generated value of at least 20
   characters. It encrypts the refresh token before the token is stored in the
   server-only `_private_calendar_credentials` collection.
5. Deploy Functions, Firestore rules/indexes, and Hosting. Sign into Pantry,
   open Planning, and choose **Connect Google Calendar**.

## Outcome

Synchronize meal-plan actions to a dedicated Google Calendar so reminders are
created when a plan is written through either the Flutter app or the private
Pantry GPT API.

Use Google Calendar rather than Google Tasks for the first implementation.
Google Calendar events support timed reminders. The Google Tasks API stores only
the date portion of `due` and discards its time, so it cannot reliably represent
instructions such as "move the chicken to the fridge at 8:00 PM."

The integration should create two reminder kinds:

1. One grocery-run event before the first planned meal that cannot be covered by
   current inventory.
2. Preparation events attached to individual planned meals, initially thawing
   and later extensible to marinating, soaking, or batch preparation.

Meal events themselves are out of scope for the first version. They can be
added later without changing the synchronization design.

## Recommended Google design

- Create a secondary calendar named `Pantry Planner`.
- Request only
  `https://www.googleapis.com/auth/calendar.app.created`. This scope permits the
  app to create a secondary calendar and manage events on calendars it created,
  without granting access to every event on the user's primary calendar.
- Use the OAuth 2.0 web-server flow with offline access. Calendar synchronization
  can then run after a Pantry GPT plan update when the Flutter client is closed.
- Keep the OAuth client secret and refresh token on the server. Never return
  either credential to Flutter, Pantry GPT, Firestore collections readable by
  the client, Git, logs, or API responses.
- Put event identifiers in Calendar private extended properties so repeated
  synchronization updates existing events instead of creating duplicates.

Official references:

- [Calendar authorization scopes](https://developers.google.com/workspace/calendar/api/auth)
- [Create Calendar events](https://developers.google.com/workspace/calendar/api/guides/create-events)
- [Calendar reminders](https://developers.google.com/workspace/calendar/api/concepts/reminders)
- [OAuth web-server flow and offline access](https://developers.google.com/identity/protocols/oauth2/web-server)
- [Google Tasks resource](https://developers.google.com/tasks/reference/rest/v1/tasks)

## Why synchronization belongs in Cloud Functions

Plans can currently be changed from two places:

- Flutter writes `meal_plan` and `grocery_list` directly to Firestore.
- Pantry GPT calls `POST /v1/plans`, which writes the same collections through
  the `pantryApi` Cloud Function.

Putting Calendar calls in Flutter would miss Pantry GPT changes until the app
was opened again. Putting them only in `POST /v1/plans` would miss direct app
changes. Both write paths should therefore commit a small synchronization marker
in the same Firestore batch as the completed plan:

```text
settings/planning_sync
  generation: <unique value>
  requested_at: <server timestamp>
```

A Firestore-triggered Cloud Function watches that marker, reads the committed
plan and groceries, derives the desired reminder set, and reconciles the
dedicated calendar. This avoids observing a half-written plan and gives both
write paths one integration boundary.

The trigger must treat retries as normal. Reconciliation is a desired-state
operation, not an append operation.

## Calendar event identity

Every managed event gets a stable application identifier:

```text
grocery:<first-needed-date>
prep:<planned-meal-id>:<preparation-rule-id>
```

Store it in `extendedProperties.private.pantryReminderId`. Also store the plan
generation in `extendedProperties.private.pantryPlanGeneration` for diagnosis.

On each run:

1. Derive all desired reminder events from the current plan.
2. List only events managed by this integration.
3. Insert missing events.
4. Patch events whose title, time, description, or reminder policy changed.
5. Delete managed events that no longer exist in the plan.

Never delete or change events without a Pantry-managed private property.

## Grocery reminder derivation

The current grocery list stores an aggregate shortage but not the date on which
the shortage first matters. Add `first_needed_date` to each plan-generated
grocery item.

Calculate this by processing unfinished planned meals chronologically:

1. Start with current inventory quantities and prepared servings.
2. For each meal, use prepared servings first.
3. Convert the remaining recipe ingredients to canonical base units.
4. Deduct those amounts from a virtual inventory balance.
5. When an ingredient balance first becomes negative, record that meal's date
   as the ingredient's `first_needed_date`.

The grocery-run deadline is the earliest `first_needed_date` among unchecked
plan-generated grocery items. A default event could be scheduled for 6:00 PM on
the preceding day. The time and lead days must be user preferences rather than
hard-coded Calendar behavior.

If the grocery list is empty, or all shortages are checked, remove the managed
grocery event.

## Preparation and thawing model

Do not guess thaw duration solely from a recipe name. Add explicit reusable
preparation rules to recipes or foods:

```json
{
  "id": "thaw-chicken",
  "kind": "thaw",
  "label": "Move chicken to the refrigerator",
  "leadHours": 24
}
```

The planner combines a rule with the planned meal's date and slot time. Slot
times are preferences, for example breakfast 08:00, lunch 12:00, dinner 18:00,
and snack 15:00. Users can override or disable a generated preparation reminder
on a particular planned meal.

This explicit model is safer and more useful than inferring thaw time at sync
time. It also generalizes to preparation that is not tied to frozen inventory.

## Settings

Add a server-readable settings document without credentials:

```text
settings/calendar_sync
  enabled: true
  calendar_id: <Google secondary calendar ID>
  time_zone: America/New_York
  grocery_lead_days: 1
  grocery_time: "18:00"
  grocery_reminder_minutes: 0
  prep_reminder_minutes: 0
  slot_times:
    breakfast: "08:00"
    lunch: "12:00"
    dinner: "18:00"
    snack: "15:00"
  last_success_at: <timestamp>
  last_error: <sanitized string or null>
```

Store OAuth credentials separately from these preferences. For this private,
single-user application, Firebase Secret Manager is the simplest credential
store and follows the existing `PANTRY_API_TOKEN` deployment pattern. If the
app later supports several independent users, replace that with per-user,
server-only encrypted token storage.

## API surface

The Pantry GPT does not need direct Google credentials or a second action. It
continues to call `POST /v1/plans`; synchronization happens after the Firestore
commit.

Add authenticated maintenance endpoints for the owner:

- `GET /v1/calendar/status` — enabled state, calendar name, last successful
  synchronization, and sanitized error state.
- `POST /v1/calendar/sync` — request an idempotent reconciliation.
- `DELETE /v1/calendar/events` — remove Pantry-managed events only, useful when
  disconnecting.

OAuth connection setup should be a separate owner-only flow. It must not use the
static Pantry GPT bearer token as the browser login mechanism.

## Failure behavior

- Plan writes succeed even if Google is unavailable; Calendar state is retried
  asynchronously.
- A Calendar failure is recorded in sanitized form and is visible in settings.
- A missing or revoked refresh token disables synchronization and asks the user
  to reconnect. It must not cause repeated unauthenticated requests.
- Use exponential retry for transient `429` and `5xx` responses.
- A failed reconciliation never deletes unrecognized Calendar events.

## Delivery sequence

1. Add and test `first_needed_date` derivation in Dart and Cloud Functions.
2. Add a planning-sync marker to both Firestore write paths.
3. Add the Calendar settings model and UI, initially disabled.
4. Implement OAuth connection and creation of the `Pantry Planner` calendar.
5. Implement idempotent grocery-event reconciliation.
6. Add recipe preparation rules and thaw-event reconciliation.
7. Add status, reconnect, and managed-event cleanup controls.
8. Exercise create, edit, move, complete, and delete-plan scenarios against a
   test calendar before enabling production synchronization.

## Open product choices

- Default grocery lead: one day or two days.
- Whether grocery reminders should be one event per shopping trip or one event
  per item. One event per trip is the recommended default.
- Whether meal slot times are global preferences or editable per planned meal.
- Whether checking every grocery item should immediately remove the event or
  mark it completed in the event title.
- Whether preparation rules live on canonical foods, recipes, or both. Recipe
  rules are the recommended first version because their context is clearer.
