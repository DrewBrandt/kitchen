// Delivered in tools/list as well as initialize: clients may not retain server instructions.
export const pendingWriteGuidance = 'A proposed, pending-approval, cancelled or definitively failed write is not a committed meal. If the user revises that pending action (for example, "Actually, one serving, not two"), revise the pending intent; do not correct or void an older meal. Ask the user to cancel/decline the superseded approval if the client still shows it; do not claim you cancelled it or submit a replacement while the old action could still execute. Once it is confirmed unexecuted, submit only the revised action with a fresh requestId. For an ambiguous timeout/error, first reconcile the original action; never infer success or failure. Retry that same action only with its original requestId and identical arguments. A changed quantity is a different action. An existing similar meal does not by itself make a new eating report a duplicate; a clear normal eating report needs no extra confirmation.';

export const correctionTargetGuidance = 'Bind a correction or void to the exact event ID returned by a successful write in this conversation, or to an existing meal the user explicitly identifies. A pending approval is not a successful tool result. Do not search history for a superficially similar older event to satisfy a revision of a pending action. Readback verifies an already identified target; matching food, date or quantity alone does not establish user intent. If the target or execution state is ambiguous, ask which action/meal they mean before proposing a mutation.';

export const eatingTimeGuidance = 'A logging timestamp is not evidence of the exact eating time. Use the saved routine time zone: a user-specified exact time uses timePrecision=exact; an approximate time uses estimated; a date-only report uses dateOnly with local noon as a sorting anchor. Do not silently label the current clock time as exact eating time. For "today" with no actual time, use dateOnly. If this tool has no timePrecision field, clarify the actual eating time before using it when unknown; do not switch tools and lose plan linkage.';

const eatingTools = new Set(['consume_prepared', 'consume_inventory', 'consume_purchased_product', 'log_manual_consumption', 'fulfill_planned_entry']);
const correctionTools = new Set(['correct_consumed_quantity', 'edit_consumption', 'void_consumption']);
export function intentDescription(name: string, description: string): string {
  if (eatingTools.has(name)) return `${description} ${pendingWriteGuidance} ${eatingTimeGuidance}`;
  if (correctionTools.has(name)) return `${description} ${correctionTargetGuidance} ${pendingWriteGuidance}`;
  if (name === 'get_history') return `${description} ${correctionTargetGuidance}`;
  return description;
}
