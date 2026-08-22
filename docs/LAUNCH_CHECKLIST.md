# Launch Checklist — "What we still need at the end"

> **Single source of truth for everything that is intentionally deferred to the launch /
> device / go-live phase.** Code-side work is being done epic-by-epic now; this file collects
> the things that need **a real device, a provider account, a secret, money, or a product
> decision** — i.e. the things we cannot finish from the editor and will do together at the end.
>
> Keep this updated: when an epic finishes its code part but leaves a device/account/decision
> tail, add it here. Detail docs (`SECRETS.md`, `OTA_POLICY.md`, `COMPATIBILITY.md`,
> `IDENTIFIERS.md`) stay authoritative for *how*; this file is the *what's-left* overview.

**Legend — Owner:** 👤 = you/business decision or account · 🤖 = me (code/config once unblocked) · 🧪 = on-device QA.

---

## 1. Provider accounts to create / enroll

These gate everything in stores, payments, OTA and crash reporting. Nothing here can be done
from code.

| # | Account | Unlocks | Cost | Owner | Done |
|---|---------|---------|------|-------|------|
| A1 | **Apple Developer Program** | iOS signing, App Store Connect, TestFlight, App Store Server API (IAP) | ~99 €/yr | 👤 | ☑ |
| A2 | **Google Play Console** developer account | Android upload, Play Internal Testing, Play Developer API (IAP) | ~25 € once | 👤 | ☑ |
| A3 | **Self-hosted Capgo** deployment | OTA bundle hosting, telemetry, rollback, and signing (Epic 8) | self-hosted | 👤 | ☑ |
| A4 | **Google Cloud project** (Pub/Sub) | Play Real-time Developer Notifications for IAP (Epic 5) | usage-based | 👤 | ☐ |
| A5 | **Crash-reporting vendor** (e.g. Sentry) project | Native crash reporting + DSN (Epic 10) | free/paid | 👤 | ☐ |
| A6 | **Stripe** (already exists for web) | confirm web checkout stays the only web payment path | — | 👤 | ☐ |

> After A1/A2: record the Apple **Team ID** and final **bundle IDs** in `docs/IDENTIFIERS.md`
> (dev/staging/prod split, Epic 10.1).

---

## 2. Secrets & environment variables

Full policy + storage locations live in **`docs/SECRETS.md`** (the golden rule: no secret value
ever in git). This is the quick "what must exist before go-live" list.

### 2a. Build / release secrets (synaplan-apps, CI secret store)

| Env / file | Purpose | Source | Owner | Done |
|------------|---------|--------|-------|------|
| `CAPGO_API_KEY`, `CAPGO_SUPA_ANON` | upload to the approved self-hosted Capgo deployment | deployment API keys (upload scope) | 👤→🤖 | ☐ |
| `CAPGO_BUNDLE_PRIVATE_KEY` | sign/encrypt OTA bundles; public key is a protected build variable | `npm run ota:key:create` (generate once, **back up!**) | 🤖→👤 | ☐ |
| Apple distribution cert (`.p12`) + provisioning profiles | iOS signing | App Store Connect / fastlane match | 👤 | ☐ |
| App Store Connect API key (`.p8`) + Key ID + Issuer ID | TestFlight upload **and** App Store Server API v2 (IAP) | App Store Connect → Integrations | 👤 | ☐ |
| Android upload keystore (`.jks`) + alias + passwords | Android signing — **back up, unrecoverable if lost** | generated once | 👤 | ☐ |
| Google Play service-account JSON | Play upload + Play Developer API (IAP) | Google Cloud IAM | 👤 | ☐ |
| Crash-reporting DSN (Sentry) | native crash reporting | Sentry project | 👤 | ☐ |

### 2b. Backend runtime env (synaplan submodule / server — out of this repo, but needed for the app to work)

