---
epic: 1
title: Capacitor Shell & Minimal Native App
sprint: "Sprint 1"
aspect: null
status: planned
depends_on: [0]
repos:
  - synaplan-apps (private)
  - synaplan (public, submodule)
estimate: M
---

# Epic 1 — Capacitor Shell & Minimal Native App

> The "minimal work" core of the whole program: wrap the existing SPA in Capacitor 8 with
> **no new UI**. The bundled `synaplan/frontend/dist/` runs in a WebView; everything else is
> native plumbing. Keep it minimal — but add *just enough* native value so Apple's Guideline
> 4.2 reviewer can tell in ~30s "why this is an app" (deep detail in Epic 9).

## Goal

A buildable, runnable iOS + Android app that loads the bundled SPA from the local origin
(`capacitor://localhost` / `https://localhost`), with the essential native plugins wired in.

## v4.0 context / Why

This is the foundation the four Aspects bolt onto: Aspect 1 (User-Agent) is a Capacitor config
flag added here; Aspect 3 (payments) and Aspect 4 (assets) need a working shell to test on.

## Scope

### In scope

- Capacitor 8 dependencies + `capacitor.config.ts`.
- `npx cap add ios` / `npx cap add android`.
- Build flow (`build.sh` → `npx cap sync`) + npm scripts.
- Native essentials: status bar, splash, keyboard, app (back button/deep links).
- CSP + WebView origin config so the bundled SPA loads (no white screen).

### Out of scope (deferred)

- User-Agent string → **Epic 2** (one config flag, kept separate because it owns Aspect 1).
- Runtime API base URL / auth / CORS → **Epic 3**.
- IAP → **Epic 5**. Device permissions (camera/mic/files) → **Epic 7**. Icons/splash art → **Epic 6**.

## Prerequisites

- Epic 0 done: submodule pinned, `build.sh` produces `dist/`, app/bundle IDs decided.

## Tasks

### 1.1 — Install Capacitor 8

- [ ] Add deps in `synaplan-apps`: `@capacitor/core`, `@capacitor/cli`, `@capacitor/ios`,
      `@capacitor/android`. (Pin to Capacitor **8**; verify it satisfies Android **Target API
      35** — mandatory for new/updated apps in 2026.)
- [ ] `capacitor.config.ts`: `appId` + `appName` (from `docs/IDENTIFIERS.md`),
      `webDir: 'synaplan/frontend/dist'`.

### 1.2 — Add native projects + build flow

- [ ] `npx cap add ios` and `npx cap add android` → creates `ios/` + `android/` in this repo.
- [ ] Wire `build.sh` to finish with `npx cap sync`.
- [ ] npm scripts: `cap:sync`, `cap:ios`, `cap:android` (open/run helpers).
- [ ] Confirm `ios/Pods`, `android/.gradle`, and build outputs are gitignored.

### 1.3 — Native essentials

- [ ] Add + configure `@capacitor/status-bar`, `@capacitor/splash-screen`, `@capacitor/keyboard`,
      `@capacitor/app` (Android hardware back button + deep-link `appUrlOpen` listener stub).
- [ ] Safe-area insets already exist in the submodule's `style-v2.css` — verify they render
      correctly under the native status bar/notch.
- [ ] Status-bar theming must follow light/dark mode (ties into `--brand` / Epic 4).

### 1.4 — CSP & WebView origin

- [ ] Adjust the Content-Security-Policy in the submodule's `synaplan/frontend/index.html` so it
      permits the `capacitor://` / `https://localhost` origin (otherwise: **white screen** in the
      native build). This is a submodule change — coordinate with Epic 3 (CORS) and Epic 7
      (reCAPTCHA/CSP) so it's done once, cleanly.
- [ ] iOS: consider `iosScheme: "https"` for stricter parity with production WKWebView.
- [ ] Confirm the existing `sw.js` service worker (`synaplan/frontend/public/sw.js`) doesn't
      break under the local origin (it's cache-busting only).

### 1.5 — Minimum native value (Guideline 4.2 seed)

- [ ] Confirm at least: native splash, status-bar theming, Android back-button handling, and
      keyboard avoidance work. (Full 4.2 hardening — camera/share/offline — is Epic 7 + 9.)

## Acceptance criteria (Definition of Done)

- `./build.sh && npx cap sync` succeeds; `npx cap run ios` and `npx cap run android` launch the
  app and the **bundled SPA renders** (no white screen) on a simulator/emulator and a real device.
- App shows a native splash, themed status bar, and handles the Android back button.
- No remote `server.url` is used — the app loads the **bundled** `dist/`.
- `ios/` and `android/` exist; secrets/build artifacts are gitignored.

## Test notes (for the QA person)

- Launch on iOS simulator + a real iPhone, and Android emulator (API 24+, current System
  WebView) + a real device.
- Verify the SPA actually loads (this catches CSP/origin breakage early). Login won't work yet —
  that's Epic 3.
- Confirm splash → app transition and status-bar color in both light and dark mode.

## Risks & mitigations

- **White screen from CSP/origin (most common Capacitor failure):** fix in 1.4; test on a real
  device, not just simulator.
- **Capacitor 8 / Target API 35 drift:** verify the toolchain hits API 35 now, not at submission.
- **Submodule `index.html` edits leaking to web build:** make the CSP additive and origin-scoped
  so the web build is unaffected; review with Epic 3.

## Open questions

- `iosScheme: "https"` from the start, or default? (affects cookie/origin behavior in Epic 3).
