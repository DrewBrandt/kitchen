import { createCipheriv, createDecipheriv, createHash, randomBytes } from "node:crypto";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, Timestamp, getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { defineSecret } from "firebase-functions/params";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { onRequest } from "firebase-functions/v2/https";

import {
  CalendarSyncSettings,
  JsonRecord,
  calendarEventChanged,
  deriveDesiredCalendarEvents,
  parseCalendarSettings,
} from "./calendar_logic";

const calendarClientId = defineSecret("GOOGLE_CALENDAR_CLIENT_ID");
const calendarClientSecret = defineSecret("GOOGLE_CALENDAR_CLIENT_SECRET");
const calendarTokenKey = defineSecret("CALENDAR_TOKEN_KEY");

const calendarScope = "https://www.googleapis.com/auth/calendar.app.created";
const calendarSettings = "calendar_sync";
const planningSync = "planning_sync";
const credentialDocument = "google";
const allowedOrigins = new Set([
  "https://pantry-tracker-4bc45.firebaseapp.com",
  "https://pantry-tracker-4bc45.web.app",
  "https://drewbrandt.github.io",
  "http://localhost",
  "http://localhost:5000",
]);

export async function readCalendarStatus(): Promise<JsonRecord> {
  const snapshot = await getFirestore().collection("settings").doc(calendarSettings).get();
  const data = snapshot.data() ?? {};
  return {
    enabled: data.enabled === true,
    connected: typeof data.calendar_id === "string" && data.calendar_id.length > 0,
    calendarName: data.calendar_name ?? null,
    timeZone: data.time_zone ?? "America/New_York",
    groceryLeadDays: data.grocery_lead_days ?? 1,
    groceryTime: data.grocery_time ?? "18:00",
    lastSuccessAt: timestampText(data.last_success_at),
    lastAttemptAt: timestampText(data.last_attempt_at),
    lastError: typeof data.last_error === "string" ? data.last_error : null,
  };
}

export async function requestCalendarReconciliation(action: "sync" | "clear" = "sync"): Promise<string> {
  const generation = randomBytes(16).toString("hex");
  const db = getFirestore();
  const batch = db.batch();
  if (action === "clear") {
    batch.set(db.collection("settings").doc(calendarSettings), { enabled: false }, { merge: true });
  }
  batch.set(db.collection("settings").doc(planningSync), {
    generation,
    action,
    requested_at: FieldValue.serverTimestamp(),
  });
  await batch.commit();
  return generation;
}

