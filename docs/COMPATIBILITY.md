# Compatibility Matrix

> Single source of truth for **which app version works with which platform**. The forced-update
> gate (Epic 8) and the joint release gate (Epic 11) read from this table. Update it on **every**
> release.

## Matrix

| App version (UA `Synaplan Mobile Vx.x`) | Pinned `synaplan` submodule tag | Min. backend API contract | Current OTA bundle | Min. supported app version | Notes |
|-----------------------------------------|---------------------------------|---------------------------|--------------------|----------------------------|-------|
| 4.0.1 | `v4.3.0` | unchanged from 4.0.0 | — | _empty (gate off)_ | Reviewed mobile baseline v4.3.0 |
| 4.0.0 | `v4.2.4` | v4 runtime config (`client`, `branding`, `mobile`) + Sign in with Apple, content moderation, native-channel IAP anti-steering, `GET /api/v1/subscription/plans` (public) | — | _empty (gate off)_ | Reviewed mobile baseline v4.2.4 |

## Pin history

Newest first. The sync automation rewrites the matrix row above but not this prose, so a section
titled after "the current pin" goes stale on the next release — append here instead of editing.

### `v4.0.11` — TestFlight build 122

Tags `71481dff124b3c83cedf35d1fb0848ed3ce46d3c`. Two of the changes are store-compliance fixes found
while preparing the first submission:

1. [metadist/synaplan#1425](https://github.com/metadist/synaplan/pull/1425) — the subscription page
   states the renewal terms and links to the terms of use and the privacy policy. App Store Review
   Guideline 3.1.2 requires both on the surface that sells the subscription; only the paywall modal
   had them, and the page is what the review screenshots point at.
2. [metadist/synaplan#1427](https://github.com/metadist/synaplan/pull/1427) — a blank
   `APP_ADMIN_EMAIL` no longer breaks the abuse-report flow. `??` returned the empty string rather
   than falling through, the recipient was rejected while building the mail, and the reporting user
   got a 400 — the Guideline 1.2 mechanism, visibly broken.
3. [#1423](https://github.com/metadist/synaplan/pull/1423) — store webhooks answer 503 instead of
   acknowledging a notification the server could not process, so Apple and Google retry.
4. [#1419](https://github.com/metadist/synaplan/pull/1419),
   [#1420](https://github.com/metadist/synaplan/pull/1420) and
   [#1424](https://github.com/metadist/synaplan/pull/1424) — chat planner performance and a batch of
   unrelated fixes.

- Release classification: **store-required** — purchase-screen billing copy is a payment-path
  change and must never ship as an OTA bundle.

### `v4.0.10` — TestFlight build 120

The pin pointed at `3e23862b2df58a9e6a979bb48cca8941dbc53ad4`. It added two changes on top of
`v4.0.9`:

1. [metadist/synaplan#1421](https://github.com/metadist/synaplan/pull/1421) — the subscription page
   localizes the plan benefits instead of printing the English `features` list the API returns. The
   paywall modal already did; the two surfaces now share one implementation. Without this the
   German store screenshots and the running app disagree on the very screen Apple inspects for IAP.
2. [metadist/synaplan#1422](https://github.com/metadist/synaplan/pull/1422) — the Apple IAP
   verifier says which part of its configuration is missing instead of failing blindly, and refuses
   an unknown `IAP_APPLE_ENVIRONMENT` rather than silently falling back to Production.

- Release classification: **store-required** — subscription copy and IAP configuration handling
  are payment-path changes and must never ship as an OTA bundle.

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
5. Add a new row to the matrix and a new entry at the top of the pin history. Only after the store
   version is available, set the minimum version and a grace-period deadline for a genuine security
   or API incompatibility.
6. Reference this table in `docs/RELEASE_GATE_v4.md` (Epic 11).
