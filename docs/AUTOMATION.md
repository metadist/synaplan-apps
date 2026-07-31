# Zero-Touch Release Automation

> How a merge into `metadist/synaplan` `main` reaches an installed app without a manual step,
> what the guard rails are, and how to stop a rollout.

Related: [`OTA_POLICY.md`](./OTA_POLICY.md) for what may ship over the air,
[`COMPATIBILITY.md`](./COMPATIBILITY.md) for the pin record, [`SECRETS.md`](./SECRETS.md) for the
credentials this chain needs.

## The chain

| # | Where | Workflow | What it does |
|---|-------|----------|--------------|
| 1 | `synaplan` | `auto-tag.yml` | Classifies the merge with `scripts/mobile-impact.mjs`. Only `ota-candidate` and `store-required` get an automatic patch tag `vX.Y.Z`. |
| 2 | `synaplan` | `ci.yml` | Runs on the new tag. |
| 3 | `synaplan` | `mobile-release-artifacts.yml` | Publishes the attested `mobile-release-<tag>-<sha>` artifact and dispatches `synaplan-mobile-release` to this repository. |
| 4 | `synaplan-apps` | `sync-synaplan.yml` | Verifies the artifact and its attestation, moves the submodule pin, updates `COMPATIBILITY.md` and `IDENTIFIERS.md`, opens a PR and enables auto-merge. |
| 5 | `synaplan-apps` | `ci.yml` | Builds the web bundle and runs the drift gate on the PR. Green means the auto-merge fires. |
| 6 | `synaplan-apps` | `release-dispatch.yml` | Reads the classification recorded by the sync PR and routes it: `ota-candidate` to `ota.yml`, `store-required` to `store-rc.yml`. |
| 7a | `synaplan-apps` | `ota.yml` | Builds, signs and publishes the bundle to the production channel. |
| 7b | `synaplan-apps` | `store-rc.yml` | Builds signed binaries and uploads them to TestFlight and the Play internal track. |
| 8 | `synaplan-apps` | `ota-health.yml` | Watches the freshly published bundle and rolls back automatically when it fails to become healthy. |

The classification is written to `.github/release-route.json` by the sync workflow, so step 6 routes
on a value that was verified against the signed source manifest instead of re-deriving it.

## What is still manual

- Submitting a store build for App Store review and answering review questions. Everything up to
  the TestFlight and Play internal builds is automatic.
- The one-time credential setup below.
- Pinning against a `synaplan` feature branch that has not been merged yet. See
  [`DEVELOPMENT.md`](./DEVELOPMENT.md); no pin is needed to build and run locally.

## One-time setup

Creating the apps needs organization-level rights. Until that is done, the chain stops after step 3
and `mobile-release-artifacts.yml` reports a skipped dispatch.

> **Doing it for the first time?** [`AUTOMATION_SETUP.md`](./AUTOMATION_SETUP.md) walks through the
> same setup click by click. This section is the reference for what has to exist and why.

### 1. Three GitHub Apps

| App | Installed on | Repository permissions | Secrets stored in |
|-----|--------------|------------------------|-------------------|
| Release tagger | `metadist/synaplan` | Contents: read and write | `synaplan`: `MOBILE_TAG_APP_ID`, `MOBILE_TAG_APP_PRIVATE_KEY` |
| Dispatcher | `metadist/synaplan-apps` | Contents: read-only | `synaplan`: `MOBILE_APPS_APP_ID`, `MOBILE_APPS_APP_PRIVATE_KEY` |
| Synchronizer | `metadist/synaplan-apps` | Contents + Pull requests: read and write | `synaplan-apps`: `MOBILE_SYNC_APP_ID`, `MOBILE_SYNC_APP_PRIVATE_KEY` |

App tokens are required rather than the default `GITHUB_TOKEN` in two places: a tag created with
`GITHUB_TOKEN` does not start a workflow run, so nothing would ever be built, and a merge performed
with it would record the release route without ever acting on it.

Three apps rather than one keeps the write scope for the app repository out of the public
repository, and keeps the tagger's write access to `synaplan` away from the app repository.

### 2. Repository settings in `synaplan-apps`

Enable **Allow auto-merge** under Settings → General → Pull Requests. Without it
`gh pr merge --auto` fails and the chain stops at an open pull request.

Repository-level secrets (Settings → Secrets and variables → Actions):

| Secret | Why it cannot live in an environment |
|--------|--------------------------------------|
| `MOBILE_SYNC_APP_ID` / `MOBILE_SYNC_APP_PRIVATE_KEY` | `sync-synaplan.yml` runs without an environment |
| `SYNAPLAN_ARTIFACT_TOKEN` | Also read by `ci.yml`, which runs without an environment. Only needed if `GITHUB_TOKEN` cannot read Actions artifacts and attestations from `metadist/synaplan` |

### 3. Environments in `synaplan-apps`

Create `canary`, `production` and `store-qa` under Settings → Environments.

Do **not** add required reviewers to `canary` or `production`: a reviewer there reintroduces the
manual approval this chain removes, and `production` is shared with `ota.yml`. A store submission
is a human decision anyway, so `store-qa` may keep reviewers — the automatic build still runs, only
the upload waits.

