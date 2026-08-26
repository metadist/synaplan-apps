# OTA (Over-the-Air) Update Policy

> OTA lets us push **web-layer changes** to installed apps without a store review, so a store
> submission is only needed when a change genuinely requires a new binary. This power is bounded by
> store rules — misuse risks an **app ban**. Read this before shipping any OTA bundle.

## TL;DR

- ✅ OTA is for the **web layer of the bundled SPA**: application code (Vue/TypeScript), styling,
  translations, assets, generated API schemas, and web dependencies — including new frontend
  features, as long as they stay within the app's approved purpose. Apple ADPLA 3.3.2 and Google
  Play explicitly permit updating interpreted code that runs in the system WebView.
- ❌ OTA must **never** touch **payment/IAP/entitlement logic**, **authentication transport**,
  native code or capabilities, forced-update logic, or the update mechanism itself. Those ship
  **only** through a store review.
- The forced-update gate (Epic 8.2, already implemented) is the complementary lever: when an app
  is too old for the backend contract, the server blocks it with a "please update" screen instead
  of trying to OTA-fix it.

## What MAY be shipped via OTA

- Frontend features, refactors, and bug fixes in the bundled SPA (`frontend/src/**` of the pinned
  submodule), within the app's approved purpose.
- Visual/CSS fixes, layout corrections, accessibility tweaks, copy/i18n changes, assets.
- Generated API client schemas and web-only dependency updates (the OpenAPI parity check in the
  build remains the gate).
- Hotfixes for crashes/regressions in the SPA.

## What MUST NOT be shipped via OTA (store-review only)

- **Any payment / subscription / IAP logic** (purchase, restore, entitlement, paywall, channel
  gating) — Apple anti-steering and Play Billing rules.
- **Authentication transport** and native seams (OAuth redirects, token handling, biometric lock,
  `native*` services).
- Changes to native capabilities, permissions, or the Capacitor native layer.
- Forced-update/version-gate logic, the service worker, or the OTA update mechanism itself.
- Anything that alters the app's primary purpose or circumvents store review (Apple 2.5.2/4.2,
  Google "Device and Network Abuse" / deceptive behavior).

## Why (store rules)

- **Apple Developer Program License Agreement 3.3.2** — interpreted code may be downloaded as long
  as it does not change the app's primary purpose, does not create a store for other code, and
  does not bypass signing, sandbox, or other OS security features. Web code running in `WKWebView`
  satisfies all three, which is exactly what the bundled SPA is.
- **Apple App Store Review Guideline 2.5.2** — apps may not download or execute code that
  introduces or changes features outside Apple's permitted execution model; WebKit-interpreted
  code is the permitted model.
- **Apple App Store Review Guideline 4.2** — the submitted app must provide sufficient lasting
  utility; OTA cannot be used to turn a minimal shell into a materially different product.
- **Google Play** — the Device and Network Abuse policy exempts code interpreted in a WebView or
  runtime; updates must not significantly deviate from the reviewed app or introduce payment flows
  for digital goods outside Play Billing.

Bottom line: OTA ships the web layer of the already-approved product. It never changes the app's
purpose, and **never** touches money, authentication transport, or native behavior.

## Unattended publishing

OTA bundles are published automatically once an `ota-candidate` synchronization merges — see
[`AUTOMATION.md`](./AUTOMATION.md) for the full chain. Nothing in this policy is relaxed by that:

- The classification that decides `ota-candidate` versus `store-required` is produced by
  `.github/mobile-impact-policy.json` in the source repository and is **fail-closed**: any path
  that is not explicitly allow-listed is `store-required`, and the payment, authentication
  transport, native-seam, and update-mechanism paths are explicitly pinned to `store-required`.
  That file is the single gate protecting every rule above, so a change to it is a change to this
  policy. New paths are classified in the same PR that introduces them.
- `ota.yml` refuses any class other than `ota-candidate`, whoever starts it.
- `ota-health.yml` observes every published bundle and turns the run red when no device picks it up.

The immediate protection against a broken bundle is on the device and needs no workflow: a bundle
that does not call `notifyAppReady()` within `appReadyTimeout` is reverted locally and the device
reports the previous version again.

Automatic **withdrawal** from the channel is opt-in (`withdraw_on_unhealthy`) because of what the
statistics API can measure. It reports device counts per bundle from a daily rollup and exposes no
failure counter at all, so shortly after publishing "no device runs the new bundle yet" and "the
rollout is still reaching devices" look identical. Enabling withdrawal on a channel that is too
quiet would remove healthy releases.

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
- ✅ `CapacitorUpdater` configured in `capacitor.config.ts`: `autoUpdate: 'atBackground'` with
  `keepUrlPathAfterReload`, `periodCheckDelay`, `resetWhenUpdate`, `appReadyTimeout`, auto-delete
  failed/previous. A published bundle is downloaded in the background while the app keeps running on
  the current bundle, activated when the app moves to the background, and live the next time the
  user opens the app — a launch never waits for the update check and a session is never reloaded out
  from under the user. Urgent changes go through the forced-update gate, not through OTA.
