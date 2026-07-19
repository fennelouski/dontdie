// Don't Die backend — Supabase Edge Function deployment.
//
// This is the production port of backend/src/app.js (the zero-dependency Node
// reference implementation, which remains the source of truth for behavior and
// carries the test suite). Same routes, same response shapes, backed by
// Postgres instead of the JSON file store.
//
// Deployed with verify_jwt=false: routes are either self-authenticating
// (per-device bearer tokens, hashed at rest) or public webhooks/health checks.

import { createClient } from "jsr:@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const DAILY_REWARD_CAP_MB = 200;
const REWARD_MB_PER_MINUTE = 1;
const LEGACY_DEVICE_ID = "00000000-0000-0000-0000-000000000001";
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// ---- helpers ----

function normalizePhoneNumber(input: unknown): string | null {
  if (typeof input !== "string") return null;
  const digits = input.replace(/[^\d+]/g, "");
  if (/^\+1\d{10}$/.test(digits)) return digits;
  if (/^1\d{10}$/.test(digits)) return "+" + digits;
  if (/^\d{10}$/.test(digits)) return "+1" + digits;
  return null;
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function randomTokenHex(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function isoZ(value: string | Date): string {
  return new Date(value).toISOString();
}

function xmlEscape(value: unknown): string {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

const twimlSay = (message: string) =>
  `<?xml version="1.0" encoding="UTF-8"?>\n<Response><Say voice="alice">${xmlEscape(message)}</Say></Response>`;
const twimlMessage = (message: string) =>
  `<?xml version="1.0" encoding="UTF-8"?>\n<Response><Message>${xmlEscape(message)}</Message></Response>`;
const twimlEmpty = () => '<?xml version="1.0" encoding="UTF-8"?>\n<Response></Response>';

class ApiError extends Error {
  constructor(public status: number, public code: string, message: string) {
    super(message);
  }
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function xml(body: string): Response {
  return new Response(body, { status: 200, headers: { "Content-Type": "text/xml" } });
}

// ---- data access ----

type DeviceRow = {
  device_id: string;
  token_hash: string;
  phone_number: string | null;
  total_reward_mb: number;
  rewards_by_day: Record<string, number>;
  current_session_id: string | null;
};

type SessionRow = {
  session_id: string;
  device_id: string;
  started_at: string;
  ended_at: string | null;
  reward_earned_mb: number;
};

async function getDevice(deviceId: string): Promise<DeviceRow | null> {
  if (!UUID_RE.test(deviceId)) return null;
  const { data, error } = await supabase.from("devices").select("*").eq("device_id", deviceId).maybeSingle();
  if (error) throw error;
  return data;
}

async function getSession(sessionId: string): Promise<SessionRow | null> {
  const { data, error } = await supabase.from("sessions").select("*").eq("session_id", sessionId).maybeSingle();
  if (error) throw error;
  return data;
}

async function requireDevice(req: Request, deviceId: string): Promise<DeviceRow> {
  const device = await getDevice(deviceId);
  if (!device) throw new ApiError(404, "device_not_found", "Unknown device.");
  const match = (req.headers.get("authorization") || "").match(/^Bearer\s+(\S+)$/i);
  if (!match) throw new ApiError(401, "missing_token", "Authorization: Bearer <deviceToken> header required.");
  const hashed = await sha256Hex(match[1]);
  if (!constantTimeEqual(hashed, device.token_hash)) {
    throw new ApiError(401, "invalid_token", "Device token is not valid for this device.");
  }
  return device;
}

function publicSession(session: SessionRow | null) {
  return session ? { sessionId: session.session_id, startedAt: isoZ(session.started_at) } : null;
}

function fullSession(session: SessionRow) {
  return {
    sessionId: session.session_id,
    deviceId: session.device_id,
    startedAt: isoZ(session.started_at),
    endedAt: session.ended_at ? isoZ(session.ended_at) : null,
    rewardEarnedMB: session.reward_earned_mb,
  };
}

async function publicDevice(device: DeviceRow) {
  const session = device.current_session_id ? await getSession(device.current_session_id) : null;
  return {
    deviceId: device.device_id,
    driveMode: Boolean(session),
    phoneNumber: device.phone_number,
    totalRewardMB: device.total_reward_mb,
    currentSession: publicSession(session),
  };
}

function publicMissedCall(row: {
  id: string;
  device_id: string;
  from_number: string;
  call_sid: string | null;
  in_drive_mode: boolean;
  at: string;
}) {
  return {
    id: row.id,
    deviceId: row.device_id,
    from: row.from_number,
    callSid: row.call_sid,
    inDriveMode: row.in_drive_mode,
    at: isoZ(row.at),
  };
}

async function startDriveMode(device: DeviceRow, at: Date) {
  if (device.current_session_id) {
    const session = await getSession(device.current_session_id);
    if (session) return { device: await publicDevice(device), session: fullSession(session) };
  }
  const { data: session, error } = await supabase
    .from("sessions")
    .insert({ device_id: device.device_id, started_at: at.toISOString() })
    .select("*")
    .single();
  if (error) throw error;
  const { error: updateError } = await supabase
    .from("devices")
    .update({ current_session_id: session.session_id })
    .eq("device_id", device.device_id);
  if (updateError) throw updateError;
  device.current_session_id = session.session_id;
  return { device: await publicDevice(device), session: fullSession(session) };
}

async function endDriveMode(device: DeviceRow, at: Date) {
  const session = device.current_session_id ? await getSession(device.current_session_id) : null;
  if (!session) {
    return { device: await publicDevice(device), session: null, missedCalls: [], rewardEarnedMB: 0 };
  }

  const endedAt = at.toISOString();
  const minutes = Math.max(0, (at.getTime() - new Date(session.started_at).getTime()) / 60000);
  const uncapped = Math.floor(minutes * REWARD_MB_PER_MINUTE);
  const day = endedAt.slice(0, 10);
  const rewardsByDay = device.rewards_by_day || {};
  const earnedToday = rewardsByDay[day] || 0;
  const reward = Math.max(0, Math.min(uncapped, DAILY_REWARD_CAP_MB - earnedToday));
  rewardsByDay[day] = earnedToday + reward;

  const { error: sessionError } = await supabase
    .from("sessions")
    .update({ ended_at: endedAt, reward_earned_mb: reward })
    .eq("session_id", session.session_id);
  if (sessionError) throw sessionError;

  const { error: deviceError } = await supabase
    .from("devices")
    .update({
      current_session_id: null,
      total_reward_mb: device.total_reward_mb + reward,
      rewards_by_day: rewardsByDay,
    })
    .eq("device_id", device.device_id);
  if (deviceError) throw deviceError;

  device.current_session_id = null;
  device.total_reward_mb += reward;
  session.ended_at = endedAt;
  session.reward_earned_mb = reward;

  const { data: missedCalls, error: callsError } = await supabase
    .from("missed_calls")
    .select("*")
    .eq("device_id", device.device_id)
    .gte("at", session.started_at)
    .lte("at", endedAt)
    .order("at", { ascending: true });
  if (callsError) throw callsError;

  return {
    device: await publicDevice(device),
    session: fullSession(session),
    missedCalls: (missedCalls || []).map(publicMissedCall),
    rewardEarnedMB: reward,
  };
}

async function deviceByPhoneNumber(phoneNumber: string): Promise<DeviceRow | null> {
  const { data, error } = await supabase.from("devices").select("*").eq("phone_number", phoneNumber).maybeSingle();
  if (error) throw error;
  return data;
}

async function legacyDevice(): Promise<DeviceRow> {
  const existing = await getDevice(LEGACY_DEVICE_ID);
  if (existing) return existing;
  const { data, error } = await supabase
    .from("devices")
    .upsert({ device_id: LEGACY_DEVICE_ID, token_hash: await sha256Hex(randomTokenHex()), platform: "legacy-ios" })
    .select("*")
    .single();
  if (error) throw error;
  return data;
}

// ---- request handling ----

async function parseBody(req: Request): Promise<Record<string, unknown>> {
  const contentType = req.headers.get("content-type") || "";
  const raw = await req.text();
  if (!raw) return {};
  if (contentType.includes("application/x-www-form-urlencoded")) {
    return Object.fromEntries(new URLSearchParams(raw));
  }
  try {
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === "object" ? parsed : {};
  } catch {
    throw new ApiError(400, "invalid_json", "Request body is not valid JSON.");
  }
}

async function route(req: Request, path: string, query: URLSearchParams): Promise<Response> {
  const method = req.method;
  const now = new Date();

  if (method === "GET" && path === "/health") {
    return json(200, { status: "ok", service: "dontdie-backend", time: now.toISOString() });
  }

  if (method === "POST" && path === "/v1/devices") {
    const body = await parseBody(req);
    const token = randomTokenHex();
    const { data, error } = await supabase
      .from("devices")
      .insert({
        token_hash: await sha256Hex(token),
        platform: typeof body.platform === "string" ? body.platform.slice(0, 64) : "unknown",
        app_version: typeof body.appVersion === "string" ? body.appVersion.slice(0, 32) : null,
      })
      .select("device_id")
      .single();
    if (error) throw error;
    return json(201, { deviceId: data.device_id, deviceToken: token });
  }

  let match = path.match(/^\/v1\/devices\/([\w-]+)$/);
  if (method === "GET" && match) {
    const device = await requireDevice(req, match[1]);
    return json(200, await publicDevice(device));
  }

  match = path.match(/^\/v1\/devices\/([\w-]+)\/phone-number$/);
  if (method === "PUT" && match) {
    const device = await requireDevice(req, match[1]);
    const body = await parseBody(req);
    const phoneNumber = normalizePhoneNumber(body.phoneNumber);
    if (!phoneNumber) {
      throw new ApiError(400, "invalid_phone_number", "phoneNumber must be a US number in E.164 form, e.g. +14045551234.");
    }
    const { error } = await supabase.from("devices").update({ phone_number: phoneNumber }).eq("device_id", device.device_id);
    if (error) {
      if ((error as { code?: string }).code === "23505") {
        throw new ApiError(409, "phone_number_in_use", "That phone number is linked to another device.");
      }
      throw error;
    }
    device.phone_number = phoneNumber;
    return json(200, await publicDevice(device));
  }

  match = path.match(/^\/v1\/devices\/([\w-]+)\/drive-mode$/);
  if (method === "POST" && match) {
    const device = await requireDevice(req, match[1]);
    const body = await parseBody(req);
    if (typeof body.enabled !== "boolean") {
      throw new ApiError(400, "invalid_enabled", 'Body must include boolean field "enabled".');
    }
    if (body.enabled) {
      const result = await startDriveMode(device, now);
      return json(200, { device: result.device, session: result.session });
    }
    const result = await endDriveMode(device, now);
    return json(200, {
      device: result.device,
      session: result.session,
      rewardEarnedMB: result.rewardEarnedMB,
      missedCalls: result.missedCalls,
    });
  }

  match = path.match(/^\/v1\/devices\/([\w-]+)\/missed-calls$/);
  if (method === "GET" && match) {
    const device = await requireDevice(req, match[1]);
    let builder = supabase.from("missed_calls").select("*").eq("device_id", device.device_id).order("at", { ascending: true });
    if (query.get("since")) {
      const since = new Date(query.get("since")!);
      if (Number.isNaN(since.getTime())) {
        throw new ApiError(400, "invalid_since", '"since" must be an ISO-8601 timestamp.');
      }
      builder = builder.gte("at", since.toISOString());
    }
    const { data, error } = await builder;
    if (error) throw error;
    return json(200, { missedCalls: (data || []).map(publicMissedCall) });
  }

  if (method === "POST" && path === "/webhooks/voice") {
    const body = await parseBody(req);
    const forwardedFrom = normalizePhoneNumber(body.ForwardedFrom ?? body.To ?? "");
    const from = normalizePhoneNumber(body.From ?? "") || String(body.From || "unknown");
    const device = forwardedFrom ? await deviceByPhoneNumber(forwardedFrom) : null;
    if (!device) {
      return xml(twimlSay("The person you are calling is unavailable. Please try again later."));
    }
    const driving = Boolean(device.current_session_id);
    const { error } = await supabase.from("missed_calls").insert({
      device_id: device.device_id,
      from_number: from,
      call_sid: typeof body.CallSid === "string" ? body.CallSid : null,
      in_drive_mode: driving,
      at: now.toISOString(),
    });
    if (error) throw error;
    const message = driving
      ? "The person you are calling is currently driving. They will see your call as soon as they arrive. If this is an emergency, hang up and dial 9 1 1."
      : "The person you are calling is unavailable right now. Your call has been logged and they will be notified.";
    return xml(twimlSay(message));
  }

  if (method === "POST" && path === "/webhooks/sms") {
    const body = await parseBody(req);
    const to = normalizePhoneNumber(body.ForwardedFrom ?? body.To ?? "");
    const device = to ? await deviceByPhoneNumber(to) : null;
    if (device && device.current_session_id) {
      const { error } = await supabase.from("messages").insert({
        device_id: device.device_id,
        from_number: normalizePhoneNumber(body.From ?? "") || String(body.From || "unknown"),
        body: typeof body.Body === "string" ? body.Body.slice(0, 1600) : "",
        at: now.toISOString(),
      });
      if (error) throw error;
      return xml(twimlMessage("I am driving right now and will reply when I arrive. (Automated reply from Don’t Die.)"));
    }
    return xml(twimlEmpty());
  }

  if (method === "GET" && path === "/blockCalls") {
    await startDriveMode(await legacyDevice(), now);
    return new Response("OK", { status: 200, headers: { "Content-Type": "text/plain" } });
  }

  if (method === "GET" && path === "/allowCalls") {
    await endDriveMode(await legacyDevice(), now);
    return new Response("OK", { status: 200, headers: { "Content-Type": "text/plain" } });
  }

  throw new ApiError(404, "not_found", "No such endpoint.");
}

Deno.serve(async (req: Request) => {
  const url = new URL(req.url);
  // Strip the function-invocation prefixes so the same paths work whether the
  // caller uses https://<ref>.supabase.co/functions/v1/api/... or a custom
  // domain routed straight to /api/...
  const path = url.pathname.replace(/^\/functions\/v1/, "").replace(/^\/api/, "") || "/";

  try {
    return await route(req, path, url.searchParams);
  } catch (err) {
    if (err instanceof ApiError) {
      return json(err.status, { error: err.code, message: err.message });
    }
    console.error("Unhandled error:", err);
    return json(500, { error: "internal_error" });
  }
});
