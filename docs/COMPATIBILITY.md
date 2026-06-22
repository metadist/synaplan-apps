# Compatibility Matrix

> Single source of truth for **which app version works with which platform**. The forced-update
> gate (Epic 8) and the joint release gate (Epic 11) read from this table. Update it on **every**
> release.

## Matrix

| App version (UA `Synaplan Mobile Vx.x`) | Pinned `synaplan` submodule tag | Min. backend API contract | Current OTA bundle | Min. supported app version | Notes |
|-----------------------------------------|---------------------------------|---------------------------|--------------------|----------------------------|-------|
| _(unreleased)_ 4.0.0 | _TBD — v4.0 baseline tag_ | v4.0 runtime config (`client`, `branding`, `minAppVersion`) | — | 4.0.0 | First mobile release |

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
  get the blocking "please update" screen.

## Update procedure (per release)

1. Tag the `synaplan` platform release.
2. Pin this app's submodule to that exact tag.
3. Bump the app version + `versionCode`/`CFBundleVersion`.
4. Add a new row here; set the new min-supported version if there is a breaking API change.
5. Reference this table in `docs/RELEASE_GATE_v4.md` (Epic 11).
