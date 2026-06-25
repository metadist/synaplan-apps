# synaplan-apps
Mobile apps for Synaplan.com platform AND your own hosted AI platforms. Brandable!

## Build & local gate

```bash
./build.sh                 # build the bundled SPA (+ cap sync); see docs/BUILD_ENVIRONMENTS.md
npm run ci-local           # app-repo quality gate: lint + format-check + typecheck + parse tests
npm run config:app:print   # show the resolved env/version/bundle-id identity
```

`npm run ci-local` runs gates 1, 3 & 4 (ESLint lint + `tsc` typecheck, parse tests, Prettier
format-check) for the **app-repo** code (`capacitor.config.ts`, `scripts/`, `tests/`, and the
ES5 bootstrap). Use `npm run lint:fix` / `npm run format` to auto-fix. Changes inside the
`synaplan/` submodule keep using that repo's own `make` gate (see its `AGENTS.md`).
Native click-through (gate 2) runs via Maestro and is **device-gated** (built app + booted
emulator/simulator), so it lives outside `ci-local`: `npm run e2e` — see
[`docs/NATIVE_E2E.md`](docs/NATIVE_E2E.md). (`ci-local` still guards the flow files' integrity.)

Gate details: [`docs/QUALITY_GATES.md`](docs/QUALITY_GATES.md) · Multi-environment builds:
[`docs/BUILD_ENVIRONMENTS.md`](docs/BUILD_ENVIRONMENTS.md).

## Docs

- **[`docs/LAUNCH_CHECKLIST.md`](docs/LAUNCH_CHECKLIST.md)** — everything deferred to the
  launch/device/go-live phase: provider accounts, secrets & env, open product decisions,
  on-device QA, store-listing content. **Start here for "what we still need at the end".**
- [`docs/STORE_LISTINGS.md`](docs/STORE_LISTINGS.md) — App Store + Play copy (de/en/es/tr)
- [`docs/QUALITY_GATES.md`](docs/QUALITY_GATES.md) — per-epic test matrix (the five gates)
- [`docs/AI_LOGIC_REVIEW.md`](docs/AI_LOGIC_REVIEW.md) — gate-5 AI review checklist/prompt
- [`docs/BUILD_ENVIRONMENTS.md`](docs/BUILD_ENVIRONMENTS.md) — dev/staging/prod builds + versioning
- [`docs/SECRETS.md`](docs/SECRETS.md) — secret inventory & injection policy
- [`docs/IDENTIFIERS.md`](docs/IDENTIFIERS.md) — bundle IDs / Team ID
- [`docs/OTA_POLICY.md`](docs/OTA_POLICY.md) · [`docs/COMPATIBILITY.md`](docs/COMPATIBILITY.md) — OTA rules + version matrix
- [`docs/ASSETS.md`](docs/ASSETS.md) — icon/splash art & regeneration
- [`docs/SERVER_CONFIG.md`](docs/SERVER_CONFIG.md) — in-app server switcher
- [`docs/SYNAPLAN_BLAST_RADIUS.md`](docs/SYNAPLAN_BLAST_RADIUS.md) — changes to the public submodule
