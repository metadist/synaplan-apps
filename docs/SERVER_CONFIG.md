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
| Settings UI | `app/synaplan-native.js` overlay | App-owned vanilla-DOM overlay (NOT the SPA): current server, edit, Save, Reset. Reachable via a discreet gear button and **auto-opens when the configured server is unreachable** |
| First-run onboarding | `synaplan/frontend/src/components/onboarding/OnboardingServerStep.vue` | Step 2 of the native first-run flow (`/onboarding`): default server preselected, "Use my own server" expert affordance. Probes + persists via the same `window.SynaplanServer.save()` seam; the resulting WebView reload resumes the flow at step 3 (sessionStorage resume step) |
| Per-server identity | `synaplan/frontend/src/services/api/nativeAuth.ts` | Bearer-token secure-storage keys are suffixed with a hash of the resolved server URL, so A's token is never sent to B and switching back restores A's session |

## Switch flow

1. User edits the URL in the overlay and taps **Save**.
2. The candidate is normalized (`https://` default, trailing slash stripped) and **probed**; an
   unreachable/non-Synaplan server is rejected with a message and the previous server stays active.
3. On success the URL is persisted and the app **reloads**. The reload re-bootstraps the SPA
   against the new server: new API base URL, branding re-fetch (Epic 4), and a fresh per-server
   token scope (logged-out if that server has no stored token; the previous server's token stays
   under its own scope for when the user switches back).
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
      session restored (per-server identity).
- [ ] Release/TestFlight build (WKWebView is stricter than Xcode debug, §3.5).
