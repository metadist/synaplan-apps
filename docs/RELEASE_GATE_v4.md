# Release Gate — Synaplan v4.0 (platform + mobile apps)

> The single **go/no-go decision gate** for shipping platform v4.0 and the iOS/Android apps
> **together** (Epic 11.4). Every **GO** item must be checked (or explicitly waived with an owner
> + reason) before tagging. This file is the *decision*; the *how/what's-left* lives in the docs
> linked per section — this gate only **references** them, never duplicates them.
>
> Run this once, in a single release meeting, against a **clean checkout** and **release-track**
> builds. A red item is a **BLOCKER** unless waived in writing in §8.

**Legend — Owner:** 👤 business/account decision · 🤖 code/config (done from repo) · 🧪 on-device/release-track QA.
**State:** ✅ done · ⬜ open · 🟡 waived (record in §8).

---

## 0. Pre-gate snapshot (fill in at decision time)

| Field | Value |
|-------|-------|
| App version (`MAJOR.MINOR.PATCH`, UA `Synaplan Mobile Vx.x`) | `4.0.2` |
| `synaplan` submodule tag the bundle was built from | `v4.3.0` (`0849c2a0d`, worktree clean and equal to the gitlink) |
| iOS build (`CFBundleVersion`) / Android (`versionCode`) | `145` / `145` |
| Store-RC runs the internal-track binaries came from | iOS [`32948496598`](https://github.com/metadist/synaplan-apps/actions/runs/32948496598) · Android [`32947325781`](https://github.com/metadist/synaplan-apps/actions/runs/32947325781) — both green |
| Crash-reporting vendor decided? | ⬜ (see §6) |
| Decision date / chair | `__________` |

> Snapshot recorded **2026-08-26** for the 4.0.2 launch-screen release. Every ✅ below carries its
> evidence inline. 🧪 and 👤 items cannot be closed from the repository and are the remaining work.

---

## 1. Engineering gates — both repos green, unfiltered (Epic 11.3 / 12)

> A green run of a **filtered** subset does **not** count (see the submodule `AGENTS.md`
> "`--filter` ≠ `make test`" trap). Full gate definitions: [`docs/QUALITY_GATES.md`](QUALITY_GATES.md).

### 1a. `synaplan` submodule (platform)

> Verified against the **pinned commit itself** (`0849c2a0d`) via its platform CI run, not a local
> stack. The maintained workstation's standalone platform checkout sits at `v4.3.0+3` (touching
> `httpClient.ts` and `auth.ts`, i.e. auth paths), so a local run there would have recorded a green
> gate for a tree the bundle was **not** built from. Per the submodule `AGENTS.md`, each local target
> maps 1:1 to a CI job and `All Checks Passed` is the gate — that job is green on this commit.

- ✅ 🤖 `make -C backend lint` (PSR-12) — CI job *PHP Code Formatting*: success
- ✅ 🤖 `make -C backend phpstan` (analyses `src/` **and** `tests/`) — CI job *Backend (PHP/Symfony)*: success
- ✅ 🤖 `make -C backend test` (full PHPUnit suite, not just `Unit/`) — same job, unfiltered: success
- ✅ 🤖 `make -C frontend lint` — CI job *Frontend (Vue/TypeScript)*: success
- ✅ 🤖 `docker compose exec -T frontend npm run check:types` (vue-tsc) — same job: success
- ✅ 🤖 `make -C frontend test` (Vitest) — same job: success; *E2E Tests* (chromium, firefox, mobile, OIDC) and *E2E Visual Snapshots* also green
- ✅ 🤖 If runtime-config schema changed (Epics 2/4/8): `make -C frontend generate-schemas` re-run + type check clean — **no runtime-config schema change in 4.0.2**; the release is app-side only
- ✅ 🤖 App build generated schemas from the same reviewed OpenAPI contract as the pinned
  submodule; no schema drift between platform and bundled SPA — each Store-RC run downloads the
  commit-matching OpenAPI artifact and `check:release:strict` reported `app=4.0.2 synaplan=v4.3.0 mode=strict`
- ✅ 🤖 Characterization snapshots reviewed (no unintended routing/classifier drift) — the
  characterization suite runs inside the green *Backend (PHP/Symfony)* job on the pinned commit, and
  4.0.2 changes no platform code, so no snapshot drift originates here

### 1b. `synaplan-apps` (native shell)
- ✅ 🤖 `npm run ci-local` — gate 1 (ESLint + tsc), 3 (parse + native-manifest), 4 (Prettier) green; re-run for 4.0.2: **55/55**
- ✅ 🤖 Gate 2 native click-through — **Android emulator 3/3** ([`docs/NATIVE_E2E.md`](NATIVE_E2E.md)); iOS shell manually verified (Maestro-iOS WebView limitation, tracked)
- ⬜ 🧪 Gate 2 re-run on a **release-track** build (not just debug) on at least one iOS + one Android device
  — *the release-track binaries are on both internal tracks (TestFlight build 145, Play versionCode 145) and ready to install*

