export type JsonRecord = Record<string, unknown>;

export type CalendarSyncSettings = {
  enabled: boolean;
  calendarId?: string;
  calendarName: string;
  timeZone: string;
  groceryLeadDays: number;
  groceryTime: string;
  groceryReminderMinutes: number;
  prepReminderMinutes: number;
  slotTimes: Record<string, string>;
};

export type DesiredCalendarEvent = {
  reminderId: string;
  summary: string;
  description: string;
  start: { dateTime: string; timeZone: string };
  end: { dateTime: string; timeZone: string };
  reminders: { useDefault: false; overrides: Array<{ method: "popup"; minutes: number }> };
  extendedProperties: {
    private: {
      pantryManaged: "true";
      pantryReminderId: string;
      pantryPlanGeneration: string;
    };
  };
};

const defaultSlotTimes: Record<string, string> = {
  breakfast: "08:00",
  lunch: "12:00",
  dinner: "18:00",
  snack: "15:00",
};

export function parseCalendarSettings(raw: JsonRecord): CalendarSyncSettings {
  const slotTimes = raw.slot_times != null && typeof raw.slot_times === "object"
    ? raw.slot_times as JsonRecord
    : {};
  return {
    enabled: raw.enabled === true,
    calendarId: optionalText(raw.calendar_id),
    calendarName: optionalText(raw.calendar_name) ?? "Pantry Planner",
    timeZone: optionalText(raw.time_zone) ?? "America/New_York",
    groceryLeadDays: boundedInteger(raw.grocery_lead_days, 1, 0, 14),
    groceryTime: clock(raw.grocery_time, "18:00"),
    groceryReminderMinutes: boundedInteger(raw.grocery_reminder_minutes, 0, 0, 40320),
    prepReminderMinutes: boundedInteger(raw.prep_reminder_minutes, 0, 0, 40320),
    slotTimes: Object.fromEntries(
      Object.entries(defaultSlotTimes).map(([slot, fallback]) => [slot, clock(slotTimes[slot], fallback)]),
    ),
  };
}

export function deriveDesiredCalendarEvents(input: {
  settings: CalendarSyncSettings;
  generation: string;
  meals: Array<{ id: string; data: JsonRecord }>;
  groceries: Array<{ id: string; data: JsonRecord }>;
  recipes: Map<string, JsonRecord>;
  mealTemplates: Map<string, JsonRecord>;
}): DesiredCalendarEvent[] {
  if (!input.settings.enabled || input.settings.calendarId == null) return [];
  const events: DesiredCalendarEvent[] = [];
  const firstNeeded = input.groceries
    .filter(({ data }) => data.from_plan === true && data.checked !== true)
    .map(({ data }) => asDate(data.first_needed_date))
    .filter((date): date is Date => date != null)
    .sort((a, b) => a.getTime() - b.getTime())[0];
  if (firstNeeded != null) {
    const groceryDate = shiftDateOnly(dateKey(firstNeeded), -input.settings.groceryLeadDays);
    const start = zonedInstant(groceryDate, input.settings.groceryTime, input.settings.timeZone);
    const outstanding = input.groceries
      .filter(({ data }) => data.from_plan === true && data.checked !== true)
      .map(({ data }) => optionalText(data.name))
      .filter((name): name is string => name != null);
    events.push(eventBody({
      reminderId: `grocery:${dateKey(firstNeeded)}`,
      generation: input.generation,
      summary: "Grocery run for the meal plan",
      description: outstanding.length === 0
        ? "Shop for the upcoming Pantry meal plan."
        : `Needed for the upcoming Pantry meal plan:\n${outstanding.map((name) => `• ${name}`).join("\n")}`,
      start,
      end: new Date(start.getTime() + 60 * 60 * 1000),
      timeZone: input.settings.timeZone,
      reminderMinutes: input.settings.groceryReminderMinutes,
    }));
  }

  for (const meal of input.meals) {
    if (meal.data.completed_at != null || meal.data.intent === "leftover") continue;
    const mealDate = asDate(meal.data.date);
    const slot = optionalText(meal.data.slot);
    if (mealDate == null || slot == null) continue;
    const slotTime = input.settings.slotTimes[slot];
    if (slotTime == null) continue;
    const sources = recipeSourcesForMeal(meal.data, input.mealTemplates);
    for (const source of sources) {
      const recipe = input.recipes.get(source.recipeId);
      if (recipe == null || !Array.isArray(recipe.preparation_rules)) continue;
      for (const rawRule of recipe.preparation_rules) {
        if (rawRule == null || typeof rawRule !== "object") continue;
        const rule = rawRule as JsonRecord;
        const id = optionalText(rule.id);
        const label = optionalText(rule.label);
        const leadHours = positiveNumber(rule.lead_hours ?? rule.leadHours);
        if (id == null || label == null || leadHours == null) continue;
        const mealStart = zonedInstant(dateKey(mealDate), slotTime, input.settings.timeZone);
        const prepStart = new Date(mealStart.getTime() - leadHours * 60 * 60 * 1000);
        const mealName = optionalText(meal.data.name) ?? "planned meal";
        const suffix = sources.length > 1 ? ` (${optionalText(recipe.name) ?? source.recipeId})` : "";
        events.push(eventBody({
          reminderId: `prep:${meal.id}:${source.recipeId}:${id}`,
          generation: input.generation,
          summary: `${label}${suffix}`,
          description: `Preparation for ${mealName}, planned ${dateKey(mealDate)} at ${slotTime}.`,
          start: prepStart,
          end: new Date(prepStart.getTime() + 30 * 60 * 1000),
          timeZone: input.settings.timeZone,
          reminderMinutes: input.settings.prepReminderMinutes,
        }));
      }
    }
  }
  return events;
}

