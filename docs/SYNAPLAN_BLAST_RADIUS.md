# Synaplan Submodule — Blast-Radius Registry

> **Single source of truth for "what we changed in the public `synaplan` repo and why it's safe."**
> This is the in-repo realization of [Epic 13](../planning/planning_13_synaplan_encapsulation.md).
> Every submodule PR for the app program **must** keep this table current. If a PR touches a
> `synaplan` file that is not listed here, either add it (with a guard + default justification) or
> move the logic into `synaplan-apps`.

## The five encapsulation rules (non-negotiable)

1. **Default-off / no-op by default.** A fresh, unconfigured deployment is identical to before.
2. **One seam, not many.** Prefer new files; where a shared file must change, keep it to the
   smallest guarded hook.
3. **Guard every branch.** Native behavior is gated by `isNativeApp()` (client) and/or
   `client.isMobileApp` (server trust); branding by BCONFIG defaults.
4. **Additive contracts only.** Runtime-config/API responses gain new **optional** keys with safe
   defaults — never remove/repurpose existing fields.
5. **Reversible.** Each change toggles off / reverts cleanly.

## Seam markers

Every shared-file hook carries a grep-able marker so the whole blast radius is locatable in
seconds:

```bash
# from the synaplan/ submodule root
rg -n "MOBILE-APP SEAM"
```

The marker form is `MOBILE-APP SEAM (Epic N)` and is enforced by the AI logic review (gate 5,
[Epic 12](../planning/planning_12_quality_gates.md)).

## New files (no shared-file risk — pure additions)

These hold the actual logic so shared files stay thin. None of them change existing behavior.

