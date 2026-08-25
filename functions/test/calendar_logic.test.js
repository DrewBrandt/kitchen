const assert = require("node:assert/strict");
const test = require("node:test");

const {
  calendarEventChanged,
  deriveDesiredCalendarEvents,
  parseCalendarSettings,
  zonedInstant,
} = require("../lib/calendar_logic.js");

test("zonedInstant handles daylight-saving offsets", () => {
  assert.equal(
    zonedInstant("2026-01-15", "18:00", "America/New_York").toISOString(),
    "2026-01-15T23:00:00.000Z",
  );
  assert.equal(
    zonedInstant("2026-08-15", "18:00", "America/New_York").toISOString(),
    "2026-08-15T22:00:00.000Z",
  );
});

test("derives one grocery event from the earliest unchecked shortage", () => {
  const settings = parseCalendarSettings({
    enabled: true,
    calendar_id: "calendar-id",
    time_zone: "America/New_York",
    grocery_lead_days: 1,
    grocery_time: "18:00",
  });
  const events = deriveDesiredCalendarEvents({
    settings,
    generation: "generation-1",
    meals: [],
    groceries: [
      { id: "later", data: { name: "Milk", from_plan: true, checked: false, first_needed_date: "2026-08-28" } },
      { id: "done", data: { name: "Eggs", from_plan: true, checked: true, first_needed_date: "2026-08-24" } },
      { id: "first", data: { name: "Rice", from_plan: true, checked: false, first_needed_date: "2026-08-26" } },
    ],
    recipes: new Map(),
    mealTemplates: new Map(),
  });
  assert.equal(events.length, 1);
  assert.equal(events[0].reminderId, "grocery:2026-08-26");
  assert.equal(events[0].start.dateTime, "2026-08-25T22:00:00.000Z");
  assert.match(events[0].description, /Milk/);
  assert.match(events[0].description, /Rice/);
  assert.doesNotMatch(events[0].description, /Eggs/);
});

test("derives explicit preparation rules for recipes and combined meals", () => {
  const settings = parseCalendarSettings({ enabled: true, calendar_id: "calendar-id" });
  const chicken = {
    name: "Roast chicken",
    preparation_rules: [
      { id: "thaw", kind: "thaw", label: "Move chicken to the refrigerator", lead_hours: 24 },
    ],
  };
  const events = deriveDesiredCalendarEvents({
    settings,
    generation: "generation-2",
    meals: [
      {
        id: "meal-1",
        data: {
          date: "2026-08-27",
          slot: "dinner",
          source: "meal",
          source_id: "dinner-template",
          intent: "prepare",
          name: "Chicken dinner",
          completed_at: null,
        },
      },
    ],
    groceries: [],
    recipes: new Map([["chicken", chicken]]),
    mealTemplates: new Map([["dinner-template", { components: [{ recipe_id: "chicken" }] }]]),
  });
  assert.equal(events.length, 1);
  assert.equal(events[0].reminderId, "prep:meal-1:chicken:thaw");
  assert.equal(events[0].start.dateTime, "2026-08-26T22:00:00.000Z");
  assert.equal(events[0].extendedProperties.private.pantryManaged, "true");
});

test("derives plan-specific prep tasks from an exact meal time", () => {
  const settings = parseCalendarSettings({
    enabled: true,
    calendar_id: "calendar-id",
    time_zone: "America/New_York",
  });
  const events = deriveDesiredCalendarEvents({
    settings,
    generation: "generation-task",
    meals: [{
      id: "late-dinner",
      data: {
        date: "2026-09-03",
        slot: "dinner",
        scheduled_time: "20:15",
        source: "custom",
        name: "Dinner after class",
        preparation_tasks: [{
          id: "thaw-chicken",
          kind: "thaw",
          label: "Move chicken to the refrigerator",
          lead_hours: 24,
          duration_minutes: 5,
        }],
      },
    }],
    groceries: [],
    recipes: new Map(),
    mealTemplates: new Map(),
  });
  assert.equal(events.length, 1);
  assert.equal(events[0].reminderId, "task:late-dinner:thaw-chicken");
  assert.equal(events[0].start.dateTime, "2026-09-03T00:15:00.000Z");
  assert.equal(events[0].end.dateTime, "2026-09-03T00:20:00.000Z");
  assert.match(events[0].description, /20:15/);
});

test("disabled settings derive no desired events", () => {
  const events = deriveDesiredCalendarEvents({
    settings: parseCalendarSettings({ enabled: false, calendar_id: "calendar-id" }),
    generation: "generation-3",
    meals: [],
    groceries: [{ id: "item", data: { from_plan: true, first_needed_date: "2026-08-26" } }],
    recipes: new Map(),
    mealTemplates: new Map(),
  });
  assert.deepEqual(events, []);
});

test("event comparison detects only managed field changes", () => {
  const desired = deriveDesiredCalendarEvents({
    settings: parseCalendarSettings({ enabled: true, calendar_id: "calendar-id" }),
    generation: "generation-4",
    meals: [],
    groceries: [{ id: "item", data: { name: "Flour", from_plan: true, first_needed_date: "2026-08-26" } }],
    recipes: new Map(),
    mealTemplates: new Map(),
  })[0];
  assert.equal(calendarEventChanged({ ...desired, id: "google-event" }, desired), false);
  assert.equal(calendarEventChanged({ ...desired, summary: "Changed" }, desired), true);
});
