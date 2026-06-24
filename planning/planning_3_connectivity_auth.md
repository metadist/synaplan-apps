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

# Epic 3 — Configurable Server, Cross-Origin Connectivity & Auth

> The single biggest technical risk. In the native WebView the origin is
> `capacitor://localhost` (iOS) / `https://localhost` (Android) — **every same-origin assumption
> breaks**: cookies, redirects, SSE, WebSockets, OAuth. Start with a spike; don't build on
> unverified assumptions.
>
> **New in this revision:** the server is **not** a hardcoded constant. The app **ships with a
> default server (`https://web.synaplan.com`)** but the user can **change it and save it**, and the
> app **stores the signed-in identity per configured server**. Everything below (CORS, Bearer,
> SSE/WS, OAuth, and the branding in Epic 4) is resolved against *the currently configured server*,
> not a build-time domain.

## Goal

A user can point the app at **any** Synaplan server — defaulting to `https://web.synaplan.com`,
editable and persisted in-app — and the bundled SPA can log in, stream chat (SSE), connect
realtime (WebSocket), and complete OAuth against that configured backend cross-origin — reliably
in **release/TestFlight** builds, not just debug. The signed-in identity is stored **bound to the
configured server**, so switching servers switches identity cleanly.

## v4.0 context / Why

Without this, the app is a static shell. It also defines how Aspect 1 (User-Agent on all
transports) and Aspect 3 (authenticated IAP calls bound to a user) actually reach the backend.

## Scope

### In scope

- **In-app server configuration**: a default server (`https://web.synaplan.com`) the user can
  **edit, validate, save, and reset**; everything else resolves against it.
- **Per-server identity storage**: the signed-in identity (Bearer token + user) is stored keyed by
  the configured server URL; switching server switches identity without leaking tokens across
  servers.
- Native runtime config: API base URL, app base URL, WS URL derived **from the configured server**
  and set **before** `config.init()`.
- CORS allow-listing for the app origin.
- **Bearer-token auth path** for native (reusing `BTOKENS`), with secure native storage.
- SSE + WebSocket working cross-origin in the WebView.
- OAuth/social login via **system browser** + PKCE + Universal/App Links.

### Out of scope (deferred)

- Secure-storage hardening (Keychain/Keystore) detail + resume-reconnect → Epic 7 (this epic
  proves the path; Epic 7 hardens it).
- *Applying* the configured server's branding (color/font/name/start page) → Epic 4 (this epic only
  guarantees a server switch triggers a branding re-fetch).

## Approach (decision)

Cross-origin cookies in a WebView are fragile (third-party cookie blocking) and **SSE
(`EventSource`) + WebSockets can't be routed cleanly through `CapacitorHttp`**. Therefore:
**native uses a Bearer token**, web stays on cookies. The backend accepts `Authorization: Bearer`
in addition to cookies.

## Tasks

### 3.0 — In-app server configuration (default + editable + persisted) — **app-side only**

> **Encapsulation note:** this is implemented **entirely in the `synaplan-apps` repo** (a native
> "Server" settings surface + a small bootstrap shim) so it adds **zero** blast radius to the
> public `synaplan` repo. The only submodule touch is reading the resolved value in 3.1. See
> [Epic 13](planning_13_synaplan_encapsulation.md).

- [ ] **Default server constant** in `synaplan-apps` (e.g. `app/server-config.ts`):
      `DEFAULT_SERVER_URL = 'https://web.synaplan.com'`. This is the only place the default lives.
- [ ] **Server config store + persistence**: persist the chosen server URL in encrypted native
      storage (same secure store as the token, 3.3) under a stable key. On first launch (no saved
      value) fall back to `DEFAULT_SERVER_URL`.
- [ ] **Validation before save**: normalize (force `https://`, strip trailing slash), then probe
      the candidate server's **public** runtime-config endpoint (`GET /api/v1/config/runtime`,
      no auth) to confirm it's a reachable Synaplan server **before** persisting. Reject with a
      clear error otherwise (no half-applied state).
- [ ] **Native "Server" settings UI** (in the app shell, not the SPA): show current server, an
      edit field, **Save**, and **Reset to default**. Changing the server must:
      (a) clear the *previous* server's in-memory auth, (b) persist the new URL, (c) reload the
      SPA so `main.ts` re-bootstraps against the new server, (d) trigger a branding re-fetch
      (Epic 4).