export const calendarAuth = onRequest(
  {
    region: "us-east4",
    secrets: [calendarClientId, calendarClientSecret, calendarTokenKey],
    invoker: "public",
    timeoutSeconds: 60,
    maxInstances: 1,
  },
  async (request, response) => {
    setCors(request.get("origin"), response);
    if (request.method === "OPTIONS") {
      response.status(204).send("");
      return;
    }
    try {
      const mode = typeof request.query.mode === "string" ? request.query.mode : "callback";
      if (mode === "start") {
        if (request.method !== "POST") {
          response.status(405).json({ error: "Use POST to begin Calendar connection" });
          return;
        }
        const uid = await verifyOwner(request.get("authorization"));
        const returnOrigin = normalizeReturnOrigin(request.get("origin"));
        const state = randomBytes(32).toString("base64url");
        await getFirestore().collection("_calendar_oauth_states").doc(state).set({
          uid,
          return_origin: returnOrigin,
          expires_at: Timestamp.fromMillis(Date.now() + 10 * 60 * 1000),
          created_at: FieldValue.serverTimestamp(),
        });
        const callbackUrl = calendarCallbackUrl(request.get("host"));
        const url = new URL("https://accounts.google.com/o/oauth2/v2/auth");
        url.searchParams.set("client_id", calendarClientId.value());
        url.searchParams.set("redirect_uri", callbackUrl);
        url.searchParams.set("response_type", "code");
        url.searchParams.set("scope", calendarScope);
        url.searchParams.set("access_type", "offline");
        url.searchParams.set("prompt", "consent");
        url.searchParams.set("state", state);
        response.status(200).json({ authorizationUrl: url.toString() });
        return;
      }

      if (request.method !== "GET") {
        response.status(405).send("Method not allowed");
        return;
      }
      const code = requiredQuery(request.query.code, "code");
      const state = requiredQuery(request.query.state, "state");
      const stateReference = getFirestore().collection("_calendar_oauth_states").doc(state);
      const stateData = await getFirestore().runTransaction(async (transaction) => {
        const stateSnapshot = await transaction.get(stateReference);
        const data = stateSnapshot.data();
        const expiry = data?.expires_at;
        if (!stateSnapshot.exists || !(expiry instanceof Timestamp) || expiry.toMillis() < Date.now()) {
          if (stateSnapshot.exists) transaction.delete(stateReference);
          throw new Error("This Calendar connection link has expired. Return to Pantry and try again.");
        }
        transaction.delete(stateReference);
        return data;
      });
      const callbackUrl = calendarCallbackUrl(request.get("host"));
      const token = await tokenRequest({
        client_id: calendarClientId.value(),
        client_secret: calendarClientSecret.value(),
        code,
        redirect_uri: callbackUrl,
        grant_type: "authorization_code",
      });
      if (typeof token.refresh_token !== "string" || token.refresh_token.length === 0) {
        throw new Error("Google did not return offline access. Reconnect and approve Calendar access.");
      }
      const accessToken = requiredText(token.access_token, "Google access token");
      const encrypted = encryptToken(token.refresh_token, calendarTokenKey.value());
      await getFirestore().collection("_private_calendar_credentials").doc(credentialDocument).set({
        ...encrypted,
        scope: calendarScope,
        owner_uid: stateData?.uid ?? null,
        updated_at: FieldValue.serverTimestamp(),
      });
      const currentSettings = await getFirestore().collection("settings").doc(calendarSettings).get();
      const existingCalendarId = currentSettings.data()?.calendar_id;
      const calendar = await ensurePantryCalendar(
        accessToken,
        typeof existingCalendarId === "string" ? existingCalendarId : undefined,
      );
      await getFirestore().collection("settings").doc(calendarSettings).set({
        enabled: true,
        calendar_id: calendar.id,
        calendar_name: calendar.summary ?? "Pantry Planner",
        time_zone: currentSettings.data()?.time_zone ?? "America/New_York",
        grocery_lead_days: currentSettings.data()?.grocery_lead_days ?? 1,
        grocery_time: currentSettings.data()?.grocery_time ?? "18:00",
        grocery_reminder_minutes: currentSettings.data()?.grocery_reminder_minutes ?? 0,
        prep_reminder_minutes: currentSettings.data()?.prep_reminder_minutes ?? 0,
        slot_times: currentSettings.data()?.slot_times ?? {
          breakfast: "08:00",
          lunch: "12:00",
          dinner: "18:00",
          snack: "15:00",
        },
        connected_at: FieldValue.serverTimestamp(),
        last_error: null,
      }, { merge: true });
      await requestCalendarReconciliation();
      const returnOrigin = normalizeReturnOrigin(
        typeof stateData?.return_origin === "string" ? stateData.return_origin : undefined,
      );
      response.status(200).type("html").send(successHtml(returnOrigin));
    } catch (error) {
      const message = safeError(error);
      logger.error("Calendar OAuth failed", { message });
      response.status(400).type("html").send(errorHtml(message));
    }
  },
);

