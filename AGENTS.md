---
name: Synaplan Mobile Apps
description: Capacitor shells for the Synaplan iOS and Android applications
---

# Synaplan Mobile Apps Development Guide

Private release repository for the Capacitor 8 iOS and Android shells. It bundles the Vue SPA from
the public `synaplan/` submodule and owns native configuration, store compliance, signing, and OTA
release orchestration.

**Stack:** Node.js 22+, TypeScript, Capacitor 8, Swift Package Manager, Gradle, Maestro.

## Repository Architecture

| Path | Purpose |
| ---- | ------- |
| `synaplan/` | Public platform submodule; source of the bundled backend contract and Vue SPA |
| `app/` | App-owned bootstrap loaded before the SPA |
| `ios/`, `android/` | Native projects, manifests, permissions, signing, and store metadata |
| `scripts/` | Build identity and validation helpers |
| `tests/`, `.maestro/` | Contract/manifest tests and device click-through flows |
| `docs/` | Release, compatibility, compliance, secrets, and operational guides |

## Critical Rules

### Language

- **Code, comments, documentation, and commit messages are always English.**
- User-facing copy follows the platform's four-locale requirement: `de`, `en`, `es`, `tr`.

### Git and Submodules

- Never commit or push directly to `main`; use feature branches and pull requests.
- Use Conventional Commits and never add AI attribution.
- Resolve merge conflicts manually. Never accept `ours` or `theirs` blindly; preserve the intent
  and functionality of both sides.
- The `synaplan/` submodule must point to an exact reviewed tag or SHA, never a branch.
- Release builds must use a reviewed release tag. A temporary SHA pin is allowed during
  development only when it is recorded in `docs/COMPATIBILITY.md`.
- Review the submodule diff and its `MOBILE-APP SEAM` markers before changing a pin.

### Docker Environment

- Platform backend/frontend tooling runs in Docker. On the maintained release workstation, use
  Docker context `m4` explicitly; do not assume the default context.
- Prefer the `synaplan/` make targets where they wrap Docker correctly.

### Mandatory Gates

Run the unfiltered gates for every affected repository before committing:

```bash
# App-owned lint, formatting, type checks, and parse/manifest tests
npm run ci-local

# Device-gated native click-through after building the relevant target
npm run e2e

# Public submodule gate (run with the configured Docker context)
DOCKER_CONTEXT=m4 make -C synaplan/backend lint
DOCKER_CONTEXT=m4 make -C synaplan/backend phpstan
DOCKER_CONTEXT=m4 make -C synaplan/backend test
DOCKER_CONTEXT=m4 make -C synaplan/frontend lint
docker --context m4 compose -f synaplan/docker-compose.yml exec -T frontend npm run check:types
DOCKER_CONTEXT=m4 make -C synaplan/frontend test
```

- A filtered test run is diagnostic only and never replaces the complete gate.
- Run device/release-track tests for changes to auth/OAuth, SSE/WebSockets, server switching, IAP,
  native plugins, lifecycle, permissions, forced updates, or OTA behavior.
- Review `docs/QUALITY_GATES.md` and complete `docs/RELEASE_GATE_v4.md` for a store release.

### Build and OpenAPI Parity

- `./build.sh` is the canonical app build; it builds the pinned SPA and synchronizes native
  projects. Use `./build.sh --web-only` only when native synchronization is intentionally excluded.
- The app-generated Zod schemas must come from the same backend OpenAPI contract as the pinned
  `synaplan` source. Never hand-edit generated schemas or substitute manual API interfaces.
- For an OpenAPI change, regenerate schemas through the documented build path, run the submodule
  frontend type check, and verify a clean app build against the intended specification.
- Never release a bundle built from an unrecorded working tree or moving submodule branch.

## Release Classification

Classify each change before choosing a release path:

- **backend-only:** no bundled SPA or native-shell effect. Deploy through the platform process.
- **ota-candidate:** web assets only, within already reviewed behavior, with no entitlement,
  payment, security, permission, privacy, or feature-contract change.
