# Graphics, Logos & Asset Pipeline (Epic 6)

> Owns **Aspect 4** — *"Graphics and logos should be well sorted for the app release."*
> This is the single source of truth for how app icons, splash screens, web favicons/PWA
> icons and store assets are produced, where they live, and how a white-label hoster
> (Epic 4) re-brands them with minimal effort.

## Source of truth

All raster output is derived **deterministically** from a small set of committed vector
masters in the `synaplan` submodule — there is no hand-drawn PNG art:

| Master (in `synaplan/frontend/public/`) | Fill | Used for |
|------|------|----------|
| `single_bird.svg` | brand `#0003c7` | web favicon / PWA mark |
| `single_bird-light.svg` | white `#ffffff` | mark on the **brand background** (app icon, splash) |
| `single_bird-dark.svg` | near-black `#0d0d0d` | mark on light backgrounds |
| `synaplan-light.svg` / `synaplan-dark.svg` | — | in-app wordmark (light/dark) |

**Canonical brand color: `#003fc7`** — consistent across `index.html` `theme-color`,
`site.webmanifest` `theme_color`, `src/style.css` `--brand`, and the Capacitor splash
`backgroundColor`. (The historical `#0003c7` typo in `site.webmanifest` was fixed in Epic 6.)

## Native app icons + splash (synaplan-apps)

Generated via [`@capacitor/assets`](https://github.com/ionic-team/capacitor-assets) from the
masters under `assets/`:

```
synaplan-apps/
  assets/
    icon-only.png        # 1024×1024, white bird on brand background, NO alpha (iOS requirement)
    icon-foreground.png  # 1024×1024, white bird, transparent, sized inside the Android adaptive safe zone
    icon-background.png   # 1024×1024, solid brand #003fc7 (Android adaptive background)
    splash.png            # 2732×2732, white bird centered on brand background
    splash-dark.png       # 2732×2732, identical brand background (brand blue works in both modes)
```

The native sets are **committed** so the build is reproducible without regenerating:

- iOS → `ios/App/App/Assets.xcassets/AppIcon.appiconset/`, `…/Splash.imageset/`
- Android → `android/app/src/main/res/mipmap-*` (incl. `mipmap-anydpi-v26/` adaptive XML) and
  `…/res/drawable-*` splash.

### Regenerate the masters (only if the brand mark changes)

```bash
# from synaplan-apps/, using ImageMagick (`brew install imagemagick`)
SRC=synaplan/frontend/public; BRAND='#003fc7'
magick -background "$BRAND" -density 1200 "$SRC/single_bird-light.svg" -resize 520x594 \
  -gravity center -background "$BRAND" -extent 1024x1024 -alpha remove -alpha off \
  -type TrueColor -depth 8 -strip assets/icon-only.png
magick -background none -density 1200 "$SRC/single_bird-light.svg" -resize 420x480 \
  -gravity center -background none -extent 1024x1024 -type TrueColorAlpha -depth 8 -strip assets/icon-foreground.png
magick -size 1024x1024 "xc:$BRAND" -alpha off -type TrueColor -depth 8 -strip assets/icon-background.png
magick -background "$BRAND" -density 1600 "$SRC/single_bird-light.svg" -resize 560x640 \
  -gravity center -background "$BRAND" -extent 2732x2732 -alpha remove -alpha off \
  -type TrueColor -depth 8 -strip assets/splash.png
cp assets/splash.png assets/splash-dark.png
```

### Regenerate the native sets

```bash
# from synaplan-apps/
npm run assets:generate
```

This wraps `capacitor-assets generate --ios --android` with the brand background colors. PWA
generation is intentionally **skipped** (the `--ios --android` flags exclude it) because there is
no `www/manifest.json` in this shell — the PWA icon set lives in the `synaplan` submodule. The
generator's unused PWA byproducts (`icons/`, `www/`) are git-ignored.

## Web favicon / PWA icons (synaplan submodule)

The PNG set (`favicon-32.png`, `apple-touch-icon.png`, `icon-192.png`, `icon-512.png`) is
**committed** in `synaplan/frontend/public/` so a clean clone/build is never missing them
(referenced by `index.html` + `site.webmanifest`). Regenerate from the bird mark when it changes:

```bash
# from synaplan/frontend/
npm install sharp --no-save && npm run icons:generate
```

## White-label swap (re-branding for a hoster) — cross-links Epic 4

Two complementary layers:

1. **Build-time native assets (this epic):** replace the brand mark(s) under
   `synaplan/frontend/public/` (or point the masters at hoster art), re-run the master +
   `@capacitor/assets` commands above, then `npm run build` + `cap sync`. The brand color
   is passed via the `*BackgroundColor` flags — change them to the hoster's color.
2. **Runtime branding (Epic 4):** the running app reads `branding.*` from the server's
   `runtime-config` (name, colors, fonts, logo/icon URLs, landing page). A hoster who only
   wants their logo *inside* the app does **not** touch generated files — they configure the
   server. Generated native icons/splash remain the installer's brand and are swapped only
   for a true white-label store build.

This separation keeps **Synaplan-default** assets (committed) distinct from
**hoster-overridable** slots (runtime config), so white-labeling never requires editing
generated files.

## Status

- [x] 6.1 Master art (icon light=brand-bg+white-bird; adaptive fg/bg; splash) — committed under `assets/`.
- [x] 6.2 Native iOS + Android icon/splash sets generated via `@capacitor/assets` and committed.
- [x] 6.3 Web favicon/PWA PNGs committed; brand-color typo fixed; `npm run icons:generate` added.
- [x] 6.4 Asset layout + this doc, incl. white-label swap and default/overridable separation.
- [x] Orphans removed: `synaplan.svg`, `groq.svg`, `src/assets/vue.svg`.
- [ ] **6.2 device check (deferred):** verify home-screen icon (light/dark + Android adaptive
      masking) and splash on real iOS/Android devices — part of the on-device QA pass.
- [ ] **6.5 store listing assets (deferred → Epic 10):** per-device screenshots and the Android
      feature graphic for launch locales `de/en/es/tr` require the finished UI on devices/simulators.

## Open questions

- Dedicated dark **app icon** (iOS 18 tinted/dark variant)? Currently one brand-blue icon serves
  both modes (renders well on light + dark home screens).
- Ship iPad/tablet layouts at launch? (affects the required 6.5 screenshot sets)
