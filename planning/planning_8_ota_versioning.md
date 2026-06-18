---
epic: 8
title: OTA, Versioning & Forced Update
sprint: "Sprint 8"
aspect: null
status: planned
depends_on: [1, 2]
repos:
  - synaplan-apps (private)
  - synaplan (public, submodule)
estimate: M
---

# Epic 8 — OTA, Versioning & Forced Update

> Native apps linger on old versions for a long time; the web app doesn't. This epic adds OTA
> live updates (from day one, per the confirmed decision) and a server-driven min-version gate so
> a too-old app can be forced to update. It builds directly on the version carried in the
> `Synaplan Mobile Vx.x` User-Agent (Epic 2).

## Goal

Ship conforming web-asset fixes without a store review (OTA), and reliably block/upgrade
incompatible old app versions via a runtime min-version gate, with a documented compatibility
matrix.

## v4.0 context / Why

For a "pretty bug-free" v4.0 that keeps improving, OTA lets us push non-payment fixes fast, while
the forced-update gate protects against breaking-API drift between long-lived app installs and the
evolving backend.

## Scope

### In scope

- Capgo OTA: plugin, update server/account, bundle versioning, signature, rollback.
- Min-version gate: runtime config delivers a minimum app version; too-old app shows
  "please update".
- Compatibility matrix: App version ↔ pinned frontend submodule tag ↔ backend API ↔ OTA bundle.

### Out of scope (deferred)

- Any OTA of payment/behavior logic — **forbidden** (store ban risk).

## Tasks

### 8.1 — OTA (Capgo) — synaplan-apps

- [ ] Add the Capgo plugin + update server/account. Version the web bundles; enable signature
      verification + a rollback strategy.
- [ ] **Only conforming changes via OTA** (UI/logic fixes) — **never** changes to behavior or
      payment logic (Apple 3.2.2 / Google). Document this rule in `docs/OTA_POLICY.md`.
- [ ] Tie OTA bundle versioning to the app + backend version (see matrix below).

### 8.2 — Forced update gate (synaplan submodule)

- [ ] Backend runtime config delivers a **minimum supported app version** (BCONFIG, exposed in
      `getRuntimeConfig()` alongside Epic 2's `client` block).
- [ ] App compares its version (same source as the UA, Epic 2) to the minimum; if too old, show a
      blocking "please update" screen with a store link. Server can also reject API calls from
      below-min versions using the parsed UA version (defense in depth).

### 8.3 — Compatibility matrix

- [ ] Fill in `docs/COMPATIBILITY.md` (created in Epic 0): App version ↔ pinned `synaplan`
      submodule tag ↔ backend API contract ↔ current OTA bundle. Keep it updated each release;
      Epic 11 reads it at the release gate.

## Acceptance criteria (Definition of Done)

- An OTA bundle update is delivered to a running app; restart picks up the new web version;
  rollback works.
- Setting the min-version above the installed app's version triggers the "please update" gate on
  next launch; setting it at/below lets the app run.
- `docs/COMPATIBILITY.md` is current and `docs/OTA_POLICY.md` exists.
- No payment/behavior logic is shipped via OTA (policy + review check).

## Test notes (for the QA person)

- Roll out a bundle update; confirm restart loads the new web version; test rollback.
- Forced-update: artificially set min-version > installed version → must block; then lower it.
- Confirm OTA does not (and cannot per policy) alter IAP/payment flows.

## Risks & mitigations

- **Store ban from OTA misuse:** strict OTA policy doc + review gate; payment logic never OTA'd.
- **Bricking via bad bundle:** signature + rollback; staged rollout.
- **Version-source mismatch:** single version source shared with the UA (Epic 2).

## Open questions

- OTA channel strategy (prod vs beta) and rollout percentages?
- Minimum-version bump policy: who decides and when?
