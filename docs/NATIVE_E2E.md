# Native E2E / Click-through (Gate 2)

Gate 2 ("it actually works when a human/agent uses it") for the **native app shell**.
Unlike gates 1/3/4, this is **device-gated**: it needs a built app installed on a running
emulator/simulator, so it is **not** part of the fast, dependency-free `npm run ci-local`.

## Tool decision: Maestro

| Tool | Drives native shell | Drives WebView content | Install footprint | Verdict |
|------|---------------------|------------------------|-------------------|---------|
| **Maestro** | ✅ | ✅ (hybrid/WebView aware) | standalone CLI (curl) — **no npm dep** | ✅ chosen |
| Appium | ✅ | ✅ | heavy (WebDriver server + npm/driver deps) | overkill for a single-WebView shell |
| Playwright-mobile | ❌ | ✅ (remote-debug only) | npm dep | can't reach the native shell (splash, permission dialogs, back button) |

Synaplan's app is a single Capacitor WebView wrapping the Vue SPA. Maestro is the only option
that exercises **both** the native shell and the WebView, uses simple declarative YAML, and —
because it installs as a standalone binary — keeps the app-repo's lean dependency line intact
(it never lands in `package.json` / `node_modules`).

## What the flows assert

The flows live in [`.maestro/`](../.maestro) and anchor on the **app-owned, locale-independent**
environment badge from `app/synaplan-native.js` (not SPA/i18n text), so they are robust across
servers, locales, and branding:

| Flow | Proves |
|------|--------|
| `01-smoke.yaml` | Cold launch (clean state) renders the bundled SPA — **no white screen**. Waits for the app-owned env badge, which only appears once `index.html` + JS booted in the shell. Targets a non-prod build (the badge is prod-hidden). |
| `03-env-badge.yaml` | Non-prod builds show the env badge (Epic 10.1) so a tester never mistakes dev/staging for prod. **Run against a dev/staging build only.** |

> **The old always-on "Server settings" gear was removed.** The server switch now lives inside
> the SPA (Admin → App server, native-only). The previous `02-server-settings.yaml` (which drove
> the gear-opened overlay) was therefore dropped. The app-owned overlay still exists as a
> **recovery surface** (auto-opens when the configured server is unreachable), but that path is
> verified manually — pre-seeding an unreachable URL is not reliably scriptable in Maestro.

> Higher-risk paths (login + chat **SSE** + realtime **WS** + **OAuth**, sandbox **IAP** /
> restore / anti-steering) are intentionally **not** scripted here yet — they require a
> release/TestFlight build, signing, and test accounts (Epic 10.2/10.5). They stay manual /
> reviewer-path until those gates open; see `docs/QUALITY_GATES.md` (rows 3, 5).

## Manual — iOS App Shortcuts (Kurzbefehle)

Maestro cannot open Apple's Shortcuts app, so this path is a **manual Simulator /
device check** after the first launch (App Intents are indexed only then).

1. Build a **dev** iOS binary (`SYNAPLAN_ENV=dev ./build.sh`, then `xcodebuild` /
   `npx cap run ios`) and launch `com.synaplan.app.dev` once.
2. Open **Kurzbefehle / Shortcuts**. Under the Synaplan Dev (or Synaplan)
   donation, confirm three donated shortcuts:
   - **Open Synaplan** — brings the app to the foreground and does nothing else.
   - **Start dictation** — opens chat and starts the microphone (needs a server
     with speech-to-text; otherwise a toast explains it is unavailable).
   - **Analyze photo** — opens chat and the camera. On the Simulator there is no
     camera: the capture UI falls back to the photo library. The chosen image is
     **attached**, not auto-sent.
3. Siri phrase recognition is **not** available in the Simulator; phrases can
   still be inspected on the shortcut's detail page / Spotlight on a device.

Cold-start and warm-start (app already in memory) should both work. A guest
session hitting Analyze photo must show the existing attach feature-gate, not
the camera.

## Install Maestro

```bash
curl -fsSL "https://get.maestro.mobile.dev" | bash
# then add ~/.maestro/bin to PATH (the installer prints the exact line)
maestro --version
```

## Run

1. Build + install the app on a **booted** emulator/simulator (see `docs/BUILD_ENVIRONMENTS.md`):

```bash
# Android emulator (host loopback backend for the dev spike):
SYNAPLAN_ENV=dev SYNAPLAN_DEV_BACKEND=http://10.0.2.2:8000 ./build.sh
npx cap run android        # builds, installs, launches on the running emulator

# iOS simulator:
SYNAPLAN_ENV=dev ./build.sh
npx cap run ios
```

2. Run the suite (appId is parameterised, defaults to prod `com.synaplan.app`):

```bash
npm run e2e                 # prod build (com.synaplan.app)
npm run e2e:dev             # dev build (com.synaplan.app.dev)
npm run e2e:staging         # staging build
# or a single flow:
maestro test .maestro/01-smoke.yaml -e APP_ID=com.synaplan.app.dev
```

Screenshots land in `.maestro/artifacts/` (gitignored).

## Verified runs

> The suite was reduced from 3 → 2 flows when the always-on gear was removed (server switch
> moved into the SPA's Admin → App server panel). The runs below were on the previous 3-flow
> suite; the gate must be **re-verified on a dev/staging build** after this change (env-badge
> anchor is unchanged, so `01-smoke` + `03-env-badge` are expected to pass on Android as before).

| Platform | Build/install | Maestro flows | Notes |
|----------|---------------|---------------|-------|
| **Android** (emulator API 35) | ✅ `cap run android` (`com.synaplan.app.dev`) | ✅ previously 3/3 (`01-smoke`, `02-server-settings`, `03-env-badge`); now 2 flows (`01-smoke`, `03-env-badge`) — re-verify | The automated gate-2 runner. |
| **iOS** (Simulator, iOS 26) | ✅ `cap run ios` (`com.synaplan.app.dev`, display name "Synaplan Dev") | 🧪 app shell verified by direct launch + screenshot (DEV badge renders correctly); **Maestro assertions blocked** — see limitation below. | Anti-steering / env-badge confirmed visually. |

## Known limitation — Maestro on iOS + heavy WebViews

On the iOS Simulator the Maestro XCUITest driver **hangs while dumping the view
hierarchy** of our content-rich WKWebView (the SPA exposes a very large accessibility
tree). The app itself launches and renders correctly — the env badge is
on screen — but `assertVisible` / `extendedWaitUntil` never returns because the
hierarchy snapshot call stalls. This is a documented Maestro-on-iOS behavior with large
WebViews, **not an app defect**.

Consequences / how we handle it:
- **Android is the automated gate-2 runner** for the app shell today (`npm run e2e:dev`).
- **iOS app-shell health is verified manually** (build → `cap run ios` → launch → confirm
  no white screen + DEV badge) until the driver limitation is resolved (newer
  Maestro, or trimming the WebView a11y tree). Track this before relying on iOS Maestro in
  CI.
- The deeper, highest-risk paths (login, SSE/WS, OAuth, sandbox IAP) are device/account-
  gated on **both** platforms anyway and run on the beta tracks (Epic 10.2/10.5).

## How this is kept honest in `ci-local`

`npm run ci-local` does **not** run Maestro, but `tests/maestro-flows.test.mjs` validates the
committed flows (correct `${APP_ID}` parameterisation, a real `launchApp` + assertion body, and
the app-owned env-badge anchor the flows depend on). If someone changes the env-badge label in
`app/synaplan-native.js` without updating the flows, the gate goes red locally — long before the
device run would.
