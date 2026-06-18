---
epic: 9
title: Store Compliance & UX
sprint: "Sprint 9"
aspect: null
status: planned
depends_on: [4, 5, 6, 7]
repos:
  - synaplan-apps (private)
  - synaplan (public, submodule)
estimate: M
---

# Epic 9 — Store Compliance & UX

> The submission gate. This epic collects every "or your app gets rejected" requirement into one
> checklist and does the final UX polish so a reviewer sees, in ~30 seconds, why this is a real
> app (Guideline 4.2). It depends on branding (4), payments (5), assets (6), and native features
> (7) being in place.

## Goal

The app clears Apple App Review + Google Play policy on first submission: account deletion,
privacy manifests/labels, subscription metadata, anti-steering, and minimum functionality.

## v4.0 context / Why

A rejected submission delays the whole v4.0 launch. Compliance is cross-cutting, so it gets its
own pass rather than being scattered.

## Scope / Tasks

### 9.1 — Account deletion (mandatory)

- [ ] **In-app account deletion** (Apple & Google require it when accounts can be created). Google
      additionally requires a **web link** to deletion. Wire to the existing backend account flow.

### 9.2 — Apple privacy manifest

- [ ] `PrivacyInfo.xcprivacy` (2026: strictly enforced at upload): declare Required-Reason APIs.
      **Every third-party SDK** (Capacitor plugins, Capgo, Sentry, IAP plugin) needs its own
      manifest + signature. A missing/invalid manifest **fails the upload**.

### 9.3 — Privacy & data-safety labels

- [ ] App Store Privacy Nutrition Label + Play Data Safety must match actual data use. Permission
      purpose strings (camera/mic/files) consistent with Epic 7.
- [ ] Privacy-Policy **and** Terms-of-Use links in store metadata **and** reachable in-app
      (e.g. Settings). Reconcile with the branded/configurable links from Epic 4.

### 9.4 — Subscription metadata & anti-steering

- [ ] Subscription prices/trial terms readable and consistent with App Store Connect / Play.
- [ ] **Anti-steering** verified (from Epic 5): no advertising of cheaper web prices, no in-app
      link to web checkout for digital goods. "Restore purchases" + manage-via-store present.

### 9.5 — Guideline 4.2 minimum functionality

- [ ] Demonstrable native value: splash, status-bar theming, offline handling, native
      navigation/back, camera/file/share (Epics 1 + 7). A pure web wrapper is rejected — the
      reviewer must immediately see "why this is an app".
- [ ] Android hardware back-button, keyboard behavior (verify the existing
      `useKeyboardOpen.ts`/`useKeyboard*` handling), dark-mode status bar.

### 9.6 — Misc gates

- [ ] Age rating, support URL, privacy URL set in both stores.
- [ ] Android **Target API 35** confirmed (also checked in Epic 1).

## Acceptance criteria (Definition of Done)

- Account can be deleted in-app (and via web link for Google).
- A build with a valid `PrivacyInfo.xcprivacy` (incl. all SDK manifests) passes upload validation.
- Privacy/data-safety labels filled and accurate; privacy + ToU links present in-app and in
  metadata.
- Anti-steering verified; restore + manage-subscription present.
- The app shows clear native functionality (4.2) on a reviewer's quick pass.
- Target API 35 confirmed; age rating + URLs set.

## Test notes (for the QA person)

- Attempt an upload with a missing/broken privacy manifest → confirm it's rejected (then fix).
- Walk the reviewer's path: install → see native value within 30s → find privacy/ToU → restore
  purchases → delete account.
- Cross-check privacy labels against the permissions actually requested (Epic 7).

## Risks & mitigations

- **Privacy manifest upload reject (very common in 2026):** verify before submission; cover every
  SDK.
- **4.2 "minimum functionality" reject:** ensure tangible native features, not just a web view.
- **Anti-steering slip via branding links (Epic 4):** audit all in-app links for web-payment paths.

## Open questions

- Which legal entity / URLs back the privacy policy + ToU for self-hosted brands vs SaaS?