export const syncPlanningCalendar = onDocumentWritten(
  {
    document: "settings/planning_sync",
    region: "us-east4",
    secrets: [calendarClientId, calendarClientSecret, calendarTokenKey],
    timeoutSeconds: 120,
    maxInstances: 1,
    retry: true,
  },
  async (event) => {
    const marker = event.data?.after.data() ?? {};
    const generation = typeof marker.generation === "string" ? marker.generation : event.id;
    const action = marker.action === "clear" ? "clear" : "sync";
    const settingsReference = getFirestore().collection("settings").doc(calendarSettings);
    await settingsReference.set({ last_attempt_at: FieldValue.serverTimestamp() }, { merge: true });
    try {
      const settingsSnapshot = await settingsReference.get();
      const settings = parseCalendarSettings(settingsSnapshot.data() ?? {});
      if (settings.calendarId == null) {
        if (settings.enabled) throw new Error("Google Calendar is not connected");
        return;
      }
      const refreshToken = await loadRefreshToken();
      const accessToken = await refreshAccessToken(refreshToken);
      await reconcileCalendar(accessToken, settings, generation, action);
      await settingsReference.set({
        last_success_at: FieldValue.serverTimestamp(),
        last_error: null,
      }, { merge: true });
    } catch (error) {
      const message = safeError(error);
      logger.error("Calendar reconciliation failed", { generation, action, message });
      const revoked = message.includes("invalid_grant") || message.includes("revoked");
      await settingsReference.set({
        last_error: message,
        ...(revoked ? { enabled: false } : {}),
      }, { merge: true });
      const transient = /Google Calendar (429|5\d\d):/.test(message) ||
        /Google OAuth (429|5\d\d):/.test(message);
      if (transient && !revoked) throw error;
    }
  },
);

async function reconcileCalendar(
  accessToken: string,
  settings: CalendarSyncSettings,
  generation: string,
  action: "sync" | "clear",
): Promise<void> {
  const db = getFirestore();
  const [meals, groceries, recipes, mealTemplates] = await Promise.all([
    db.collection("meal_plan").get(),
    db.collection("grocery_list").get(),
    db.collection("recipes").get(),
    db.collection("meal_templates").get(),
  ]);
  const desired = action === "clear"
    ? []
    : deriveDesiredCalendarEvents({
      settings,
      generation,
      meals: meals.docs.map((document) => ({ id: document.id, data: document.data() })),
      groceries: groceries.docs.map((document) => ({ id: document.id, data: document.data() })),
      recipes: new Map(recipes.docs.map((document) => [document.id, document.data()])),
      mealTemplates: new Map(mealTemplates.docs.map((document) => [document.id, document.data()])),
    });
  const existing = await listManagedEvents(accessToken, settings.calendarId!);
  const existingByReminder = new Map<string, JsonRecord>();
  for (const item of existing) {
    const privateProperties = (item.extendedProperties as JsonRecord | undefined)?.private;
    const reminderId = privateProperties != null && typeof privateProperties === "object"
      ? (privateProperties as JsonRecord).pantryReminderId
      : undefined;
    if (typeof reminderId === "string") existingByReminder.set(reminderId, item);
  }
  const desiredIds = new Set(desired.map((item) => item.reminderId));
  for (const item of desired) {
    const current = existingByReminder.get(item.reminderId);
    if (current == null) {
      await calendarRequest(accessToken, `/calendars/${encodeURIComponent(settings.calendarId!)}/events`, {
        method: "POST",
        body: item,
      });
    } else if (calendarEventChanged(current, item)) {
      await calendarRequest(
        accessToken,
        `/calendars/${encodeURIComponent(settings.calendarId!)}/events/${encodeURIComponent(requiredText(current.id, "event id"))}`,
        { method: "PATCH", body: item },
      );
    }
  }
  for (const item of existing) {
    const privateProperties = (item.extendedProperties as JsonRecord | undefined)?.private;
    const reminderId = privateProperties != null && typeof privateProperties === "object"
      ? (privateProperties as JsonRecord).pantryReminderId
      : undefined;
    if (typeof reminderId !== "string" || desiredIds.has(reminderId)) continue;
    await calendarRequest(
      accessToken,
      `/calendars/${encodeURIComponent(settings.calendarId!)}/events/${encodeURIComponent(requiredText(item.id, "event id"))}`,
      { method: "DELETE" },
    );
  }
}

