'use strict';

const crypto = require('crypto');

const MAX_BODY_BYTES = 64 * 1024;
const RATE_LIMIT_PER_MINUTE = 240;
const DAILY_REWARD_CAP_MB = 200;
const REWARD_MB_PER_MINUTE = 1;

// E.164, US-focused: +1 followed by a 10-digit number (or bare 10 digits).
function normalizePhoneNumber(input) {
  if (typeof input !== 'string') return null;
  const digits = input.replace(/[^\d+]/g, '');
  if (/^\+1\d{10}$/.test(digits)) return digits;
  if (/^1\d{10}$/.test(digits)) return '+' + digits;
  if (/^\d{10}$/.test(digits)) return '+1' + digits;
  return null;
}

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function xmlEscape(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

function twimlSay(message) {
  return `<?xml version="1.0" encoding="UTF-8"?>\n<Response><Say voice="alice">${xmlEscape(message)}</Say></Response>`;
}

function twimlMessage(message) {
  return `<?xml version="1.0" encoding="UTF-8"?>\n<Response><Message>${xmlEscape(message)}</Message></Response>`;
}

function twimlEmpty() {
  return '<?xml version="1.0" encoding="UTF-8"?>\n<Response></Response>';
}

class ApiError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

function createApp(store, options = {}) {
  const now = options.now || (() => new Date());
  const rateBuckets = new Map();

  function checkRateLimit(ip) {
    const minute = Math.floor(now().getTime() / 60000);
    const key = `${ip}:${minute}`;
    const count = (rateBuckets.get(key) || 0) + 1;
    rateBuckets.set(key, count);
    if (rateBuckets.size > 10000) {
      for (const bucketKey of rateBuckets.keys()) {
        if (!bucketKey.endsWith(`:${minute}`)) rateBuckets.delete(bucketKey);
      }
    }
    return count <= (options.rateLimitPerMinute || RATE_LIMIT_PER_MINUTE);
  }

  function requireDevice(req, deviceId) {
    const device = store.data.devices[deviceId];
    if (!device) throw new ApiError(404, 'device_not_found', 'Unknown device.');
    const header = req.headers['authorization'] || '';
    const match = header.match(/^Bearer\s+(\S+)$/i);
    if (!match) throw new ApiError(401, 'missing_token', 'Authorization: Bearer <deviceToken> header required.');
    const hashed = sha256(match[1]);
    const expected = device.tokenHash;
    const a = Buffer.from(hashed);
    const b = Buffer.from(expected);
    if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
      throw new ApiError(401, 'invalid_token', 'Device token is not valid for this device.');
    }
    return device;
  }

  function deviceByPhoneNumber(phoneNumber) {
    const deviceId = store.data.phoneIndex[phoneNumber];
    return deviceId ? store.data.devices[deviceId] : null;
  }

  function activeSession(device) {
    return device.currentSessionId ? store.data.sessions[device.currentSessionId] : null;
  }

  function rewardEarnedToday(device, at) {
    const day = at.toISOString().slice(0, 10);
    return device.rewardsByDay && device.rewardsByDay[day] ? device.rewardsByDay[day] : 0;
  }

  function publicDevice(device) {
    const session = activeSession(device);
    return {
      deviceId: device.deviceId,
      driveMode: Boolean(session),
      phoneNumber: device.phoneNumber || null,
      totalRewardMB: device.totalRewardMB || 0,
      currentSession: session
        ? { sessionId: session.sessionId, startedAt: session.startedAt }
        : null
    };
  }

  function startDriveMode(device, at) {
    if (device.currentSessionId) {
      const session = store.data.sessions[device.currentSessionId];
      return { device: publicDevice(device), session, alreadyActive: true };
    }
    const session = {
      sessionId: crypto.randomUUID(),
      deviceId: device.deviceId,
      startedAt: at.toISOString(),
      endedAt: null,
      rewardEarnedMB: 0
    };
    store.data.sessions[session.sessionId] = session;
    device.currentSessionId = session.sessionId;
    store.save();
    return { device: publicDevice(device), session, alreadyActive: false };
  }

  function endDriveMode(device, at) {
    const session = activeSession(device);
    if (!session) {
      return { device: publicDevice(device), session: null, missedCalls: [], rewardEarnedMB: 0 };
    }
    session.endedAt = at.toISOString();
    const minutes = Math.max(0, (at - new Date(session.startedAt)) / 60000);
    const uncapped = Math.floor(minutes * REWARD_MB_PER_MINUTE);
    const day = at.toISOString().slice(0, 10);
    device.rewardsByDay = device.rewardsByDay || {};
    const earnedToday = rewardEarnedToday(device, at);
    const reward = Math.max(0, Math.min(uncapped, DAILY_REWARD_CAP_MB - earnedToday));
    session.rewardEarnedMB = reward;
    device.rewardsByDay[day] = earnedToday + reward;
    device.totalRewardMB = (device.totalRewardMB || 0) + reward;
    device.currentSessionId = null;
    const missedCalls = store.data.missedCalls.filter(
      (call) => call.deviceId === device.deviceId && call.at >= session.startedAt && call.at <= session.endedAt
    );
    store.save();
    return { device: publicDevice(device), session, missedCalls, rewardEarnedMB: reward };
  }

  function logMissedCall(device, { from, callSid, inDriveMode, at }) {
    const record = {
      id: crypto.randomUUID(),
      deviceId: device.deviceId,
      from,
      callSid: callSid || null,
      inDriveMode,
      at: at.toISOString()
    };
    store.data.missedCalls.push(record);
    store.save();
    return record;
  }

  // ---- legacy single-user endpoints (/blockCalls, /allowCalls) ----
  // The original 2016 client toggled a global flag on a Heroku app. Keep the
  // same URLs working, mapped onto a dedicated device record, so an old build
  // keeps functioning against the new backend.
  function legacyDevice() {
    let device = store.data.devices['legacy'];
    if (!device) {
      device = {
        deviceId: 'legacy',
        tokenHash: sha256(crypto.randomUUID()),
        createdAt: now().toISOString(),
        platform: 'legacy-ios',
        totalRewardMB: 0,
        rewardsByDay: {},
        currentSessionId: null,
        phoneNumber: null
      };
      store.data.devices['legacy'] = device;
      store.save();
    }
    return device;
  }

  const routes = [
    {
      method: 'GET',
      pattern: /^\/health$/,
      handler: () => ({ status: 200, body: { status: 'ok', service: 'dontdie-backend', time: now().toISOString() } })
    },

    {
      method: 'POST',
      pattern: /^\/v1\/devices$/,
      handler: (req, params, body) => {
        const token = crypto.randomBytes(32).toString('hex');
        const device = {
          deviceId: crypto.randomUUID(),
          tokenHash: sha256(token),
          createdAt: now().toISOString(),
          platform: typeof body.platform === 'string' ? body.platform.slice(0, 64) : 'unknown',
          appVersion: typeof body.appVersion === 'string' ? body.appVersion.slice(0, 32) : null,
          totalRewardMB: 0,
          rewardsByDay: {},
          currentSessionId: null,
          phoneNumber: null
        };
        store.data.devices[device.deviceId] = device;
        store.data.tokenIndex[device.tokenHash] = device.deviceId;
        store.save();
        return { status: 201, body: { deviceId: device.deviceId, deviceToken: token } };
      }
    },

    {
      method: 'GET',
      pattern: /^\/v1\/devices\/([\w-]+)$/,
      handler: (req, params) => {
        const device = requireDevice(req, params[0]);
        return { status: 200, body: publicDevice(device) };
      }
    },

    {
      method: 'PUT',
      pattern: /^\/v1\/devices\/([\w-]+)\/phone-number$/,
      handler: (req, params, body) => {
        const device = requireDevice(req, params[0]);
        const phoneNumber = normalizePhoneNumber(body.phoneNumber);
        if (!phoneNumber) {
          throw new ApiError(400, 'invalid_phone_number', 'phoneNumber must be a US number in E.164 form, e.g. +14045551234.');
        }
        const existingOwner = store.data.phoneIndex[phoneNumber];
        if (existingOwner && existingOwner !== device.deviceId) {
          throw new ApiError(409, 'phone_number_in_use', 'That phone number is linked to another device.');
        }
        if (device.phoneNumber && device.phoneNumber !== phoneNumber) {
          delete store.data.phoneIndex[device.phoneNumber];
        }
        device.phoneNumber = phoneNumber;
        store.data.phoneIndex[phoneNumber] = device.deviceId;
        store.save();
        return { status: 200, body: publicDevice(device) };
      }
    },

    {
      method: 'POST',
      pattern: /^\/v1\/devices\/([\w-]+)\/drive-mode$/,
      handler: (req, params, body) => {
        const device = requireDevice(req, params[0]);
        if (typeof body.enabled !== 'boolean') {
          throw new ApiError(400, 'invalid_enabled', 'Body must include boolean field "enabled".');
        }
        const at = now();
        if (body.enabled) {
          const result = startDriveMode(device, at);
          return { status: 200, body: { device: result.device, session: result.session } };
        }
        const result = endDriveMode(device, at);
        return {
          status: 200,
          body: {
            device: result.device,
            session: result.session,
            rewardEarnedMB: result.rewardEarnedMB,
            missedCalls: result.missedCalls
          }
        };
      }
    },

    {
      method: 'GET',
      pattern: /^\/v1\/devices\/([\w-]+)\/missed-calls$/,
      handler: (req, params, body, query) => {
        const device = requireDevice(req, params[0]);
        let since = null;
        if (query.get('since')) {
          since = new Date(query.get('since'));
          if (Number.isNaN(since.getTime())) {
            throw new ApiError(400, 'invalid_since', '"since" must be an ISO-8601 timestamp.');
          }
        }
        const missedCalls = store.data.missedCalls.filter(
          (call) => call.deviceId === device.deviceId && (!since || new Date(call.at) >= since)
        );
        return { status: 200, body: { missedCalls } };
      }
    },

    // Twilio-compatible voice webhook. Point a Twilio number's "A call comes
    // in" webhook here; users conditionally forward their carrier number to
    // that Twilio number. Twilio sends ForwardedFrom = the user's real number.
    {
      method: 'POST',
      pattern: /^\/webhooks\/voice$/,
      handler: (req, params, body) => {
        const forwardedFrom = normalizePhoneNumber(body.ForwardedFrom || body.To || '');
        const from = normalizePhoneNumber(body.From || '') || (body.From || 'unknown');
        const device = forwardedFrom ? deviceByPhoneNumber(forwardedFrom) : null;
        if (!device) {
          return { status: 200, contentType: 'text/xml', body: twimlSay('The person you are calling is unavailable. Please try again later.') };
        }
        const driving = Boolean(activeSession(device));
        logMissedCall(device, { from, callSid: body.CallSid, inDriveMode: driving, at: now() });
        const message = driving
          ? 'The person you are calling is currently driving. They will see your call as soon as they arrive. If this is an emergency, hang up and dial 9 1 1.'
          : 'The person you are calling is unavailable right now. Your call has been logged and they will be notified.';
        return { status: 200, contentType: 'text/xml', body: twimlSay(message) };
      }
    },

    // Twilio-compatible SMS webhook: auto-reply while the recipient is driving.
    {
      method: 'POST',
      pattern: /^\/webhooks\/sms$/,
      handler: (req, params, body) => {
        const to = normalizePhoneNumber(body.ForwardedFrom || body.To || '');
        const device = to ? deviceByPhoneNumber(to) : null;
        if (device && activeSession(device)) {
          store.data.messages.push({
            id: crypto.randomUUID(),
            deviceId: device.deviceId,
            from: normalizePhoneNumber(body.From || '') || (body.From || 'unknown'),
            body: typeof body.Body === 'string' ? body.Body.slice(0, 1600) : '',
            at: now().toISOString()
          });
          store.save();
          return {
            status: 200,
            contentType: 'text/xml',
            body: twimlMessage('I am driving right now and will reply when I arrive. (Automated reply from Don’t Die.)')
          };
        }
        return { status: 200, contentType: 'text/xml', body: twimlEmpty() };
      }
    },

    { method: 'GET', pattern: /^\/blockCalls$/, handler: () => { startDriveMode(legacyDevice(), now()); return { status: 200, contentType: 'text/plain', body: 'OK' }; } },
    { method: 'GET', pattern: /^\/allowCalls$/, handler: () => { endDriveMode(legacyDevice(), now()); return { status: 200, contentType: 'text/plain', body: 'OK' }; } }
  ];

  function parseBody(raw, contentType) {
    if (!raw || raw.length === 0) return {};
    if (contentType.includes('application/x-www-form-urlencoded')) {
      return Object.fromEntries(new URLSearchParams(raw.toString('utf8')));
    }
    try {
      const parsed = JSON.parse(raw.toString('utf8'));
      return parsed && typeof parsed === 'object' ? parsed : {};
    } catch {
      throw new ApiError(400, 'invalid_json', 'Request body is not valid JSON.');
    }
  }

  return function handleRequest(req, res) {
    const chunks = [];
    let received = 0;
    let aborted = false;

    req.on('data', (chunk) => {
      received += chunk.length;
      if (received > MAX_BODY_BYTES) {
        aborted = true;
        res.writeHead(413, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'payload_too_large' }));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });

    req.on('end', () => {
      if (aborted) return;
      let status = 500;
      let contentType = 'application/json';
      let payload = JSON.stringify({ error: 'internal_error' });

      try {
        const ip = req.socket.remoteAddress || 'unknown';
        if (!checkRateLimit(ip)) {
          throw new ApiError(429, 'rate_limited', 'Too many requests; slow down.');
        }
        const url = new URL(req.url, 'http://localhost');
        const body = parseBody(Buffer.concat(chunks), req.headers['content-type'] || '');
        const route = routes.find((r) => r.method === req.method && r.pattern.test(url.pathname));
        if (!route) {
          const pathExists = routes.some((r) => r.pattern.test(url.pathname));
          throw new ApiError(
            pathExists ? 405 : 404,
            pathExists ? 'method_not_allowed' : 'not_found',
            pathExists ? 'Method not allowed for this path.' : 'No such endpoint.'
          );
        }
        const params = url.pathname.match(route.pattern).slice(1);
        const result = route.handler(req, params, body, url.searchParams);
        status = result.status;
        contentType = result.contentType || 'application/json';
        payload = contentType === 'application/json' ? JSON.stringify(result.body) : result.body;
      } catch (err) {
        if (err instanceof ApiError) {
          status = err.status;
          contentType = 'application/json';
          payload = JSON.stringify({ error: err.code, message: err.message });
        } else {
          console.error('Unhandled error:', err);
          status = 500;
          contentType = 'application/json';
          payload = JSON.stringify({ error: 'internal_error' });
        }
      }

      res.writeHead(status, { 'Content-Type': contentType });
      res.end(payload);
    });
  };
}

module.exports = { createApp, normalizePhoneNumber };
