# Compatibility Matrix

> Single source of truth for **which app version works with which platform**. The forced-update
> gate (Epic 8) and the joint release gate (Epic 11) read from this table. Update it on **every**
> release.

## Matrix

| App version (UA `Synaplan Mobile Vx.x`) | Pinned `synaplan` submodule tag | Min. backend API contract | Current OTA bundle | Min. supported app version | Notes |
|-----------------------------------------|---------------------------------|---------------------------|--------------------|----------------------------|-------|
| _(unreleased)_ 4.0.0 | _TBD — v4.0 baseline tag_ | v4.0 runtime config (`client`, `branding`, `mobile`) | — | _empty (gate off)_ | First mobile release |

## How to read / maintain

- **App version** is the human `MAJOR.MINOR.PATCH` carried in the WebView User-Agent (Epic 2)
  and surfaced to the backend. It is the same value the forced-update gate compares against.
- **Pinned submodule tag** is the exact `synaplan` release tag the app's bundled `dist/` was
  built from. Always a tag/SHA, never a moving branch.
- **Min. backend API contract** notes which backend runtime-config fields the app relies on, so
  a backend deploy never silently breaks a released app.
- **OTA bundle** is the latest Capgo web-asset bundle shipped on top of this store build
  (conforming changes only — see `OTA_POLICY.md`, Epic 8).
- **Min. supported app version** is the value the backend emits in runtime config; apps below it
  get the blocking "please update" screen. _Empty = gate disabled_ (the default), so no install is
  ever blocked until an operator sets a value.

## Forced-update gate — implementation reference (Epic 8.2)

The gate is fully server-driven. There is **nothing to build into the app per release** beyond the
version it already advertises in the User-Agent.

- **Config source:** BCONFIG group `MOBILE` (ownerId `0`), editable in Admin → System Config →
  *Mobile App*:
  - `MIN_APP_VERSION` — minimum supported version (e.g. `4.0` or `4.1.2`); empty disables the gate.
  - `IOS_APP_URL` / `ANDROID_APP_URL` — store links for the update button.
- **Backend:** `App\Service\Client\MobileVersionService` compares the parsed UA version
  (`ClientContext`, Epic 2) against `MIN_APP_VERSION` with PHP `version_compare`.
- **Runtime config:** `GET /api/config/runtime-config` returns a `mobile` block:
  `{ minVersion, updateRequired, iosAppUrl, androidAppUrl }`. `updateRequired` is computed
  server-side (only ever `true` for a mobile client below the minimum).
- **Frontend:** `ForceUpdateScreen.vue` shows a blocking overlay when `isNativeApp()` **and**
  `config.mobile.updateRequired`; the CTA deep-links to the platform store URL.

## Update procedure (per release)

1. Tag the `synaplan` platform release.
2. Pin this app's submodule to that exact tag.
3. Bump the app version + `versionCode`/`CFBundleVersion`.
4. Add a new row here; set the new min-supported version if there is a breaking API change.
5. Reference this table in `docs/RELEASE_GATE_v4.md` (Epic 11).
