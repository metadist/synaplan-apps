# Graphics & Logos — Inventory and Asset Pipeline

> Discovery half of **Aspect 4 / Epic 6**. This documents the *current* asset reality in the
> `synaplan` submodule, the gaps that block a store release, and the target layout for a clean,
> brandable (white-label, Epic 4) asset system.

## Current asset reality (in `synaplan/frontend/public/`)

### Committed and present

| File | Purpose | Notes |
|------|---------|-------|
| `single_bird.svg`, `single_bird-light.svg`, `single_bird-dark.svg` | Bird mark (favicon + in-app) | Primary icon mark |
| `synaplan-light.svg`, `synaplan-dark.svg` | Wordmark (light/dark) | In-app logos |
| `synaplan.svg` | **Orphan** wordmark | Appears unused — archive or delete (Epic 6) |
| `groq.svg` | **Orphan** provider logo | Appears unused — archive or delete (Epic 6) |
| `favicon-32.png` | Browser favicon fallback | **Now committed** (planning doc said generated-only — outdated) |
| `apple-touch-icon.png` | iOS home-screen (web/PWA) | Committed |
| `icon-192.png`, `icon-512.png` | PWA icons | Committed |
| `og-image.png` | Social share image (1.2 MB) | Committed |
| `integrations/nextcloud.svg`, `integrations/opencloud.svg` | Integration logos | Committed |
| `src/assets/vue.svg` | **Orphan** Vite default | Delete (Epic 6) |

### Generation script

- `synaplan/frontend/scripts/generate-icons.mjs` (uses `sharp`) regenerates the PNG icon set.
  It is **not wired into `npm run build`**; the PNGs are currently committed instead. Decide in
  Epic 6: wire into build *or* keep committing outputs (reproducibility).

### Gaps blocking a store release (hand-off to Epic 6)

- ❌ No **1024×1024 master app icon** (light + dark / Android adaptive foreground+background).
- ❌ No **splash screen** master.
- ❌ No native iOS/Android icon + splash sets (generated via `@capacitor/assets` in Epic 6).
- ❌ No **store listing assets** (screenshots per device size, Android feature graphic) for
  the launch locales `de/en/es/tr`.

## Known inconsistency — brand color (fix in Epic 6, align with Epic 4 `--brand`)

| Location | Value |
|----------|-------|
| `index.html` `<meta name="theme-color">` | `#003fc7` |
| `public/site.webmanifest` `theme_color` | `#0003c7` |
| `src/style.css` `--brand` | _verify in Epic 4_ |

➡️ These disagree (`#003fc7` vs `#0003c7`). Pick the canonical brand color and align all three
plus the runtime `branding.primaryColor` default (Epic 4).

## Hardcoded brand touchpoints (hand-off to Epic 4)

These must become config-driven (white-label) in Epic 4:

- `frontend/src/router/index.ts` — `APP_NAME = 'Synaplan'`
- `frontend/src/App.vue` — `document.title`
- `frontend/index.html` — `<title>`, `apple-mobile-web-app-title`, description
- `frontend/public/site.webmanifest` — name/short_name/description
- "Powered by" + `synaplan.com` links in `LoginView.vue`, `RegisterView.vue`,
  `LoggedOutView.vue`, `SharedChatView.vue`, `components/widgets/ChatWidget.vue`
- Backend `SharedChatPageController.php` — `og:site_name`
- `src/i18n/{en,de,es,tr}.json` — product-name + "Powered by" strings
- `src/style.css` — `--brand` accent color

## Target layout (to be created in Epic 6)

```
synaplan-apps/
  assets/
    icon.png           # 1024×1024 master, light
    icon-dark.png      # 1024×1024 master, dark
    splash.png         # splash master, light
    splash-dark.png    # splash master, dark
    unused/            # archived orphans (synaplan.svg, groq.svg, vue.svg)
```

`@capacitor/assets` consumes `assets/` and emits the native `ios/`+`android/` icon and splash
sets. White-label hosters override the masters (Epic 4 points the running app at config URLs;
this layout keeps default vs. overridable assets separate).

## Open questions (Epic 6)

- Who provides the 1024px master icon + splash source art?
- Ship iPad/tablet layouts at launch? (affects required screenshot sets)
