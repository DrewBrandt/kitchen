// @vitest-environment node
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createFormAttempt, formTimestamp, mutationError, runRetryableMutation } from './mutation-feedback';

const stored = new Map<string, string>();
vi.stubGlobal('localStorage', { getItem: (key: string) => stored.get(key) ?? null, setItem: (key: string, value: string) => stored.set(key, value), clear: () => stored.clear() });
beforeEach(() => localStorage.clear());

describe('mutation feedback and retry identity', () => {
  it('retries ambiguous direct actions with the same identity and permits a new action after success', async () => {
    const client = {};
    const attempts: string[] = [];
    let fail = true;
    const perform = async (id: string, timestamp: string) => { attempts.push(`${id}/${timestamp}`); if (fail) throw new Error('Connection lost'); return 'saved'; };
    await expect(runRetryableMutation(client, 'eat', { lot: 'one', quantity: 1 }, perform)).rejects.toThrow('Connection lost');
    fail = false;
    await expect(runRetryableMutation({}, 'eat', { lot: 'one', quantity: 1 }, perform)).resolves.toBe('saved');
    expect(attempts[1]).toBe(attempts[0]);
    await runRetryableMutation(client, 'eat', { lot: 'one', quantity: 1 }, perform);
    expect(attempts[2]).not.toBe(attempts[0]);
  });
  it('reuses the request and generated timestamp after ambiguous failure, but changes identity when input changes', async () => {
    const attempt = createFormAttempt();
    const form = () => { const data = new FormData(); data.set('label', 'Lunch'); return data; };
    const first = await attempt(form());
    const retry = await createFormAttempt()(form());
    expect(retry.get('request_id')).toBe(first.get('request_id'));
    expect(retry.get('occurred_at')).toBe(first.get('occurred_at'));
    expect(JSON.stringify([...stored])).not.toContain('Lunch');
    const changed = form(); changed.set('label', 'Dinner');
    expect((await attempt(changed)).get('request_id')).not.toBe(first.get('request_id'));
  });

  it('shows PostgREST validation messages and a clear permission error', () => {
    expect(mutationError({ code: 'P0001', message: 'Prepared lot has only 1 serving remaining' })).toContain('only 1 serving');
    expect(mutationError({ code: '42501', message: 'permission denied for function private_helper' })).toBe('This action is not enabled for your signed-in account. Your change was not saved.');
  });

  it('retains a date-only entry in the pantry time zone', () => {
    const form = new FormData();
    form.set('occurred_at', '2026-01-02T00:05');
    form.set('time_precision', 'dateOnly');
    form.set('owner_time_zone', 'America/Los_Angeles');
    expect(formTimestamp(form, 'occurred_at')).toBe('2026-01-02T20:00:00.000Z');
    form.set('time_precision', 'exact');
    expect(formTimestamp(form, 'occurred_at')).toBe('2026-01-02T08:05:00.000Z');
  });

  it('rejects a nonexistent local time during the spring clock change', () => {
    const form = new FormData();
    form.set('occurred_at', '2026-03-08T02:30');
    form.set('owner_time_zone', 'America/Los_Angeles');
    expect(() => formTimestamp(form, 'occurred_at')).toThrow('does not exist');
  });
});