- **store-required:** native code/configuration, plugins, permissions, privacy manifests, IAP,
  authentication transport, new capabilities, or material behavior changes.

OTA releases originate only here, use the self-hosted Capgo service, and must follow
`docs/OTA_POLICY.md`. Ambiguous changes are store-required.

The classification, the submodule pin, and the delivery are automated end to end
(`docs/AUTOMATION.md`). The automation never widens what may ship over the air: it routes on the
fail-closed classification produced in the source repository and records it in
`.github/release-route.json`. Treat that policy file and this routing as release-critical code.

## Native and Store Rules

### Plugins, Permissions, and Privacy

- Ask before adding or upgrading a native plugin or changing native capabilities.
- Declare only permissions that are required by reachable functionality; keep iOS purpose strings
  and Android permissions synchronized with actual behavior.
- Audit every native SDK/plugin for Apple privacy-manifest and required-reason API obligations.
  Keep `PrivacyInfo.xcprivacy`, App Store privacy disclosures, and Google Play Data safety answers
  aligned with the shipped binary.
- Permission denial must degrade safely and must not crash or expose secrets.

### IAP and Anti-Steering

- Digital subscriptions and entitlements in native apps use store IAP and server-side validation.
- Never unlock an entitlement from a client receipt alone; restore and store-managed subscription
  flows must remain available.
- Never expose Stripe/web checkout, external purchase links, pricing steering, or payment-related
  behavior through OTA. Preserve server-enforced cross-channel protections.
- Treat all purchase, restore, receipt, entitlement, and billing-channel changes as store-required.

### Apple Review Baseline

- App Store Review Guideline **2.5.2** and Apple Developer Program License Agreement **3.3.2**
  constrain downloaded/interpreted code and OTA behavior.
- App Store Review Guideline **4.2** requires sufficient lasting native/app value.
- Re-check the current Apple and Google policies at release time; documentation is not a substitute
  for the current agreements.

## Secrets

- Never commit tokens, signing keys, certificates, provisioning profiles, keystores, service-account
  files, `.env` files, or private infrastructure endpoints.
- Inject secrets through local secure storage or the approved CI/release secret store.
- Back up irreplaceable signing material securely and separately. See `docs/SECRETS.md`.
- Logs, screenshots, fixtures, and review notes must not expose credentials, receipts, tokens,
  account identifiers, or private infrastructure.

## Boundaries

### Ask First Before

- Adding/upgrading dependencies or native plugins
- Changing native permissions, entitlements, privacy manifests, bundle identifiers, or signing
- Modifying build, CI, release, OTA, or store-submission configuration
- Changing IAP products, billing behavior, or compatibility/forced-update policy
- Updating the `synaplan` submodule pin for a release

### Never Do

- Publish an OTA bundle for payment, entitlement, native, privacy, permission, or material feature
  changes
- Build a release from a branch or dirty/unrecorded submodule state
- Put app-store, signing, OTA-hosting, or private infrastructure details in the public submodule
- Edit generated native dependencies, `node_modules/`, or built artifacts
- Commit with failing gates or without updating the compatibility record

## Detailed Documentation

- `docs/AUTOMATION.md` — the automated release chain, its setup, and the kill switch
- `docs/AUTOMATION_SETUP.md` — step-by-step activation of the automation credentials
- `docs/STORE_SETUP.md` — obtaining the Apple and Google signing and upload credentials
- `docs/DEVELOPMENT.md` — local build, simulator live reload, and OpenAPI schema generation
- `docs/QUALITY_GATES.md` — automated and device-gated test matrix
- `docs/RELEASE_GATE_v4.md` — coordinated release decision
- `docs/COMPATIBILITY.md` — app, platform pin, API, and OTA compatibility
- `docs/OTA_POLICY.md` — allowed OTA scope and rollout controls
- `docs/SECRETS.md` — credentials and signing-material policy
- `docs/IDENTIFIERS.md` — immutable IDs and versioning
