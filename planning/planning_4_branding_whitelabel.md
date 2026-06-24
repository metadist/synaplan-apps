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
> config — the name, logos, colors, fonts, and "Powered by synaplan" footers are **hardcoded**
> across the frontend. This epic introduces a single, config-driven branding layer.
>
> **New in this revision:** the **server emits the brand** — **name, color(s), fonts, logo, and the
> platform start page** — and these are **easily editable by the Admin** of any `synaplan` server
> from the System Config UI. The **core Open Source product is brandable too** (not just the app):
> the same config drives the web app, the PWA, and the mobile app. The mobile app re-fetches this
> brand whenever its configured server changes (Epic 3, §3.0).

## Goal

A **server Admin** can change the displayed brand — **name, accent color(s), fonts, logo, and the
start/landing page** — and the attribution line (e.g. `<Their Brand> · powered by Synaplan`) from
the **System Config UI** (no source edits, no rebuild) — and the SaaS `web.synaplan.com` keeps its
default "Synaplan" branding. This applies to the **core open-source web product** and the **mobile
app** alike; the app inherits whatever brand the configured backend emits.

## v4.0 context / Why

"Flexible and Open Source" is a v4.0 promise. White-label is what makes the same binary + same
public repo usable by Synaplan and by independent hosters. It also interacts with store review:
the app must show **the platform's** branding, and the attribution must be honest.

## Scope (entirely in the `synaplan` public repo)

### In scope

- A backend **branding config group** (BCONFIG) with sane defaults.
- Expose `branding` in `GET /api/v1/config/runtime`.
- **Admin-editable branding**: name, colors, **fonts**, logo, and **start/landing page** editable
  from the System Config UI (no rebuild).
- Frontend: consume branding from config; replace hardcoded brand touchpoints. **Applies to the
  core open-source web app + PWA + mobile app.**
- A configurable **attribution** line: brand name + optional "powered by Synaplan" (label + URL),
  with a flag to show/hide.
- Runtime accent color(s) + **font family/web-font** + logo via brand config (with safe fallback to
  current assets).
- A configurable **start page** (logged-out landing entry) and **default post-login route**.

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
| Font family / web font | `synaplan/frontend/src/style.css` (`font-family` / `--font-*`) + any `<link>`/`@font-face` in `index.html` |
| Start page / default route | `synaplan/frontend/src/router/index.ts` (default/redirect route) + logged-out landing entry |
| i18n product-name strings (4 locales) | `src/i18n/{en,de,es,tr}.json` |

## Tasks

### 4.1 — Backend branding config (BCONFIG) + endpoint

- [ ] Add a **`branding` config group** (BCONFIG, idempotent seed in `backend/src/Seed/`):
      - **Identity:** `BRAND_NAME` (default `Synaplan`), `BRAND_TAGLINE`/description,
        `BRAND_HOMEPAGE_URL` (default `https://www.synaplan.com`).
      - **Color:** `BRAND_PRIMARY_COLOR` (default `#003fc7`), optional `BRAND_SECONDARY_COLOR` /
        `BRAND_ACCENT_COLOR` for a fuller palette.
      - **Fonts (new):** `BRAND_FONT_FAMILY` (default = current stack), optional `BRAND_FONT_URL`
        (a stylesheet URL for a self-hosted/Google web font) and `BRAND_HEADING_FONT_FAMILY`.
        Document that any external font origin must be added to the CSP allow-list (Epic 1/7) and,
        for the app, to the configured server's allowed origins.
      - **Logos:** `BRAND_LOGO_URL` / `BRAND_LOGO_DARK_URL` / `BRAND_ICON_URL`.
      - **Start page (new):** `BRAND_LANDING_PAGE` (logged-out entry, default = current landing)
        and `BRAND_DEFAULT_ROUTE` (post-login start, default = current default route).
      - **Attribution:** `BRAND_SHOW_POWERED_BY` (bool, default `true`),
        `BRAND_POWERED_BY_LABEL` (default `Synaplan`),
        `BRAND_POWERED_BY_URL` (default `https://www.synaplan.com`).
