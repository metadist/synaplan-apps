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

## Status & setup (Capgo) — ASK-FIRST follow-up

The **policy and the forced-update gate (8.2) are implemented**. The actual Capgo wiring is a
deliberate, separate step because it requires owner decisions and external resources:

- **New dependency** (`@capgo/capacitor-updater`) — adding npm/native deps is an "ask-first" action.
- **External account/service** — a Capgo account (or self-hosted update server), an API key, and a
  signing key (record in `docs/SECRETS.md`, Epic 10).
- **Channel strategy** — prod vs. beta channels and rollout percentages (open question, below).

### Setup checklist (to do together once approved)

1. Decide hosting: Capgo cloud vs. self-hosted update server.
2. Add `@capgo/capacitor-updater`, configure the plugin + channel(s).
3. Provision the signing key + API key; store as secrets (never commit).
4. Enable signature verification + a rollback/auto-revert policy on bad bundles.
5. Add a CI step that builds, signs, and uploads the bundle, then records it in
   `docs/COMPATIBILITY.md`.
6. Verify the round-trip on a test device: deliver a bundle, restart, confirm the new web version
   loads, then test rollback.

## Open questions

- OTA channel strategy (prod vs. beta) and rollout percentages?
- Minimum-version bump policy: who decides, and when does a change require a store build + a
  forced-update bump instead of an OTA?
