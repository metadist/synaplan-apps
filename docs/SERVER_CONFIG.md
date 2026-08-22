# In-App Server Configuration (Epic 3 §3.0)

The app ships with a default server but lets the user point it at **any** Synaplan server,
persists the choice, and binds the signed-in identity **per server**. This lives **entirely in
`synaplan-apps`** — the only submodule touch is the single seam where `main.ts` reads the resolved
URL (see [Blast Radius](SYNAPLAN_BLAST_RADIUS.md)).

## Pieces

| Concern | Where | How |
|---------|-------|-----|
| Default server | `app/synaplan-native.js` (`DEFAULT_SERVER_URL`) | `https://web.synaplan.com` — the only place the default lives |
| Pre-SPA bootstrap | `app/synaplan-native.js` | Classic `<script>` injected as the **first** element of `dist/index.html` by `build.sh`; sets `window.__SYNAPLAN_API_BASE_URL__` **synchronously** before the SPA's deferred module runs |
| Submodule seam | `synaplan/frontend/src/main.ts` → `nativeRuntime.getNativeApiBaseUrl()` | Reads `window.__SYNAPLAN_API_BASE_URL__`, falls back to `https://web.synaplan.com` |
| Persistence | `localStorage['synaplan.serverUrl']` | The URL is **not a secret** and must be read synchronously at bootstrap; `localStorage` is persistent in the `capacitor://localhost` / `https://localhost` WebView origin |
| Validation | `probeServer()` | `GET {url}/api/v1/config/runtime` (public, no auth) must return 200 + a JSON object before saving — no half-applied state |
| Settings UI (logged in) | `synaplan/frontend/src/components/NativeServerControl.vue` | Shared SPA component embedded in **Settings** (every authenticated user) and **Admin → App server**. Calls `window.SynaplanServer.save()/reset()` (persist only), then signs the user out of every server and calls `window.SynaplanServer.reload()` itself |
| Settings UI (logged out / recovery) | `app/synaplan-native.js` overlay | App-owned vanilla-DOM overlay (NOT the SPA): current server, edit, Save, Reset. Reachable via `window.SynaplanServer.open()` (guest menu, login/register screens) and **auto-opens when the configured server is unreachable**. Persists + reloads immediately on its own — there is no SPA session to clean up in this flow |
| First-run onboarding | `synaplan/frontend/src/components/onboarding/OnboardingServerModal.vue` | Own-server modal opened from a quiet "Own server" pill on the native first-run welcome page (`/onboarding`): URL entry replacing the default server. Probes + persists via `window.SynaplanServer.save()`, then reloads explicitly via `window.SynaplanServer.reload()`; the resulting WebView reload lands back on the welcome page (completion is not persisted yet) |
| Per-server identity | `synaplan/frontend/src/services/api/nativeAuth.ts` | Bearer-token secure-storage keys are suffixed with a hash of the resolved server URL, so A's token is never sent to B. This scoping still applies while a session is active, but a deliberate server change (via `NativeServerControl.vue`) now always clears **every** stored token (`clearAllNativeTokens()`) — switching back to a previously-used server no longer auto-restores its session; the user always has to log in again |

## Switch flow

### Logged in (SPA: Settings / Admin → App server)

1. User edits the URL in `NativeServerControl.vue` and taps **Test & save** (or **Reset to
   default**).
2. The candidate is normalized and **probed** via `window.SynaplanServer.save()`; an
   unreachable/non-Synaplan server is rejected with a message and the previous server stays
   active — nothing else happens.
3. On success the URL is persisted (`window.SynaplanServer.save()`/`reset()` — persist only, no
   reload). The SPA then **always** signs the user out (`authStore.logout()`) and clears **every**
   stored native token (`clearAllNativeTokens()`), regardless of whether the target server was used
   before.
4. Only then does the SPA call `window.SynaplanServer.reload()` itself. The reload re-bootstraps
   against the new server: new API base URL, branding re-fetch (Epic 4), and no restorable
   session — the user always lands on the login screen.

### Logged out / recovery (native overlay)

1. User edits the URL in the app-owned overlay (`window.SynaplanServer.open()`, or the
   non-dismissable recovery variant) and taps **Save**.
2. Same normalize + probe as above.
3. On success the overlay persists the URL and **reloads immediately itself** — there is no SPA
   session to clean up in this flow.
4. **Reset to default** clears the stored URL and reloads against `https://web.synaplan.com`.

## Security notes

- The server URL lives in `localStorage` (not secret, needs sync read). The sensitive Bearer
  tokens stay in **secure storage** (Keychain / Keystore, Epic 7), keyed per server.
- An external server's branding may reference a `BRAND_FONT_URL`; that origin must be reachable and
  CSP-allowed (Epic 1 / Epic 4).

## Remaining (on-device) verification

- [ ] Spike on a real device/emulator: fresh install → default server → login → chat SSE +
      realtime WS via Bearer (Epic 3 §3.3).
- [ ] Switch to a second Synaplan server, confirm identity + branding swap, switch back, confirm
      the user is signed out and must log in again on **both** servers (no session restoration).
- [ ] Release/TestFlight build (WKWebView is stricter than Xcode debug, §3.5).
