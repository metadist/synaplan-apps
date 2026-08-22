# Quality Gates — Per-Epic Test Matrix (Epic 12.7)

> The single map of **which gate covers which acceptance criterion**, and what is still
> **manual-only** (with a reason). Epic 12 defines five mandatory gates; no epic is "done"
> until its acceptance criteria are mapped here and green on the relevant gates.

## The five gates + how to run them

| # | Gate | App repo (`synaplan-apps`) | Submodule (`synaplan/`) |
|---|------|----------------------------|--------------------------|
| 1 | **Lint** (style + static safety) | `npm run lint` (ESLint flat config: `capacitor.config.ts` + `scripts/` + `tests/` + ES5 bootstrap) **and** `npm run typecheck` (tsc on `capacitor.config.ts`) | `make -C backend lint`, `make -C backend phpstan`, `make -C frontend lint`, `npm run check:types` (vue-tsc) |
| 2 | **Click** (it actually works) | native click-through via **Maestro** (`npm run e2e`, [`.maestro/`](../.maestro), [`docs/NATIVE_E2E.md`](NATIVE_E2E.md)) — device-gated; flow integrity guarded in `ci-local` | Playwright (web), Vitest + Testing Library (components) |
| 3 | **Parse** (config/contract validates) | `npm run test` (`tests/*.test.mjs`): build-identity resolver **+ native-manifest validation** (Info.plist purpose strings + build-setting wiring, AndroidManifest permissions + `${appLabel}`, `PrivacyInfo.xcprivacy` structure, all XML well-formed) | Zod runtime-config parse tests, UA-parser unit test |
| 4 | **Format** (deterministic, complete) | `npm run format:check` (Prettier on app-owned code: `capacitor.config.ts`, `eslint.config.js`, `scripts/`, `tests/`, ES5 bootstrap) | `prettier --check`, `php-cs-fixer --dry-run`, **i18n completeness (en/de/es/tr)** |
| 5 | **AI logic review** (Cursor) | [`docs/AI_LOGIC_REVIEW.md`](AI_LOGIC_REVIEW.md) on every PR | same checklist |

```bash
# App-repo gate: gates 1 (lint + typecheck) + 3 (parse) + 4 (format-check)
npm run ci-local

# Submodule gate (run inside synaplan/, never a filtered subset)
make -C backend lint && make -C backend phpstan && make -C backend test
make -C frontend lint && docker compose exec -T frontend npm run check:types && make -C frontend test
```

**Legend:** ✅ automated & wired · 🟡 partially automated · 🧪 manual / device-gated · ⏳ not built yet.

For any backend OpenAPI change, regenerate the frontend schemas through the platform path and the
app build path, then verify that both consume the same reviewed specification. A successful build
against a different live schema is not parity.

## Standing regression (applies to every submodule epic)

**Default-safety / blast radius (gates 2 + 5).** An *unconfigured* web/self-host deployment
(no branding, no app client, no IAP config) must look and behave **identically to the
pre-program baseline**. This is the non-negotiable test behind every Aspect epic (2/4/5) and
is enforced by the encapsulation contract (Epic 13) + the AI logic
review. Diff the submodule against the pinned baseline tag; the changed-file set must equal
the `docs/SYNAPLAN_BLAST_RADIUS.md` registry — nothing more.

The reviewed `v3.9.6` baseline contains the approved mobile seams. Diff future platform tags
against it and re-run both repositories' complete gates before changing the app pin.

## Per-epic matrix

