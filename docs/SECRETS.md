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
| Capgo API token (`CAPGO_TOKEN`) | OTA bundle upload (Epic 8, `npm run ota:upload`) | Capgo Cloud account → Account → API keys (upload scope) | CI secret store / `.env` (never git) | TODO |
| Capgo OTA signing private key (`.capgo_key_v2`) | Signing/E2E-encrypting OTA bundles at upload (Epic 8) | Generated locally via `npm run ota:key:create` | Local + CI secret store (gitignored); **back up safely** — public key is committed in `capacitor.config.ts` | TODO |
| Crash-reporting DSN (e.g. Sentry) | Native crash reporting (Epic 10) | Sentry project | App config / `.env` | TODO |
| Submodule access token or SSH deploy key | `git submodule update` in CI (Epic 0/10) | Git host | CI secret store | TODO (public repo → may be unnecessary) |

## Backup-critical secrets (losing these is unrecoverable)

- **Android upload keystore** — if lost, you cannot ship updates to the same Play listing
  without Google Play App Signing key reset. Store an encrypted backup off-machine.
- **Apple App Store Connect API key (`.p8`)** — downloadable only once at creation.
- **Capgo OTA signing private key (`.capgo_key_v2`)** — if lost, you cannot publish bundles that
  the already-installed apps will accept (they verify against the embedded public key). Store an
  encrypted backup off-machine.

## Checklist (fill during Epic 0.1 / 10)

- [ ] Apple Developer Program enrolled; Team ID recorded in `IDENTIFIERS.md`.
- [ ] Google Play Console created; developer account active.
- [ ] Android keystore generated and backed up (encrypted, off-repo).
- [ ] App Store Connect API key created and stored in the CI secret store.
- [ ] Play service-account JSON created and stored in the CI secret store.
- [ ] `.gitignore` audited to cover all secret file patterns (see Epic 0.3).
