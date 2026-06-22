# OTA (Over-the-Air) Update Policy

> Locked in **Epic 8.1**. OTA lets us push **web-asset fixes** to installed apps without a store
> review. This power is tightly bounded by store rules — misuse risks an **app ban**. Read this
> before shipping any OTA bundle.

## TL;DR

- ✅ OTA is for **conforming changes only**: UI fixes, copy, styling, non-behavioral bug fixes to
  the bundled web assets (`dist/`).
- ❌ OTA must **never** change app behavior, feature gating, or **payment/IAP logic**
  (Apple Guideline 3.2.2 / Google Play policy). Those ship **only** through a store review.
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
- Anything that alters the app's purpose or circumvents store review (Apple 3.2.2, Google
  "Device and Network Abuse" / deceptive behavior).

## Why (store rules)

- **Apple App Store Guideline 3.2.2 (vii)** — apps may download code that does not "change the
  app's primary purpose, provide features different from those reviewed, or download executable
  code"; interpreted-code updates must remain consistent with the reviewed app.
- **Google Play** — updates that significantly deviate from the reviewed app, or that introduce
  payment flows for digital goods outside Play Billing, violate policy.

Bottom line: OTA fixes the *presentation* of already-approved behavior. It never introduces or
changes *behavior*, and **never** touches money.

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

Decisions taken: **auto-update** behavior, **production-only** channel for now, **signature/E2E
encryption enabled**, hosting **= Capgo Cloud for the v4.0 launch** with **self-hosted Capgo kept as
a documented migration path** (switching is just an `updateUrl`/`channelUrl` override in
`capacitor.config.ts` — no app code change).

### Done (code-first — inert until an account/bundle exists)

- ✅ `@capgo/capacitor-updater` added to `package.json` (native plugin) **and** the shared frontend
  `synaplan/frontend/package.json` (so the SPA can call `notifyAppReady()`).
- ✅ `CapacitorUpdater` configured in `capacitor.config.ts`: `autoUpdate`, `resetWhenUpdate`,
  `directUpdate: false`, `appReadyTimeout`, auto-delete failed/previous.
- ✅ The SPA confirms each launch via `notifyAppReady()` (`src/services/otaUpdates.ts`, native-only)
  so Capgo auto-reverts a bad bundle.
- ✅ npm scripts: `ota:key:create` (signing key) and `ota:upload` (publish a bundle).
- ✅ Secrets documented (`docs/SECRETS.md`); `.capgo_key_v2` gitignored.

Until the app is registered and a bundle is published, the update check finds nothing and the
builtin `dist/` bundle is always used — i.e. the wiring is a safe no-op.

### Remaining (needs the Capgo Cloud account — ASK-FIRST follow-up)

1. **Create/connect the Capgo Cloud account** and register the app:
   `npx @capgo/cli@latest login <CAPGO_TOKEN>` then `npx @capgo/cli@latest app add com.synaplan.app`.
2. **Generate the signing key** (writes `publicKey` into `capacitor.config.ts`, keeps the private
   key as `.capgo_key_v2`): `npm run ota:key:create`. Back up the private key (see `SECRETS.md`).
3. **Store `CAPGO_TOKEN`** in the CI secret store / local `.env` (never commit).
4. **Publish a bundle** (conforming changes only): `./build.sh --web-only` then
   `npm run ota:upload` (uploads `synaplan/frontend/dist` to the `production` channel at the current
   app version), and record it in `docs/COMPATIBILITY.md`.
5. **Verify the round-trip** on a device: publish a bundle → reopen the app → new web version loads
   on next cold start; then test rollback by publishing a deliberately-broken bundle (must
   auto-revert via `appReadyTimeout`).

## Open questions

- Rollout percentages / staged rollout policy on the production channel?
- Minimum-version bump policy: who decides, and when does a change require a store build + a
  forced-update bump instead of an OTA?
- When (if ever) to introduce a `beta` channel for internal testers.
