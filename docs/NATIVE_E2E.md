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

The flows live in [`.maestro/`](../.maestro) and anchor on **app-owned, locale-independent**
strings from `app/synaplan-native.js` (not SPA/i18n text), so they are robust across servers,
locales, and branding:

| Flow | Proves |
|------|--------|
| `01-smoke.yaml` | Cold launch renders the bundled SPA — **no white screen**. Waits for the app-owned "Server settings" gear, which only appears once `index.html` + JS booted in the shell. |
| `02-server-settings.yaml` | The native Server overlay (Epic 3 §3.0) opens from the gear, shows Save / Cancel / Reset, and dismisses cleanly. |
| `03-env-badge.yaml` | Non-prod builds show the env badge (Epic 10.1) so a tester never mistakes dev/staging for prod. **Run against a dev/staging build only.** |

> Higher-risk paths (login + chat **SSE** + realtime **WS** + **OAuth**, sandbox **IAP** /
> restore / anti-steering) are intentionally **not** scripted here yet — they require a
> release/TestFlight build, signing, and test accounts (Epic 10.2/10.5). They stay manual /
> reviewer-path until those gates open; see `docs/QUALITY_GATES.md` (rows 3, 5).

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

## How this is kept honest in `ci-local`

`npm run ci-local` does **not** run Maestro, but `tests/maestro-flows.test.mjs` validates the
committed flows (correct `${APP_ID}` parameterisation, a real `launchApp` + assertion body, and
the exact app-owned anchors the flows depend on). If someone renames the "Server settings" gear
or a Server-overlay button in `app/synaplan-native.js` without updating the flows, the gate goes
red locally — long before the device run would.
