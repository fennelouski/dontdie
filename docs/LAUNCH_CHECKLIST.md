# US Launch Checklist

What stands between this repository and a real US launch. Code items are done
in this repo; account/business items need a human with credentials.

## 1. Backend deployment

- [x] Backend service implemented (`backend/`) with tests, Dockerfile, Procfile.
- [x] **Deployed to production**: Supabase project `dontdie-backend`
      (us-east-1) — Postgres + edge function
      (`backend/supabase/functions/api/index.ts`), live at
      `https://weqofpccjrcvdqnwcmln.supabase.co/functions/v1/api` with HTTPS.
      Tables are RLS-locked to the service role; smoke-tested end to end.
- [x] `DTDAPIBaseURL` in the app's Info.plist points at the live URL.
- [ ] Set up monitoring on `GET /health` (any uptime pinger).
- [ ] Optional: put a custom domain (e.g. `api.dontdie.app`) in front via a
      Supabase custom domain or a proxy, then update `DTDAPIBaseURL`.

## 2. Telephony (call/text interception)

- [ ] Create a Twilio account, buy a US number, and point its Voice webhook at
      `POST /webhooks/voice` and Messaging webhook at `POST /webhooks/sms`.
- [ ] Add Twilio signature validation (`X-Twilio-Signature`) to the webhooks —
      the backend README lists this as a pre-launch hardening step.
- [ ] Onboarding flow: after linking a phone number, verify ownership with an
      SMS one-time code before the backend accepts it (prevents claiming
      someone else's number). Endpoint design exists; needs an SMS provider key.
- [ ] Document per-carrier conditional call forwarding codes for users
      (GSM `*004*<number>#`, Verizon `*71<number>`, etc.).

## 3. Gimbal / drive detection

- [ ] The Gimbal beacon platform has been sunset for new customers since this
      prototype was written. Decide:
      - **Option A (recommended):** replace beacon detection with Apple's
        native driving detection (`CMMotionActivityManager` automotive activity
        + speed from Core Location, which the app already reads). No hardware,
        no third-party SDK, and the app already has the motion/location
        plumbing and permission strings.
      - **Option B:** any iBeacon in the car via Core Location beacon ranging —
        a drop-in replacement for the Gimbal visit callbacks.
- [ ] If keeping Gimbal short-term: register an app at manager.gimbal.com and
      set `DTDGimbalAPIKey` in Info.plist (the old hardcoded key was removed).

## 4. App Store / Apple

- [ ] Apple Developer Program enrollment ($99/yr); set a real bundle ID
      (currently `com.gimbal.hello-gimbal-ios` — change it).
- [ ] Raise the project's iOS deployment target to a current version and build
      with the latest SDK (App Review requires it). The code now uses only
      current, non-deprecated APIs (`UNUserNotificationCenter`, `NSURLSession`).
- [ ] App icon set is empty (`Images.xcassets`) — needs real artwork, plus
      launch screen and App Store screenshots.
- [ ] Privacy “nutrition label” in App Store Connect: location (not linked to
      identity), phone number (linked), call metadata. Matches
      `docs/PRIVACY_POLICY.md`.
- [ ] App Review notes: explain the call-forwarding model clearly — the app
      does not access the user's calls; interception happens at the carrier
      level with user-configured forwarding.

## 5. Legal / naming

- [ ] The prototype's display name was **“It Can Wait”** — that is AT&T's
      trademarked campaign. It has been changed to **“Don't Die”**; clear that
      name (or pick another) with a trademark search before launch.
- [ ] Publish the privacy policy (template in `docs/PRIVACY_POLICY.md`) at a
      public URL; App Store Connect requires one.
- [ ] Terms of service, especially around the data-reward program (how MB
      convert to real-world value, expiry, fraud).
- [ ] TCPA review for the automated SMS replies (they're user-initiated
      auto-responses, but get counsel's sign-off).

## 6. Data rewards fulfillment

- [ ] The ledger is implemented server-side (1 MB/minute, 200 MB/day cap).
      Fulfillment needs a business partner: carrier top-up API, gift cards, or
      a sponsor. Until then, present rewards as points, not promised data.

## 7. Known code gaps (acceptable for v1, fix soon after)

- Device token is stored in `NSUserDefaults`; move to Keychain.
- Legacy `/blockCalls`–`/allowCalls` endpoints map to a single shared device;
  remove once no pre-2026 builds exist (realistically: remove now).
- No admin dashboard; the JSON store is inspectable by hand until Postgres.