function recipeSourcesForMeal(
  meal: JsonRecord,
  mealTemplates: Map<string, JsonRecord>,
): Array<{ recipeId: string }> {
  const sourceId = optionalText(meal.source_id);
  if (meal.source === "recipe" && sourceId != null) return [{ recipeId: sourceId }];
  if (meal.source !== "meal" || sourceId == null) return [];
  const template = mealTemplates.get(sourceId);
  if (template == null || !Array.isArray(template.components)) return [];
  return template.components
    .map((raw) => raw != null && typeof raw === "object" ? optionalText((raw as JsonRecord).recipe_id) : undefined)
    .filter((recipeId): recipeId is string => recipeId != null)
    .map((recipeId) => ({ recipeId }));
}

function eventBody(input: {
  reminderId: string;
  generation: string;
  summary: string;
  description: string;
  start: Date;
  end: Date;
  timeZone: string;
  reminderMinutes: number;
}): DesiredCalendarEvent {
  return {
    reminderId: input.reminderId,
    summary: input.summary,
    description: input.description,
    start: { dateTime: input.start.toISOString(), timeZone: input.timeZone },
    end: { dateTime: input.end.toISOString(), timeZone: input.timeZone },
    reminders: {
      useDefault: false,
      overrides: [{ method: "popup", minutes: input.reminderMinutes }],
    },
    extendedProperties: {
      private: {
        pantryManaged: "true",
        pantryReminderId: input.reminderId,
        pantryPlanGeneration: input.generation,
      },
    },
  };
}

export function calendarEventChanged(existing: JsonRecord, desired: DesiredCalendarEvent): boolean {
  return JSON.stringify(comparableEvent(existing)) !== JSON.stringify(comparableEvent(desired));
}

function comparableEvent(event: JsonRecord | DesiredCalendarEvent): JsonRecord {
  const start = event.start as JsonRecord | undefined;
  const end = event.end as JsonRecord | undefined;
  const reminders = event.reminders as JsonRecord | undefined;
  const extended = event.extendedProperties as JsonRecord | undefined;
  const privateProperties = extended?.private as JsonRecord | undefined;
  const overrides = Array.isArray(reminders?.overrides)
    ? reminders.overrides
      .filter((item): item is JsonRecord => item != null && typeof item === "object")
      .map((item) => ({ method: item.method, minutes: item.minutes }))
      .sort((a, b) => Number(a.minutes) - Number(b.minutes))
    : [];
  const startText = typeof start?.dateTime === "string" ? start.dateTime : "";
  const endText = typeof end?.dateTime === "string" ? end.dateTime : "";
  return {
    summary: event.summary,
    description: event.description,
    startMillis: new Date(startText).getTime(),
    startTimeZone: start?.timeZone,
    endMillis: new Date(endText).getTime(),
    endTimeZone: end?.timeZone,
    reminders: { useDefault: reminders?.useDefault, overrides },
    private: {
      pantryManaged: privateProperties?.pantryManaged,
      pantryReminderId: privateProperties?.pantryReminderId,
      pantryPlanGeneration: privateProperties?.pantryPlanGeneration,
    },
  };
}

function asDate(value: unknown): Date | undefined {
  if (value instanceof Date && !Number.isNaN(value.getTime())) return value;
  if (value != null && typeof value === "object" && "toDate" in value) {
    const candidate = (value as { toDate(): Date }).toDate();
    if (!Number.isNaN(candidate.getTime())) return candidate;
  }
  if (typeof value === "string") {
    const candidate = new Date(value);
    if (!Number.isNaN(candidate.getTime())) return candidate;
  }
  return undefined;
}

function optionalText(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed.length === 0 ? undefined : trimmed;
}

function positiveNumber(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) && value > 0 ? value : undefined;
}

function boundedInteger(value: unknown, fallback: number, minimum: number, maximum: number): number {
  return typeof value === "number" && Number.isInteger(value) && value >= minimum && value <= maximum
    ? value
    : fallback;
}

function clock(value: unknown, fallback: string): string {
  return typeof value === "string" && /^([01]\d|2[0-3]):[0-5]\d$/.test(value) ? value : fallback;
}

function dateKey(date: Date): string {
  return date.toISOString().slice(0, 10);
}

function shiftDateOnly(value: string, days: number): string {
  const date = new Date(`${value}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

export function zonedInstant(date: string, time: string, timeZone: string): Date {
  const [year, month, day] = date.split("-").map(Number);
  const [hour, minute] = time.split(":").map(Number);
  const desiredWallTime = Date.UTC(year, month - 1, day, hour, minute);
  let candidate = desiredWallTime;
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const parts = new Intl.DateTimeFormat("en-US", {
      timeZone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hourCycle: "h23",
    }).formatToParts(new Date(candidate));
    const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
    const representedWallTime = Date.UTC(
      Number(values.year),
      Number(values.month) - 1,
      Number(values.day),
      Number(values.hour),
      Number(values.minute),
      Number(values.second),
    );
    const correction = desiredWallTime - representedWallTime;
    if (correction === 0) break;
    candidate += correction;
  }
  return new Date(candidate);
}
