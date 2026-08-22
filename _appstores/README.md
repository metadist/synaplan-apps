# `_appstores/` — Store Release Assets & Metadata

Everything needed to publish the Synaplan app to the **Apple App Store** and **Google Play**,
in one place. This directory is **public / open source** — except for `.local/`, which is
git-ignored and holds certificates, keys, and passwords (see below).

Launch copy source of truth: [`docs/STORE_LISTINGS.md`](../docs/STORE_LISTINGS.md).
Asset generation & re-branding guide: [`docs/ASSETS.md`](../docs/ASSETS.md).
Secrets policy: [`docs/SECRETS.md`](../docs/SECRETS.md).

## Layout

```
_appstores/
├── .local/                     # NEVER committed (gitignored): certs, keys, passwords, account notes
├── apple/
│   ├── icon/                   # App Store marketing icon (1024×1024)
│   ├── metadata/               # Listing texts per locale (fastlane deliver layout)
│   │   ├── en-US/  de-DE/  es-ES/  tr/
│   └── screenshots/
│       ├── en-US/  de-DE/  es-ES/  tr/
│       │   ├── iphone-6.9/     # 1320×2868 portrait (required)
│       │   └── ipad-13/        # 2064×2752 portrait (only if iPad is supported)
├── google/
│   ├── icon/                   # Play hi-res icon (512×512)
│   ├── feature-graphic/        # 1024×500 (required by Play)
│   ├── metadata/               # Listing texts per locale (fastlane supply layout)
│   │   ├── en-US/  de-DE/  es-ES/  tr-TR/
│   └── screenshots/
│       ├── en-US/  de-DE/  es-ES/  tr-TR/
│       │   ├── phone/          # ≥2 required, 1080×1920 recommended
│       │   ├── tablet-7/       # optional unless tablet is targeted
│       │   └── tablet-10/      # optional unless tablet is targeted
└── source/
    ├── masters/                # High-res source art (icon/splash masters, PSD/Sketch/Figma exports)
    └── raw-screenshots/        # Unframed device captures, before framing/captioning
```

Locale codes follow each store's convention: App Store Connect uses `en-US, de-DE, es-ES, tr`;
Google Play uses `en-US, de-DE, es-ES, tr-TR`. The layouts match fastlane's `deliver` (Apple)
and `supply` (Google) metadata trees so they can be wired into release automation (Epic 10.5)
without moving files.

## Required images & sizes

### Apple App Store

| Asset | Size (px) | Format | Required | Notes |
|-------|-----------|--------|----------|-------|
| Marketing app icon | **1024×1024** | PNG or JPEG, **no alpha/transparency**, sRGB | Yes | Flat square — Apple applies the rounded mask. No pre-rounded corners. |
| iPhone 6.9" screenshots | **1320×2868** portrait (alt: 1290×2796, 1260×2736; landscape swapped) | PNG or JPEG, no alpha | Yes — min 1, max 10 per locale | The only required iPhone set; Apple auto-scales to all smaller iPhones. Aim for 5. |
| iPad 13" screenshots | **2064×2752** portrait (alt: 2048×2732; landscape swapped) | PNG or JPEG, no alpha | Only if the app runs on iPad | Apple auto-scales to smaller iPads. |
| App preview video (optional) | 886×1920 (6.9" class), 15–30 s | .mov/.m4v/.mp4 | No | Skip for v4.0 launch. |

### Google Play

| Asset | Size (px) | Format | Required | Notes |
|-------|-----------|--------|----------|-------|
| Hi-res icon | **512×512** | 32-bit PNG **with alpha**, ≤1 MB | Yes | Full square, no rounded corners/shadows — Play masks and shadows it. |
| Feature graphic | **1024×500** | JPEG or 24-bit PNG, **no alpha**, ≤15 MB | Yes | Keep logo/message in the center ~80%; avoid pure white/black backgrounds. |
| Phone screenshots | **1080×1920** (9:16) recommended; any side 320–3840, max 2:1 ratio | JPEG or 24-bit PNG, no alpha, ≤8 MB each | Yes — min 2, max 8 | For Play promotional surfaces: ≥4 screenshots at ≥1080 px. |
| 7" tablet screenshots | e.g. **1200×1920**; same limits as phone | JPEG or 24-bit PNG, no alpha | Only if tablet is targeted | Max 8. |
| 10" tablet screenshots | e.g. **1600×2560**; same limits as phone | JPEG or 24-bit PNG, no alpha | Only if tablet is targeted | Max 8. |
| Promo video (optional) | — | Public YouTube URL (no file) | No | Skip for v4.0 launch. |

### Screenshot content plan

Suggested caption flow (≤ ~6 words each, localized — see `docs/STORE_LISTINGS.md`):

1. "Chat with leading AI models"
2. "Answers from YOUR documents"
3. "Speak instead of type"
4. "Generate images in chat"
5. "Your data, your server"

Capture raw shots into `source/raw-screenshots/`, then export framed/captioned finals into the
per-locale store folders. Screenshots without in-image text can be reused across locales.

### Screenshot naming convention

Store-ready files are named `NN-slug.png` inside their locale/device folder — the alphabetical
order **is** the App Store display order, so the number prefix controls the storefront sequence
(fastlane `deliver` uploads in filename order):

```
apple/screenshots/<locale>/<device>/NN-slug.png
  NN     two-digit order (01 = first/hero shot, gapless)
  slug   short kebab-case content tag (chat-home, files, memories, ...)

e.g. apple/screenshots/de-DE/iphone-6.9/01-chat-home.png
```

Raw, unprocessed captures keep the same `NN-slug` plus their real pixel size so the source
device class stays obvious: `source/raw-screenshots/<locale>/<capture-set>/NN-slug-WxH.png`.
Uncategorized one-off captures go to `source/raw-screenshots/unsorted/`. Apple accepts max
**10 screenshots per locale** — if a folder holds more, the surplus must be dropped before upload.

## `.local/` — private, never committed

`_appstores/.local/` is excluded via `.gitignore` (plus the repo-wide `*.p8`/`*.p12`/
`*.keystore`/... patterns as a second net). It is the local working area for:

- Apple distribution certificate (`.p12`), provisioning profiles, App Store Connect API key (`.p8`)
- Android upload keystore (`.jks`/`.keystore`), key alias & passwords, Play service-account JSON
- Store-account notes, passwords, 2FA recovery info

The golden rule from `docs/SECRETS.md` applies: **no secret value ever lands in git**. Back up
the unrecoverable ones (Android keystore, `.p8` key) encrypted and off-machine. Since `.local/`
is fully ignored, recreate it after a fresh clone with `mkdir -p _appstores/.local`.

## Status / TODO

- [x] Export `apple/icon/app-store-icon-1024.png` from the master (white bird on `#003fc7`,
      rendered from `source/masters/single_bird.svg`, 1024×1024 PNG, no alpha)
- [x] Export `google/icon/play-icon-512.png` from the master (512×512, 32-bit PNG with alpha)
- [ ] Design `google/feature-graphic/feature-graphic-1024x500.png`
- [x] Produce iPhone 6.9" screenshot set **de-DE** (12 candidates in
      `apple/screenshots/de-DE/iphone-6.9/` — trim to ≤10 before upload)
- [ ] Produce iPhone 6.9" screenshot sets (en, es, tr)
- [ ] Decide iPad support → produce 13" set if yes (see `docs/STORE_LISTINGS.md` open points)
- [ ] Produce Play phone screenshot sets (en, de, es, tr)
- [ ] Confirm support / privacy-policy / terms URLs (Epic 9.3) and add them to the metadata
