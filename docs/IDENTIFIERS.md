# Identifiers & Versioning

> Locked in **Epic 0.2**. Bundle IDs are near-permanent in the stores — do **not** change them
> after a store product exists (Epic 5/10). The User-Agent format (Epic 2) and the
> forced-update gate (Epic 8) depend on the version scheme below.

## App name (store display / home screen)

- **`Synaplan`**

## Bundle / application IDs (per environment)

| Environment | iOS bundle ID / Android applicationId | Notes |
|-------------|----------------------------------------|-------|
| Production  | `com.synaplan.app`                     | The public store listing ID |
| Staging     | `com.synaplan.app.staging`             | Internal pre-prod track |
| Development | `com.synaplan.app.dev`                 | Local/dev builds |

The environment is selected at build time (Epic 10) together with the API/WS base URL
(`setApiBaseUrl`, Epic 3). Non-prod builds must carry a visible environment indicator.

## Production endpoint

- **API / WebSocket base URL:** `https://web.synaplan.com`
  (consumed by `setApiBaseUrl` + `appBaseUrl`/`realtime.wsUrl` overrides in Epic 3)

## Version scheme

- **Human version:** `MAJOR.MINOR.PATCH`, starting on the **v4.0** line. Initial app release:
  **`4.0.0`**.
- **Build number:** monotonic integer `versionCode` (Android) / `CFBundleVersion` (iOS),
  starting at **`1`** and auto-incremented per build (Epic 10). Never reused, never decreased.
- **Single source of truth:** the human version lives in this repo's `package.json` `version`
  and flows into:
  - the native project versions (`cap sync` / build tooling),
  - the User-Agent token (Epic 2, injected at build time),
  - the compatibility matrix (`docs/COMPATIBILITY.md`).

## User-Agent contract (Aspect 1 / Epic 2)

- **Format (frozen):** `Synaplan Mobile V<major>.<minor>[.<patch>]`
  - Appended (not overridden) to the default WebView UA via Capacitor `appendUserAgent`.
  - Example for `4.0.0`: the appended token is `Synaplan Mobile V4.0` (major.minor) — patch is
    **optional** and only added if per-patch forced-update granularity is required (Epic 8).
- **Backend parser regex (frozen):** `/Synaplan Mobile V(\d+)\.(\d+)(?:\.(\d+))?/`
- Must round-trip through **every** WebView transport: fetch/XHR, `EventSource`/SSE, and the
  WebSocket upgrade. (Verified in Epic 2 acceptance.)

## Submodule pin

- **Repo:** `synaplan` (public) via **HTTPS** (`https://github.com/metadist/synaplan.git`).
- **Path:** `./synaplan`
- **Current pin:** `v4.2.1` (exact release tag/SHA; never a moving branch).

## Apple / Google account identifiers (fill in Epic 0.1)

| Field | Value |
|-------|-------|
| Apple Developer account (legal entity) | metadist data management GmbH |
| Apple Developer Team ID | `X9GM4T2MQG` |
| Apple App Store Connect app ID (Apple ID) | `6784278288` |
| Apple App Store Connect SKU | `synaplanai` |
| Google Play developer account ID | _TODO_ |

> ASC API key details (Issuer ID, Key ID) and the `.p8` file are secret-adjacent and live only in
> `_appstores/.local/` per `docs/SECRETS.md` — never in this tracked file.
