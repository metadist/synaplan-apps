---
epic: 14
title: Self-hosted Capgo OTA update server
sprint: null
aspect: null
status: planned
depends_on: [8]
repos:
  - synaplan-apps (private)
  - synaplan-platform (private, deployment)
estimate: L
---

# Epic 14 — Self-hosted Capgo OTA update server

> Epic 8.1 wired the `@capgo/capacitor-updater` plugin against **Capgo Cloud** and documented
> self-hosting as the migration path ("just an `updateUrl`/`channelUrl` override — no app code
> change", see `docs/OTA_POLICY.md`). This epic executes that migration path: run the Capgo
> backend (github.com/Cap-go/capgo) on our own servers.

## Analysis — what self-hosted Capgo actually is

Capgo's production runs on Cloudflare Workers + Supabase, but per their README
**"When self-hosted, installing only Supabase is sufficient."** The self-hosted product is
three pieces:

1. **A self-hosted Supabase stack** (the standard `supabase/docker` Compose bundle) that Capgo's
   database migrations, storage buckets, and Deno edge functions are deployed onto. The edge
   functions ARE the Capgo API — including the plugin endpoints our apps call
   (`updates`, `stats`, `channel_self`).
2. **The Capgo web console** — a static Vue 3 SPA (`src/` in the Capgo repo, built with `bun`)
   that talks to the Supabase instance. Served by any static web server.
3. **The Capgo CLI** (`@capgo/cli`, already used by our `ota:upload` npm script) pointed at our
   instance instead of Capgo Cloud.

The `cloudflare_workers/` layer is an **optional** cost/scale optimization for Capgo's ~50M
devices; we do not need it.

## Services that must run on our servers

### Docker containers (Supabase self-hosted stack, one `docker-compose.yml`)

| Service | Image role | Why Capgo needs it |
| --- | --- | --- |
| `db` (Postgres 15+) | `supabase/postgres` | Capgo schema: apps, channels, bundles, devices, orgs, RLS policies, CRON/queue jobs (`pg_cron`, `pg_net`) |
| `kong` | API gateway | Single HTTPS entry point; routes `/auth`, `/rest`, `/storage`, `/functions`, `/realtime` |
| `auth` (GoTrue) | Auth server | Console user accounts / login |
| `rest` (PostgREST) | REST over Postgres | Console CRUD (apps, channels, stats views) |
| `realtime` | WebSockets | Live console updates |
| `storage` + `imgproxy` | Storage API | **The OTA bundle zips live here** (file-backend volume by default; S3 optional) |
| `functions` (Edge Runtime, Deno) | Serverless runtime | Runs `supabase/functions/`: plugin API (`updates`, `stats`, `channel_self`), public API, private console API, triggers/CRON |
| `studio` + `meta` (postgres-meta) | Admin dashboard | DB administration (internal only) |
| `supavisor` | Connection pooler | Postgres pooling |
| `vector` + `analytics` (Logflare) | Logs (optional) | Can be disabled to save resources |

Roughly **10–12 containers**. Supabase's stated minimum: **2 CPU / 4 GB RAM / 40 GB SSD**;
recommended 4 CPU / 8 GB. Bundle storage grows with every OTA release — plan disk accordingly.

### Our own additions on top

| Service | Purpose |
| --- | --- |
| Static web server (Caddy/nginx container) | Serves the built Capgo console SPA |
| Reverse proxy + TLS | Three public hostnames: `console.<domain>` (SPA), `api.<domain>` (plugin/public API → Kong/functions), `sb.<domain>` (Supabase/Kong for console auth+REST) |
| Backups | `pg_dump` + storage volume snapshot (bundles) |

### Build/CI tooling (not runtime services)

- **Docker + Docker Compose** on the host.
- **bun** + **Supabase CLI** — to run migrations, deploy functions, build the console.
- **`@capgo/cli`** in CI — uploads bundles to our instance (already in `package.json` scripts).

### External/optional dependencies

- **Cloudflare Turnstile** (`CAPTCHA_KEY`) — console signup captcha. Optional.
- **Bento** (`BENTO_*` keys) — org-invitation emails only; without it, invites are silently not
  sent. Acceptable for an internal instance (create users directly).
- **S3-compatible storage** — only if we outgrow the local file backend.

### What the mobile app needs (already 90% done in Epic 8.1)

Only a config override in `capacitor.config.ts` — no code change:

```ts
CapacitorUpdater: {
  updateUrl: 'https://api.<domain>/updates',
  statsUrl: 'https://api.<domain>/stats',
  channelUrl: 'https://api.<domain>/channel_self',
  // publicKey stays as-is (signing is ours either way)
}
```

## Key risks / open decisions (resolve before Phase 1)

- **Cloud-first repo, self-host second.** `configs.json` defaults to Capgo production values;
  every value must be overridden via env (`BASE_DOMAIN`, `SUPA_URL`, `SUPA_ANON`, `API_DOMAIN`)
  or the instance silently talks to capgo.app. The repo moves fast (16k commits, >1000
  releases) — we must **pin a release tag** and treat upgrades as deliberate maintenance.
- **Function deployment on self-hosted Supabase** is file-based (functions mounted into the
  edge-runtime volume), not `supabase functions deploy` like cloud — needs a smoke-tested
  deploy script.
- **AGPL-3.0**: running it for ourselves is fine; if we modify Capgo and expose it as a network
  service, we must publish those modifications.
- **Cost/benefit**: the v4.0 decision (OTA_POLICY.md) was Capgo Cloud first. Self-hosting trades
  a subscription for a VM + ongoing Supabase/Capgo maintenance. Confirm the trigger (privacy,
  cost, EU hosting?) before investing.
- **Where to host**: a **dedicated VM/compose stack**, managed like the other services in
  `synaplan-platform` — NOT co-located with the Galera web nodes (Supabase brings its own
  Postgres and its own Kong on 80/443-adjacent ports).

## Tasks

### 14.1 — Provision host + base Supabase stack — ✅ DONE 2026-07-07

- [x] Dedicated VM: `capgo.synaplan.com` (`syncapgo`, 4 vCPU / 7.6 GB / 150 GB,
      Ubuntu 26.04, `ssh -p16803`), Docker + Compose, cluster firewall + NFS at `/wwwroot`.
      Documented in `synaplan-platform/CLUSTER-DOC.md`.
- [x] `supabase/docker` deployed under `/opt/capgo/supabase` — fresh JWT secret, anon/service
      keys, DB + dashboard passwords (all in `/opt/capgo/secrets.env` on the box, chmod 600).
- [x] DNS + TLS: wildcard `*.capgo.synaplan.com` → box; Caddy auto-ACME for
      `capgo.` (console), `api.` (plugin API), `sb.` (Kong). Studio not publicly exposed.
- [ ] Disable public signup in GoTrue (invite-only console) — currently signup is OPEN with
      email autoconfirm; lock down before real use. **← remaining**

### 14.2 — Deploy Capgo onto the stack — ✅ DONE 2026-07-07

- [x] `Cap-go/capgo` cloned at pinned tag **`capgo-12.190.2`** (`/opt/capgo/capgo`).
- [x] All 335 migrations applied via psql (CLI `db push` refuses non-TLS DB); `capgo` storage
      bucket + `plans` seeded. Two quirks: one `CREATE INDEX CONCURRENTLY` file must run
      un-wrapped, and `psql -1` per file otherwise.
- [x] Functions rsynced into `volumes/functions/` (stock `main/` router kept); Capgo env
      injected via `docker-compose.override.yml` (**must stay listed in `.env` `COMPOSE_FILE`**);
      storage S3-protocol creds wired for bundle upload.
- [x] Smoke-tested externally: `/ok` → `{"status":"ok"}`; `/updates` → structured responses
      (`on_premise_app` → after app registration `no_channel`, both correct).

### 14.3 — Build + deploy the console — ✅ DONE 2026-07-07

- [x] Console built on the box (bun 1.3.14) with `BASE_DOMAIN/SUPA_URL/SUPA_ANON/API_DOMAIN`
      overrides; verified the bundle references `sb.capgo.synaplan.com`, not Capgo prod.
- [x] Served from `/opt/capgo/console` via `capgo-caddy` at `https://capgo.synaplan.com`.
- [x] Admin account `admin@synaplan.com` (password in `secrets.env`), org
      `Synaplan organization`, app `com.synaplan.app` registered, upload apikey created
      (`CAPGO_APIKEY` in `secrets.env`). `.dev`/`.staging` app ids not registered yet.

### 14.4 — Wire the app + CI

- [ ] Override `updateUrl`/`statsUrl`/`channelUrl` in `capacitor.config.ts` (behind
      `SYNAPLAN_ENV` if staging should hit a staging channel).
- [ ] Point `ota:upload` / CI at our instance (CLI `--supa-host`/`--supa-anon` or CLI config —
      verify against the pinned CLI version) with an apikey from our console.
- [ ] Keep the existing signing flow (`ota:key:create`, `.capgo_key_v2` per `docs/SECRETS.md`).
- [ ] Device round-trip per OTA_POLICY.md: publish bundle → cold start picks it up → publish a
      broken bundle → auto-revert via `appReadyTimeout`.

### 14.5 — Ops hardening + docs

- [ ] Nightly `pg_dump` + storage-volume backup; restore drill once.
- [ ] Monitoring/alerts on the update endpoint (an outage = no OTA, apps fall back to builtin
      bundle — degraded, not broken).
- [ ] Documented upgrade runbook (new Capgo tag → migrations → functions → console rebuild).
- [ ] Update `docs/OTA_POLICY.md` (hosting section) + `docs/SECRETS.md` (instance credentials);
      record the switch in `docs/COMPATIBILITY.md`.

## Definition of done

- App on a physical device receives an OTA bundle from `api.<domain>` and auto-reverts a broken
  one, with Capgo Cloud fully out of the loop.
- Backups + upgrade runbook exist; all secrets in the secret store per `docs/SECRETS.md`.