- [ ] **Per-server identity binding**: key the stored identity (Bearer token + cached user id) by
      a hash of the normalized server URL. Switching servers selects that server's identity (or
      "logged out" if none). Never send server A's token to server B.
- [ ] **Expose the resolved server URL** to the SPA bootstrap via a single injected global (e.g.
      `window.__SYNAPLAN_SERVER__`) read in 3.1 — keeps the submodule edit to one line.

### 3.1 — Native runtime config (synaplan submodule)

- [ ] In `synaplan/frontend/src/main.ts`, **before** `config.init()`: if
      `Capacitor.isNativePlatform()`, call `setApiBaseUrl(resolvedServerUrl)` where
      `resolvedServerUrl` comes from the app's server-config shim (3.0), **falling back to
      `https://web.synaplan.com`** if absent. (`setApiBaseUrl` helper already exists in
      `synaplan/frontend/src/services/api/httpClient.ts`.) **This is the single, minimal submodule
      seam for server selection** — no server logic lives in the submodule.
- [ ] Override `appBaseUrl` for native in `synaplan/frontend/src/stores/config.ts` (today it's
      `window.location.origin`, which becomes `capacitor://localhost` and breaks OAuth/redirects/
      share links). Derive it from the resolved server URL.
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
      **keyed per configured server** (3.0), **not** `localStorage` and **not** plain
      `@capacitor/preferences`. (The web "no token in localStorage" rule is about the web threat
      model; native secure storage is different — but use the encrypted store, not preferences.)

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

- **Fresh install defaults to `https://web.synaplan.com`** with no configuration; the user can open
  Server settings, change the URL to another valid Synaplan server, **save**, and the app reloads
  against it; **Reset to default** restores `https://web.synaplan.com`.
- An **invalid/unreachable** server URL is rejected at save time with a clear message and **no
  partial state** (the previous working server stays active).
- **Identity is per-server**: signing in to server A then switching to server B shows B's identity
  (or logged-out); switching back to A restores A's session without re-login (until token expiry).
  Server A's token is never sent to server B.
- Switching server triggers a branding re-fetch (verified jointly with Epic 4).
- In a **release/TestFlight** build on a real device: email/password login works, chat **SSE
  streams**, realtime **WebSocket** connects and survives a backgrounding/resume, and at least one
  **OAuth provider** completes via the system browser and returns to the app.
- The Bearer token is stored in encrypted native storage (keyed per server) and never logged.
- Web build is unaffected (still cookie-based); the submodule diff is the **one-line**
  `setApiBaseUrl(resolvedServerUrl)` seam plus the `appBaseUrl`/`wsUrl` derivations.
- On 401, the app clears the (current server's) token and routes to sign-in (mirrors web's
  refresh-then-bounce).

## Test notes (for the QA person)

- This is the **critical regression path** — test it most thoroughly.
- **Server config**: default value present on fresh install; edit → save → reload against new
  server; reset to default; reject a bogus URL (typo, `http://`, non-Synaplan host).
- **Per-server identity**: log in to two different servers, switch back and forth, confirm
  identities don't leak and tokens are not cross-sent (inspect outgoing `Authorization` per host).
- Test login + chat-SSE + WebSocket realtime in the **native WebView** (Bearer path).
- Test OAuth round-trip via system browser + deep-link return on both platforms.
- Specifically test **after backgrounding the app and reopening** over TestFlight/Play internal —
  WKWebView release strictness is the classic failure.
- Map every check above to the five quality gates in
  [Epic 12](planning_12_quality_gates.md) (lint / click / parse / format / AI logic review).

## Risks & mitigations

- **Bearer-vs-cookie uncertainty:** front-loaded spike (3.3) before committing the design.
- **SSE/WS through Capacitor:** use direct WebView fetch/EventSource/WS (not `CapacitorHttp`);
  verify in spike.
- **OAuth reject risk:** strictly system-browser + deep links, never in-WebView external login.
- **Release-only breakage:** mandatory release-build verification (3.5).

## Open questions

- Default server is `https://web.synaplan.com` — confirmed. Any allow-list/deny-list on which
  custom servers the *store* build may connect to (e.g. block plain-HTTP), or fully open?
- When switching servers, do we **wipe** the previous server's stored identity or **retain** it for
  fast switch-back? (Default proposed: retain, encrypted + per-server.)
- Which OAuth providers must work at launch vs later?
