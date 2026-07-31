# Development — Native App Shell (Capacitor 8)

> How to build and run the Synaplan native apps locally. The app wraps the bundled Vue SPA
> (`synaplan` submodule) in a Capacitor 8 WebView — **no new UI** (see `../Planning.md`).

## Prerequisites

| Tool | Needed for | Status on this machine |
|------|-----------|------------------------|
| Node 22+ | Frontend build, Capacitor CLI | ✅ |
| Xcode 26+ | iOS build/run | ✅ (26.5) |
| **Java 21 (JDK)** | Android Gradle build | ❌ — install (e.g. `brew install --cask temurin@21`) |
| **Android SDK / Android Studio** | Android build/run, `ANDROID_HOME` | ❌ — install + set `ANDROID_HOME` |
| CocoaPods | **Not required** — Capacitor 8 iOS uses Swift Package Manager | n/a |

> The missing Android toolchain (Java + SDK) and the store accounts are tracked in Epic 0.1.
> Until Java + the Android SDK are installed, only the **iOS** target can be built/run locally.

## Build flow

The web payload and native sync are produced by `build.sh`:

```bash
./build.sh              # init submodule → build SPA → cap sync (needs platforms)
./build.sh --web-only   # only produce synaplan/frontend/dist/
```

### Why `build.sh` generates API schemas

The submodule frontend imports `@/generated/api-schemas`, which is **gitignored** (generated
from the backend OpenAPI spec). The platform normally generates it from `http://backend` inside
Docker. For a standalone app build we generate it from a reachable spec instead:

```bash
SYNAPLAN_OPENAPI_URL=http://localhost:8000/api/doc.json ./build.sh --web-only
```

There is **no default**. `build.sh` requires exactly one of `SYNAPLAN_OPENAPI_URL` or
`SYNAPLAN_OPENAPI_FILE` and exits with code 2 otherwise, because a silent production fallback
would hide a mismatch between the app schemas and the pinned commit.

`scripts/fetch-openapi.mjs` resolves the two legitimate sources:

```bash
# From a running local backend (default http://localhost:8000/api/doc.json)
SYNAPLAN_OPENAPI_FILE="$(npm run --silent openapi:fetch)" ./build.sh

# From the attested artifact of the currently pinned Synaplan commit (needs gh)
SYNAPLAN_OPENAPI_FILE="$(npm run --silent openapi:fetch -- --from-release)" ./build.sh
```

`build.sh` runs `openapi-zod-client` then the submodule's own
`scripts/generate-schemas.js --skip-fetch` post-processor, so the generated schemas are identical
to the platform's pipeline (no submodule edits required).

> If the Docker stack runs in a non-default context (for example `m4`), the backend is not on
> `localhost` — use that machine's address for both the spec URL and `SYNAPLAN_API_BASE_URL`.

## Run on device / simulator

```bash
npm run cap:sync        # copy dist/ + update native projects
npm run cap:ios         # build + run iOS (Xcode toolchain)
npm run cap:android     # build + run Android (needs Java + Android SDK)
npm run cap:open:ios    # open ios/App in Xcode
npm run cap:open:android# open android/ in Android Studio
```

## Testing an unmerged Synaplan change in the simulator

Local testing has **nothing to do with the submodule pin**. The simulator only ever shows what is
in `synaplan/frontend` — commit, branch and uncommitted edits included. The submodule worktree is a
full clone with its own `origin`, so work directly in it:

```bash
cd synaplan && git checkout -b my-feature && cd ..
```

### Full build (what actually ships)

Produces a standalone `com.synaplan.app.dev` app with a DEV badge that installs next to the
production app.

```bash
SYNAPLAN_ENV=dev \
SYNAPLAN_OPENAPI_URL=http://localhost:8000/api/doc.json \
SYNAPLAN_API_BASE_URL=http://192.168.1.20:8000 \
./build.sh
npm run cap:ios
```