---

## 2. Aspect default-safety regression — the web must be unchanged (Epic 11.2)

> The reviewed baseline `v3.9.6` contains the approved mobile seams. The
> non-negotiable platform contract is that an **unconfigured** web/self-host deployment (no branding,
> no app client, no IAP keys) behaves **identically to pre-v4.0**. Enforced by
> [`docs/SYNAPLAN_BLAST_RADIUS.md`](SYNAPLAN_BLAST_RADIUS.md) + the AI logic review
> ([`docs/AI_LOGIC_REVIEW.md`](AI_LOGIC_REVIEW.md)).

- ⬜ 🤖 **Blast radius:** submodule diff vs the v4.0 baseline tag == the file set in `SYNAPLAN_BLAST_RADIUS.md` — nothing more.
  — *Cannot be answered as written: the recorded baseline is `v3.9.6` while the pin is now `v4.3.0`, so
  the diff contains regular platform development far beyond the mobile seams. Needs re-basing to the
  current pin before it can be a pass/fail check.*
- ⬜ 🧪 **Aspect 1 (UA):** web User-Agent unchanged; backend client-detection defaults to `web` for non-app clients.
- ⬜ 🧪 **Aspect 2 (branding):** unconfigured deployment is pixel-identical to pre-v4.0; all four locales (de/en/es/tr) intact; no hardcoded "Powered by".
- ⬜ 🧪 **Aspect 3 (payments):** web Stripe checkout + portal + webhooks fully work; existing subs report `source:'stripe'`; open-source/no-billing mode unaffected (no purchase UI).
- ⬜ 🧪 **Aspect 4 (assets):** web favicons/PWA icons present + correct; brand color consistent.

---

## 3. Per-epic acceptance — app go-criteria (Epic 11.4)

> Pulls the launch-critical acceptance criterion from each epic. Code-complete items are marked ✅;
> the device/account tail for each lives in [`docs/LAUNCH_CHECKLIST.md`](LAUNCH_CHECKLIST.md).

### 3.1 Shell & identity (Epics 1–2)
- ✅ 🤖 `build.sh` + `cap sync` succeed; bundled SPA renders, no remote `server.url`; secrets/artifacts gitignored.
- ⬜ 🧪 Cold launch on real iOS + Android: no white screen; splash + themed status bar + Android back button behave.
  — *The launch-screen hang this release fixes was reproduced and re-verified on the iOS simulator and
  the Android emulator against both a dead and a live OTA endpoint; the bootstrap watchdog bounds the
  wait. Confirmation on real hardware after a multi-day cold start is still open — that is the exact
  condition the original report came from.*
- ⬜ 🧪 UA carries `Synaplan Mobile V4.0` on **fetch + SSE + WS upgrade**; web UA unchanged.

### 3.2 Auth (Epic 3) — highest-risk path
- ✅ 🤖 Default server `web.synaplan.com`; in-app server switch validates by probe; rejects bogus/`http://`/non-Synaplan URL.
- ⬜ 🧪 Login + chat **SSE** + realtime **WS** + ≥1 **OAuth** provider work in a **release/TestFlight** build; survive background→resume.
- ⬜ 🧪 Per-server token isolation; token never sent to another host; never logged (AI security review).

### 3.3 Payments / IAP (Epic 5) — store-critical
- ✅ 🤖 Server-side validation (5.4) done; `/iap/*` returns 503 until keys set (Stripe/web-only fallback safe).
- ⬜ 🧪 Sandbox IAP grants tier **only after server validation**, user-bound; **Restore** + **manage-in-store** work.
- ⬜ 🧪 **Cross-channel block** server-enforced (Stripe-web ↔ IAP); ASSN V2 / RTDN update entitlement with app closed; Google ack < 3 days.

### 3.4 Native features (Epic 7)
- ✅ 🤖 iOS purpose strings present + `Info.plist`/manifest well-formed (`tests/native-manifests.test.mjs`).
- ⬜ 🧪 Camera/file/mic/download/share on device; permission-denial degrades (no crash); token in Keychain/Keystore; offline recovers; reCAPTCHA works under `capacitor://` in a release build.

