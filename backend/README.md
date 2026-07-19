# Don't Die — Backend

Zero-dependency Node.js (≥18) service that replaces the original prototype's dead
Heroku app and the retired AT&T Foundry carrier API. It tracks devices, drive-mode
sessions, and data rewards, and captures missed calls/texts through
Twilio-compatible webhooks.

## Run

```bash
node server.js            # PORT (default 3000), DATA_DIR (default ./data)
npm test                  # node:test suite, no dependencies to install
```

Deploy with the included `Dockerfile` (mount a volume at `/data`) or `Procfile`
(Heroku/Render — note the JSON file store needs a persistent disk; on ephemeral
filesystems swap `src/store.js` for a database adapter before launch).

## API

All request/response bodies are JSON unless noted. Device-scoped routes require
`Authorization: Bearer <deviceToken>`.

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | Liveness check |
| POST | `/v1/devices` | Register a device → `{deviceId, deviceToken}` (token shown once) |
| GET | `/v1/devices/:id` | Device state: drive mode, reward total, current session |
| PUT | `/v1/devices/:id/phone-number` | Link the user's US phone number (E.164) |
| POST | `/v1/devices/:id/drive-mode` | `{"enabled": true|false}`; disabling returns the session's missed calls and reward earned |
| GET | `/v1/devices/:id/missed-calls?since=ISO8601` | Missed-call log |
| POST | `/webhooks/voice` | Twilio voice webhook (form-encoded) → TwiML |
| POST | `/webhooks/sms` | Twilio SMS webhook → auto-reply TwiML while driving |
| GET | `/blockCalls`, `/allowCalls` | Legacy endpoints kept for the original client |

## How call capture works

iOS apps cannot read or block the phone's cellular calls, and the AT&T carrier
API this project originally used no longer exists. The launchable design:

1. The user enables **conditional call forwarding** (busy/no-answer) from their
   carrier number to a Twilio number you provision (e.g. dial `*004*<twilio>#`
   on GSM carriers).
2. Twilio's "a call comes in" webhook points at `POST /webhooks/voice`. Twilio
   passes `ForwardedFrom` = the user's real number, which we map to a device.
3. While the device is in drive mode, callers hear a "driving right now"
   message and the call is logged; when drive mode ends, the app shows the
   missed calls returned by the drive-mode disable response.
4. `POST /webhooks/sms` auto-replies to texts the same way (requires texts to
   flow through the Twilio number).

Rewards: 1 MB of data credit per minute of drive mode, capped at 200 MB/day.
The reward ledger is tracked per device; fulfillment (e.g. carrier top-ups or
gift cards) is a business integration left to launch operations.

## Production hardening before launch

- Put the service behind TLS (any reverse proxy / PaaS does this).
- Validate Twilio webhook signatures (`X-Twilio-Signature`) once you have a
  Twilio auth token to validate against.
- Verify phone-number ownership with an SMS OTP before linking (prevents
  claiming someone else's number).
- Swap the JSON file store for Postgres when you outgrow one node.
