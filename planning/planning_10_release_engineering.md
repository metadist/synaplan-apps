---
epic: 10
title: Release Engineering & Delivery
sprint: "Sprint 10"
aspect: null
status: planned
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

### 10.1 — Build environments & versioning

- [ ] Local builds: iOS only on macOS/Xcode, Android via Android Studio/Gradle
      (`npx cap run ios|android`).
- [ ] Auto-increment `CFBundleVersion` / `versionCode`; separate **bundle IDs for
      dev/staging/prod** + an environment switch (`setApiBaseUrl`, Epic 3). Keep versions aligned
      with the UA version (Epic 2) and the compatibility matrix (Epic 8).

### 10.2 — Signing & secrets

- [ ] Signing management (e.g. **fastlane**): Apple certificates/profiles, Android keystore. Store
      secrets per `docs/SECRETS.md`; never in git.

### 10.3 — Crash reporting

- [ ] Native crash reporting (e.g. Sentry) — needs its own Apple privacy manifest (Epic 9).

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
- Crash-reporting vendor choice (Sentry vs other) + data-residency for EU.