### 3.5 OTA & forced update (Epic 8)
- ✅ 🤖 `capacitor.config.ts` OTA block inert until registered; `OTA_POLICY.md` + `COMPATIBILITY.md` present.
- ✅ 🤖 Self-hosted Capgo update/channel endpoints configured privately; upload target verified
  before publishing. — *Injected as protected variables on the `store-qa` environment (never in the
  repository); the Store-RC step "Require a verifiable OTA configuration" is green in every run, and
  both endpoints answered an empty probe with HTTP 400 in under a second on 2026-08-26, so the service
  is reachable and rejecting malformed input as expected.*
- ⬜ 🧪 OTA bundle delivered + applied on restart; staged rollout and rollback work; min-version
  gate blocks too-old then allows.
  — *Deliberately not exercised for 4.0.2. With `autoUpdate: 'atBackground'` the apply timing changed,
  so this needs re-running against a published bundle once one is cut.*
- ✅ 🤖 **No payment/behavior logic shipped via OTA** (policy check — [`docs/OTA_POLICY.md`](OTA_POLICY.md)).
  — *4.0.2 ships **no** OTA bundle at all: it changes the launch-screen and OTA-apply path, which the
  policy classifies as store-required, and it went out through Store-RC only.* The 🧪 half of this
  check belongs to the OTA verification above.

### 3.6 Store compliance (Epic 9)
- ✅ 🤖 In-app account deletion + public web deletion page (+ configurable `BRAND_ACCOUNT_DELETION_URL`); anti-steering UX (no web/Stripe checkout in-app, Restore + manage-in-store, hidden Stripe top-up/dunning); Apple Guideline 4.2 gaps (status-bar theming, Android back).
- ✅ 🤖 OTA/store classification reviewed against Apple Guideline 2.5.2 and Apple Developer
  Program License Agreement 3.3.2. — *4.0.2 was classified **store-required** and recorded as such in
  [`COMPATIBILITY.md`](COMPATIBILITY.md): it changes the update mechanism's own timing and the launch
  screen, which ADPLA 3.3.2 does not permit shipping as interpreted code over the air.*
- ⬜ 🧪 Reviewer path: install → native value visible ~30 s → find privacy/ToU → restore purchases → delete account.
- ⬜ 🧪 Upload with a broken `PrivacyInfo.xcprivacy` is rejected → fixed; **every** SDK manifest covered (Capacitor plugins, Capgo, crash SDK, IAP plugin).
- ⬜ 👤 Privacy-nutrition / data-safety labels accurate vs actual permissions.

### 3.7 Build env & versioning (Epic 10.1)
- ✅ 🤖 `SYNAPLAN_ENV` → bundle-id + app-name suffix + in-app badge; version single-sourced from `package.json`; build number from `SYNAPLAN_BUILD_NUMBER` (git-count fallback). Verified on Android emulator + iOS build settings ([`docs/BUILD_ENVIRONMENTS.md`](BUILD_ENVIRONMENTS.md)).
  — *Store builds now add `STORE_BUILD_NUMBER_OFFSET` (140) to the commit count. Squashing the history
  had reset the count below the published range, and Google Play rejects a `versionCode` that does not
  increase per package even under a new `versionName`. Proven end to end: both stores accepted 145.*

---

