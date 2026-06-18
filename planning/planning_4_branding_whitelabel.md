---
epic: 4
title: White-Label Branding & Attribution
sprint: "Sprint 4"
aspect: 2
status: planned
depends_on: [2]
repos:
  - synaplan (public)
estimate: L
---

# Epic 4 — White-Label Branding & Attribution

> **Owns Aspect 2:** *"The platform must emit the branding of the platform. Open-source hosters
> must be able to add a kind of 'Synaplan powered by Cristian'."* Today there is **no** branding
> config — the name, logos, colors, and "Powered by synaplan" footers are **hardcoded** across
> the frontend. This epic introduces a single, config-driven branding layer.

## Goal

A self-hoster can change the displayed brand (name, logo, accent color) and the attribution line
(e.g. `<Their Brand> · powered by Synaplan`) from configuration — no source edits, no rebuild —
and the SaaS `web.synaplan.com` keeps its default "Synaplan" branding. The app inherits whatever
brand the backend it points to emits.

## v4.0 context / Why

"Flexible and Open Source" is a v4.0 promise. White-label is what makes the same binary + same
public repo usable by Synaplan and by independent hosters. It also interacts with store review:
the app must show **the platform's** branding, and the attribution must be honest.

## Scope (entirely in the `synaplan` public repo)

### In scope

- A backend **branding config group** (BCONFIG) with sane defaults.
- Expose `branding` in `GET /api/v1/config/runtime`.
- Frontend: consume branding from config; replace hardcoded brand touchpoints.
- A configurable **attribution** line: brand name + optional "powered by Synaplan" (label + URL),
  with a flag to show/hide.
- Runtime accent color + logo via brand config (with safe fallback to current assets).

### Out of scope (deferred)

- The actual high-res logo/icon files & app store assets → **Epic 6** (this epic makes them
  config-addressable; Epic 6 produces them).
- Per-widget branding already exists (colors/icon/title); we only add the ability to **hide /
  re-attribute** the widget "Powered by" footer here.

## Current hardcoded touchpoints (must be replaced)

| Touchpoint | File |
|------------|------|
| App name constant | `synaplan/frontend/src/router/index.ts` (`APP_NAME = 'Synaplan'`) + `App.vue` (`document.title`) |
| Static HTML title / apple-web-app-title / description | `synaplan/frontend/index.html` |
| PWA name/short_name/description | `synaplan/frontend/public/site.webmanifest` |
| Auth "Powered by" + logo + `synaplan.com` link | `LoginView.vue`, `RegisterView.vue` |
| Logged-out "Powered by Synaplan" | `LoggedOutView.vue` (i18n `auth.poweredBySynaplan`) |
| Shared-chat footer + `og:site_name` | `SharedChatView.vue` + backend `SharedChatPageController.php` |
| Widget "Powered by synaplan" (no hide flag today) | `components/widgets/ChatWidget.vue` |
| Brand accent color | `synaplan/frontend/src/style.css` (`--brand` etc.) + `index.html` theme-color + manifest |
| i18n product-name strings (4 locales) | `src/i18n/{en,de,es,tr}.json` |

## Tasks

### 4.1 — Backend branding config (BCONFIG) + endpoint

- [ ] Add a **`branding` config group** (BCONFIG, idempotent seed in `backend/src/Seed/`):
      `BRAND_NAME` (default `Synaplan`), `BRAND_TAGLINE`/description, `BRAND_PRIMARY_COLOR`
      (default `#003fc7`), `BRAND_LOGO_URL` / `BRAND_LOGO_DARK_URL` / `BRAND_ICON_URL`,
      `BRAND_HOMEPAGE_URL` (default `https://www.synaplan.com`),
      `BRAND_SHOW_POWERED_BY` (bool, default `true`),
      `BRAND_POWERED_BY_LABEL` (default `Synaplan`),
      `BRAND_POWERED_BY_URL` (default `https://www.synaplan.com`).
