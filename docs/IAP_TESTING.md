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
| Product IDs (must match `IAP_PRODUCT_*` on the server) | `com.synaplan.app.pro.monthly`, `.team.monthly.v2`, `.business.monthly.v2` |

> The backend has **no** built-in product IDs — `IAP_PRODUCT_PRO` / `_TEAM` / `_BUSINESS` are empty
> by default and every environment sets its own. Team and Business carry the `.v2` suffix because
> the original products were created with Family Sharing enabled, which Apple cannot switch off
> again (see the launch plan); the replacements have it disabled.

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
   Sandbox) and sign in on the device. The row is under **Settings → Developer →
   Sandbox Apple Account** on a device carrying a development profile, and under
   Settings → Apps → App Store otherwise.
   **Do not use sandbox to verify prices — verify the purchase FLOW.** StoreKit
   reports USD prices and en-US product names in sandbox/TestFlight regardless of
   the storefront, while the purchase sheet (resolved live against the real
   account) shows the buyer's actual currency. Confirmed 2026-08-01 with a
   diagnostic build: a German Apple Account, a German sandbox tester, complete
   country availability on the app AND every subscription, and correct EUR price
   points still yielded `currency=USD` from `SKProduct.priceLocale`. It is a known
   sandbox limitation, not a configuration error, and it does not occur in
   production. Do not re-investigate ASC over it.
3. Backend: `IAP_APPLE_ENVIRONMENT=Sandbox`, real Apple root certs in
   `IAP_APPLE_ROOT_CERTS_DIR`, `IAP_APPLE_APP_APPLE_ID` set.
4. Configure the App Store Server Notifications V2 URL (sandbox) to
   `https://<server>/api/v1/iap/apple/notifications`.

### Persist the Apple root certificates (production hosts)

`IAP_APPLE_ROOT_CERTS_DIR` (usually `var/apple-roots`) lives **inside the backend
container** unless you mount it. A `docker compose up -d` (or any image rebuild)
**wipes the directory** and every purchase fails until the certificates are back.

**This is not hypothetical — it happened on 2026-08-01**, during the first real
sandbox purchase: Apple charged nothing, the app showed the generic "purchase
could not be completed", and nothing else looked wrong. `/api/v1/subscription/plans`
still reported `iapConfigured: true` (that flag covers the product IDs, not the
verifier) and `POST /iap/verify` still answered `401` rather than `503`, so the
endpoint check people usually run does **not** catch it. Only the container told
the truth: `ls: cannot access 'var/apple-roots'`.

So **mount** the directory; do not copy into the container. On the production
cluster the compose directory is shared across the nodes, so one copy serves all
three:

```bash
cd /netroot/synaplanCluster/synaplan-compose
mkdir -p apple-roots
for u in https://www.apple.com/appleca/AppleIncRootCertificate.cer \
         https://www.apple.com/certificateauthority/AppleComputerRootCertificate.cer \
         https://www.apple.com/certificateauthority/AppleRootCA-G2.cer \
         https://www.apple.com/certificateauthority/AppleRootCA-G3.cer; do
  curl -fsSL "$u" -o "apple-roots/$(basename "$u")"
done
chmod 644 apple-roots/*.cer
```

Then add to the `backend` **and** `worker` services (adjust the container path to
the backend's project dir, `/var/www/backend` there):

```yaml
    volumes:
      - ./apple-roots:/var/www/backend/var/apple-roots:ro
```

Download **all four** roots from the Apple PKI site, as the App Store Server
Library's README asks. StoreKit 2 JWS currently chains to **G3** alone, so the
others are insurance against Apple rotating the chain; an unused trust anchor is
harmless. Keep them exactly as Apple ships them (**DER** `.cer`) — do not convert
to PEM.

Sanity-check after every backend recreate:

```bash
docker compose exec backend sh -c 'for f in var/apple-roots/*.cer; do openssl x509 -inform der -in "$f" -noout -subject -enddate; done'
```

## Flip Sandbox → Production (go-live only)

Keep `IAP_APPLE_ENVIRONMENT=Sandbox` through **TestFlight QA and App Review**.
TestFlight purchases and Apple's reviewer purchases are always Sandbox; with
`Production` they fail and the review is rejected.

Flip **only after Apple approves**, immediately before you manually release the
version (or right after approval if you chose automatic release):

1. Set `IAP_APPLE_ENVIRONMENT=Production` on the production backend (and worker).
2. Restart: `docker compose up -d backend` (and worker if applicable).
3. In App Store Connect → App → App Information → **App Store Server
   Notifications V2**: switch the URL from the Sandbox endpoint to Production
   (same path: `https://web.synaplan.com/api/v1/iap/apple/notifications`).
4. Confirm `var/apple-roots` still has `AppleRootCA-G3.cer` (see above).
5. Smoke-test **one real purchase** on a production App Store account (real
   money — refund via App Store Connect if needed).

Do **not** leave production on Sandbox after go-live: real store receipts would
then fail verification.

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