## 4. Store listing & assets readiness (Epics 6 / 10.4)
- ✅ 🤖 Listing copy (name/subtitle/description/keywords/what's-new) for **de/en/es/tr**, store-safe + within limits ([`docs/STORE_LISTINGS.md`](STORE_LISTINGS.md)).
- ⬜ 👤 Final **support / privacy / ToU / marketing URLs** confirmed (drafted defaults in `STORE_LISTINGS.md`).
- ⬜ 👤 **Age-rating** questionnaire answered (likely iOS 17+ / Play Teen — confirm).
- ⬜ 🧪 **Screenshots** per locale + **Android feature graphic** (1024×500); icon/splash on real devices incl. dark + Android adaptive masking.
  — *The assets exist under `_appstores/` (framed iPhone 6.5" sets for `en-US` and `de-DE`, Play phone
  screenshots, `feature-graphic-1024x500.png`) but are **uncommitted** — they only live in the working
  tree of one machine. Commit them, then close the on-device icon/splash half separately.*

---

## 5. Accounts, secrets & provisioning (gating; cannot be coded)
> Full inventory: [`docs/LAUNCH_CHECKLIST.md`](LAUNCH_CHECKLIST.md) §1–2, §6–7 + [`docs/SECRETS.md`](SECRETS.md).
- ✅ 👤 Apple Developer + Google Play Console enrolled; **Team ID + final bundle IDs** recorded in [`docs/IDENTIFIERS.md`](IDENTIFIERS.md).
  — *Both enrolments are proven by the 2026-08-26 uploads reaching TestFlight and the Play internal
  track; Team ID `X9GM4T2MQG` and the three bundle IDs are recorded.*
- ⬜ 👤 Signing material in place (Apple cert/profiles + ASC API key `.p8`; Android keystore — **backed up**, unrecoverable if lost).
  — *Presence and validity are proven: the signed IPA and AAB built, were signed and were accepted by
  both stores today. **The backup obligation is what remains unverified** and only you can confirm it
  ([`SECRETS.md`](SECRETS.md)) — the Android keystore is unrecoverable if lost.*
- ⬜ 👤 IAP provisioning live (ASC API key, Google service account, Pub/Sub RTDN, ASSN V2 URL, sandbox/license testers).
- ⬜ 👤 Self-hosted Capgo service + upload credential + OTA signing key available and **backed up**
  (public key injected as a protected build variable; private endpoint/credentials kept out of docs).
- ⬜ 👤 No secret value committed to git (spot-check; `.env`/credentials gitignored).

---

## 6. Crash reporting (Epic 10.3)
> Decided: EU SaaS region · capture native + WebView JS (native-gated) · opt-out default + privacy
> disclosure · strict PII scrubbing · prod+staging only · release-tagged via Epic 10.1.
- ⬜ 👤 **Vendor chosen** (Sentry vs Crashlytics vs Bugsnag) — *deferred*; must be decided **before** wiring the SDK.
- ⬜ 🤖 SDK integrated behind the decided config; PII scrubbing on; `PrivacyInfo.xcprivacy` updated for the SDK.
- ⬜ 🧪 A forced test crash reaches the dashboard from a release build.

---

## 7. Coordinated tagging & compatibility (Epic 11.4)
- ✅ 🤖 Tag `v4.3.0` created and the app submodule pinned to its exact commit (`0849c2a0d`; worktree
  clean and equal to the gitlink, so the bundle was built from the pin).
- ✅ 🤖 Bump app version + `versionCode`/`CFBundleVersion`. — *`4.0.2`, build `145` on both platforms.*
- ✅ 🤖 Add the release row to [`docs/COMPATIBILITY.md`](COMPATIBILITY.md); set `MIN_APP_VERSION` only if there is a breaking API change.
  — *Row present; the version gate stays empty because 4.0.2 changes no API contract.*
- ⬜ 🤖 Tag platform + apps consistently; confirm the pinned tag matches the snapshot in §0.
  — *Deliberately still open. The platform carries `v4.3.0` and the pin matches §0, but `synaplan-apps`
  has no `v4.0.2` tag, because this gate requires every GO item to be checked **before** tagging. When
  the decision lands, tag commit `b62e1fd4c` — both build-145 binaries came from it (no workflow in
  this repository triggers on tags, so it is a marker only).*
- ✅ 🤖 The protected production workflow references a successful Store-RC run and re-checks the
  recorded AAB/IPA checksums before changing either staged rollout. — *`production-promotion.yml`
  asserts `conclusion == "success"` on the referenced run, re-verifies `checksums.sha256` against the
  downloaded binaries and matches `appVersion` / build number / `googlePlayTrack` from
  `upload-request.json`. Exercised on 2026-08-26: both promotion dry runs passed these checks for
  Apple build 145 and Play versionCode 145 without touching either store.*

---

## 8. Sign-off & waivers

| Role | Name | GO / NO-GO | Date |
|------|------|-----------|------|
| Platform / backend | | | |
| Mobile / app | | | |
| Product / business | | | |

**Waived items** (item id · reason · owner · follow-up date):

- `__________`

**Decision:** ⬜ GO  ·  ⬜ NO-GO  ·  ⬜ GO with waivers (listed above)

---

## Related docs
| Doc | Role in the gate |
|-----|------------------|
| [`QUALITY_GATES.md`](QUALITY_GATES.md) | The five gates + per-epic test matrix (§1) |
| [`LAUNCH_CHECKLIST.md`](LAUNCH_CHECKLIST.md) | The deferred account/secret/device tail (§3–6) |
| [`COMPATIBILITY.md`](COMPATIBILITY.md) | App ↔ submodule tag ↔ API ↔ OTA matrix (§7) |
| [`SYNAPLAN_BLAST_RADIUS.md`](SYNAPLAN_BLAST_RADIUS.md) | Default-safety / encapsulation proof (§2) |
| [`AI_LOGIC_REVIEW.md`](AI_LOGIC_REVIEW.md) | The gate-5 review prompt (§1–2) |
| [`SECRETS.md`](SECRETS.md) · [`IDENTIFIERS.md`](IDENTIFIERS.md) · [`OTA_POLICY.md`](OTA_POLICY.md) · [`STORE_LISTINGS.md`](STORE_LISTINGS.md) | §4–7 detail |
