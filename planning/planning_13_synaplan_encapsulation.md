---
epic: 13
title: Synaplan Repo Encapsulation & Blast-Radius Contract (cross-cutting)
sprint: "Cross-cutting (applies to every epic that touches the submodule)"
aspect: null
status: planned
depends_on: []
repos:
  - synaplan (public, submodule)
estimate: M
---

# Epic 13 — Synaplan Repo Encapsulation & Blast-Radius Contract (cross-cutting)

> **Goal of this doc: make the changes to the public `synaplan` repo as small, isolated, and
> reversible as possible — and list every one of them in a single place.** The mobile app, the
> in-app server switcher, and the IAP flow live in `synaplan-apps`. The `synaplan` repo must change
> only where it genuinely cannot be avoided, and **every such change must be a no-op for the
> existing web + self-host product until it is explicitly configured.**

## Why a dedicated contract

The app program touches shared platform code in several epics (2, 3, 4, 5, 6, 8). Without a
contract, those edits sprawl across the public repo and risk regressing the web app, the PWA, and
self-hosters. This doc is the **single source of truth** for "what we changed in `synaplan` and why
it's safe," and it's what the AI logic review (gate 5, [Epic 12](planning_12_quality_gates.md))
checks against.

## The five encapsulation rules (non-negotiable)

1. **Default-off / no-op by default.** Every change reproduces today's behavior and look until an
   admin configures branding, the caller is the app (server-confirmed `client` flag, Epic 2), or
   IAP/store config is present. A fresh, unconfigured deployment must be **identical to today**.
2. **One seam, not many.** Prefer **new files** (services, components, controllers, config seeds)
   over editing shared ones. Where a shared file *must* change, keep the diff to the **smallest
   possible guarded hook** (ideally one line calling into a new module). Example: the native server
   selection is a **single** `setApiBaseUrl(resolvedServerUrl)` line in `main.ts` (Epic 3 §3.1) —
   all the logic lives in `synaplan-apps`.
3. **Guard every branch.** Native-only behavior is gated by `Capacitor.isNativePlatform()` (client
   signal) **and/or** the server-side `client.isMobileApp` (trust signal); branding by BCONFIG
   defaults; billing channel by the `source` model. No unguarded behavior change on shared paths.
4. **Additive contracts only.** Runtime-config and API responses gain **new optional keys**
   (`branding`, `client`, `minVersion`, subscription `source`) with safe defaults — never remove or
   repurpose existing fields. After schema changes: `make -C frontend generate-schemas` + re-typecheck.
5. **Reversible.** Each change is independently revertible / toggle-off-able, and proven so by the
   default-safety regression test (gate 2/5).

## Registry of `synaplan` (submodule) changes — the whole blast radius in one table

> Keep this table authoritative. If a PR touches a `synaplan` file not listed here, either add it
> with a justification + guard, or move the logic into `synaplan-apps`.

