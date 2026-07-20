# IAP Testing (Simulator & Sandbox)

How to test in-app purchases end-to-end without real charges. The purchase UI
lives in the Synaplan SPA (`synaplan/frontend`); the native billing bridge is
`cordova-plugin-purchase` + `cordova-plugin-purchase-storekit2` (iOS StoreKit 2)
and Play Billing (Android). The backend endpoint `POST /api/v1/iap/verify` is
the single source of truth — no tier is ever granted client-side.

## iOS Simulator (StoreKit Configuration File)

Everything runs locally — no App Store Connect products, no sandbox account,
no network calls to Apple.

### Pieces already in place

| Piece | Where |
| ----- | ----- |
| StoreKit config file with the 3 subscriptions | `ios/App/App/Synaplan.storekit` |
| Shared scheme that loads it on launch | `ios/App/App.xcodeproj/xcshareddata/xcschemes/App.xcscheme` |
| Product IDs (match the backend defaults) | `com.synaplan.app.pro.monthly`, `.team.monthly`, `.business.monthly` |

The `.storekit` prices mirror the server's `appPrice` (web price + the
`IAP_STORE_PRICE_*` EUR catalogue, must match ASC): €24.99 / €64.99 / €129.99. In-app prices
are ALWAYS the marked-up ones — the plain web price is never shown in the app
(anti-steering); see `synaplan/docs/PAYMENTS_CHANNELS.md`.

### Backend setup (local `synaplan` stack)

Xcode signs local StoreKit transactions with its own certificate, not Apple's.
The App Store Server Library skips the Apple cert-chain check when the
environment is `Xcode` — set this in `synaplan/backend/.env.local`:

```bash
IAP_APPLE_BUNDLE_ID=com.synaplan.app
IAP_APPLE_ENVIRONMENT=Xcode          # accepts Xcode-signed JWS (NEVER in prod)
IAP_APPLE_ROOT_CERTS_DIR=var/apple-roots   # must exist and contain ≥1 file
```

`isConfigured()` requires a non-empty root-certs dir even in Xcode mode, and
the App Store Server Library parses every file in it as a **DER**-encoded
certificate at verifier construction — a PEM file (e.g. the system
`ca-certificates.crt` bundle) makes initialization fail with
`INVALID_CERTIFICATE` and every verify returns 503. Put Apple's real root CA
(already DER) there once:

```bash
docker compose exec backend sh -c 'mkdir -p var/apple-roots && curl -fsSL https://www.apple.com/certificateauthority/AppleRootCA-G3.cer -o var/apple-roots/AppleRootCA-G3.cer'
docker compose exec backend php bin/console cache:clear
```

### Point the app at your local backend

The Simulator reaches the host machine via `localhost`. Use the dev server
override (see `docs/SERVER_CONFIG.md`): build the app, then in the app's admin
"App server" settings enter `http://localhost:8000`, or set
`SYNAPLAN_DEV_BACKEND=http://localhost:8000` for the build.

### Run it

```bash
npm run build          # SPA + cap sync
npx cap open ios       # open in Xcode
```

In Xcode select the **App** scheme → any iOS Simulator → Run. The scheme
already references `Synaplan.storekit`, so the store sheet uses the local
catalogue and prices.

Test flow: sign in → Subscription page → plan cards show the **store** price
(from the .storekit file) → buy → Xcode payment sheet → confirm → the app
POSTs the JWS to `/api/v1/iap/verify` → tier is granted.

Useful Xcode menus while the app runs:

- **Debug → StoreKit → Manage Transactions…** — refund, expire, or renew the
  test subscription (exercises the webhook-less paths).
- Edit `Synaplan.storekit` in Xcode to simulate interrupted/failed purchases
  ("Enable Interrupted Purchases", error injection).

### What the Simulator does NOT cover

- App Store Server Notifications (renew/cancel webhooks) — sandbox/TestFlight only.
- Real receipt chain validation (`IAP_APPLE_ENVIRONMENT=Sandbox`/`Production`).
- Ask to Buy approval flow UI (can be simulated via "Ask to Buy" in the
  .storekit settings, but approval happens in Manage Transactions).

## iOS Sandbox (real device / TestFlight)

1. Create the subscription products in App Store Connect (same product IDs).
2. Create a **Sandbox Apple Account** (App Store Connect → Users and Access →
   Sandbox) and sign in on the device under Settings → App Store → Sandbox Account.
3. Backend: `IAP_APPLE_ENVIRONMENT=Sandbox`, real Apple root certs in
   `IAP_APPLE_ROOT_CERTS_DIR`, `IAP_APPLE_APP_APPLE_ID` set.
4. Configure the App Store Server Notifications V2 URL (sandbox) to
   `https://<server>/api/v1/iap/apple/notifications`.

## Android (Play Billing)

There is no local-only equivalent of the StoreKit configuration file:

1. Upload an AAB to the **Internal testing** track in Play Console.
2. Create the subscriptions (same product IDs) and add **License testers**
   (Play Console → Settings → License testing) — testers purchase for free.
3. Backend: `IAP_GOOGLE_*` service-account credentials (see
   `synaplan/backend/.env.example`), RTDN Pub/Sub push to
   `https://<server>/api/v1/iap/google/notifications`.
4. Install from the testing track (NOT a debug sideload — billing requires the
   Play-installed package) and test the purchase in the app.

## Quick reference: what to check after a purchase

1. `/api/v1/iap/verify` responded `granted: true` with the right `tier`.
2. User level updated (badge on the Subscription page).
3. The entitlement is recorded on the user's payment details (`BUSERS.BPAYMENTDETAILS`,
   source `apple`/`google`) — check via phpMyAdmin or backend logs.
4. Restore Purchases on a second install recovers the tier.
