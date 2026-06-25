---
epic: 10
title: Release Engineering & Delivery
sprint: "Sprint 10"
aspect: null
status: in-progress
depends_on: [8, 9]
repos:
  - synaplan-apps (private)
estimate: L
---

# Epic 10 — Release Engineering & Delivery

> Turn a compliant app into a repeatable, signed, shippable artifact on both stores' beta tracks,
> then production. Everything functional is done by now; this is signing, versioning,
> crash-reporting, store metadata, and (carefully) CI.

## Goal

Reproducible signed builds for dev/staging/prod, automated version bumping, crash reporting, store
metadata in all launch locales, and beta distribution via TestFlight + Play Internal Testing.

## v4.0 context / Why

This is the delivery rail for the v4.0 app launch and every subsequent update; it must coexist
with OTA (Epic 8) and the joint release gate (Epic 11).

## Scope / Tasks

### 10.1 — Build environments & versioning ✅ (code-complete)

- [x] Local builds: iOS only on macOS/Xcode, Android via Android Studio/Gradle
      (`npx cap run ios|android`).
- [x] Auto-increment `CFBundleVersion` / `versionCode`; separate **bundle IDs for
      dev/staging/prod** + an environment switch (`setApiBaseUrl`, Epic 3). Keep versions aligned
      with the UA version (Epic 2) and the compatibility matrix (Epic 8).

> **Implemented** (see `docs/BUILD_ENVIRONMENTS.md`). A single env switch
> `SYNAPLAN_ENV` (dev|staging|prod) selects the bundle id suffix (`.dev`/`.staging`)
> and a visible app-name suffix ("Synaplan Dev"/"Synaplan Staging"). The human
> version is owned by `package.json` (drives `versionName`/`MARKETING_VERSION` **and**
> the UA token), and `SYNAPLAN_BUILD_NUMBER` (CI) → `versionCode`/`CFBundleVersion`,
> falling back to the git commit count locally. Android is wired Gradle-natively
> (`android/app/build.gradle`); iOS is stamped by `scripts/app-config.mjs` (run from
> `build.sh`). Non-prod builds also carry an in-app environment badge.
> **Verified** on the Android emulator: `com.synaplan.app.dev`, label "Synaplan Dev",
> versionName 4.0.0 / versionCode 1, badge "DEV · 4.0.0 (1)" — coexisting with prod;
> iOS resolves `com.synaplan.app.dev` / 4.0.0 via `xcodebuild -showBuildSettings`.

### 10.2 — Signing & secrets

- [ ] Signing management (e.g. **fastlane**): Apple certificates/profiles, Android keystore. Store
      secrets per `docs/SECRETS.md`; never in git.

### 10.3 — Crash reporting (parameters decided; **vendor deferred to the end**)

- [ ] Native crash reporting — needs its own Apple privacy manifest (Epic 9).

> **Decided** (2026-06-25), implementation BLOCKED on the vendor pick (see end-of-project
> decisions). When the vendor is chosen, build to these parameters:
> - **Hosting / residency:** EU SaaS region (managed; self-host only if later required).
> - **Capture scope:** native crashes **+ WebView JS errors**, wired in the native shell
>   and `isNativeApp()`-gated — no crash SDK on the plain web deployment (zero blast
>   radius in the submodule).
> - **Consent (GDPR):** ON by default with a clear **opt-out** toggle in settings + a
>   privacy disclosure. Respect the toggle before initializing the SDK.
> - **PII:** strict scrubbing — never send message content or auth tokens, anonymize IP;
>   send only stack traces, device model/OS, and the app version/build.
> - **Environments:** enabled in **prod + staging** only (dev off), tagged with the
>   Epic 10.1 version/build as the release for symbolication.
> - **Privacy manifest / Data Safety:** add the vendor's required `PrivacyInfo` reasons +
>   declare "crash data / diagnostics" in both stores once the SDK is in.

### 10.4 — Store listings

- [ ] Screenshots + descriptions in **4 languages (de/en/es/tr)** (assets from Epic 6), age
      rating, support/privacy URLs (Epic 9).

### 10.5 — Beta distribution + CI

- [ ] **TestFlight** (iOS) + **Play Internal Testing** (Android) for beta. Verify auth + IAP in
      these tracks (release strictness — Epics 3 & 5).
- [ ] CI/signing automation — **only after explicit sign-off** (Docker/CI config changes are
      gated per repo AGENTS rules). Reuse the submodule build flow.

## Acceptance criteria (Definition of Done)

- One command (per platform) produces a signed build for a chosen environment with the correct
  bundle ID + auto-incremented version.
- A build is live on **TestFlight** and **Play Internal Testing**, installable by testers.
- Crash reporting receives a test crash from a native build.
- Store listings (metadata + screenshots) complete in de/en/es/tr.
- Auth + IAP verified in the beta tracks (not just local debug).

## Test notes (for the QA person)

- Install via TestFlight + Play Internal Testing on real devices.
- Re-run the **Epic 3 auth** and **Epic 5 IAP** acceptance checks in these **release** tracks
  (WKWebView/StoreKit behave differently than debug).
- Confirm a forced crash appears in the crash dashboard.

## Risks & mitigations

- **Signing/provisioning friction:** fastlane + documented secrets; do a dry run early.
- **CI changing gated configs:** require sign-off; keep CI optional until then.
- **Env/bundle-ID mix-ups:** distinct IDs + visible environment indicator in non-prod builds.

## Open questions

- Use fastlane now or manual signing for the first release?
- **Crash-reporting vendor choice** (Sentry vs Crashlytics vs Bugsnag) — **deferred to the
  end-of-project decisions**. Residency + all other parameters are already decided (see 10.3).
