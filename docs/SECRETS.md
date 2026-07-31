# Secrets & Credentials Policy

> **Golden rule:** No secret values ever land in git. This repo only documents *where* each
> secret lives and *how* it is injected. If you find a real key committed, rotate it immediately.

This is part of **Epic 0 — Preparation & Foundations**. It is read/extended by Epic 5
(payments), Epic 8 (OTA) and Epic 10 (release engineering).

> See **`docs/LAUNCH_CHECKLIST.md`** for the consolidated launch-time view (provider accounts,
> open decisions, on-device QA, store content) that ties these secrets to the go-live phase.

## How secrets are injected

- **Local development:** untracked `.env` files (already covered by `.gitignore`) and the local
  macOS Keychain (Xcode signing). Never commit `.env`, `*.p8`, `*.p12`, `*.keystore`,
  `*.jks`, `*-service-account*.json`.
- **CI / release (later, Epic 10):** repository/organization secret store (e.g. GitHub Actions
  secrets) injected as environment variables or decoded files at build time.
- **Backend runtime (`synaplan` submodule):** the platform reads its secrets from its own
  environment (`backend/.env`), which is out of scope for this repo.

## Secret inventory

| Secret | Used by | Owner / source | Storage (where it lives) | Status |
|--------|---------|----------------|--------------------------|--------|
| Apple Developer Team ID | Signing, App Store Connect | Apple Developer Program | Not secret, record in `IDENTIFIERS.md` | TODO |
| Apple distribution certificate (`.p12`) + provisioning profiles | iOS signing (Epic 10) | App Store Connect / fastlane match | CI secret store / local Keychain | TODO |
| Apple App Store Connect API key (`.p8`) + Key ID + Issuer ID | TestFlight upload, App Store Server API v2 (Epic 5) | App Store Connect → Users and Access → Integrations | CI secret store; backend env for server validation | TODO |
| Android upload keystore (`.keystore`/`.jks`) + key alias + passwords | Android signing (Epic 10) | Generated once, **back up safely** | CI secret store / local (never git) | TODO |
| Google Play service-account JSON | Play Developer API, Play upload (Epic 5/10) | Google Cloud → IAM service account w/ Play access | CI secret store; backend env for server validation | TODO |
| Google Cloud Pub/Sub topic + push endpoint auth | Real-time Developer Notifications (Epic 5) | Google Cloud project | Backend env / infra config | TODO |
| Self-hosted Capgo API key (`CAPGO_API_KEY`) | OTA bundle upload (`ota.yml`) | Approved self-hosted deployment, upload-only scope | `canary` / `production` environment secret | TODO |
| Self-hosted Supabase anonymous key (`CAPGO_SUPA_ANON`) | Routes the pinned Capgo CLI to the self-hosted backend | Approved self-hosted deployment | `canary` / `production` environment secret | TODO |
| Capgo OTA signing private key (`CAPGO_BUNDLE_PRIVATE_KEY`) | Signing/E2E-encrypting OTA bundles | Generated once with Capgo CLI | Environment secret + encrypted offline backup | TODO |
| GitHub App credentials (`MOBILE_SYNC_APP_ID`, `MOBILE_SYNC_APP_PRIVATE_KEY`) | Cross-repository sync branch and PR (`sync-synaplan.yml`) | GitHub App owned by `metadist`, installed on `synaplan-apps` only, Contents + Pull requests read/write | Repository secret in `synaplan-apps` | TODO |
| GitHub App credentials (`MOBILE_APPS_APP_ID`, `MOBILE_APPS_APP_PRIVATE_KEY`) | Dispatching the synchronization from `synaplan` (`mobile-release-artifacts.yml`) | Separate GitHub App owned by `metadist`, installed on `synaplan-apps` only, Contents read-only | Repository secret in the **public** `synaplan` repository | TODO |
| GitHub App credentials (`MOBILE_TAG_APP_ID`, `MOBILE_TAG_APP_PRIVATE_KEY`) | Creating the automatic release tag (`auto-tag.yml`); a `GITHUB_TOKEN` ref would not start CI | GitHub App owned by `metadist`, installed on `synaplan` only, Contents read/write | Repository secret in the **public** `synaplan` repository | TODO |
| Synaplan artifact token (`SYNAPLAN_ARTIFACT_TOKEN`) | Read commit-matching artifacts and attestations from `synaplan` | Fine-grained token/App installation with Actions + Attestations read | CI secret store | TODO |
| Crash-reporting DSN (e.g. Sentry) | Native crash reporting (Epic 10) | Sentry project | App config / `.env` | TODO |
| Submodule access token or SSH deploy key | `git submodule update` in CI (Epic 0/10) | Git host | CI secret store | TODO (public repo → may be unnecessary) |

## Backup-critical secrets (losing these is unrecoverable)

- **Android upload keystore** — if lost, you cannot ship updates to the same Play listing
  without Google Play App Signing key reset. Store an encrypted backup off-machine.
- **Apple App Store Connect API key (`.p8`)** — downloadable only once at creation.
- **Capgo OTA signing private key (`.capgo_key_v2`)** — if lost, you cannot publish bundles that
  the already-installed apps will accept (they verify against the embedded public key). Store an
  encrypted backup off-machine.

Self-hosted Capgo endpoint details, administrator credentials, internal hostnames, and deployment
topology are private infrastructure data. Keep them in the approved release environment/runbook,
not in git or public submodule documentation.

The self-hosted Supabase host, updater/channel/stats URLs, channel name, and public bundle key are
not credentials, but still belong in protected environment variables so production builds cannot
silently target an unreviewed deployment.

## Checklist (fill during Epic 0.1 / 10)

- [ ] Apple Developer Program enrolled; Team ID recorded in `IDENTIFIERS.md`.
- [ ] Google Play Console created; developer account active.
- [ ] Android keystore generated and backed up (encrypted, off-repo).
- [ ] App Store Connect API key created and stored in the CI secret store.
- [ ] Play service-account JSON created and stored in the CI secret store.
- [ ] `.gitignore` audited to cover all secret file patterns (see Epic 0.3).
- [ ] Both synchronization GitHub Apps created and their credentials stored on the correct side
      (see [`AUTOMATION.md`](./AUTOMATION.md)); the release chain stays inert until then.
- [ ] Environments `canary`, `production` and `store-qa` created, with the Capgo and store secrets
      attached and **without** required reviewers on `canary`/`production`.
- [ ] Repository setting **Allow auto-merge** enabled in `synaplan-apps`.
