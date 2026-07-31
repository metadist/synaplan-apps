# OTA (Over-the-Air) Update Policy

> Locked in **Epic 8.1**. OTA lets us push **web-asset fixes** to installed apps without a store
> review. This power is tightly bounded by store rules — misuse risks an **app ban**. Read this
> before shipping any OTA bundle.

## TL;DR

- ✅ OTA is for **conforming changes only**: UI fixes, copy, styling, non-behavioral bug fixes to
  the bundled web assets (`dist/`).
- ❌ OTA must **never** change app behavior, feature gating, or **payment/IAP logic**
  (Apple Guideline 2.5.2, Program License Agreement 3.3.2, and Google Play policy). Those ship
  **only** through a store review.
- The forced-update gate (Epic 8.2, already implemented) is the complementary lever: when an app
  is too old for the backend contract, the server blocks it with a "please update" screen instead
  of trying to OTA-fix it.

## What MAY be shipped via OTA

- Visual/CSS fixes, layout corrections, accessibility tweaks.
- Copy/i18n corrections.
- Bug fixes in the **web** layer that do not change documented behavior, entitlements, or pricing.
- Hotfixes for crashes/regressions in the SPA that are within the already-reviewed feature set.

## What MUST NOT be shipped via OTA (store-review only)

- **Any payment / subscription / IAP logic** (purchase, restore, entitlement, channel gating).
- New features or feature flags that materially change what the reviewed app does.
- Changes to native capabilities, permissions, or the Capacitor native layer.
- Anything that alters the app's purpose or circumvents store review (Apple 2.5.2/4.2, Google
  "Device and Network Abuse" / deceptive behavior).

## Why (store rules)

- **Apple App Store Review Guideline 2.5.2** — apps must be self-contained and may not download,
  install, or execute code that introduces or changes app features or functionality.
- **Apple Developer Program License Agreement 3.3.2** — downloaded interpreted code must stay
  within Apple's permitted execution model and must not change the app's primary purpose or bypass
  review.
- **Apple App Store Review Guideline 4.2** — the submitted app must provide sufficient lasting
  utility; OTA cannot be used to turn a minimal shell into a materially different product.
- **Google Play** — updates that significantly deviate from the reviewed app, or that introduce
  payment flows for digital goods outside Play Billing, violate policy.

Bottom line: OTA fixes the *presentation* of already-approved behavior. It never introduces or
changes *behavior*, and **never** touches money.

## Unattended publishing

OTA bundles are published automatically once an `ota-candidate` synchronization merges — see
[`AUTOMATION.md`](./AUTOMATION.md) for the full chain. Nothing in this policy is relaxed by that:

- The classification that decides `ota-candidate` versus `store-required` is produced by
  `.github/mobile-impact-policy.json` in the source repository and is **fail-closed**: any path
  that is not explicitly allow-listed, and any file that can carry executable code, is
  `store-required`. That file is the single gate protecting every rule above, so a change to it is
  a change to this policy.
- `ota.yml` refuses any class other than `ota-candidate`, whoever starts it.
- `ota-health.yml` observes every published bundle and withdraws it without a human when the
  failure rate exceeds the configured threshold.

The manual `pause`, `resume` and `rollback` operations remain available at all times and are the
kill switch for the automation.

## Safety mechanisms (required for any OTA rollout)

- **Signature verification** on every bundle (reject unsigned / tampered bundles).
- **Bundle versioning** tied to the app + backend version (see `docs/COMPATIBILITY.md`).
- **Staged rollout** (small % → wider) and a **rollback** path to the last-good bundle.
- **No silent behavior drift:** an OTA bundle is built from a pinned `synaplan` submodule commit
  and recorded in the compatibility matrix.

## Versioning & the compatibility matrix

Every OTA bundle is recorded in `docs/COMPATIBILITY.md` against the store app version it sits on
top of and the pinned `synaplan` submodule tag it was built from. The bundle version never
implies a new *behavior* contract — if behavior must change, ship a store build and (if needed)
raise the forced-update minimum version.

## Status & setup (Capgo)

Decisions taken: **auto-update** behavior, native-version-bound **canary** and **production**
channels, **signature/E2E encryption enabled**, and hosting on the approved **self-hosted Capgo**
deployment. The native configuration receives `updateUrl`, `channelUrl`, `statsUrl`, the public
signing key, and the default channel through protected release-environment variables.

### Done (code-first — inert until an account/bundle exists)

- ✅ `@capgo/capacitor-updater` added to `package.json` (native plugin) **and** the shared frontend
  `synaplan/frontend/package.json` (so the SPA can call `notifyAppReady()`).
- ✅ `CapacitorUpdater` configured in `capacitor.config.ts`: `autoUpdate: 'always'` with
  `autoSplashscreen`, `periodCheckDelay`, `resetWhenUpdate`, `appReadyTimeout`, auto-delete
  failed/previous. A published bundle is applied on the next foreground, not the next cold start.
- ✅ The SPA confirms each launch via `notifyAppReady()` (`src/services/otaUpdates.ts`, native-only)
  so Capgo auto-reverts a bad bundle.
- ✅ `ota.yml` builds from a commit-matching OpenAPI artifact, signs the unique bundle, targets the
  configured self-hosted Supabase host, and supports publish, pause, resume, and rollback.
- ✅ npm scripts prepare deterministic manifests/checksums without publishing as a side effect.
- ✅ Secrets documented (`docs/SECRETS.md`); `.capgo_key_v2` gitignored.

Until the app is registered and a bundle is published, the update check finds nothing and the
builtin `dist/` bundle is always used — i.e. the wiring is a safe no-op.

### Environment setup and first release drill

1. Configure `CAPGO_SUPA_HOST`, the three updater endpoint URLs, the public signing key, and the
   channel name as protected environment variables for `canary` and `production`.
2. Configure `CAPGO_SUPA_ANON`, `CAPGO_API_KEY`, and `CAPGO_BUNDLE_PRIVATE_KEY` as environment
   secrets. Keep the signing-key backup outside GitHub as well.
3. Run `ota.yml` in dry-run mode, then publish to `canary` after approval.
4. Verify cold-start activation and telemetry on physical devices. Publish a deliberately broken
   canary bundle to prove automatic rollback, then exercise the explicit rollback operation.
5. Promote the same reviewed source to `production` only through the protected environment.
