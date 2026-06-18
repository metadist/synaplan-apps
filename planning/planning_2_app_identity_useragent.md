---
epic: 2
title: App Identity & "Synaplan Mobile Vx.x" User-Agent
sprint: "Sprint 2"
aspect: 1
status: planned
depends_on: [1]
repos:
  - synaplan-apps (private)
  - synaplan (public, submodule)
estimate: S
---

# Epic 2 — App Identity & "Synaplan Mobile Vx.x" User-Agent

> **Owns Aspect 1:** *"App client must call the platform with a `Synaplan Mobile Vx.x`
> User-Agent."* Small but load-bearing: the platform uses this identity for branding decisions
> (Epic 4), payment channel gating / anti-steering (Epic 5), and analytics. It also has to round
> -trip through **every** transport the WebView uses (XHR/fetch, `EventSource`/SSE, WebSocket).

## Goal

Every request from the native app carries a stable, version-bearing identity
(`Synaplan Mobile Vx.x`), and the backend reliably detects "this is the official mobile app" and
exposes that fact where later epics need it.

## v4.0 context / Why

Open-source hosting + store distribution means the platform can't assume its caller. A clear
client identity is the seam that lets the platform behave differently for the app (IAP-only
payments, store-safe branding) versus the web — without fragile heuristics.

## Scope

### In scope

- Set the WebView User-Agent to include `Synaplan Mobile V<version>`.
- Make it cover fetch + SSE + WebSocket handshakes.
- Backend detection + a typed "client" concept surfaced to the runtime config / session.
- Version sourced from the native app version (single source of truth).

### Out of scope (deferred)

- *Using* the identity for branding → Epic 4. For payment gating → Epic 5.

## Approach (decision)

Use Capacitor's **`appendUserAgent`** (not `overrideUserAgent`) in `capacitor.config.ts` so the
default WKWebView/Android WebView UA is preserved (compatibility, bot checks) **and** our token
is appended. The appended string applies to **all** requests originating from the WebView —
including `fetch`, `EventSource`, and the WebSocket upgrade — which JS-level `fetch` headers
cannot reliably do (browsers forbid setting `User-Agent` from JS).

> The version must be injected at build time from the app's `package.json` / native version so
> there's a single source of truth (`docs/IDENTIFIERS.md`, Epic 0). E.g. generate the config
> value during `build.sh` so it reads `Synaplan Mobile V4.0` (or `V4.0.1`).

## Tasks

### 2.1 — Append the User-Agent (synaplan-apps)

- [ ] In `capacitor.config.ts`, set platform `appendUserAgent` (iOS + Android) to
      `Synaplan Mobile V<version>`, where `<version>` is templated from the app version at
      build time (extend `build.sh` to write it, or use a config factory).
- [ ] Decide the exact format and **freeze it as a contract** (the backend regex depends on it).
      Recommended: `Synaplan Mobile V<major>.<minor>` with optional patch, e.g. `Synaplan Mobile V4.0`.
      Document it in `docs/IDENTIFIERS.md`.

### 2.2 — Backend detection (synaplan submodule)

- [ ] Add a small `ClientContext` helper (Symfony) that reads the request `User-Agent`
      (`Request::headers->get('User-Agent')`), matches `/Synaplan Mobile V(\d+)\.(\d+)(?:\.(\d+))?/`,
      and yields `{ isMobileApp: bool, appVersion: string|null, platform: 'web'|'mobile' }`.
- [ ] **Persist it where it's useful**: `synaplan/backend/src/Entity/Session.php` already has a
      `BUSERAGENT` column + `setUserAgent()` that is currently **never called** — wire it up on
      session/token creation (login + token issue in `AuthController` / `TokenService`) so we can
      see app vs web per session. Confirm with a migration check (column exists).
- [ ] Expose `client` in the runtime config response
      (`synaplan/backend/src/Controller/ConfigController.php` → `getRuntimeConfig()`), e.g.
      `client: { isMobileApp, appVersion }`, so the frontend can switch behavior server-truthfully
      rather than only via `Capacitor.isNativePlatform()`.

### 2.3 — Frontend plumbing (synaplan submodule)

- [ ] Extend the runtime-config Zod schema + `synaplan/frontend/src/stores/config.ts` to read the
      new `client` block (additive; web build sees `isMobileApp: false`).
- [ ] Keep `Capacitor.isNativePlatform()` as the **client-side** signal and `config.client` as the
      **server-confirmed** signal; document when to use which (UI gating = native flag; security
      decisions = server-side UA check, never trust the client).

### 2.4 — Min-version hook (handoff to Epic 8)

- [ ] Because the UA now carries the version, the forced-update gate (Epic 8) can compare it
      server-side. Just expose the parsed version; the gate logic lives in Epic 8.

## Acceptance criteria (Definition of Done)

- A request from the running app shows a `User-Agent` containing `Synaplan Mobile V<version>` in
  backend logs — verified for a normal API call, an SSE chat stream, **and** the WebSocket
  upgrade request.
- The web app's User-Agent is unchanged (no `Synaplan Mobile` token).
- `/api/v1/config/runtime` returns a `client` block; web build → `isMobileApp:false`,
  app build → `isMobileApp:true` with the correct `appVersion`.
- The UA format is documented in `docs/IDENTIFIERS.md` and the backend regex matches it
  (unit-tested).

## Test notes (for the QA person)

- Inspect backend access logs / a debug endpoint for the UA on: (a) `GET /api/v1/auth/me`,
  (b) the chat SSE stream, (c) the realtime WebSocket connect. All three must carry the token.
- Confirm a desktop browser session does **not** carry `Synaplan Mobile`.
- Bump the app version and confirm the version in the UA changes (build-time sourcing works).
- Backend unit test: UA parser handles `V4.0`, `V4.0.1`, and rejects spoof-ish non-matches.

## Risks & mitigations

- **SSE/WS not inheriting the WebView UA:** `appendUserAgent` is WebView-wide, so it should — but
  **verify explicitly** (acceptance criteria) since this is the whole point of the aspect.
- **UA is trivially spoofable:** never use it as an auth control. It's an identity hint;
  security still rests on the Bearer token (Epic 3) and server-side validation (Epic 5).
- **Format drift breaking the regex:** freeze the format in `docs/IDENTIFIERS.md`; unit-test the parser.

## Open questions

- Include patch version in the UA (`V4.0.1`) or only `major.minor` (`V4.0`)? (Affects how granular
  the forced-update gate can be in Epic 8.)