- [ ] Surface them in `backend/src/Controller/ConfigController.php` → `getRuntimeConfig()` under a
      `branding` key. **No auth required** (it's already a public endpoint).
- [ ] Add an admin UI surface (System Config) to edit these, alongside the existing
      `APP_SENDER_NAME` field (`backend/src/Service/Admin/SystemConfigService.php`).

### 4.2 — Frontend config plumbing

- [ ] Extend the runtime-config Zod schema + `synaplan/frontend/src/stores/config.ts` with a
      `branding` getter (additive; defaults reproduce today's look).
- [ ] Replace `APP_NAME` usage in `router/index.ts` + `App.vue` to read `config.branding.name`
      (keep a build-time fallback so the static `index.html` title still works pre-hydration).
- [ ] Inject `--brand*` CSS variables at runtime from `config.branding.primaryColor` (root style
      override on boot), falling back to the current `style.css` values.

### 4.3 — Replace "Powered by" / attribution blocks

- [ ] Build a single small `<BrandAttribution>` component that renders:
      `{brand.name}` + (if `showPoweredBy`) `· powered by <poweredByLabel>` linking to
      `poweredByUrl`. This is the `"Synaplan powered by Cristian"` pattern, generalized.
- [ ] Use it in `LoginView.vue`, `RegisterView.vue`, `LoggedOutView.vue`, `SharedChatView.vue`
      (footer + `og:site_name`), and the widget footer in `ChatWidget.vue`.
- [ ] Move the hardcoded English "Powered by" strings to i18n and parameterize the brand name
      (update all four locales `en/de/es/tr`).
- [ ] Replace hardcoded `synaplan.com` links in those views with `config.branding.homepageUrl`.

### 4.4 — Logos & favicons addressable by config

- [ ] Make logo `<img src>` read `config.branding.logoUrl` / `logoDarkUrl` with fallback to the
      existing `synaplan-light.svg` / `synaplan-dark.svg` / `single_bird*.svg`.
- [ ] Document that swapping favicons/PWA icons + app icons is Epic 6's asset pipeline; this epic
      only makes them config-pointable.

### 4.5 — Widget attribution policy

- [ ] Add a per-widget / global flag to **hide or re-attribute** the widget "Powered by synaplan"
      footer (today it's always shown with no flag — this is also the long-promised "White-label
      Widgets" billing feature, currently marketing-only). Gate it behind the appropriate tier if
      that's the business rule.

## Acceptance criteria (Definition of Done)

- Setting `BRAND_NAME`, `BRAND_PRIMARY_COLOR`, `BRAND_LOGO_URL`, and the powered-by fields via
  config changes the **document title, accent color, logos, and attribution** across login,
  register, logged-out, shared-chat, and the widget — **without a frontend rebuild**.
- Default (unconfigured) deployment looks **identical to today** (`Synaplan`, `#003fc7`,
  "Powered by synaplan", synaplan.com links).
- A self-hoster can produce `<Brand> · powered by Synaplan` (label + link), or hide the
  attribution entirely if their tier permits.
- The app, pointed at a branded backend, shows that backend's brand.
- All four locales updated; no hardcoded "Powered by" English left in the listed views.

## Test notes (for the QA person)

- Run with **no branding config** → must match current production look (regression).
- Set a fake brand (name "Acme", red accent, custom logo URL, powered-by "Synaplan" + URL) →
  verify every touchpoint, light + dark mode.
- Verify `og:site_name` / shared-chat SSR reflect the brand (check backend
  `SharedChatPageController.php` output).
- Verify the widget footer can be hidden/re-attributed and the default still shows "Powered by
  synaplan".
- Frontend lint + `vue-tsc` + Vitest; after the runtime-config schema change run
  `make -C frontend generate-schemas` then re-run type check (per repo rules).

## Risks & mitigations

- **Regression of the default look:** defaults must reproduce today exactly; gate with the
  no-config test.
- **Pre-hydration title flash:** keep a build-time default in `index.html`; only override after
  config loads.
- **Anti-steering interaction (store):** the attribution/links must not become a path to web
  payment inside the app — coordinate with Epic 5 + Epic 9.
- **i18n drift:** a key missing from one of `en/de/es/tr` silently falls back to English — update
  all four.

## Open questions

- Is hiding the "powered by" a paid (BUSINESS-tier) capability for SaaS customers, but free for
  self-hosters? (Business rule to confirm.)
- Should the attribution default to `<Brand> · powered by Synaplan` even on `web.synaplan.com`
  (where Brand == Synaplan, so it collapses to just "Synaplan")?