async function listManagedEvents(accessToken: string, calendarId: string): Promise<JsonRecord[]> {
  const result: JsonRecord[] = [];
  let pageToken: string | undefined;
  do {
    const query = new URLSearchParams({ privateExtendedProperty: "pantryManaged=true", maxResults: "2500" });
    if (pageToken != null) query.set("pageToken", pageToken);
    const page = await calendarRequest(
      accessToken,
      `/calendars/${encodeURIComponent(calendarId)}/events?${query.toString()}`,
    );
    if (Array.isArray(page.items)) {
      result.push(...page.items.filter((item): item is JsonRecord => item != null && typeof item === "object"));
    }
    pageToken = typeof page.nextPageToken === "string" ? page.nextPageToken : undefined;
  } while (pageToken != null);
  return result;
}

async function ensurePantryCalendar(
  accessToken: string,
  existingCalendarId?: string,
): Promise<{ id: string; summary?: string }> {
  if (existingCalendarId != null) {
    try {
      const existing = await calendarRequest(accessToken, `/calendars/${encodeURIComponent(existingCalendarId)}`);
      return { id: requiredText(existing.id, "calendar id"), summary: optionalText(existing.summary) };
    } catch (error) {
      if (!safeError(error).includes("404")) throw error;
    }
  }
  const created = await calendarRequest(accessToken, "/calendars", {
    method: "POST",
    body: { summary: "Pantry Planner", description: "Grocery and preparation reminders managed by Pantry." },
  });
  return { id: requiredText(created.id, "calendar id"), summary: optionalText(created.summary) };
}

async function refreshAccessToken(refreshToken: string): Promise<string> {
  const token = await tokenRequest({
    client_id: calendarClientId.value(),
    client_secret: calendarClientSecret.value(),
    refresh_token: refreshToken,
    grant_type: "refresh_token",
  });
  return requiredText(token.access_token, "Google access token");
}

async function tokenRequest(parameters: Record<string, string>): Promise<JsonRecord> {
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(parameters),
  });
  const body = await response.json() as JsonRecord;
  if (!response.ok) {
    throw new Error(`Google OAuth ${response.status}: ${optionalText(body.error) ?? "request failed"}`);
  }
  return body;
}

async function calendarRequest(
  accessToken: string,
  path: string,
  options: { method?: string; body?: unknown } = {},
): Promise<JsonRecord> {
  for (let attempt = 0; attempt < 4; attempt += 1) {
    const response = await fetch(`https://www.googleapis.com/calendar/v3${path}`, {
      method: options.method ?? "GET",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        ...(options.body == null ? {} : { "Content-Type": "application/json" }),
      },
      ...(options.body == null ? {} : { body: JSON.stringify(options.body) }),
    });
    if (response.ok) {
      if (response.status === 204) return {};
      return await response.json() as JsonRecord;
    }
    const detail = (await response.text()).slice(0, 500);
    if ((response.status === 429 || response.status >= 500) && attempt < 3) {
      await new Promise((resolve) => setTimeout(resolve, [250, 750, 1750][attempt]));
      continue;
    }
    throw new Error(`Google Calendar ${response.status}: ${detail}`);
  }
  throw new Error("Google Calendar retry limit reached");
}

async function verifyOwner(authorization: string | undefined): Promise<string> {
  if (!authorization?.startsWith("Bearer ")) throw new Error("Sign in to Pantry first");
  const decoded = await getAuth().verifyIdToken(authorization.substring(7));
  const access = await getFirestore().collection("app_access").doc(decoded.uid).get();
  if (!access.exists) throw new Error("This account does not have Pantry access");
  return decoded.uid;
}

function encryptToken(token: string, secret: string): JsonRecord {
  if (secret.length < 20) throw new Error("CALENDAR_TOKEN_KEY must contain at least 20 characters");
  const key = createHash("sha256").update(secret).digest();
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  const encrypted = Buffer.concat([cipher.update(token, "utf8"), cipher.final()]);
  return {
    ciphertext: encrypted.toString("base64"),
    iv: iv.toString("base64"),
    tag: cipher.getAuthTag().toString("base64"),
    algorithm: "aes-256-gcm",
  };
}

