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
SYNAPLAN_OPENAPI_URL=https://web.synaplan.com/api/doc.json ./build.sh --web-only
```

`SYNAPLAN_OPENAPI_URL` defaults to production. `build.sh` runs `openapi-zod-client` then the
submodule's own `scripts/generate-schemas.js --skip-fetch` post-processor, so the generated
schemas are identical to the platform's pipeline (no submodule edits required).

## Run on device / simulator

```bash
npm run cap:sync        # copy dist/ + update native projects
npm run cap:ios         # build + run iOS (Xcode toolchain)
npm run cap:android     # build + run Android (needs Java + Android SDK)
npm run cap:open:ios    # open ios/App in Xcode
npm run cap:open:android# open android/ in Android Studio
```

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
