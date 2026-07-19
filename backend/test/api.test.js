'use strict';

const test = require('node:test');
const assert = require('node:assert');
const http = require('node:http');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const { Store } = require('../src/store');
const { createApp, normalizePhoneNumber } = require('../src/app');

let server;
let baseUrl;
let dataDir;
let clock;
let store;

test.beforeEach(async () => {
  dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'dontdie-test-'));
  clock = { time: new Date('2026-07-19T12:00:00Z') };
  store = new Store(dataDir);
  server = http.createServer(createApp(store, { now: () => clock.time }));
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

test.afterEach(async () => {
  await new Promise((resolve) => server.close(resolve));
  store.flushSync();
  fs.rmSync(dataDir, { recursive: true, force: true });
});

async function api(method, urlPath, { body, token, form } = {}) {
  const headers = {};
  let payload;
  if (form) {
    headers['Content-Type'] = 'application/x-www-form-urlencoded';
    payload = new URLSearchParams(form).toString();
  } else if (body !== undefined) {
    headers['Content-Type'] = 'application/json';
    payload = JSON.stringify(body);
  }
  if (token) headers['Authorization'] = `Bearer ${token}`;
  const res = await fetch(baseUrl + urlPath, { method, headers, body: payload });
  const text = await res.text();
  const contentType = res.headers.get('content-type') || '';
  return {
    status: res.status,
    contentType,
    body: contentType.includes('application/json') ? JSON.parse(text) : text
  };
}

async function registerDevice() {
  const res = await api('POST', '/v1/devices', { body: { platform: 'ios', appVersion: '1.0' } });
  assert.strictEqual(res.status, 201);
  return res.body;
}

test('health endpoint reports ok', async () => {
  const res = await api('GET', '/health');
  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.body.status, 'ok');
});

test('device registration returns id and token; state requires auth', async () => {
  const { deviceId, deviceToken } = await registerDevice();
  assert.ok(deviceId && deviceToken);

  const unauthorized = await api('GET', `/v1/devices/${deviceId}`);
  assert.strictEqual(unauthorized.status, 401);

  const badToken = await api('GET', `/v1/devices/${deviceId}`, { token: 'nope' });
  assert.strictEqual(badToken.status, 401);

  const ok = await api('GET', `/v1/devices/${deviceId}`, { token: deviceToken });
  assert.strictEqual(ok.status, 200);
  assert.strictEqual(ok.body.driveMode, false);
  assert.strictEqual(ok.body.totalRewardMB, 0);
});

test('drive mode session earns time-based reward with daily cap', async () => {
  const { deviceId, deviceToken } = await registerDevice();

  const on = await api('POST', `/v1/devices/${deviceId}/drive-mode`, { token: deviceToken, body: { enabled: true } });
  assert.strictEqual(on.status, 200);
  assert.strictEqual(on.body.device.driveMode, true);
  assert.ok(on.body.session.sessionId);

  clock.time = new Date('2026-07-19T12:30:00Z'); // 30 minutes of driving
  const off = await api('POST', `/v1/devices/${deviceId}/drive-mode`, { token: deviceToken, body: { enabled: false } });
  assert.strictEqual(off.status, 200);
  assert.strictEqual(off.body.device.driveMode, false);
  assert.strictEqual(off.body.rewardEarnedMB, 30);
  assert.strictEqual(off.body.device.totalRewardMB, 30);

  // A ten-hour session the same day hits the 200 MB daily cap (30 + 170).
  const on2 = await api('POST', `/v1/devices/${deviceId}/drive-mode`, { token: deviceToken, body: { enabled: true } });
  assert.strictEqual(on2.status, 200);
  clock.time = new Date('2026-07-19T22:30:00Z');
  const off2 = await api('POST', `/v1/devices/${deviceId}/drive-mode`, { token: deviceToken, body: { enabled: false } });
  assert.strictEqual(off2.body.rewardEarnedMB, 170);
  assert.strictEqual(off2.body.device.totalRewardMB, 200);
});

test('enabling drive mode twice is idempotent', async () => {
  const { deviceId, deviceToken } = await registerDevice();
  const first = await api('POST', `/v1/devices/${deviceId}/drive-mode`, { token: deviceToken, body: { enabled: true } });
  const second = await api('POST', `/v1/devices/${deviceId}/drive-mode`, { token: deviceToken, body: { enabled: true } });
  assert.strictEqual(second.status, 200);
  assert.strictEqual(first.body.session.sessionId, second.body.session.sessionId);
});

test('phone number linking validates and rejects duplicates', async () => {
  const alice = await registerDevice();
  const bob = await registerDevice();

  const bad = await api('PUT', `/v1/devices/${alice.deviceId}/phone-number`, { token: alice.deviceToken, body: { phoneNumber: '12345' } });
  assert.strictEqual(bad.status, 400);

  const ok = await api('PUT', `/v1/devices/${alice.deviceId}/phone-number`, { token: alice.deviceToken, body: { phoneNumber: '(404) 555-1234' } });
  assert.strictEqual(ok.status, 200);
  assert.strictEqual(ok.body.phoneNumber, '+14045551234');

  const conflict = await api('PUT', `/v1/devices/${bob.deviceId}/phone-number`, { token: bob.deviceToken, body: { phoneNumber: '+14045551234' } });
  assert.strictEqual(conflict.status, 409);
});