| Epic | Key acceptance criterion | Gate(s) | Status — where |
|------|--------------------------|---------|----------------|
| **1 Shell** | `build.sh && cap sync` succeeds; bundled SPA renders (no white screen); splash + themed status bar + Android back | 1,2 | 🧪 device launch (iOS sim + Android emu verified); ✅ `build.sh`/`cap sync` |
| **1 Shell** | No remote `server.url`; `ios/`+`android/` present; secrets/artifacts gitignored | 3,5 | ✅ config (`webDir` bundled) + AI review |
| **2 UA (Aspect 1)** | UA carries `Synaplan Mobile V<x.y>` on fetch **+ SSE + WS upgrade**; web UA unchanged | 2,3 | 🧪 backend-log inspection on all 3 transports; ✅ `appendUserAgent` typecheck |
| **2 UA** | Backend UA parser regex matches `V4.0`/`V4.0.1`, rejects spoofs | 1,3 | 🟡 backend unit test (`MobileVersionServiceTest`) in submodule |
| **2 UA** | `/config/runtime` returns `client` block (web `false`, app `true`+version) | 3,5 | 🟡 submodule Zod parse + AI review (additive key) |
| **3 Auth** | Fresh install defaults to `web.synaplan.com`; edit→save→reload; reset; reject bogus/`http://`/non-Synaplan URL | 2,3 | 🧪 manual server-switch; 🟡 URL normalize/probe logic (`app/synaplan-native.js`) |
| **3 Auth** | Per-server identity isolation; token A never sent to server B; never logged | 5 | 🧪 manual (inspect outgoing `Authorization` per host) + **AI security review** |
| **3 Auth** | Login + chat **SSE** + realtime **WS** + ≥1 **OAuth** in a **release/TestFlight** build, survives background/resume | 2 | 🧪 device, release track (highest-risk path) |
| **4 Branding (Aspect 2)** | Admin edits name/colors/fonts/logo/start-page/attribution → all touchpoints update; **default == today** | 2,4,5 | 🧪 Playwright branded-vs-default + 🟡 Zod branding-parse + **default-safety AI review** |
| **4 Branding** | All four locales updated; no hardcoded English "Powered by" left | 4 | 🟡 i18n-completeness test (submodule) |
| **5 Payments (Aspect 3)** | Status endpoint returns single `{active,tier,source,manageUrl}`; existing subs `source:'stripe'` | 1,3,5 | 🟡 backend unit tests (mocked store APIs) |
| **5 Payments** | App: sandbox IAP grants tier **only after server validation**, user-bound, restore works, **no Stripe redirect reachable** | 2,5 | 🧪 sandbox device + **anti-steering AI review** |
| **5 Payments** | Block-cross (Stripe↔IAP) server-enforced; ASSN V2 / RTDN update without app open; Google ack < 3 days | 2,3 | 🧪 store test-notification payloads + 🟡 backend tests |
| **5 Payments** | Open-source mode (no keys) → billing disabled, unlimited, no purchase UI | 2,5 | 🧪 + default-safety AI review |
| **6 Assets (Aspect 4)** | Icon/splash set renders on real devices (incl. Android adaptive, dark); clean clone not missing favicons; brand color consistent | 1,2 | 🧪 device home-screen; 🟡 clean-clone build check |
| **7 Native features** | Camera/file/mic/download/share on device; permission-denial degrades (no crash); token in Keychain/Keystore; offline recovers | 2,5 | 🧪 device + **security review (token storage, never logged)** |
| **7 Native features** | iOS purpose strings present (missing → crash/reject); reCAPTCHA works under `capacitor://`; no white screen | 1,3 | ✅ `Info.plist` purpose-string + well-formedness check (`tests/native-manifests.test.mjs`); 🧪 reCAPTCHA/device |
| **8 OTA / forced update** | Self-hosted Capgo delivers the OTA bundle; staged rollout + rollback work; min-version gate blocks too-old then allows | 2,5 | 🧪 device rollout + verified self-hosted upload target + **"no payment/behavior logic via OTA" AI review** |
| **8 OTA** | `COMPATIBILITY.md` current; `OTA_POLICY.md` exists | 4,5 | ✅ docs present |
| **9 Store compliance** | In-app account deletion (+ web link for Google); anti-steering verified; restore + manage-via-store present | 2,5 | 🧪 reviewer path (9.4/9.5 code-complete) + AI store-policy review |
| **9 Store compliance** | Build with valid `PrivacyInfo.xcprivacy` (incl. all SDK manifests) passes upload; privacy/data-safety labels accurate | 3 | 🟡 app-level `PrivacyInfo` structure + well-formedness checked (`tests/native-manifests.test.mjs`); 🧪 SDK-manifest completeness + upload-rejection test (device/account-gated) |
| **10.1 Build env + versioning** | One env switch → correct bundle id + auto-incremented version per env; version single-sourced | 1,3 | ✅ `npm run ci-local` (`tests/app-config.test.mjs`) + verified on Android emu + iOS build settings |
| **10.2 Signing** | One command per platform → signed build for a chosen env | 1,3 | ✅ protected `store-rc.yml`; first credentialed run remains account-gated |
| **10.3 Crash reporting** | Test crash reaches the dashboard | — | ⏳ vendor decision pending (params decided) |
| **10.4 Store listings** | Metadata + screenshots in de/en/es/tr | 4 | ⏳ assets/account-gated |
| **10.5 Beta/CI** | Live on TestFlight + Play Internal; auth + IAP green in release tracks | 1–5 | ✅ automated upload to TestFlight Internal + Play Internal; device/account smoke remains gated |
| **11 Stabilization** | Must-fix bugs closed; all four Aspects no-op for web; full gates green; release-gate checklist complete | 1–5 | ⏳ final gate (reads this matrix + `COMPATIBILITY.md`) |
| **12 Quality gates** | App `ci-local` + submodule make gate cover gates 1–4; AI review recorded on every PR | 1,2,3,4,5 | ✅ app gate (1 lint+typecheck, 3 parse, 4 format); ✅ gate-2 Maestro flows authored + integrity-guarded; Android run **3/3 green**, iOS shell manually verified (Maestro-iOS WebView limit) |
| **13 Encapsulation** | Blast-radius registry == actual changed files; every seam guarded + default-safe | 5 | ✅ `SYNAPLAN_BLAST_RADIUS.md` + AI review |