| Setting | Purpose | Owner | Done |
|---------|---------|-------|------|
| Production **server URL** confirmed | the app's default is `https://web.synaplan.com` (in `app/synaplan-native.js`); confirm or change | 👤 | ☐ |
| OAuth credentials (GitHub + Google client id/secret) | native + web login (Epic 3) already wired; values are server-side | 👤 | ☐ |
| reCAPTCHA keys (runtime config) | login/register must work under the `capacitor://` origin (Epic 7.3) | 👤 | ☐ |
| `IAP_APPLE_BUNDLE_ID`, `IAP_APPLE_APP_APPLE_ID`, `IAP_APPLE_ENVIRONMENT`, `IAP_APPLE_ROOT_CERTS_DIR` | Apple server-side IAP validation (Epic 5.4 — **code done**, just unset until keys exist → `/iap/*` returns 503) | 👤 | ☐ |
| `IAP_GOOGLE_PACKAGE_NAME`, `IAP_GOOGLE_SERVICE_ACCOUNT_JSON` | Google server-side IAP validation (Epic 5.4 — **code done**, unset = disabled) | 👤 | ☐ |
| Google Cloud Pub/Sub topic + push endpoint auth | Play RTDN for IAP renew/cancel/refund (Epic 5.6) | 👤 | ☐ |
| `BRAND_*` config (per server) | white-label branding is DB/BCONFIG-driven, not env — set per deployment if white-labeling | 👤 | ☐ |

---

## 3. Open product decisions (need your call)

Collected from every epic's "Open questions" plus the asset decisions. None block current coding;
each affects launch scope.

### Branding / assets (Epic 6)
- [ ] **Dedicated dark app icon** (iOS 18 tinted/dark)? Today one brand-blue icon serves both modes. 👤
- [ ] **iPad / Android tablet** supported at launch? (Determines required screenshot sets + layout QA.) 👤
- [ ] **Custom designer 1024px icon** instead of the brand bird? If yes: replace `assets/icon-only.png` (+ foreground/background) and run `npm run assets:generate`. 👤

### OTA / versioning (Epic 8)
- [x] OTA strategy: protected **canary → production**, with pause/resume/rollback controls.
- [x] Minimum-version bump: only after the replacement is available in both stores, with an
  `UPDATE_ENFORCE_AFTER` grace period and a valid platform store URL.

### Payments / IAP (Epic 5)
- [ ] **Yearly IAP products at launch**, or monthly only first? 👤
- [ ] Exact **store price tiers per region** once the ≈30 % (15 %) commission is baked in? (ref: ~€19.95 / €49.95 / €99.95) 👤

### Native features / compliance (Epic 7 / 9)
- [ ] **Guest mode** in the app at launch? (Verified working in the shell; keep or hide.) 👤
- [ ] **Biometric lock** at launch or v2? (Optional opt-in toggle is already implemented, native-guarded.) 👤
- [ ] **Privacy-Policy + Terms-of-Use**: which legal entity / URLs back them for the SaaS brand vs self-hosted white-label brands? (Needed in-app **and** in store metadata.) 👤

### Release engineering (Epic 10)
- [x] Pinned fastlane automation for TestFlight, Play Internal, and protected staged production.
- [ ] **Crash-reporting vendor** (Sentry vs Crashlytics vs Bugsnag)? 👤 — **DEFERRED, decide before 10.3 build.** Everything else is already decided: EU SaaS region, capture native + WebView JS (native-gated), opt-out default + privacy disclosure, strict PII scrubbing, prod+staging only, release-tagged via Epic 10.1.

---

## 4. On-device / store QA (the device-bound phase)

Requires real iOS + Android devices (and beta tracks). Cannot be done from the editor.

### Assets (Epic 6.5)
- [ ] 🧪 Home-screen **icon** on real iOS + Android: light/dark + **Android adaptive masking** (circle/squircle/rounded). 
- [ ] 🧪 **Splash** screen on real devices, incl. dark mode.
- [ ] 👤 **Store screenshots** per launch locale **de/en/es/tr** (iPhone, + iPad if §3 says yes; Android phone + tablet).
- [ ] 👤 **Android feature graphic** (1024×500).

### Native features (Epic 7)
- [ ] 🧪 Camera + file-picker upload, microphone/voice, download + share — on a real device with correct permission prompts.
- [ ] 🧪 **Permission-denial** paths degrade gracefully (no crash).
- [ ] 🧪 Background several minutes → resume → realtime (WS/Centrifugo) + chat still work.
- [ ] 🧪 Airplane-mode toggle mid-session → offline UI → reconnect.
- [ ] 🧪 reCAPTCHA works (no white screen) in a **release** build under `capacitor://`.
- [ ] 🧪 Device locale mapping for each of de/en/es/tr.

### OTA + forced update (Epic 8)
- [ ] 🧪 Publish first OTA bundle → running app picks up new web version on restart; **rollback** works.
- [ ] 🧪 Set min-version > installed → "please update" gate blocks; lower it → app runs.
- [ ] 🧪 Confirm OTA cannot/does not alter IAP/payment flows (policy check).