test('voice webhook logs missed call while driving and returns TwiML', async () => {
  const { deviceId, deviceToken } = await registerDevice();
  await api('PUT', `/v1/devices/${deviceId}/phone-number`, { token: deviceToken, body: { phoneNumber: '+14045551234' } });
  await api('POST', `/v1/devices/${deviceId}/drive-mode`, { token: deviceToken, body: { enabled: true } });

  clock.time = new Date('2026-07-19T12:10:00Z');
  const webhook = await api('POST', '/webhooks/voice', {
    form: { From: '+14045559999', To: '+15555550000', ForwardedFrom: '+14045551234', CallSid: 'CA123' }
  });
  assert.strictEqual(webhook.status, 200);
  assert.ok(webhook.contentType.includes('text/xml'));
  assert.match(webhook.body, /currently driving/);

  clock.time = new Date('2026-07-19T12:20:00Z');
  const off = await api('POST', `/v1/devices/${deviceId}/drive-mode`, { token: deviceToken, body: { enabled: false } });
  assert.strictEqual(off.body.missedCalls.length, 1);
  assert.strictEqual(off.body.missedCalls[0].from, '+14045559999');
  assert.strictEqual(off.body.missedCalls[0].inDriveMode, true);

  const list = await api('GET', `/v1/devices/${deviceId}/missed-calls?since=2026-07-19T12:00:00Z`, { token: deviceToken });
  assert.strictEqual(list.body.missedCalls.length, 1);
});

test('voice webhook for unknown number returns generic TwiML without logging', async () => {
  const webhook = await api('POST', '/webhooks/voice', { form: { From: '+14045559999', To: '+15555550000' } });
  assert.strictEqual(webhook.status, 200);
  assert.match(webhook.body, /unavailable/);
});

test('sms webhook auto-replies only while driving', async () => {
  const { deviceId, deviceToken } = await registerDevice();
  await api('PUT', `/v1/devices/${deviceId}/phone-number`, { token: deviceToken, body: { phoneNumber: '+14045551234' } });

  const idle = await api('POST', '/webhooks/sms', { form: { From: '+14045559999', ForwardedFrom: '+14045551234', Body: 'hey' } });
  assert.strictEqual(idle.status, 200);
  assert.ok(!idle.body.includes('<Message>'));

  await api('POST', `/v1/devices/${deviceId}/drive-mode`, { token: deviceToken, body: { enabled: true } });
  const driving = await api('POST', '/webhooks/sms', { form: { From: '+14045559999', ForwardedFrom: '+14045551234', Body: 'hey' } });
  assert.match(driving.body, /<Message>.*driving.*<\/Message>/);
});

test('legacy blockCalls/allowCalls endpoints still work', async () => {
  const block = await api('GET', '/blockCalls');
  assert.strictEqual(block.status, 200);
  assert.strictEqual(block.body, 'OK');
  const allow = await api('GET', '/allowCalls');
  assert.strictEqual(allow.status, 200);
  assert.strictEqual(allow.body, 'OK');
});

test('unknown route 404s, wrong method 405s, bad JSON 400s', async () => {
  const missing = await api('GET', '/nope');
  assert.strictEqual(missing.status, 404);

  const wrongMethod = await api('DELETE', '/health');
  assert.strictEqual(wrongMethod.status, 405);

  const res = await fetch(baseUrl + '/v1/devices', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: '{not json'
  });
  assert.strictEqual(res.status, 400);
});

test('data persists across store reloads', async () => {
  const { deviceId, deviceToken } = await registerDevice();
  await api('POST', `/v1/devices/${deviceId}/drive-mode`, { token: deviceToken, body: { enabled: true } });
  clock.time = new Date('2026-07-19T12:05:00Z');
  await api('POST', `/v1/devices/${deviceId}/drive-mode`, { token: deviceToken, body: { enabled: false } });

  await new Promise((resolve) => server.close(resolve));
  store.flushSync();
  const reloaded = new Store(dataDir);
  assert.ok(reloaded.data.devices[deviceId]);
  assert.strictEqual(reloaded.data.devices[deviceId].totalRewardMB, 5);

  store = reloaded;
  server = http.createServer(createApp(reloaded, { now: () => clock.time }));
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

test('normalizePhoneNumber handles US formats', () => {
  assert.strictEqual(normalizePhoneNumber('(404) 555-1234'), '+14045551234');
  assert.strictEqual(normalizePhoneNumber('14045551234'), '+14045551234');
  assert.strictEqual(normalizePhoneNumber('+14045551234'), '+14045551234');
  assert.strictEqual(normalizePhoneNumber('4045551234'), '+14045551234');
  assert.strictEqual(normalizePhoneNumber('555-1234'), null);
  assert.strictEqual(normalizePhoneNumber(42), null);
});