## Open automation gaps (need a decision before closing)

- **App-repo lint + format (gates 1+4):** ✅ done — ESLint (flat config, `eslint.config.js`)
  + Prettier (`.prettierrc.json`) added as dev-deps; wired into `npm run ci-local` as
  `npm run lint` and `npm run format:check`. The ES5 bootstrap (`app/synaplan-native.js`) is
  linted with a relaxed browser/ES5 override; the `synaplan/` submodule keeps its own toolchain.
- **Native click-through (gate 2):** ✅ tool decided — **Maestro** (rationale + run steps in
  [`docs/NATIVE_E2E.md`](NATIVE_E2E.md)). Committed flows in [`.maestro/`](../.maestro) cover
  the app-shell smoke (no white screen), the native Server overlay, and the non-prod env badge,
  anchored on app-owned locale-independent strings. Execution is device-gated (built app +
  emulator/sim), so it stays out of the fast `ci-local`; `tests/maestro-flows.test.mjs` guards
  the flows' integrity there. **Verified:** Android emulator **3/3 passed**; iOS Simulator —
  app shell launches + renders (DEV badge + gear confirmed by screenshot) but Maestro's iOS
  XCUITest driver hangs dumping the heavy WebView a11y tree, so iOS is **manually verified**
  for now (known Maestro-on-iOS limitation, not an app defect — see `docs/NATIVE_E2E.md`).
  _Remaining (device/account-gated): login + SSE/WS/OAuth and sandbox-IAP/anti-steering flows
  need a signed release build + test accounts (Epic 10.2/10.5)._
- **Manifest/`PrivacyInfo` validation (gate 3):** ✅ done — `tests/native-manifests.test.mjs`
  validates `Info.plist` (purpose strings + version/bundle-id build-setting wiring + OAuth
  scheme), `AndroidManifest.xml` (permissions + `${appLabel}` + OAuth filter), and the
  app-level `PrivacyInfo.xcprivacy` (required-reason structure), all XML well-formed via the
  dependency-free `scripts/xml-wellformed.mjs`. _Remaining (device/upload-gated): SDK-manifest
  completeness across every pod/SPM package._
