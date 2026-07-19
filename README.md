# Don't Die — Drive Mode

An iOS app + backend that fights distracted driving. When the app detects you're
in your car (via a Gimbal Bluetooth beacon), it enters **drive mode**: incoming
calls and texts are intercepted with an "I'm driving" message, missed calls are
shown when you arrive, and you earn a **data reward** (1 MB per minute of
undistracted driving, capped at 200 MB/day).

This repository contains:

| Path | What it is |
|---|---|
| `hello-gimbal-ios/` + `*.m/.h` at root | The iOS app (Objective-C, Gimbal SDK) |
| `backend/` | The backend service (zero-dependency Node.js ≥18, tested with `node:test`) |
| `docs/` | US launch checklist and privacy policy template |

## How it works

1. A Gimbal beacon lives in your car. When your phone sees it, the app flips
   into drive mode and tells the backend (`POST /v1/devices/:id/drive-mode`).
2. Your phone number is linked to your device on the backend. You set up
   **conditional call forwarding** from your carrier number to a Twilio number
   pointed at the backend's `/webhooks/voice` endpoint.
3. While you're driving, callers hear "they're driving, they'll see your call
   when they arrive" and the call is logged. Texts get an automatic
   "I'm driving" reply.
4. When you stop driving, the app shows the calls you missed and your updated
   data reward.

This is the honest, launchable architecture: iOS apps cannot read or block the
phone's cellular calls directly, and the AT&T Foundry carrier API the 2016
prototype used no longer exists. Call interception has to happen in the network
(carrier forwarding + Twilio), which is exactly what the backend implements.

## Running the backend

```bash
cd backend
npm test          # no dependencies to install
node server.js    # PORT=3000 by default
```

See `backend/README.md` for the full API and deployment notes (Dockerfile and
Procfile included).

## Building the iOS app

Requires Xcode on macOS.

1. Open `hello-gimbal-ios.xcodeproj`.
2. In `hello-gimbal-ios/Info.plist`, set:
   - `DTDAPIBaseURL` — your deployed backend URL (HTTPS).
   - `DTDGimbalAPIKey` — your API key from [manager.gimbal.com](https://manager.gimbal.com/).
3. Build and run on a device (Bluetooth beacon detection doesn't work in the
   simulator; the invisible bottom toolbar tap/swipe gestures simulate
   entering/leaving the car for testing).

## Launching in the US

See [`docs/LAUNCH_CHECKLIST.md`](docs/LAUNCH_CHECKLIST.md) for everything that
stands between this codebase and the App Store: accounts to create, services to
provision, and the legal/App Review items to clear.

## License

MIT — see [LICENSE](LICENSE).
