# Onboarding — from a change in `synaplan` to an updated app

> For a developer who just joined, already knows how to work on `synaplan`, and now has to get a
> change out to the installed iOS and Android apps.
>
> Read it once from top to bottom. After that, sections 5 to 11 are your daily loop.

Nothing in here requires you to build a store binary, hold a signing certificate, or run a release
runner. All of that happens on GitHub-hosted machines with organization secrets. Your job is to
write the change, prove it is green, and start the release.

## 1. What you are looking at

Two repositories:

| Repository | Visibility | What it is |
|---|---|---|
| `metadist/synaplan` | public | Symfony backend and the Vue SPA. Where you write features. |
| `metadist/synaplan-apps` | private | The Capacitor 8 iOS/Android shell. It contains `synaplan` as a **pinned submodule**. |

The app does not follow `synaplan` `main`. It carries one exact, immutable commit of it — the
**pin**. That is deliberate: a phone in a customer's pocket must show a reviewed state, not whatever
was merged five minutes ago.

Three consequences you have to internalize:

- **Merging to `synaplan` `main` changes nothing on any device.** Not the web app's mobile view, not
  TestFlight, nothing. A release has to be cut.
- **Your local simulator ignores the pin entirely.** It shows whatever is in the `synaplan/` working
  directory, including uncommitted edits. So you can test before anything is merged.
- **Two version numbers exist and neither is the `synaplan` tag.** The marketing version (`4.0.0`)
  lives in `package.json` of `synaplan-apps`. The build number is the commit count of
  `synaplan-apps` and increments by itself. Check with `npm run config:app:print`.

## 2. Access you need on day one

Ask the maintainer for these. You cannot do the job without the first three.

| Access | What for | Notes |
|---|---|---|
| GitHub org membership, write on both repos | Branches, PRs, starting workflows | `gh auth login` afterwards |
| Apple Developer / App Store Connect, role **App Manager** | Seeing TestFlight builds, reading review status | Not needed to *build* — CI signs |
| Capgo console login | Seeing which OTA bundle a channel serves | Self-hosted instance |
| Production server SSH | Only if you touch backend deployment | Not needed for app work |

You will **not** get: signing certificates, the `.p8` App Store Connect key, the OTA signing key, or
the Play service account. Those live only in GitHub environment secrets. If you ever find yourself
copying one onto your laptop, stop and ask.

## 3. Set up the Mac (once)

Required: macOS, Xcode 26+ (open it once, accept the license, install an iOS Simulator under
Xcode → Settings → Components), Xcode Command Line Tools, Node.js 22+, Docker Desktop with Compose
v2, `git`, and the GitHub CLI. 16 GB RAM is realistic. iOS dependencies use Swift Package Manager,
so CocoaPods is not needed.

Android is optional and only needed if you build for Play: Android Studio, SDK 36, JDK 21, an
emulator.

Verify everything before you complain that something is broken:

```bash
git --version
node --version            # must be 22 or newer
docker compose version
docker context ls         # note which context is active — it is not always "default"
xcodebuild -version
xcrun simctl list devices available
gh auth status
```

For native click-through tests, also:

```bash
curl -fsSL "https://get.maestro.mobile.dev" | bash
```

## 4. Clone and start

Clone the private repo **with submodules**. The `synaplan/` submodule is a full clone with its own
`origin`, so you do not need a second checkout of `synaplan` — you work directly inside it.

```bash
git clone --recursive git@github.com:metadist/synaplan-apps.git
cd synaplan-apps
git submodule update --init --recursive
npm ci
```

Start the platform stack (this is the normal `synaplan` development environment):

```bash
cd synaplan
docker compose up -d
cd ..
```

Local URLs: app `http://localhost:5173`, API `http://localhost:8000`, API docs
`http://localhost:8000/api/doc`, phpMyAdmin `http://localhost:8082`, MailHog `http://localhost:8025`.
Seeded login: `demo@synaplan.com` / `demo123`.

## 5. Write the change

Branch inside the submodule, not in the app repo:

```bash
cd synaplan
git checkout main && git pull
git checkout -b feat/my-thing
```

Conventional Commits, English, no AI attribution, never commit to `main`.

## 6. See it in the simulator

