---
epic: 0
title: Preparation & Foundations
sprint: "Sprint 0 (prep)"
aspect: null
status: planned
depends_on: []
repos:
  - synaplan-apps (private)
  - synaplan (public, submodule)
estimate: M
---

# Epic 0 — Preparation & Foundations

> The prep sprint. Nothing here ships UI; it removes the blockers that otherwise stall every
> later epic (accounts, IDs, the submodule build, naming, asset sources, the compatibility
> matrix). Do this first and the rest of the "vibing sprints" can run mostly unattended.

## Goal

Stand up a buildable `synaplan-apps` repo (Capacitor not added yet — that's Epic 1), confirm
all release-blocking decisions and accounts, and lock the identifiers/versions the whole
program depends on, in the context of the **Synaplan v4.0** release.

## v4.0 context / Why

v4.0 ships **platform stabilization + a mobile app together**. This epic establishes the
shared facts both halves rely on: which `synaplan` tag the app pins to, the app/bundle IDs that
appear in store listings, and the compatibility matrix (App ↔ pinned frontend ↔ backend API)
that the forced-update gate (Epic 8) and the joint release gate (Epic 11) will enforce.

## Scope

### In scope

- Decision confirmation + accounts.
- Private repo + Git submodule + `build.sh` skeleton.
- Identifier/version lock (app name, bundle IDs, version scheme).
- Asset & branding source inventory (hand-off to Epic 6 and Epic 4).
- Compatibility matrix document + secrets handling policy.

### Out of scope (deferred)

- `npx cap add ios/android` and any native project → **Epic 1**.
- Any code change inside the `synaplan` submodule → owned by the relevant later epic.

## Prerequisites

- Decide the Git host/org for the **private** `synaplan-apps` repo (already exists locally).
- Node 22+ available locally; macOS + Xcode 26+ for iOS (can be a later machine).

## Tasks

### 0.1 — Confirm decisions & set up store accounts

- [ ] Confirm the carried decisions in `Planning.md` → "Confirmed decisions".
- [ ] Create / verify **Apple Developer Program** ($99/yr) and **Google Play Console**
      ($25 once). Record team IDs. **This is the longest lead-time item — start day one.**
- [ ] Decide the final **production API/WS domain** the app will hit (e.g. `https://app.synaplan.com`
      or `https://web.synaplan.com`). This feeds `setApiBaseUrl` in Epic 3.

### 0.2 — Lock identifiers & versioning

- [ ] **App name** (store display) + **appId / bundle ID** (e.g. `com.synaplan.app`). Decide
      whether to use `dev`/`staging`/`prod` suffixes now (recommended; Epic 10 needs them).
- [ ] **Version scheme**: human `MAJOR.MINOR.PATCH` (starts at the v4.0 line) + monotonic
      `versionCode`/`CFBundleVersion`. Document how the version string flows into the
      `Synaplan Mobile Vx.x` User-Agent (Epic 2).
- [ ] Record all of the above in a `docs/IDENTIFIERS.md` in this repo.

### 0.3 — Repo + submodule + build skeleton

- [ ] Add the public `synaplan` repo as a **Git submodule** (e.g. at `./synaplan`), pinned to a
      **release tag/SHA** (not a moving branch).
- [ ] Write `build.sh`:
      `git submodule update --init` → `cd synaplan/frontend && npm ci && npm run build`
      (→ `synaplan/frontend/dist/`). (`npx cap sync` is added in Epic 1.)
- [ ] Verify `.gitignore` already covers native build artifacts (`ios/Pods`, `android/.gradle`,
      builds) **and** secrets (signing, service-account keys). (It exists; audit it.)
- [ ] Document the update workflow: `git submodule update --remote` **only to tagged releases**.

### 0.4 — Asset & branding source inventory (hand-off)

This is the discovery half of Aspects 2 & 4 — do the inventory now, implement later.

- [ ] Catalog existing brand assets in the submodule:
      `synaplan/frontend/public/single_bird*.svg`, `synaplan-light.svg`, `synaplan-dark.svg`,
      `site.webmanifest`, and note that `favicon-32.png` / `apple-touch-icon.png` /
      `icon-192.png` / `icon-512.png` are **generated, not committed**
      (`synaplan/frontend/scripts/generate-icons.mjs`).
- [ ] Identify the **high-resolution source art** needed for store icons (1024×1024) and splash.
      Flag the gap to Epic 6.
- [ ] List the current hardcoded brand touchpoints (feeds Epic 4): `APP_NAME` in
      `synaplan/frontend/src/router/index.ts`, "Powered by" blocks in `LoginView.vue`,
      `RegisterView.vue`, `LoggedOutView.vue`, `SharedChatView.vue`,
      `components/widgets/ChatWidget.vue`, and `--brand` in `synaplan/frontend/src/style.css`.

### 0.5 — Compatibility matrix + secrets policy

- [ ] Create `docs/COMPATIBILITY.md`: a table of **App version ↔ pinned `synaplan` submodule
      tag ↔ backend API contract ↔ OTA bundle**. Epic 8 (forced update) and Epic 11 (release
      gate) read from this.
- [ ] Create `docs/SECRETS.md`: where each secret lives and how it's injected (Apple private
      key, Google service-account key, Android keystore, signing certs, Capgo key). **No secret
      values in git.**

## Acceptance criteria (Definition of Done)

- `git clone --recursive` + `./build.sh` produces `synaplan/frontend/dist/` on a clean Node 22
  machine, with the submodule pinned to a tag.
- Apple + Google accounts exist (or a dated blocker is recorded with an owner).
- `docs/IDENTIFIERS.md`, `docs/COMPATIBILITY.md`, `docs/SECRETS.md` exist and are filled in.
- The production API/WS domain is decided and written down.
- Asset/branding gaps are itemized and handed to Epics 4 and 6.

## Test notes (for the QA person)

- No app to test yet. Sanity check: a teammate can clone fresh and `./build.sh` succeeds
  without manual steps beyond Node 22 + submodule credentials.

## Risks & mitigations

- **Account approval delay (Apple/Google can take days–weeks):** start 0.1 immediately; treat as
  the critical path.
- **Submodule auth friction in later CI:** decide HTTPS token vs SSH deploy key now (0.3) and
  record in `docs/SECRETS.md`.
- **ID churn later is expensive** (bundle IDs are near-permanent in stores): lock 0.2 before any
  store product is created (Epic 5/10).

## Open questions

- Final production API/WS domain?
- App name + bundle ID (incl. dev/staging/prod strategy)?
- Git host/org + submodule access method?
- Which `synaplan` tag is the v4.0 baseline the app pins to?