| Epic | File / area (in `synaplan/`) | Change | Guard / default (why it's safe) |
|------|------------------------------|--------|---------------------------------|
| 1 | `frontend/index.html` | CSP additive entries for `capacitor://` / `https://localhost` (+ any branding font origin) | Origin-scoped + additive; web CSP unchanged in effect |
| 2 | `backend/src/Http/ClientContext.php` *(new)* | UA parser → `{isMobileApp, appVersion, platform}` | New file; pure read of UA |
| 2 | `backend/src/Controller/ConfigController.php` | Add optional `client` block to runtime config | Additive key; web → `isMobileApp:false` |
| 2 | `backend/src/Entity/Session.php` + `AuthController`/`TokenService` | Wire the already-present `setUserAgent()` on session/token create | Fills an existing unused column; no behavior change |
| 2/4/8 | `frontend/src/stores/config.ts` + runtime-config Zod schema | Read new optional `client` / `branding` / `minVersion` blocks | Additive; defaults reproduce today |
| 3 | `frontend/src/main.ts` | **One line**: native → `setApiBaseUrl(resolvedServerUrl)` (fallback `https://web.synaplan.com`) | Guarded by `isNativePlatform()`; web untouched |
| 3 | `frontend/src/stores/config.ts` (`appBaseUrl`) | Native → derive from resolved server, not `window.location.origin` | Native-guarded; web keeps origin |
| 3 | realtime client (`wsUrl` source) | Use backend `realtime.wsUrl` instead of `window.location.host` | Backend already exposes it; same value on web |
| 3 | backend CORS config | Allow-list app origin(s) | Additive origin entries |
| 3 | `httpClient.ts` | Native → attach `Authorization: Bearer`; web stays cookie (`credentials:'include'`) | Native-guarded; web header path unchanged |
| 3 | `SocialLogin.vue` + backend OAuth redirect URIs | System-browser + deep-link return for native | Native-guarded; web OAuth unchanged |
| 4 | `backend/src/Seed/` *(new branding seed)* + `SystemConfigService.php` + `ConfigController.php` | BCONFIG branding group (name/colors/**fonts**/logo/**start page**/powered-by) + admin UI + runtime exposure | Idempotent seed with defaults == today; admin-only edit |
| 4 | `router/index.ts`, `App.vue`, `style.css`, `LoginView`/`RegisterView`/`LoggedOutView`/`SharedChatView`, `ChatWidget.vue`, `SharedChatPageController.php`, `i18n/{en,de,es,tr}.json` | Read brand from config; `<BrandAttribution>` *(new)*; runtime color/font/start-page injection | All fall back to current hardcoded values when unconfigured |
| 5 | `BillingService`, `User` (subscription helpers), `SubscriptionController`, `StripeWebhookController`, `SubscriptionView.vue`, `subscriptionApi.ts`, BCONFIG pricing | Add subscription `source`; channel gating; status returns `{active,tier,source,manageUrl}` | `source` backfills to `stripe`; web Stripe path unchanged; no-billing mode unchanged |
| 5 | `backend/src/Controller/MobilePurchaseController.php` *(new)* + service | Server-side IAP validation (Apple ASSN V2 / Google RTDN) | New, app-only path; never reached by web |
| 6 | `frontend/scripts/generate-icons.mjs`, `public/site.webmanifest`, `index.html` theme-color, favicons/PWA icons | Commit/generate missing icons; reconcile color typo | Fixes a current gap; visual parity preserved |
| 8 | BCONFIG min-version + `ConfigController.php` | Expose optional `minVersion` for forced-update gate | Additive key; ignored by web |

## Tasks

### 13.1 — Establish the contract in-repo

- [ ] Add `docs/SYNAPLAN_BLAST_RADIUS.md` in `synaplan-apps` that **is** the registry table above,
      kept in sync as epics land. Every submodule PR updates it.
- [ ] Add the **default-safety regression** as a first-class, always-run test (gate 2/5): an
      unconfigured deployment renders + behaves identically to the pre-program baseline.

### 13.2 — Enforce "new file over edited file"

- [ ] For each submodule epic, prefer new modules: `ClientContext` (E2), branding seed +
      `<BrandAttribution>` (E4), `MobilePurchaseController` (E5). Shared-file edits must be a single
      guarded hook with a comment pointing back to its owning epic.

### 13.3 — Make the seam auditable

- [ ] A single grep-able marker/comment convention (e.g. `// MOBILE-APP SEAM (Epic N)`) on every
      shared-file hook so the entire blast radius can be located and reviewed in seconds, and the
      AI logic review (gate 5) can verify each is guarded + default-safe.

### 13.4 — Keep the app's own logic out of the submodule

- [ ] In-app server config + persistence + per-server identity (Epic 3 §3.0), IAP UI glue, OTA, and
      native features live in `synaplan-apps`. The submodule only **reads** resolved values and
      **exposes** additive config — it never holds app-only business logic.

## Acceptance criteria (Definition of Done)

- `docs/SYNAPLAN_BLAST_RADIUS.md` exists and lists **every** changed `synaplan` file with its
  guard + default; no submodule PR adds an unlisted, unguarded edit.
- The unconfigured web/self-host product is **provably unchanged** (default-safety test green).
- Every shared-file hook is native-/config-/source-guarded and carries the seam marker.
- App-only logic is absent from the submodule (verified by review).
- Each additive contract key has a safe default and updated generated schemas.

## Test notes (for the QA person)

- Diff the submodule against the pinned baseline tag and confirm the changed-file set **equals** the
  registry table — nothing more.
- Run the default-safety regression (no branding, no app, no IAP config) → identical to baseline.
- Toggle each seam off (or leave unconfigured) and confirm web parity.

## Risks & mitigations

- **Scope creep into the public repo:** the registry table + "new file over edited file" rule +
  seam markers keep it visible and reviewable.
- **Silent web regression:** default-safety test is mandatory and runs every gate (Epic 12).
- **Submodule drift:** changes pin to the v4.0 tag; the registry is part of the release gate
  (Epic 11).

## Open questions

- Should the seam marker be lint-enforced (a custom ESLint/PHPStan rule that flags unguarded
  shared-path behavior changes), or convention + AI review only?
