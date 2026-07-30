# Compatibility Matrix

> Single source of truth for **which app version works with which platform**. The forced-update
> gate (Epic 8) and the joint release gate (Epic 11) read from this table. Update it on **every**
> release.

## Matrix

| App version (UA `Synaplan Mobile Vx.x`) | Pinned `synaplan` submodule tag | Min. backend API contract | Current OTA bundle | Min. supported app version | Notes |
|-----------------------------------------|---------------------------------|---------------------------|--------------------|----------------------------|-------|
| 4.0.0 | `adea0218a8472f95f459ff17dbdc2c72b7841f2a` | v4 runtime config (`client`, `branding`, `mobile`) + Sign in with Apple, content moderation, native-channel IAP anti-steering | — | _empty (gate off)_ | Reviewed mobile baseline adea0218a8472f95f459ff17dbdc2c72b7841f2a |

## Pending pin change

The first-run onboarding is reduced to the welcome page: the "get started" CTA enters the chat as
a guest, and the plans (paywall), account and purchase steps are removed. Purchasing and the
Apple-required "Restore purchases" path stay on `/subscription`.

- Platform change: [metadist/synaplan#1405](https://github.com/metadist/synaplan/pull/1405),
  branched off `main` (`v4.0.6-18-ga3673ba8c`).
- Release classification: **store-required** — the IAP entry point and purchase behavior change,
  so this must never ship as an OTA bundle.
- The pin stays at the baseline above until that pull request is merged. Moving to the merged
  `main` state also picks up the platform work landed since `v4.0.2-29`, so the submodule diff and
  its `MOBILE-APP SEAM` markers need a full review before the pin moves, followed by a new row here.

## How to read / maintain

- **App version** is the human `MAJOR.MINOR.PATCH` carried in the WebView User-Agent (Epic 2)
  and surfaced to the backend. It is the same value the forced-update gate compares against.
- **Pinned submodule tag** is the exact `synaplan` release tag the app's bundled `dist/` was
  built from. Always a tag/SHA, never a moving branch.
- **Min. backend API contract** notes which backend runtime-config fields the app relies on, so
  a backend deploy never silently breaks a released app.
- **OTA bundle** is the latest Capgo web-asset bundle shipped on top of this store build
  through the self-hosted service (conforming changes only — see `OTA_POLICY.md`, Epic 8).
- **Min. supported app version** is the value the backend emits in runtime config; apps below it
  get the blocking "please update" screen. _Empty = gate disabled_ (the default), so no install is
  ever blocked until an operator sets a value.

## Forced-update gate — implementation reference (Epic 8.2)

The gate is fully server-driven. There is **nothing to build into the app per release** beyond the
version it already advertises in the User-Agent.

- **Config source:** BCONFIG group `MOBILE` (ownerId `0`), editable in Admin → System Config →
  *Mobile App*:
  - `MIN_APP_VERSION` — minimum supported version (e.g. `4.0` or `4.1.2`); empty disables the gate.
  - `UPDATE_ENFORCE_AFTER` — optional ISO-8601 grace-period deadline; invalid or future values
    fail open, and empty means immediate enforcement after `MIN_APP_VERSION` is set.
  - `IOS_APP_URL` / `ANDROID_APP_URL` — store links for the update button.
- **Backend:** `App\Service\Client\MobileVersionService` compares the parsed UA version
  (`ClientContext`, Epic 2) against `MIN_APP_VERSION` with PHP `version_compare`.
- **Runtime config:** `GET /api/config/runtime-config` returns a `mobile` block:
  `{ minVersion, updateRequired, updateEnforceAfter, iosAppUrl, androidAppUrl }`.
  `updateRequired` is computed server-side only after the grace-period deadline.
- **Frontend:** `ForceUpdateScreen.vue` shows a blocking overlay when `isNativeApp()` **and**
  `config.mobile.updateRequired` and a store URL are available; the CTA deep-links to that URL.

## Update procedure (per release)

1. Tag the reviewed `synaplan` platform release.
2. Confirm that the tag contains the approved mobile seams, then pin this app's submodule to that
   exact tag.
3. Bump the app version + `versionCode`/`CFBundleVersion`.
4. Build the app schemas from the same reviewed OpenAPI contract as the pin and verify parity.
5. Add a new row here. Only after the store version is available, set the minimum version and a
   grace-period deadline for a genuine security or API incompatibility.
6. Reference this table in `docs/RELEASE_GATE_v4.md` (Epic 11).