`canary` and `production` (used by `ota.yml` and `ota-health.yml`):

| Name | Kind | Value |
|------|------|-------|
| `CAPGO_API_KEY` | secret | Upload-scoped key of the self-hosted deployment |
| `CAPGO_SUPA_ANON` | secret | Anonymous key that routes the CLI to the self-hosted backend |
| `CAPGO_BUNDLE_PRIVATE_KEY` | secret | Bundle signing key; keep an encrypted offline backup |
| `CAPGO_SUPA_HOST` | variable | Self-hosted Supabase host |
| `CAPGO_CHANNEL` | variable | **Must equal the environment name** — `ota.yml` refuses a mismatch |
| `CAPGO_UPDATE_URL` | variable | Updater endpoint, HTTPS |
| `CAPGO_CHANNEL_URL` | variable | Channel endpoint, HTTPS |
| `CAPGO_STATS_URL` | variable | Statistics ingest endpoint the app reports to, HTTPS |
| `CAPGO_BUNDLE_PUBLIC_KEY` | variable | Counterpart of the signing key, compiled into the binary |
| `CAPGO_STATS_API_URL` | variable | Statistics **query** endpoint for `ota-health.yml`; supports `{appId}` and `{bundle}` placeholders |

`store-qa` (used by `store-rc.yml`):

| Name | Kind | Value |
|------|------|-------|
| `ANDROID_KEYSTORE_BASE64` | secret | Upload keystore, base64 encoded |
| `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | secret | Keystore credentials |
| `IOS_DISTRIBUTION_CERTIFICATE_BASE64` | secret | Distribution `.p12`, base64 encoded |
| `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` | secret | Password of that `.p12` |
| `IOS_PROVISIONING_PROFILE_BASE64` | secret | App Store provisioning profile, base64 encoded |
| `APPLE_TEAM_ID` | secret | Apple Developer team identifier |
| `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID` | secret | App Store Connect API key identifiers |
| `APP_STORE_CONNECT_PRIVATE_KEY` | secret | Contents of the `.p8`, downloadable only once |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | secret | Play service-account JSON |
| `CAPGO_UPDATE_URL`, `CAPGO_CHANNEL_URL`, `CAPGO_STATS_URL`, `CAPGO_BUNDLE_PUBLIC_KEY` | variable | Compiled into the binary, so a store build targets the reviewed deployment |
| `CAPGO_PRODUCTION_CHANNEL` | variable | Default channel of a store build, normally `production` |
| `TESTFLIGHT_INTERNAL_GROUP` | variable | TestFlight group that receives the build, default `Internal` |

`store-rc.yml` deliberately declares no `workflow_call` secrets: the credentials are resolved from
this environment, so an automatic call cannot substitute them.

### 4. Verification run

```bash
gh workflow run sync-synaplan.yml \
  -R metadist/synaplan-apps \
  -f synaplan_ref=v4.0.6 \
  -f synaplan_sha=<the 40-character sha of that tag>
```

A successful run opens a synchronization pull request. The chain is live once that PR merges by
itself.

## Guard rails

- **Classification is fail-closed.** `.github/mobile-impact-policy.json` in `synaplan` routes every
  path that is not explicitly allow-listed to `store-required`, so an unclassified change can never
  reach a device over the air.
- **Only `ota-candidate` reaches `ota.yml`.** The workflow re-checks the classification against the
  release route file and refuses anything else.
- **Bundles are signed.** `ota.yml` signs each bundle with `CAPGO_BUNDLE_PRIVATE_KEY`; the app
  verifies against the public key compiled into the binary.
- **The device reverts by itself.** A bundle that does not call `notifyAppReady()` within
  `appReadyTimeout` is discarded and the previous bundle is restored.
- **The channel is watched.** `ota-health.yml` polls the published bundle and rolls back
  automatically when the healthy share stays below the configured threshold.

## Stopping a rollout

```bash
# Freeze the channel: devices keep what they have, nothing new is served
gh workflow run ota.yml -R metadist/synaplan-apps \
  -f operation=pause -f class=ota-candidate -f channel=production -f dry_run=false

# Roll back to a known good bundle
gh workflow run ota.yml -R metadist/synaplan-apps \
  -f operation=rollback -f class=ota-candidate -f channel=production \
  -f rollback_bundle=<bundle version> -f dry_run=false

# Resume
gh workflow run ota.yml -R metadist/synaplan-apps \
  -f operation=resume -f class=ota-candidate -f channel=production -f dry_run=false
```

Published bundle versions are recorded in the run summary of `ota.yml` and in the
`Current OTA bundle` column of [`COMPATIBILITY.md`](./COMPATIBILITY.md).

To stop the automation entirely, disable `auto-tag.yml` in `synaplan`. No tag means no chain.

## Operational dependencies

`ota.yml` and `store-rc.yml` run on the self-hosted `mobile` runner. If it is offline the chain
stops silently after the sync PR merges. `ota.yml` fails fast with an explicit message when no
runner picks the job up within the configured timeout, so the failure is visible instead of a queued
job nobody notices.