Two ways. Use live reload while iterating, and do one full build before you push.

### Live reload — for iterating

Three terminals. Replace `192.168.1.20` with **your own LAN address** (`ipconfig getifaddr en0`);
an iOS device resolves `localhost` to itself.

```bash
# 1) the SPA dev server, reachable from the simulator
cd synaplan/frontend && npm run dev -- --host

# 2) the app-owned bootstrap in front of it
SYNAPLAN_API_BASE_URL=http://192.168.1.20:8000 npm run dev:shell

# 3) point the WebView at the proxy and run
SYNAPLAN_ENV=dev SYNAPLAN_DEV_SERVER=http://192.168.1.20:5174 npx cap sync ios
npm run cap:ios
```

Terminal 2 is not optional. Vite serves the submodule's own `index.html`, which lacks the app-owned
bootstrap, so without the proxy the API base URL and the in-app server switcher do not work.

### Full build — what actually ships

Produces `com.synaplan.app.dev` with a DEV badge, installed next to the production app:

```bash
SYNAPLAN_ENV=dev \
SYNAPLAN_OPENAPI_URL=http://localhost:8000/api/doc.json \
SYNAPLAN_API_BASE_URL=http://192.168.1.20:8000 \
./build.sh
npm run cap:ios
```

If you changed backend OpenAPI annotations, this is also the step that regenerates the Zod schemas.
Never hand-edit `frontend/src/generated/api-schemas.ts`.

### Reset the identity before committing in `synaplan-apps`

`build.sh` stamps the resolved identity into the native project, so a dev build leaves a `.dev`
bundle id behind:

```bash
SYNAPLAN_ENV=prod SYNAPLAN_BUILD_NUMBER=1 npm run config:app
```

## 7. Run the gates before you push

Green here means green CI. A filtered run is diagnostic only and never replaces the full gate.

In `synaplan/` (skip the half you did not touch):

```bash
make -C backend lint
make -C backend phpstan
make -C backend test
make -C frontend lint
docker compose exec -T frontend npm run check:types
make -C frontend test
node --test tests/mobile-impact.test.mjs
```

In `synaplan-apps/`:

```bash
npm run ci-local     # lint, format check, typecheck, parse/manifest tests
npm run e2e          # device-gated Maestro click-through, needs a built app + booted simulator
```

Run `npm run e2e` for anything touching auth/OAuth, SSE/WebSockets, server switching, IAP, native
plugins, lifecycle, permissions, forced updates, or OTA behavior.

## 8. Know how your change will ship — before you open the PR

Every changed file is classified by `.github/mobile-impact-policy.json` in `synaplan`. The **highest**
classification of all changed files wins.

| Class | Means | Reaches a device via |
|---|---|---|
| `no-app-impact` | docs, CI, tooling, tests | nothing |
| `backend-only` | allow-listed server code, migrations, entities, repositories | the platform deployment only |
| `ota-candidate` | CSS, `i18n/*.json`, images, icon components | over the air, minutes |
| `store-required` | everything else | Apple/Google review, days |

Preview it locally, from inside `synaplan/`:

```bash
node scripts/mobile-impact.mjs --base origin/main --head HEAD
cat mobile-release-manifest.json    # "classification" plus a reason per file
```

Two rules that surprise everyone:

- **It is fail-closed.** A path that is not explicitly allow-listed becomes `store-required`. A new
  top-level file, a new directory, an unusual extension — all store-required by design.
- **Executable code and markup never ship over the air.** `.ts`, `.tsx`, `.js`, `.mjs`, `.cjs` and
  `.html` are excluded even inside `frontend/src/assets/`, and a `.vue` component is not on the OTA
  allow-list at all. Only styling, translations and static assets qualify.

Things that are always `store-required`: `frontend/src/router/**`, anything matching `*Auth*`,
`*Iap*`, `*RuntimeConfig*`, `stores/auth.ts`, `stores/config.ts`, `services/native*.ts`,
`services/otaUpdates.ts`, the generated API schemas, any `backend/src/Controller/**`, anything
matching `*Payment*`, `*Purchase*`, `*Subscription*`, `*Stripe*`, `*Mobile*`, `composer.json`,
`package.json`, and every lock file.

