export interface PlanningRange { from: string; through: string }

export function addCalendarDays(dateKey: string, days: number) {
  const date = new Date(`${dateKey}T12:00:00Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

export function planningWeek(todayKey: string, offset = 0): PlanningRange {
  const day = new Date(`${todayKey}T12:00:00Z`).getUTCDay();
  const from = addCalendarDays(todayKey, -((day + 6) % 7) + offset * 7);
  return { from, through: addCalendarDays(from, 6) };
}

export function formatPlanningRange(range: PlanningRange) {
  const label = (key: string, year = false) => new Date(`${key}T12:00:00Z`).toLocaleDateString([], {
    timeZone: 'UTC', month: 'short', day: 'numeric', ...(year ? { year: 'numeric' as const } : {}),
  });
  return `${label(range.from, range.from.slice(0, 4) !== range.through.slice(0, 4))} – ${label(range.through, true)}`;
}