async function loadRefreshToken(): Promise<string> {
  const snapshot = await getFirestore().collection("_private_calendar_credentials").doc(credentialDocument).get();
  if (!snapshot.exists) throw new Error("Google Calendar must be reconnected");
  const data = snapshot.data() ?? {};
  const key = createHash("sha256").update(calendarTokenKey.value()).digest();
  const decipher = createDecipheriv("aes-256-gcm", key, Buffer.from(requiredText(data.iv, "credential iv"), "base64"));
  decipher.setAuthTag(Buffer.from(requiredText(data.tag, "credential tag"), "base64"));
  return Buffer.concat([
    decipher.update(Buffer.from(requiredText(data.ciphertext, "credential ciphertext"), "base64")),
    decipher.final(),
  ]).toString("utf8");
}

function calendarCallbackUrl(host: string | undefined): string {
  const projectId = process.env.GCLOUD_PROJECT ?? "pantry-tracker-4bc45";
  const safeHost = host?.endsWith("cloudfunctions.net") ? host : `us-east4-${projectId}.cloudfunctions.net`;
  return `https://${safeHost}/calendarAuth`;
}

function normalizeReturnOrigin(origin: string | undefined): string {
  if (origin != null) {
    try {
      const parsed = new URL(origin);
      const normalized = parsed.port.length > 0 ? parsed.origin : `${parsed.protocol}//${parsed.hostname}`;
      if (allowedOrigins.has(normalized) || parsed.hostname === "localhost") return parsed.origin;
    } catch {
      // Fall through to the production app.
    }
  }
  return "https://pantry-tracker-4bc45.firebaseapp.com";
}

function setCors(origin: string | undefined, response: { set(name: string, value: string): unknown }): void {
  const allowed = normalizeReturnOrigin(origin);
  response.set("Access-Control-Allow-Origin", allowed);
  response.set("Access-Control-Allow-Headers", "Authorization, Content-Type");
  response.set("Access-Control-Allow-Methods", "POST, GET, OPTIONS");
  response.set("Vary", "Origin");
}

function requiredQuery(value: unknown, label: string): string {
  if (typeof value !== "string" || value.trim().length === 0) throw new Error(`Missing ${label}`);
  return value;
}

function requiredText(value: unknown, label: string): string {
  const text = optionalText(value);
  if (text == null) throw new Error(`Missing ${label}`);
  return text;
}

function optionalText(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed.length === 0 ? undefined : trimmed;
}

function timestampText(value: unknown): string | null {
  return value instanceof Timestamp ? value.toDate().toISOString() : null;
}

function safeError(error: unknown): string {
  const message = error instanceof Error ? error.message : "Unexpected Calendar error";
  return message.replace(/[\r\n]+/g, " ").slice(0, 500);
}

function successHtml(returnOrigin: string): string {
  const safeOrigin = returnOrigin.replace(/[&<>"']/g, "");
  return `<!doctype html><meta name="viewport" content="width=device-width"><title>Calendar connected</title><body style="font-family:system-ui;padding:3rem;max-width:42rem;margin:auto"><h1>Pantry Planner is connected</h1><p>Calendar reminders will now follow your meal plan.</p><p><a href="${safeOrigin}">Return to Pantry</a></p><script>setTimeout(()=>window.close(),1500)</script></body>`;
}

function errorHtml(message: string): string {
  const safeMessage = message.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  return `<!doctype html><meta name="viewport" content="width=device-width"><title>Calendar connection failed</title><body style="font-family:system-ui;padding:3rem;max-width:42rem;margin:auto"><h1>Calendar connection failed</h1><p>${safeMessage}</p><p>Return to Pantry and try again.</p></body>`;
}
