# synaplan-apps
Mobile apps for Synaplan.com platform AND your own hosted AI platforms. Brandable!

## Build & local gate

```bash
./build.sh                 # build the bundled SPA (+ cap sync); see docs/BUILD_ENVIRONMENTS.md
npm run ci-local           # app-repo quality gate: typecheck + config/parse tests (no extra deps)
npm run config:app:print   # show the resolved env/version/bundle-id identity
```

`npm run ci-local` runs gates 1 & 3 (lint/typecheck + parse) for the **app-repo** code
(`capacitor.config.ts`, `scripts/`) using only the bundled `tsc` and Node's built-in test
runner. Changes inside the `synaplan/` submodule keep using that repo's own `make` gate
(see its `AGENTS.md`). Multi-environment builds: [`docs/BUILD_ENVIRONMENTS.md`](docs/BUILD_ENVIRONMENTS.md).

## Docs

- **[`docs/LAUNCH_CHECKLIST.md`](docs/LAUNCH_CHECKLIST.md)** — everything deferred to the
  launch/device/go-live phase: provider accounts, secrets & env, open product decisions,
  on-device QA, store-listing content. **Start here for "what we still need at the end".**
- [`docs/SECRETS.md`](docs/SECRETS.md) — secret inventory & injection policy
- [`docs/IDENTIFIERS.md`](docs/IDENTIFIERS.md) — bundle IDs / Team ID
- [`docs/OTA_POLICY.md`](docs/OTA_POLICY.md) · [`docs/COMPATIBILITY.md`](docs/COMPATIBILITY.md) — OTA rules + version matrix
- [`docs/ASSETS.md`](docs/ASSETS.md) — icon/splash art & regeneration
- [`docs/SERVER_CONFIG.md`](docs/SERVER_CONFIG.md) — in-app server switcher
- [`docs/SYNAPLAN_BLAST_RADIUS.md`](docs/SYNAPLAN_BLAST_RADIUS.md) — changes to the public submodule