- ✅ The launch screen is owned solely by `app/synaplan-native.js` (`launchAutoHide: false`, no
  `autoSplashscreen`): hidden on the SPA's first paint, with a hard ceiling as a safety net. The
  updater's `autoSplashscreen` is deliberately unused because it hides only after the update check
  returns and never arms its own timeout on a cold start, which froze launches for the full network
  timeout when the update server was slow or unreachable.
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

### Self-hosted instance runbook (operator)

Every item below was found the hard way during the first real publish (July 2026). A freshly
deployed self-hosted Capgo does **not** work out of the box for CLI publishing; apply these once
per deployment and re-check them after a Capgo/Supabase upgrade.

1. **Grant RPC execute rights.** The deployment shipped without `EXECUTE` for the `anon` role on
   several `public.*` functions the CLI calls (`get_user_id`, `get_orgs_v7`, `get_org_members`,
   `has_2fa_enabled`, ...). Symptom: the CLI reports *"Invalid API key or insufficient
   permissions"* even with a valid admin key; PostgREST returns error `42501`. Fix on the database
   host (idempotent — it only grants what is missing):

   ```bash
   docker exec supabase-db psql -U postgres -d postgres -Atc "
   SELECT format('GRANT EXECUTE ON FUNCTION public.%I(%s) TO anon, authenticated;',
                 p.proname, pg_get_function_identity_arguments(p.oid))
   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND NOT has_function_privilege('anon', p.oid, 'execute');" \
   | docker exec -i supabase-db psql -U postgres -d postgres
   ```

2. **Mark the organization as paid.** The seeded organization starts on a 14-day trial; after it
   expires every upload fails with *"Plan upgrade required"*. A self-hosted instance has no Stripe,
   so set the plan directly (adjust the `customer_id`):

   ```sql
   UPDATE public.stripe_info
   SET status = 'succeeded', paid_at = now(),
       trial_at = now() + interval '99 years',
       product_id = (SELECT stripe_id FROM public.plans WHERE name = 'Enterprise'),
       subscription_anchor_start = now(),
       subscription_anchor_end = now() + interval '99 years',
       is_good_plan = true
   WHERE customer_id = '<customer_id from public.orgs>';
   ```

3. **Let devices reach the channel.** The app requests the `production` channel itself
   (`defaultChannel` in `capacitor.config.ts`), which the server only honors when the channel has
   **"Allow devices to self dissociate/associate"** enabled (or the channel is the app-wide
   default). Symptom: update checks answer `no_channel` and devices stay on the builtin bundle.
   Keep **"Disable auto downgrade under native"** enabled — bundle versions are deliberately
   next-patch prereleases (`4.0.1-synaplan...` on a native `4.0.0`, see
   `scripts/release-lib.mjs`), so the guard passes them while still blocking stale bundles after
   a store update.

4. **Make device downloads verifiable.** The updater answers update checks with a presigned S3
   URL. Three defaults break that URL on a fresh deployment (symptom: the update check succeeds
   but the download returns `403 SignatureDoesNotMatch`, or the URL is plain `http://...:8000`
   which iOS ATS refuses):
   - `S3_ENDPOINT` for the Capgo edge functions must be the **public HTTPS** storage endpoint
     including the scheme (`https://sb.<domain>/storage/v1/s3`), not the internal
     `kong:8000/...` one — the host is part of the AWS signature, and Kong overwrites the
     `X-Forwarded-*` headers the code would otherwise guess it from.
   - The `storage` service needs `STORAGE_PUBLIC_URL: https://sb.<domain>` so it validates
     signatures against the public host instead of the internal `storage:5000` one.
   - `S3_REGION` of the edge functions must equal the storage service's `REGION` (here `stub`);
     the region is part of the signing key and storage only accepts `auto`, `us-east-1`, or its
     own region.
   Both files live in the Supabase deploy directory on the host
   (`supabase/docker-compose.override.yml` and `functions.env`);
   recreate the `functions` and `storage` containers afterwards
   (`docker compose up -d --force-recreate functions storage`).

5. **CLI routing quirks (already codified, do not undo).** The Capgo CLI silently falls back to
   the Capgo **cloud** (`api./files.capgo.app`) for file uploads unless `localApi`/`localApiFiles`
   are set in the `CapacitorUpdater` plugin config — `capacitor.config.ts` pins both to the update
   endpoint's origin. Direct (signed-URL) uploads return HTTP 403 on this deployment, so `ota.yml`
   uploads with `--tus`. The pinned CLI must stay ≥ 8.31.x; older versions cannot authenticate
   with the hashed API keys this instance issues.
