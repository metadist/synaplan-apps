---
epic: 6
title: Graphics, Logos & Store Assets
sprint: "Sprint 6"
aspect: 4
status: planned
depends_on: [0]
repos:
  - synaplan-apps (private)
  - synaplan (public, submodule)
estimate: M
---

# Epic 6 — Graphics, Logos & Store Assets

> **Owns Aspect 4:** *"Graphics and logos should be well sorted for the app release."* Today the
> brand assets are scattered and incomplete: the app-icon PNGs **aren't even committed** (a script
> generates them), there's an orphan `synaplan.svg`/`groq.svg`, and there's no high-res source art
> or store screenshot set. This epic produces a clean, organized, brandable asset system.

## Goal

A single, well-organized asset source-of-truth that produces: app icons (all iOS/Android sizes),
splash screens, favicons/PWA icons, in-app logos, and store listing assets — for **light + dark**,
and structured so a white-label hoster (Epic 4) can swap them cleanly.

## v4.0 context / Why

A polished, consistent icon/splash set is a baseline store expectation and the first thing a
reviewer and a user see. It's also the visual half of the "flexible / white-label" promise: the
asset layout must make re-branding obvious and low-effort.

## Current asset reality (from the submodule)

- **Committed SVG:** `single_bird.svg` (+ `-light`/`-dark`), `synaplan-light.svg`,
  `synaplan-dark.svg`, plus integrations SVGs. Brand color `#0003c7`/`#003fc7`.
- **Orphans (unused):** `synaplan.svg`, `groq.svg`, the Vite default `src/assets/vue.svg`.
- **Generated, NOT committed:** `favicon-32.png`, `apple-touch-icon.png`, `icon-192.png`,
  `icon-512.png` — produced by `synaplan/frontend/scripts/generate-icons.mjs` (sharp), **not wired
  into `npm run build`**.
- **PWA:** `synaplan/frontend/public/site.webmanifest` (name/short_name/description/icons/theme).
- No 1024×1024 source icon, no splash source, no store screenshots.

## Scope

### In scope

- Define/collect **high-res source art**: 1024×1024 master icon (light+dark/adaptive), splash
  master, wordmark masters.
- Generate the full native icon + splash set via `@capacitor/assets` (synaplan-apps).
- Fix/commit the web favicon + PWA icon set; wire icon generation into the build (or commit
  outputs) so they're reproducible.
- Organize assets into a clear directory layout + a short `docs/ASSETS.md` (sizes, sources,
  regen commands, white-label swap guide).
- Produce store listing assets (screenshots, feature graphic) per platform/locale.

### Out of scope (deferred)

- Making logos config-pointable in the running app → done in **Epic 4** (this epic produces the
  files Epic 4 points to).

## Tasks

### 6.1 — Master source art

- [ ] Produce a **1024×1024** master app icon (no transparency for iOS; safe-zone padding for
      Android **adaptive** icon foreground/background). Light + dark variants.
- [ ] Produce a **splash** master (single centered logo on brand background; respects safe areas).
- [ ] Tidy wordmark masters (`synaplan-light/dark.svg`) and the bird mark; remove/relocate the
      orphan `synaplan.svg` / `groq.svg` (decide: delete or move to an `unused/` archive).

### 6.2 — Native icons + splash (synaplan-apps)

- [ ] Add `@capacitor/assets`; place source art under `assets/` (e.g.
      `assets/icon.png`, `assets/icon-dark.png`, `assets/splash.png`, `assets/splash-dark.png`).
- [ ] Generate iOS + Android icon and splash sets; commit the generated native assets (or
      document the regen step in `build.sh` / `docs/ASSETS.md`).
- [ ] Verify Android **adaptive icon** (foreground/background) and iOS icon render correctly on
      device home screens, light + dark.

### 6.3 — Web favicon / PWA icons (synaplan submodule)

- [ ] Either **wire `generate-icons.mjs` into the frontend build** or commit the generated PNGs
      (`favicon-32.png`, `apple-touch-icon.png`, `icon-192.png`, `icon-512.png`) so a clean clone
      isn't missing them. (Currently they're referenced by `index.html` + `site.webmanifest` but
      absent from the repo.)
- [ ] Reconcile the brand color typo: `index.html` theme-color `#003fc7` vs `site.webmanifest`
      `#0003c7` — pick the correct one and align (also relevant to Epic 4's `--brand`).

### 6.4 — Organization + white-label readiness

- [ ] Establish a clear asset layout and write `docs/ASSETS.md`: every required size, its source
      master, the regen command, and a **"how to re-brand"** section (swap masters → regenerate →
      where the running-app brand assets are pointed, cross-linking Epic 4).
- [ ] Ensure the layout cleanly separates **Synaplan-default** assets from **hoster-overridable**
      slots so white-labeling doesn't require editing generated files.

### 6.5 — Store listing assets

- [ ] Screenshots for required device sizes (iPhone, iPad if supported; Android phone/tablet) +
      Android feature graphic, per launch locale (de/en/es/tr — align with store metadata in
      Epic 10).
- [ ] App Store / Play icon (1024×1024 / 512×512) exported from the master.

## Acceptance criteria (Definition of Done)

- A complete, committed (or reproducibly generated) icon + splash set for iOS + Android renders
  correctly on real devices, light + dark, including Android adaptive icon.
- The web favicon + PWA icon set is no longer missing from a clean clone.
- `docs/ASSETS.md` documents all sizes, sources, regen commands, and the white-label swap process.
- Brand color is consistent across `index.html`, `site.webmanifest`, and `--brand`.
- Store listing assets exist for all launch locales.
- Orphan assets are removed or archived.

## Test notes (for the QA person)

- Install on real iOS + Android devices; check the home-screen icon (incl. dark mode + Android
  adaptive icon masking), splash, and PWA "add to home screen" icon for the web build.
- Confirm a clean `git clone` of the submodule + build has all favicons/PWA icons present.
- Spot-check store-listing screenshots render at the required resolutions without distortion.

## Risks & mitigations

- **iOS icon transparency / Android safe-zone mistakes** → use `@capacitor/assets` from correct
  masters; verify on device.
- **Missing generated PNGs in clean clone** (current bug) → wire generation into build or commit.
- **White-label friction** → separate default vs overridable asset slots (6.4).

## Open questions

- Final source art ownership/handoff (who provides the 1024px master + splash)?
- Do we ship iPad/tablet layouts at launch (affects required screenshot sets)?