### Payments / IAP (Epic 5)
- [x] 🤖 **5.3 native IAP frontend — code done.** `cordova-plugin-purchase` + `cordova-plugin-purchase-storekit2` installed and synced (SPM); the SPA's `nativeIap.ts` wires purchase + "Restore purchases" into `SubscriptionView.vue`, all verified via `POST /api/v1/iap/verify`. The first-run onboarding no longer offers plans or a restore affordance — both live on the subscription page. **iOS Simulator testing works today** with the checked-in StoreKit config (`ios/App/App/Synaplan.storekit` + shared `App` scheme + backend `IAP_APPLE_ENVIRONMENT=Xcode`) — see `docs/IAP_TESTING.md`. Device/sandbox QA below still needs real store products.
- [ ] 🧪 Sandbox IAP purchase grants tier **only after server validation**, bound to the user.
- [ ] 🧪 "Restore purchases" + "manage subscription" work.
- [ ] 🧪 **Cross-channel block**: active Stripe-web user cannot buy via IAP, and vice-versa.
- [ ] 🧪 Apple ASSN V2 / Google RTDN update entitlement on renew/cancel/refund with the app closed.
- [ ] 🧪 Google `acknowledge` < 3 days; `PENDING` not unlocked.

### Compliance (Epic 9)
> **Code-complete:** 9.1 in-app account deletion (pre-existing `DELETE /api/v1/profile` + `UserDeletionService`) **plus** the Google-required public web deletion page + configurable `BRAND_ACCOUNT_DELETION_URL` (synaplan `fcbb78c51`), 9.2 app-level `PrivacyInfo.xcprivacy` (commit `4d3ae10`), 9.3 configurable privacy/ToU URLs + in-app legal links (synaplan `11da457ee`, app bump `96275bc`), 9.4 anti-steering UX (no web/Stripe checkout in-app: subscription view routes to IAP/store, Restore-Purchases + store-manage + store note, hidden Stripe top-up/dunning; synaplan `87ef69571`), and 9.5 Guideline-4.2 gaps (native status-bar theming + Android hardware back-button; synaplan `87ef69571`) are done. The items below remain device-/account-gated.

- [ ] 🧪 In-app **account deletion** works (+ web deletion link for Google) — **code done**: in-app flow in Profile → Danger Zone, public page at `/account-deletion` (or branded `BRAND_ACCOUNT_DELETION_URL`); on-device verification + filling the store metadata URL still pending.
- [ ] 🧪 **Anti-steering** (Apple 3.1.1 / Google Play) — **code done**: in the native shell the subscription view never opens web/Stripe checkout or the billing portal, shows Restore-Purchases + "managed via App Store / Google Play", and the limit-reached top-up (web checkout) is hidden; on-device verification + store-listing copy (no cheaper-web-price wording) still pending.
- [ ] 🧪 Upload with a broken **`PrivacyInfo.xcprivacy`** is rejected → then fix (cover **every** SDK: Capacitor plugins, Capgo, Sentry, IAP plugin).
- [ ] 👤 **Privacy-nutrition / data-safety labels** filled and accurate vs actual permissions.
- [ ] 🧪 Reviewer path: install → native value visible in ~30 s → find privacy/ToU → restore purchases → delete account.
- [ ] 🤖/👤 Age rating, support URL, privacy URL set in **both** stores; Android **Target API 35** confirmed.

### Release / beta (Epic 10)
- [x] ⚙️ **Build environments + versioning (Epic 10.1):** `SYNAPLAN_ENV` (dev|staging|prod) → bundle-id suffix + app-name suffix + in-app badge; version from `package.json`, `versionCode`/`CFBundleVersion` from `SYNAPLAN_BUILD_NUMBER` (git-count fallback). See `docs/BUILD_ENVIRONMENTS.md`. Verified on Android emulator + iOS build settings.
- [ ] 🧪 Live on **TestFlight** (iOS) + **Play Internal Testing** (Android), installable by testers.
- [ ] 🧪 Re-run Epic 3 **auth** + Epic 5 **IAP** acceptance in the **release** tracks (WKWebView/StoreKit differ from debug).
- [ ] 🧪 Forced test crash appears in the crash dashboard.

---

