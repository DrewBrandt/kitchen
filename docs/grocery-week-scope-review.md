# Explicit grocery week scope

Local follow-up to `6ed6ea2`. No database migration, function deployment, access change, or live mutation.

- Plan and Groceries share one selected Monday–Sunday range. The current week derives from the configured owner timezone; calendar arithmetic does not shift dates through the device timezone or daylight-saving transitions.
- Rebuild passes that exact range through App, Root, and the existing repository RPC. Navigation and plan edits never trigger it. A pending request retains its submitted range and disables another rebuild.
- The grocery page independently displays the distinct ranges recorded on generated rows. It includes inactive rows because a zero-shortage rebuild can leave only inactive rows, and reports missing/mixed ranges rather than assuming the selected week was used. With no generated records, the database cannot establish a previous rebuild; the UI says no saved generated range.
- No stale-plan badge is added. Existing data has no reliable plan revision corresponding to generated demand, so a local edited flag would miss GPT and other-session changes. Saved range is not a freshness guarantee. Selection persists across page navigation, not app reloads.

Existing reconciliation semantics are unchanged: rebuilding replaces the active generated forecast globally, not an independent list per week. Inactive generated rows retain IDs, manual quantities, notes, checks, pins, and receipt links but disappear from the grocery view. Reappearing demand can reuse those old checks and quantities; standalone manual rows remain separate. This change neither resets that state nor provides historical list snapshots or exact rebuild undo.

Regression coverage includes owner timezone boundaries, previous/next weeks across month/year boundaries, the actual repository RPC arguments, selected versus persisted ranges, failed/in-flight rebuilds, externally refreshed metadata, direct-product and grouped-plan portion edits, and hidden/legacy/mixed generated rows. Pixel-level browser acceptance remains separate.