`NSAllowsLocalNetworking` in `ios/App/App/Info.plist` permits the LAN address. The Android
emulator reaches the host through `10.0.2.2`, so use `SYNAPLAN_DEV_BACKEND=http://10.0.2.2:8000`
there instead.

### Live reload (what you want while iterating)

Skips the Vue build, `cap sync` and the native build for every change. Three terminals:

```bash
# 1) The SPA dev server, reachable from the simulator
cd synaplan/frontend && npm run dev -- --host

# 2) The app-owned bootstrap in front of it. Vite serves the submodule's own
#    index.html, which has no /synaplan-env.js and no /synaplan-native.js — this
#    proxy injects both, so window.__SYNAPLAN_API_BASE_URL__ and the in-app
#    server switcher work exactly like in a bundled build.
SYNAPLAN_API_BASE_URL=http://192.168.1.20:8000 npm run dev:shell

# 3) Point the WebView at the proxy and run
SYNAPLAN_ENV=dev SYNAPLAN_DEV_SERVER=http://192.168.1.20:5174 npx cap sync ios
npm run cap:ios
```

Use your own LAN address, not `localhost`: an iOS device resolves `localhost` to itself. Hot module
replacement is proxied, so a save is visible without a rebuild.

`SYNAPLAN_DEV_SERVER` is refused for `SYNAPLAN_ENV=prod`, and `scripts/release-drift.mjs` fails the
release check if a synced native config still carries a `server.url` — a release binary can never
load its UI from a developer machine.

### Before committing in this repository

`build.sh` writes the resolved identity into the iOS project, so a dev build leaves the `.dev`
bundle id behind. Reset it first:

```bash
SYNAPLAN_ENV=prod SYNAPLAN_BUILD_NUMBER=1 npm run config:app
```

### Pinning a branch that has no release tag

The automation ([`AUTOMATION.md`](./AUTOMATION.md)) only starts at a tag on `synaplan` `main`. For
everything before that, resolve the branch to the commit it currently points at and pin that:

```bash
npm run release:sync -- --ref origin/main --resolve --commit
```

The branch itself is never pinned; the recorded pin is always an immutable SHA.

## Identifiers / config

- `appId`/`appName`/`webDir` live in `capacitor.config.ts`; identifiers locked in
  `docs/IDENTIFIERS.md`.
- Native essentials configured: SplashScreen, Keyboard (`resize: native`). StatusBar theming is
  applied at runtime (light/dark) — wired further in Epic 4 (`--brand`).

## What is intentionally NOT here yet (later epics)

- **User-Agent `Synaplan Mobile Vx.x`** → Epic 2 (`appendUserAgent`, build-time version).
- **API base URL / Bearer auth / CORS / SSE / WS / OAuth** → Epic 3.
- **CSP:** the SPA currently ships **no** Content-Security-Policy (no `<meta>` tag, no header in
  the bundled shell), so the WebView loads without a white screen. A CSP is deliberately
  deferred to **Epic 3/7**, where the production API domain (`connect-src`) and reCAPTCHA
  requirements are known — adding a partial CSP now would risk breaking either the app or the
  shared web build.
- **IAP / payments** → Epic 5. **Device permissions** (camera/mic/files) → Epic 7.
  **Icons/splash art** → Epic 6. **OTA / forced update** → Epic 8.

## Verified vs. pending (Epic 1 acceptance)

- ✅ `./build.sh --web-only` produces `synaplan/frontend/dist/` on a clean submodule checkout.
- ✅ `npx cap add ios` + `npx cap add android` succeed; `npx cap sync` copies the SPA into both;
  `npx cap doctor` reports both platforms healthy; 4 plugins detected.
- ✅ Safe-area insets already present in the submodule (`style-v2.css`).
- ⏳ **Pending toolchain:** launch on iOS simulator + real device, Android emulator + device;
  confirm splash → app, status-bar theming (light/dark), Android back button, SPA renders with
  no white screen. (Requires Java + Android SDK for Android; iOS can be done now in Xcode.)
