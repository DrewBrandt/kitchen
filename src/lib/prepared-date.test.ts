import { expect, it } from 'vitest';
import { formatPreparedAt } from './format';

it('formats preparation dates in the pantry timezone across a day boundary', () => {
  expect(formatPreparedAt('2026-10-02T01:30:00Z', 'America/Los_Angeles')).toContain('Oct 1, 2026');
  expect(formatPreparedAt('2026-10-02T01:30:00Z', 'Asia/Tokyo')).toContain('Oct 2, 2026');
});
