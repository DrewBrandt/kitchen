type PendingAttempt = { requestId: string; occurredAt: string };
const storageKey = 'mise.pending-mutations.v1';
function readPending(): Record<string, PendingAttempt> {
  try { return JSON.parse(localStorage.getItem(storageKey) ?? '{}') as Record<string, PendingAttempt>; }
  catch { throw new Error('The browser could not read pending actions. Check browser storage before retrying.'); }
}
function writePending(pending: Record<string, PendingAttempt>) {
  try { localStorage.setItem(storageKey, JSON.stringify(pending)); }
  catch { throw new Error('The browser could not retain this action for safe retry. Check browser storage and try again.'); }
}
function pendingAttempt(key: string): PendingAttempt {
  const pending = readPending();
  if (!pending[key]) { pending[key] = { requestId: crypto.randomUUID(), occurredAt: new Date().toISOString() }; writePending(pending); }
  return pending[key];
}
export function completeFormAttempt(form: FormData) {
  const pending = readPending();
  for (const [key, value] of Object.entries(pending)) if (value.requestId === form.get('request_id')) delete pending[key];
  writePending(pending);
}
/** Retains the payload/identity in this browser across panel closes and reloads. Edited input starts a new action. */
export function createFormAttempt() {
  return (form: FormData) => {
    const fingerprint = JSON.stringify(['form', Array.from(form.entries()).filter(([key]) => key !== 'request_id').sort(([a], [b]) => a.localeCompare(b))]);
    const attempt = pendingAttempt(fingerprint);
    form.set('request_id', attempt.requestId);
    if (!form.get('occurred_at')) form.set('occurred_at', attempt.occurredAt);
    if (!form.get('acquired_at')) form.set('acquired_at', attempt.occurredAt);
    return form;
  };
}

export function mutationError(cause: unknown, fallback = 'Could not save this change.'): string {
  if (!cause || typeof cause !== 'object') return fallback;
  const { message, code } = cause as { message?: unknown; code?: unknown };
  if (code === '42501' || (typeof message === 'string' && /permission denied/i.test(message))) {
    return 'This action is not enabled for your signed-in account. Your change was not saved.';
  }
  return typeof message === 'string' && message.trim() ? message : fallback;
}

/** datetime-local is interpreted in the owner's pantry zone, not the viewing device's zone. */
export function formTimestamp(form: FormData, key: string): string {
  const raw = String(form.get(key) ?? '');
  if (!raw) return new Date().toISOString();
  if (/(?:Z|[+-]\d\d:\d\d)$/.test(raw)) return new Date(raw).toISOString();
  const timeZone = String(form.get('owner_time_zone') ?? Intl.DateTimeFormat().resolvedOptions().timeZone);
  const local = form.get('time_precision') === 'dateOnly' ? `${raw.slice(0, 10)}T12:00:00` : raw;
  const desired = Date.parse(`${local}Z`);
  if (!Number.isFinite(desired)) throw new Error('Choose a valid date and time.');
  const formatter = new Intl.DateTimeFormat('sv-SE', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23' });
  const asWallTime = (value: number) => Date.parse(`${formatter.format(new Date(value)).replace(' ', 'T')}Z`);
  let candidate = desired;
  for (let step = 0; step < 4; step++) candidate += desired - asWallTime(candidate);
  if (asWallTime(candidate) !== desired) throw new Error('That local time does not exist because the clocks changed. Choose another time.');
  return new Date(candidate).toISOString();
}

/** Confirmed results clear the pending action; ambiguous failures remain recoverable after reload. */
export async function runRetryableMutation<T>(_client: object, operation: string, payload: unknown, perform: (requestId: string, occurredAt: string) => Promise<T>): Promise<T> {
  const key = JSON.stringify(['rpc', operation, payload]);
  const attempt = pendingAttempt(key);
  const result = await perform(attempt.requestId, attempt.occurredAt);
  const pending = readPending();
  delete pending[key];
  writePending(pending);
  return result;
}