So: a translation fix ships in minutes. A router change costs an App Store review. Plan the PR
accordingly — and do not try to sneak logic into a CSS file.

## 9. Open the PR and merge

Normal `synaplan` process: PR, green CI, review, merge to `main`. The **Mobile Impact** check runs on
every PR and reports the classification in its run summary, so you see the routing before merging
without running anything locally.

If you know a change is riskier than the paths suggest, add the label
`mobile-impact:store-required` to the PR. Labels can only escalate the classification, never lower
it.

**At this point nothing has happened to any app.** No tag, no build, no device.

If your change was `backend-only`, you are done as far as the app is concerned — it reaches
production through the normal platform deployment.

## 10. Cut the release — tag, then publish

When a release is due (batch several merges; do not do this per PR):

```bash
# preview: reports the classification and the tag it would create, creates nothing
gh workflow run release-tag.yml -R metadist/synaplan -f dry_run=true

# for real: creates the tag and a DRAFT GitHub release with generated notes
gh workflow run release-tag.yml -R metadist/synaplan
```

Then review the draft release on GitHub and **publish** it. Publishing is the deliberate step that
starts the mobile chain — the tag alone only feeds the platform jobs (Docker images, version pins).

The classification happens at publish time against the previously **published** release, so one
release collects every merge since the last one into a single delivery. Ordinary backend work is
`backend-only` (nothing reaches the app), ordinary frontend work is `ota-candidate` (ships over the
air) — a store submission happens only when the release contains a `store-required` change (native,
IAP/payments, authentication transport, forced-update, update mechanism).

## 11. Watch the chain

Everything after publishing the release is unattended:

| # | Repo | Workflow | Does |
|---|---|---|---|
| 1 | `synaplan` | `mobile-release-artifacts.yml` | runs on `release: published`, verifies CI, classifies, publishes the attested manifest, dispatches |
| 2 | `synaplan-apps` | `sync-synaplan.yml` | verifies attestation, moves the pin, updates `COMPATIBILITY.md`, opens a PR with auto-merge |
| 3 | `synaplan-apps` | `ci.yml` | builds the web bundle, runs the drift gate; green means the PR merges itself |
| 4 | `synaplan-apps` | `release-dispatch.yml` | routes on `.github/release-route.json` |
| 5a | `synaplan-apps` | `ota.yml` | signs and publishes the bundle to the production channel |
| 5b | `synaplan-apps` | `store-rc.yml` | builds signed binaries, uploads to TestFlight and Play internal |
| 6 | `synaplan-apps` | `ota-health.yml` | watches the bundle, rolls back automatically if it is unhealthy |

Follow it:

```bash
gh run list -R metadist/synaplan --limit 5
gh run list -R metadist/synaplan-apps --limit 10
gh run watch -R metadist/synaplan-apps <run-id>
gh pr list -R metadist/synaplan-apps          # the sync PR, if it did not merge itself
```

If the sync PR sits there open, its CI is red. Read it — do not merge past it.

## 12a. It was `ota-candidate` — verify on a device

The bundle is on the `production` channel within minutes. On the phone:

1. Close the app **completely** (swipe it out of the app switcher). An update is applied on the next
   cold start, never while the app is in the foreground.
2. Reopen it. First launch downloads, second launch shows the new bundle.

If nothing changes, open the Capgo console and look at which bundle the `production` channel serves.
A channel pinned to a stale bundle is the single most common cause — devices keep re-downloading the
old bundle no matter how often you reinstall.

## 12b. It was `store-required` — from TestFlight to the store

CI produces the signed binaries automatically and uploads them. From there a human takes over:

1. **TestFlight**: the build appears after Apple finishes processing (typically 5–20 minutes).
   Install it, test on a real device.
2. **New App Store version?** The marketing version lives in `package.json` of `synaplan-apps`.
   Bumping `4.0.0` to `4.1.0` is a normal PR in the app repo. The build number needs no attention,
   it is the commit count.
3. **App Store Connect**: create the version, attach the build, write the "What's New" text in every
   listing locale, and submit. If subscriptions changed, they go into the *same* submission as the
   app version.
4. **Release manually, not automatically.** Automatic release publishes the moment review passes,
   which is exactly when you cannot verify anything.