| Epic | New file (`synaplan/`) | Purpose |
|------|------------------------|---------|
| 2 | `backend/src/Service/Client/ClientContext.php` | Immutable `{isMobileApp, appVersion, platform}` value object |
| 2 | `backend/src/Service/Client/ClientContextResolver.php` | UA parser → `ClientContext` (pure read of the User-Agent) |
| 3 | `backend/src/Service/NativeAuthHandoffService.php` | Short-lived signed HMAC handoff token for native OAuth |
| 3 | `backend/src/Service/OAuthLoginResponder.php` | Builds the OAuth success/error response (cookie web vs. deep-link native) |
| 4 | `backend/src/Service/Branding/BrandingService.php` | Single source of truth for the BRANDING config group |
| 4 | `backend/src/Seed/BrandingConfigSeeder.php` | Idempotent seed of branding defaults (== today's look) |
| 8 | `backend/src/Service/Client/MobileVersionService.php` | Min-app-version + store URLs (forced-update gate) |
| 8 | `backend/src/Seed/MobileConfigSeeder.php` | Idempotent seed of mobile config (gate off by default) |
| 3 | `frontend/src/services/api/nativeAuth.ts`, `nativeOAuth.ts`, `nativeRuntime.ts` | Native auth/OAuth/runtime helpers (native-guarded) |
| 3 | `frontend/src/services/authService.ts` consumers, `RealtimeClient.ts` | (see shared edits) |
| 4 | `frontend/src/components/BrandAttribution.vue` | `{name} · powered by {label}` component |
| 4 | `frontend/src/composables/useBrandLogo.ts`, `frontend/src/utils/brandingTheme.ts` | Runtime logo + color/font injection |
| 7 | `frontend/src/components/BiometricLockScreen.vue`, `OfflineBanner.vue`; `composables/useBiometricLock.ts`, `useNetworkStatus.ts`; `services/biometricLock.ts`, `nativeLifecycle.ts`, `api/nativeDownload.ts` | Native hardening (all native-guarded) |
| 8 | `frontend/src/components/ForceUpdateScreen.vue`, `services/otaUpdates.ts` | Forced-update screen + Capgo readiness ping |

## Registry of edited shared files — the whole blast radius

| Epic | File (`synaplan/`) | Change | Guard / default (why it's safe) |
|------|--------------------|--------|---------------------------------|
| 2 | `backend/src/Controller/ConfigController.php` | Add optional `client`, `branding`, `mobile` blocks to runtime config | Additive keys; web → `isMobileApp:false`, branding defaults == today, gate off |
| 2/3 | `backend/src/Controller/AuthController.php` | Native Bearer payload + handoff via `ClientContextResolver`/`NativeAuthHandoffService` | UA-guarded; web keeps cookies; tokens only for the already-authenticated account |
| 3 | `backend/src/Controller/GitHubAuthController.php`, `GoogleAuthController.php`, `KeycloakAuthController.php` | Delegate login response to `OAuthLoginResponder` (system-browser + deep-link return) | Native-guarded; web OAuth path unchanged |
| 3 | `backend/config/packages/security.yaml`, `backend/config/services.yaml` | Bearer authenticator + DI wiring for new services | Additive; cookie firewall unchanged |
| 4 | `backend/src/Controller/SharedChatPageController.php` | SSR title / `og:site_name` from `BrandingService` | Default name → historical "Synaplan AI" string |
| 4 | `backend/src/Controller/WidgetPublicController.php` | Emit `branding` powered-by subset for the cross-origin widget | Defaults keep "powered by synaplan"; hide/re-attribute opt-in |
| 4/8 | `backend/src/Service/Admin/SystemConfigService.php` | Branding tab (identity/colors/fonts/logos/start-page/attribution) + Mobile tab | Admin-only edit; DB-backed; defaults == today |
| 2/4/8 | `backend/src/Command/SeedAllCommand.php` | Register branding + mobile seeders | Idempotent insert-if-missing |
| 1 | `frontend/index.html` (CSP) | Additive `capacitor://`/`https://localhost` (+ branding font origin) | Origin-scoped + additive; web CSP unchanged in effect |
| 3 | `frontend/src/main.ts` | Native → resolve server before `config.init()`; `applyBrandingTheme()` | `isNativeApp()`-guarded; branding no-op for default brand |
| 3 | `frontend/src/services/api/httpClient.ts`, `apiService.ts`, `chatApi.ts`, `filesService.ts` | Native → `Authorization: Bearer`; web stays cookie | Native-guarded; web header/credentials path unchanged |
| 3 | `frontend/src/services/authService.ts` | Store/replay native Bearer identity | Native-guarded |
| 3 | `frontend/src/services/realtime/RealtimeClient.ts`, `stores/realtime.ts` | `wsUrl` from backend `realtime.wsUrl`; resume-reconnect | Same value on web; backend already exposes it |
| 4 | `frontend/src/stores/config.ts` | `branding` getter (name/colors/fonts/logo/start-page/powered-by) | Additive; defaults reproduce today |
| 4 | `frontend/src/router/index.ts` | `brandName()`; `resolveDefaultRoute()` / `resolveLandingTarget()` honor branding (route name **or** free-form path) | Resolved against the route table; non-public/unknown/404/self-redirect rejected; **fail safe** to `chat`/`login` |
| 4 | `frontend/src/App.vue` | `document.title` uses runtime brand name | Falls back to `Synaplan` before config |
| 4 | `frontend/src/views/LoginView.vue`, `RegisterView.vue`, `LoggedOutView.vue`, `SharedChatView.vue` | `<BrandAttribution>` + `homepageUrl` links | All fall back to current hardcoded values |
| 4 | `frontend/src/components/widgets/ChatWidget.vue`, `widget.ts` | Hide / re-attribute powered-by from branding config | Defaults show "powered by synaplan" |
| 4 | `frontend/src/i18n/{en,de,es,tr}.json`, `i18n/index.ts` | Parameterized "powered by" + new keys | Default strings == today |
| 7 | `frontend/src/views/ProfileView.vue` | Biometric-lock opt-in toggle | Native-guarded; hidden on web |
| 8 | `frontend/src/api/usageApi.ts` | (dep/typing reconcile) | No behavior change |

## How to verify (release gate)

```bash
# 1. The changed-file set equals this registry (nothing more)
git -C synaplan diff --name-status <baseline-tag>..HEAD

# 2. Every shared hook is marked
rg -n "MOBILE-APP SEAM" synaplan/

# 3. Default-safety: no branding, no app, no IAP config ⇒ identical to baseline
#    (frontend lint + vue-tsc + Vitest, backend phpstan + PHPUnit — see Epic 12)
```

## Notes

- App-only logic (in-app server switcher + per-server identity, IAP UI glue, OTA orchestration,
  native settings) lives in **`synaplan-apps`**, never in the submodule. The submodule only
  **reads** resolved values and **exposes** additive config.
- External font origins (`BRAND_FONT_URL`) and the app origin must be added to the CSP allow-list
  (`frontend/index.html`) and, for the app, to the configured server's allowed origins.
