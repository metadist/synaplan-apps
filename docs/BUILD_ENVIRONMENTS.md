# Build Environments & Versioning (Epic 10.1)

One switch (`SYNAPLAN_ENV`) selects dev / staging / prod identity; versions come from a
single source. Identifiers are frozen in [`IDENTIFIERS.md`](./IDENTIFIERS.md).

## Inputs

| Variable               | Values / default                | Effect |
|------------------------|----------------------------------|--------|
| `SYNAPLAN_ENV`         | `dev` \| `staging` \| `prod` (default `prod`) | Bundle id suffix + visible app-name suffix + in-app badge |
| `SYNAPLAN_BUILD_NUMBER`| monotonic integer (default: git commit count, else `1`) | `versionCode` (Android) / `CFBundleVersion` (iOS) |

The **human version** is owned by [`package.json`](../package.json) `version` (currently
`4.0.0`). It drives `versionName` / `MARKETING_VERSION` **and** the User-Agent token
(`capacitor.config.ts`), so bumping it in one place updates everything.

## Per-environment identity

| Env     | Bundle ID / applicationId   | App name (home screen)  | In-app badge |
|---------|------------------------------|--------------------------|--------------|
| prod    | `com.synaplan.app`           | `Synaplan`               | none |
| staging | `com.synaplan.app.staging`   | `Synaplan Staging`       | `STAGING · <ver>` |
| dev     | `com.synaplan.app.dev`       | `Synaplan Dev`           | `DEV · <ver>` |

Distinct IDs let dev/staging/prod install side-by-side on one device. The Android
`namespace` (code package / `R` class) stays `com.synaplan.app` regardless of env.

## How it's wired

- **Android** — `android/app/build.gradle` reads `package.json` + the two env vars at
  build time (Gradle-native, no file mutation). The launcher label uses the
  `${appLabel}` manifest placeholder.
- **iOS** — `scripts/app-config.mjs` stamps `MARKETING_VERSION`,
  `CURRENT_PROJECT_VERSION`, `PRODUCT_BUNDLE_IDENTIFIER` (pbxproj) and
  `CFBundleDisplayName` (Info.plist). Idempotent; re-running with the same inputs is a
  no-op. `build.sh` runs it automatically before `cap sync`.
- **In-app badge** — `build.sh` stamps `window.__SYNAPLAN_ENV__` / version / build into
  the bundle (`synaplan-env.js`); the app-owned `app/synaplan-native.js` renders a small
  banner for non-prod builds (zero blast radius in the public submodule).
- **`capacitor.config.ts`** mirrors the same env→id/name mapping so `cap` tooling stays
  in lock-step with the native projects.

## Usage

```bash
# Production (defaults)
./build.sh

# Dev build pointed at the Android-emulator host backend
SYNAPLAN_ENV=dev SYNAPLAN_DEV_BACKEND=http://10.0.2.2:8000 ./build.sh

# Android APK for an env (Gradle reads SYNAPLAN_ENV / SYNAPLAN_BUILD_NUMBER)
SYNAPLAN_ENV=staging SYNAPLAN_BUILD_NUMBER=123 \
  (cd android && ./gradlew :app:assembleDebug)

# iOS: stamp identity, then build/run
SYNAPLAN_ENV=dev node scripts/app-config.mjs && npx cap run ios

# Inspect resolved config without writing anything
npm run config:app:print            # prod
SYNAPLAN_ENV=staging npm run config:app:print
```

> The committed iOS project holds the **prod baseline** (`com.synaplan.app`, `4.0.0`,
> build `1`). After a non-prod local build, reset it with
> `SYNAPLAN_ENV=prod SYNAPLAN_BUILD_NUMBER=1 npm run config:app` before committing.

## Notes & follow-ups

- The OAuth deep-link scheme stays `com.synaplan.app://` for all envs (Info.plist /
  AndroidManifest). Per-env schemes are a later refinement; dev/staging are internal.
- `SYNAPLAN_BUILD_NUMBER` should be the CI build number for store uploads (monotonic,
  never reused). The git-commit-count fallback is for local builds only.
- Signing (Epic 10.2) and CI automation (Epic 10.5) plug into the same env switch.