## 5. Store-listing content needed (per locale: de / en / es / tr)

> **Copy drafted (Epic 10.4):** all text below is written for both stores × 4 locales in
> [`docs/STORE_LISTINGS.md`](STORE_LISTINGS.md) — store-safe (no third-party trademarks in
> name/keywords, anti-steering compliant), within each field's character limit. The remaining
> items are asset- or account-gated.

- [x] App name + subtitle/short description → `docs/STORE_LISTINGS.md`
- [x] Full description (anti-steering compliant — no cheaper-web-price advertising) → `docs/STORE_LISTINGS.md`
- [x] Keywords (App Store) → `docs/STORE_LISTINGS.md`
- [ ] Screenshots (see §4) 🧪 device + Epic 6 assets
- [ ] Android feature graphic 🧪 Epic 6 assets
- [x] Promotional / what's-new text → `docs/STORE_LISTINGS.md`
- [ ] Support URL, marketing URL, privacy URL, ToU URL 👤 confirm final URLs (drafted defaults in `docs/STORE_LISTINGS.md`)
- [ ] Age rating questionnaire answers 👤 (likely iOS 17+ / Play Teen — confirm)

---

## 6. Capgo OTA go-live follow-ups (explicit pending tail of Epic 8)

1. [x] 👤 Provision the approved self-hosted Capgo deployment.
2. [ ] 👤 Configure endpoint/public-key variables and `CAPGO_API_KEY`, `CAPGO_SUPA_ANON`, and
   `CAPGO_BUNDLE_PRIVATE_KEY` in the protected `canary` / `production` environments.
3. [ ] 👤 Configure approval rules for both environments.
4. [ ] 🤖 Publish the first canary bundle and run the on-device round-trip, automatic-revert, and
   explicit rollback tests (§4).
5. [ ] 🤖 Promote the verified source to production through the protected workflow.

---

## 7. IAP go-live provisioning (Epic 5.6 — account/infra-bound, cannot be coded)

The server-side validation code (Epic 5.4) is **done** and reads these once set; until then the
`/api/v1/iap/*` endpoints return 503 and the app stays Stripe/web-only. Every step here needs the
boss's Apple / Google / Google-Cloud access — none of it can be done from the repo.

1. [ ] 👤 **Apple App Store Connect API key (`.p8`)** + Key ID + Issuer ID → fill `IAP_APPLE_BUNDLE_ID`, `IAP_APPLE_APP_APPLE_ID`, `IAP_APPLE_ENVIRONMENT`, and provide the Apple root CA certs dir (`IAP_APPLE_ROOT_CERTS_DIR`). (Downloadable only once — back up.)
2. [ ] 👤 **Google Cloud service-account JSON** with Play Developer API access → fill `IAP_GOOGLE_PACKAGE_NAME`, `IAP_GOOGLE_SERVICE_ACCOUNT_JSON`.
3. [ ] 👤 **Google Cloud Pub/Sub topic** + push subscription pointing at `POST /api/v1/iap/google/notifications` (RTDN), incl. push-endpoint auth.
4. [ ] 👤 Wire **Apple App Store Server Notifications V2** URL → `POST /api/v1/iap/apple/notifications`.
5. [ ] 👤 Create **Apple Sandbox testers** + **Google license-testing accounts** (no real charges) for the on-device IAP QA (§4).
6. [ ] 👤 Store all of the above per `docs/SECRETS.md` (CI secret store / backend env, never git).

---

## 8. Related detail docs

| Doc | Covers |
|-----|--------|
| `docs/SECRETS.md` | Secret inventory, injection, backup-critical keys |
| `docs/IDENTIFIERS.md` | Bundle IDs, Team ID, app identifiers |
| `docs/OTA_POLICY.md` | What may / may not ship via OTA |
| `docs/COMPATIBILITY.md` | App ↔ submodule tag ↔ backend API ↔ OTA bundle matrix |
| `docs/ASSETS.md` | Icon/splash master art + regeneration |
| `docs/SERVER_CONFIG.md` | In-app server switcher + default server URL |
| `docs/IAP_TESTING.md` | IAP testing: iOS Simulator (StoreKit config), sandbox, Play internal testing |
| `docs/SYNAPLAN_BLAST_RADIUS.md` | Every change made to the public submodule |
| `docs/RELEASE_GATE_v4.md` | The go/no-go decision gate that consumes this checklist (Epic 11) |
