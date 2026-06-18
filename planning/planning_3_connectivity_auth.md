---
epic: 3
title: Cross-Origin Connectivity & Auth
sprint: "Sprint 3"
aspect: null
status: planned
depends_on: [1]
repos:
  - synaplan-apps (private)
  - synaplan (public, submodule)
estimate: L
---

# Epic 3 — Cross-Origin Connectivity & Auth

> The single biggest technical risk. In the native WebView the origin is
> `capacitor://localhost` (iOS) / `https://localhost` (Android) — **every same-origin assumption
> breaks**: cookies, redirects, SSE, WebSockets, OAuth. Start with a spike; don't build on
> unverified assumptions.

## Goal

The bundled SPA can log in, stream chat (SSE), connect realtime (WebSocket), and complete OAuth
against the production backend cross-origin — reliably in **release/TestFlight** builds, not just
debug.

## v4.0 context / Why

Without this, the app is a static shell. It also defines how Aspect 1 (User-Agent on all
transports) and Aspect 3 (authenticated IAP calls bound to a user) actually reach the backend.

## Scope

### In scope

- Native runtime config: API base URL, app base URL, WS URL set **before** `config.init()`.
- CORS allow-listing for the app origin.
- **Bearer-token auth path** for native (reusing `BTOKENS`), with secure native storage.
- SSE + WebSocket working cross-origin in the WebView.
- OAuth/social login via **system browser** + PKCE + Universal/App Links.

### Out of scope (deferred)

- Secure-storage hardening (Keychain/Keystore) detail + resume-reconnect → Epic 7 (this epic
  proves the path; Epic 7 hardens it).

## Approach (decision)

Cross-origin cookies in a WebView are fragile (third-party cookie blocking) and **SSE
(`EventSource`) + WebSockets can't be routed cleanly through `CapacitorHttp`**. Therefore:
**native uses a Bearer token**, web stays on cookies. The backend accepts `Authorization: Bearer`
in addition to cookies.

## Tasks

### 3.1 — Native runtime config (synaplan submodule)

- [ ] In `synaplan/frontend/src/main.ts`, **before** `config.init()`: if
      `Capacitor.isNativePlatform()`, call `setApiBaseUrl('<prod-domain>')` (helper already exists
      in `synaplan/frontend/src/services/api/httpClient.ts`).
- [ ] Override `appBaseUrl` for native in `synaplan/frontend/src/stores/config.ts` (today it's
      `window.location.origin`, which becomes `capacitor://localhost` and breaks OAuth/redirects/
      share links).
- [ ] Source the **WebSocket URL** from backend runtime config (`realtime.wsUrl`, already exposed)
      instead of `window.location.host` in the realtime client.

### 3.2 — CORS (synaplan submodule)

- [ ] Allow the app origin(s) (`capacitor://localhost`, `https://localhost`) for the REST API and
      SSE. Coordinate with the CSP change from Epic 1 so origin handling is consistent.

### 3.3 — Bearer-token auth path (synaplan submodule) + spike FIRST

- [ ] **Spike (do this before anything else in this epic):** stand up the app pointed at a real
      backend and verify login → chat SSE stream → realtime WS all work via Bearer. This validates
      Bearer-vs-cookie definitively; it's the highest-risk unknown.
- [ ] Backend: a login path that returns a **Bearer token** to the app (reuse the existing
      `BTOKENS` table / `TokenService`). API accepts `Authorization: Bearer …` in addition to
      cookies (today `httpClient.ts` is cookie-only: `credentials: 'include'`, no Authorization
      header — see its header-building + 401-refresh logic).
- [ ] Frontend: in native mode, `httpClient` attaches the Bearer header; SSE receives the token
      via query param; WS uses existing token auth.
- [ ] Store the token in **secure native storage** (Keychain/Keystore via a secure-storage plugin),
      **not** `localStorage` and **not** plain `@capacitor/preferences`. (The web "no token in
      localStorage" rule is about the web threat model; native secure storage is different — but
      use the encrypted store, not preferences.)

### 3.4 — OAuth / social login (synaplan submodule)

- [ ] **Do not** load external OAuth pages in the main WebView (breaks app context; reject risk;
      `allowNavigation`/`server.url` are not for production).
- [ ] Use the **system browser**: `ASWebAuthenticationSession` (iOS) / Chrome Custom Tabs
      (Android) via `@capacitor/browser` or a native social-login plugin, with **Authorization
      Code + PKCE**.
- [ ] Return to the app via **Universal Links (iOS) / App Links (Android)** + `@capacitor/app`
      `appUrlOpen` (no custom URL schemes). Update `SocialLogin.vue` + backend redirect URIs.

### 3.5 — Release-build verification

- [ ] WKWebView is **stricter in release/TestFlight** than in Xcode debug (sessions can break
      after backgrounding). Verify the **whole auth flow in a release/TestFlight build**, not just
      debug. Consider `iosScheme: "https"` (set in Epic 1).

## Acceptance criteria (Definition of Done)

- In a **release/TestFlight** build on a real device: email/password login works, chat **SSE
  streams**, realtime **WebSocket** connects and survives a backgrounding/resume, and at least one
  **OAuth provider** completes via the system browser and returns to the app.
- The Bearer token is stored in encrypted native storage and never logged.
- Web build is unaffected (still cookie-based).
- On 401, the app clears the token and routes to sign-in (mirrors web's refresh-then-bounce).

## Test notes (for the QA person)

- This is the **critical regression path** — test it most thoroughly.
- Test login + chat-SSE + WebSocket realtime in the **native WebView** (Bearer path).
- Test OAuth round-trip via system browser + deep-link return on both platforms.
- Specifically test **after backgrounding the app and reopening** over TestFlight/Play internal —
  WKWebView release strictness is the classic failure.

## Risks & mitigations

- **Bearer-vs-cookie uncertainty:** front-loaded spike (3.3) before committing the design.
- **SSE/WS through Capacitor:** use direct WebView fetch/EventSource/WS (not `CapacitorHttp`);
  verify in spike.
- **OAuth reject risk:** strictly system-browser + deep links, never in-WebView external login.
- **Release-only breakage:** mandatory release-build verification (3.5).

## Open questions

- Final production API/WS domain (shared with Epic 0)?
- Which OAuth providers must work at launch vs later?