5. **Before releasing, confirm the OTA channel does not override the reviewed binary.** A stale
   bundle on the default channel means Apple reviewed one thing and users get another.

Google Play is the same shape via the internal track.

## 13. When it goes wrong

| Symptom | Cause and fix |
|---|---|
| Release published, nothing dispatched | The batch classified as `backend-only`/`no-app-impact`. Expected — check the run summary of `mobile-release-artifacts.yml`. |
| `release-tag.yml` or `mobile-release-artifacts.yml` refuses | The commit has no successful CI run. Fix CI first. |
| Sync PR open, not merging | Its CI is red, or auto-merge is off in repo settings. |
| Drift gate fails | A synced native config still carries a `server.url` — someone committed after a live-reload `cap sync`. Run `SYNAPLAN_ENV=prod SYNAPLAN_BUILD_NUMBER=1 npm run config:app` and commit. |
| Device shows old UI after OTA | Channel serves a stale bundle, or the app was not cold-started. See 12a. |
| Bad bundle is live | Pause, then roll back (below). |
| Simulator shows the wrong backend | You used `localhost` instead of your LAN address, or terminal 2 is not running. |

Stopping a rollout:

```bash
# freeze: devices keep what they have, nothing new is served
gh workflow run ota.yml -R metadist/synaplan-apps \
  -f operation=pause -f class=ota-candidate -f channel=production -f dry_run=false

# roll back to a known good bundle
gh workflow run ota.yml -R metadist/synaplan-apps \
  -f operation=rollback -f class=ota-candidate -f channel=production \
  -f rollback_bundle=<bundle version> -f dry_run=false

# resume
gh workflow run ota.yml -R metadist/synaplan-apps \
  -f operation=resume -f class=ota-candidate -f channel=production -f dry_run=false
```

Published bundle versions are in the `ota.yml` run summary and in
[`COMPATIBILITY.md`](./COMPATIBILITY.md). To stop the automation entirely, stop cutting releases.

## 14. Never do this

- Publish an OTA bundle for payment, entitlement, native, privacy, permission, or material feature
  changes. Ambiguous means store-required. See [`OTA_POLICY.md`](./OTA_POLICY.md).
- Pin the submodule to a branch. The pin is always an immutable SHA of a reviewed tag.
- Commit or push to `main` in either repository.
- Hand-edit generated API schemas, or write a manual TypeScript interface for an API response.
- Put store, signing, OTA-hosting, endpoint, or infrastructure details into the public `synaplan`
  repository.
- Commit secrets, keystores, `.p8`/`.p12` files, provisioning profiles, or `.env` files.
- Commit with a failing gate.

## 15. Cheat sheet

```bash
# identity of the current build
npm run config:app:print

# how would my branch be classified?
cd synaplan && node scripts/mobile-impact.mjs --base origin/main --head HEAD && cat mobile-release-manifest.json

# app-repo gate
npm run ci-local

# full build + run on the simulator
SYNAPLAN_ENV=dev SYNAPLAN_OPENAPI_URL=http://localhost:8000/api/doc.json ./build.sh && npm run cap:ios

# cut a release (dry run first), then publish the draft release on GitHub
gh workflow run release-tag.yml -R metadist/synaplan -f dry_run=true
gh workflow run release-tag.yml -R metadist/synaplan

# what is running
gh run list -R metadist/synaplan-apps --limit 10
```

## Where to read further

- [`DEVELOPMENT.md`](./DEVELOPMENT.md) — local build, live reload, pinning an unmerged branch
- [`AUTOMATION.md`](./AUTOMATION.md) — the release chain in detail, guard rails, credential setup
- [`OTA_POLICY.md`](./OTA_POLICY.md) — what may ship over the air, and what may not
- [`QUALITY_GATES.md`](./QUALITY_GATES.md) — the full test matrix
- [`COMPATIBILITY.md`](./COMPATIBILITY.md) — pin history: which app version carried which platform
- [`IAP_TESTING.md`](./IAP_TESTING.md) — sandbox testers and purchase testing
- [`IDENTIFIERS.md`](./IDENTIFIERS.md) — bundle ids, product ids, versioning
- `AGENTS.md` in both repositories — the binding rules, shorter than this document