- [ ] Surface them all in `backend/src/Controller/ConfigController.php` → `getRuntimeConfig()` under
      a `branding` key. **No auth required** (it's already a public endpoint) — this is what the
      mobile app reads against its configured server (Epic 3).
- [ ] **Admin UI (the "easily configurable" requirement):** add a **Branding** section to System
      Config so an Admin can edit name, colors, fonts, logo URLs, start/landing page, and the
      powered-by fields — alongside the existing `APP_SENDER_NAME` field
      (`backend/src/Service/Admin/SystemConfigService.php`). Validate inputs (hex colors, URLs,
      known route names) and show a live/preview hint where cheap.

### 4.2 — Frontend config plumbing

- [ ] Extend the runtime-config Zod schema + `synaplan/frontend/src/stores/config.ts` with a
      `branding` getter (additive; defaults reproduce today's look). After the schema change run
      `make -C frontend generate-schemas` then re-run `vue-tsc`.
- [ ] Replace `APP_NAME` usage in `router/index.ts` + `App.vue` to read `config.branding.name`
      (keep a build-time fallback so the static `index.html` title still works pre-hydration).
- [ ] Inject `--brand*` CSS variables at runtime from `config.branding.primaryColor` (+ secondary/
      accent if set) — root style override on boot, falling back to the current `style.css` values.
- [ ] **Fonts:** inject `font-family` (body + heading) from `config.branding.fontFamily` /
      `headingFontFamily`, and if `fontUrl` is set, inject a `<link rel="stylesheet">` for it at
      boot (guarded by CSP allow-list). Fall back to the current font stack when unset.
- [ ] **Start page:** make the router honor `config.branding.landingPage` (logged-out entry) and
      `config.branding.defaultRoute` (post-login redirect target), falling back to today's defaults.
      Validate the configured route exists; ignore unknown values (fail safe to default).

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

- An **Admin** can set, from the System Config UI (no rebuild): `BRAND_NAME`, colors, **fonts**,
  logos, **start/landing page**, and the powered-by fields — and these change the **document
  title, accent color(s), fonts, logos, default route, and attribution** across login, register,
  logged-out, shared-chat, and the widget.
- Default (unconfigured) deployment looks **identical to today** (`Synaplan`, `#003fc7`, current
  font stack, current default route, "Powered by synaplan", synaplan.com links).
- A self-hoster can produce `<Brand> · powered by Synaplan` (label + link), or hide the
  attribution entirely if their tier permits.
- **Core OSS web app is brandable**, not just the mobile app — the same config drives web + PWA.
- The **mobile app**, pointed at a branded backend, shows that backend's brand, and **re-applies
  the brand when its configured server changes** (Epic 3, §3.0).
- A configured **start page / default route** is honored; an invalid value fails safe to the
  default (no broken navigation).
- A configured **font** loads (incl. external `fontUrl` once CSP-allowed) and falls back cleanly
  when unset or blocked.
- All four locales updated; no hardcoded "Powered by" English left in the listed views.

## Test notes (for the QA person)

- Run with **no branding config** → must match current production look (regression).
- Set a fake brand (name "Acme", red accent, **custom font + fontUrl**, custom logo URL, **custom
  start page**, powered-by "Synaplan" + URL) → verify every touchpoint, light + dark mode.
- **Admin edit flow**: change each field in System Config and confirm it round-trips to the runtime
  config and renders (no rebuild).
- **Start page**: set `BRAND_DEFAULT_ROUTE` / `BRAND_LANDING_PAGE`, verify redirect; set an invalid
  route → must fall back to default, not 404/blank.
- **Font**: set `BRAND_FONT_URL` to an allowed origin → font applies; to a blocked origin → falls
  back gracefully (and surfaces the CSP requirement).
- **App re-fetch on server switch**: in the app, switch from `web.synaplan.com` to a branded test
  server → brand updates; switch back → default returns.
- Verify `og:site_name` / shared-chat SSR reflect the brand (check backend
  `SharedChatPageController.php` output).
- Verify the widget footer can be hidden/re-attributed and the default still shows "Powered by
  synaplan".
- Run all five gates per [Epic 12](planning_12_quality_gates.md): frontend lint + `vue-tsc` +
  Vitest (parse/format), Playwright click-through of a branded vs default deployment, config-parse
  tests for the branding schema, and the AI logic review of the default-safety guarantee. After the
  runtime-config schema change run `make -C frontend generate-schemas` then re-run type check.

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
- **Fonts:** ship a curated allow-list of safe web-font sources (self-host + a couple of providers)
  vs. let the Admin enter any `fontUrl` (CSP/privacy trade-off)?
- **Start page:** is the configurable start page a *route name* from a fixed set, or a free-form
  path? (Free-form risks dead links; a fixed set is safer but less flexible.)
- Which branding fields, if any, should be **per-widget overridable** vs **global only**?
