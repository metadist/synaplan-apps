# Synaplan Submodule — Blast-Radius Registry

> **Single source of truth for "what we changed in the public `synaplan` repo and why it's safe."**
> This is the in-repo realization of the encapsulation contract (Epic 13).
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
Epic 12 — see `docs/QUALITY_GATES.md`).

The tables below key each row by its epic number; `FR` is the first-run onboarding and `PW` the
subscription paywall, neither of which has an epic of its own.

## New files (no shared-file risk — pure additions)

These hold the actual logic so shared files stay thin. None of them change existing behavior.

| Epic | New file (`synaplan/`) | Purpose |
|------|------------------------|---------|
| 2 | `backend/src/Service/Client/ClientContext.php` | Immutable `{isMobileApp, appVersion, platform}` value object |
| 2 | `backend/src/Service/Client/ClientContextResolver.php` | UA parser → `ClientContext` (pure read of the User-Agent) |
| 3 | `backend/src/Service/NativeAuthHandoffService.php` | Short-lived signed HMAC handoff token for native OAuth |
| 3 | `backend/src/Service/OAuthLoginResponder.php` | Builds the OAuth success/error response (cookie web vs. deep-link native) |
| 4/9 | `backend/src/Service/Branding/BrandingService.php` | Single source of truth for the BRANDING config group (+ `BRAND_ACCOUNT_DELETION_URL`, Epic 9.1) |
| 4/9 | `backend/src/Seed/BrandingConfigSeeder.php` | Idempotent seed of branding defaults (== today's look; incl. empty account-deletion URL) |
| 8 | `backend/src/Service/Client/MobileVersionService.php` | Min-app-version + store URLs (forced-update gate) |
| 8 | `backend/src/Seed/MobileConfigSeeder.php` | Idempotent seed of mobile config (gate off by default) |
| 3 | `frontend/src/services/api/nativeAuth.ts`, `nativeOAuth.ts`, `nativeRuntime.ts` | Native auth/OAuth/runtime helpers (native-guarded). `nativeAuth.ts` keys Bearer tokens **per resolved server** (§3.0 per-server identity) |
| 3 | `frontend/src/services/authService.ts` consumers, `RealtimeClient.ts` | (see shared edits) |
| 4 | `frontend/src/components/BrandAttribution.vue` | `{name} · powered by {label}` component |
| 4 | `frontend/src/composables/useBrandLogo.ts`, `frontend/src/utils/brandingTheme.ts` | Runtime logo + color/font injection |
| 7 | `frontend/src/components/BiometricLockScreen.vue`, `OfflineBanner.vue`; `composables/useBiometricLock.ts`, `useNetworkStatus.ts`; `services/biometricLock.ts`, `nativeLifecycle.ts`, `api/nativeDownload.ts` | Native hardening (all native-guarded) |
| 8 | `frontend/src/components/ForceUpdateScreen.vue`, `services/otaUpdates.ts` | Forced-update screen + Capgo readiness ping |
| 9 | `frontend/src/views/AccountDeletionView.vue` | Public account-deletion info page (Google Play store policy); brand-aware, no auth |
| 9 | `frontend/src/services/nativeStatusBar.ts` | OS status-bar theming synced to app theme/brand (Epic 9.5, Guideline 4.2); `isNativeApp()`-guarded, no-op on web |
| 9 | `frontend/src/services/nativeBackButton.ts` | Android hardware back-button (router-back → press-again-to-exit) (Epic 9.5); `isNativeApp()` + Android-only, no-op on web/iOS |
| 3 | `frontend/src/services/api/nativeServer.ts` | Typed SPA seam over the app-owned `window.SynaplanServer` (get/getDefault/save/reset). Absent on web/non-bootstrapped builds → `isNativeServerControlAvailable()` false, accessors no-op |
| SC | `frontend/src/services/api/nativeShortcuts.ts`, `nativeCamera.ts` | Typed SPA seams over the app-owned `window.SynaplanShortcuts` / `window.SynaplanCamera` bridges (iOS Kurzbefehle → dictate / attach photo). Absent on web → every accessor is a no-op |
| 3 | `frontend/src/components/admin/AdminAppServerPanel.vue` | In-app "App server" switcher UI (replaces the removed always-on gear). Reads/writes the server via `nativeServer.ts`; Tailwind/i18n/`useDialog`/`useNotification` |
| FR | `frontend/src/views/OnboardingView.vue` | Native-only first-run welcome page (single step) with the language picker; the "get started" CTA persists completion and enters the chat as a guest — no sign-in, no purchase decision |
| FR | `frontend/src/components/onboarding/OnboardingWelcomeStep.vue`, `OnboardingServerModal.vue`, `OnboardingInfoModal.vue` | The welcome page has a focused "get started" CTA plus quiet pills opening modals: the own-server modal (reuses the `nativeServer.ts` seam — probe/persist/reload stay app-owned) and RAG / chat-widget info modals. No plans page during onboarding — a purchase decision is never asked for before the user has tried the product; plans surface later through the paywall or `/subscription` (native IAP path, never Stripe web checkout) |
| FR | `frontend/src/composables/useOnboarding.ts` | Completion flag (`localStorage['synaplan.onboardingCompleted']`), first-run gate (`shouldShowOnboarding`: native + signed-out + no guest session + not completed) |
| 5/9 | `frontend/src/composables/useSubscriptionPurchase.ts` | The channel split extracted out of `SubscriptionView.vue` so the paywall and the subscription page share one implementation: store IAP with server-side verification in the app, Stripe checkout on the web, store-catalogue prices with the `appPrice` markup fallback, and the Apple-required restore path |
| PW | `frontend/src/components/subscription/SubscriptionPaywallModal.vue` | Plan sheet for a spent allowance — full-screen in the app (safe-area insets), centered on the web. Always dismissable (X, backdrop, Escape, "maybe later"); shows only store prices, offers "Restore purchases" in the app, links terms/privacy and states auto-renewal; never links a web checkout from the native shell |
| PW | `frontend/src/composables/usePaywallPrompt.ts` | Who sees the paywall and how often: hard triggers on a spent guest trial / monthly allowance, plus a reminder for guests and free (`NEW`) accounts throttled to once per 24h via `localStorage['synaplan.paywallLastShownAt']`. BUSINESS/ADMIN never; ineligible whenever `billing.enabled` is false or `isPurchaseAllowed()` is false |

## Registry of edited shared files — the whole blast radius

| Epic | File (`synaplan/`) | Change | Guard / default (why it's safe) |
|------|--------------------|--------|---------------------------------|
| 2/9 | `backend/src/Controller/ConfigController.php` | Add optional `client`, `branding`, `mobile` blocks to runtime config; `branding.accountDeletionUrl` (Epic 9.1) | Additive keys; web → `isMobileApp:false`, branding defaults == today, gate off; empty `accountDeletionUrl` → in-app `/account-deletion` |
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
| 4/9 | `frontend/src/stores/config.ts` | `branding` getter (name/colors/fonts/logo/start-page/powered-by; + `accountDeletionUrl`, Epic 9.1) | Additive; defaults reproduce today; empty `accountDeletionUrl` → `/account-deletion` |
| 4/9 | `frontend/src/router/index.ts` | `brandName()`; `resolveDefaultRoute()` / `resolveLandingTarget()` honor branding (route name **or** free-form path); + public `/account-deletion` route (Epic 9.1) | Resolved against the route table; non-public/unknown/404/self-redirect rejected; **fail safe** to `chat`/`login`; new route is public + additive |
| 4/9 | `frontend/src/App.vue` | `document.title` uses runtime brand name (Epic 4); init native status-bar + Android back-button (Epic 9.5) | Falls back to `Synaplan` before config; both native inits no-op on web |
| 5/9 | `frontend/src/views/SubscriptionView.vue` | Native: route purchase/manage to IAP/store instead of Stripe checkout/portal (Epic 5.2); show plans without Stripe config, add Restore-Purchases + store-manage label + store note, hide Stripe dunning/not-configured notices (Epic 9.4). Purchase/pricing logic now comes from `useSubscriptionPurchase`; `?plan=<tier>` from the paywall highlights and scrolls to that card | `isNativeApp()`-guarded; web checkout/portal/pricing flow unchanged. The extraction is behavior-preserving and the query parameter is optional — no parameter renders exactly as before |
| PW | `frontend/src/views/ChatView.vue` | A blocked message opens the paywall instead of the signup/limit modal when the allowance is actually spent (`lifetime`/`monthly`), plus a once-a-day reminder check on mount | Falls back to `GuestSignupModal`/`LimitReachedModal` whenever the paywall is ineligible. `billing.enabled` defaults to **false**, so an unconfigured deployment behaves exactly as before. An `hourly` throttle keeps the old modal with its reset countdown; a monthly cost-budget block keeps it on the web too, because its Stripe top-up is the more precise remedy — MOBILE-APP SEAM: that top-up is hidden in the app, which gets the paywall instead |
| SC | `frontend/src/views/ChatView.vue` | Consume a pending iOS Shortcut on mount and listen for live taps (`dictate` → `startDictation()`, `photo` → native camera → `uploadFiles`) | `isNativeApp()`-guarded; web mount path unchanged. Guest photo taps reuse the existing attach feature-gate. Photos are attached, never auto-sent |
| SC | `frontend/src/components/ChatInput.vue` | Expose `startDictation()` for the Shortcuts seam | Additive `defineExpose` method; the mic button and `toggleRecording()` path are unchanged. Missing STT shows a toast and returns false |
| SC | `frontend/src/App.vue` | `initNativeShortcuts()` navigates dictate/photo taps onto the chat route | No-op when the bridge is absent (web). `open` does not steal the current screen |
| SC | `frontend/src/i18n/{en,de,es,fr,tr}.json` | `chatInput.dictationUnavailable` + `chatInput.cameraUnavailable` | Additive keys; only rendered behind the native shortcut handlers |
| PW | `frontend/src/composables/useLimitCheck.ts` | Export the `LimitCheckResult` type so the view can branch on it | Type-only export; no behavior change |
| PW | `frontend/src/style.css` | `--plan-{pro,team,business}-{accent,soft,ink}` + `--plan-on-accent` tokens, defined for light **and** dark | New token names only; nothing existing is recolored |
| PW | `frontend/src/i18n/{en,de,es,tr}.json` | `paywall.*` keys in all four locales (titles/sublines per trigger, plan taglines, auto-renewal and store notes) | Additive keys; the plan benefits reuse the existing `subscription.features.*` strings so the sheet is localized instead of showing the API's English list |
| 3 | `frontend/src/views/AdminView.vue` | Native-only "App server" admin tab rendering `AdminAppServerPanel` (server switch moved here from the removed app-owned gear) | `isNativeApp()`-guarded tab (lazy-loaded); web admin unchanged |
| FR | `frontend/src/router/index.ts` | Public `/onboarding` route (lazy) + two guard branches: entry redirect into the first-run page, and native-only/signed-out gating of the route itself | `shouldShowOnboarding()` is hard-false on web (`isNativeApp()`), for signed-in users, after completion, and for existing guest sessions; direct web navigations to `/onboarding` bounce to chat/home — web behavior byte-identical |
| FR | `frontend/src/i18n/{en,de,es,tr}.json` | `onboarding.*` + `pageTitles.onboarding` keys (all four locales) | Keys only render inside the native-gated flow |
| 5/9 | `frontend/src/components/common/LimitReachedModal.vue` | Native: hide the Stripe web top-up CTA for digital goods (Epic 9.4) | `isNativeApp()`-guarded; web top-up + in-app upgrade route unchanged |
| 9 | `frontend/src/style-v2.css` | iOS HIG accessibility for the V2 glass material: `prefers-reduced-transparency` fallback (opaque sidebar/card surfaces + drop backdrop blur) and `prefers-reduced-motion` neutralization, both scoped to `.design-v2`; landscape `safe-area-inset-left/right` on the sidebar rail + mobile tab bar | Media-query/`env()`-gated only — default V2 look unchanged; activates solely under the user's OS accessibility settings or a notched landscape cutout |
| 9 | `frontend/src/components/MobileBackButton.vue` (**new**), `frontend/src/components/MainLayout.vue` | Native-only floating back affordance (iOS has no hardware back). Mounted once in `MainLayout`, shown only when `isNativeApp()` + in-app history exists + not on the chat/home surface; sits in the existing 62px mobile top clearance and calls `router.back()` (fallback `/`) | `isNativeApp()`- + `md:hidden`-gated and only renders when `history.state.back != null`; web/desktop unchanged, no back button on chat/home |
| 4 | `frontend/src/views/LoginView.vue`, `RegisterView.vue`, `LoggedOutView.vue`, `SharedChatView.vue` | `<BrandAttribution>` + `homepageUrl` links | All fall back to current hardcoded values |
| 4 | `frontend/src/components/widgets/ChatWidget.vue`, `widget.ts` | Hide / re-attribute powered-by from branding config | Defaults show "powered by synaplan" |
| 4/9 | `frontend/src/i18n/{en,de,es,tr}.json`, `i18n/index.ts` | Parameterized "powered by" + new keys; native subscription (restore/store) + back-button keys (Epic 9.4/9.5) | Default strings == today; native keys only render behind `isNativeApp()` |
| 7/9 | `frontend/src/views/ProfileView.vue` | Biometric-lock opt-in toggle; + account-deletion link in legal section (Epic 9.1) | Native-guarded toggle hidden on web; deletion link internal (RouterLink) or external (`<a>`) per config |
| 8 | `frontend/src/api/usageApi.ts` | (dep/typing reconcile) | No behavior change |
| 6 | `frontend/public/site.webmanifest` | Fix `theme_color` `#0003c7` → canonical `#003fc7` | Pure asset/metadata; aligns with `index.html` + `--brand` |
| 6/9 | `frontend/package.json` | Add `icons:generate` script (Epic 6); add `@capacitor/status-bar` dep for native status-bar theming (Epic 9.5) | Additive; status-bar is already a `synaplan-apps` native dep and imported only behind `isNativeApp()` |
| 6 | `frontend/scripts/generate-icons.mjs` | Doc-only header (regen command + cross-link `docs/ASSETS.md`) | Comment-only; behavior unchanged |
| 6 | `frontend/public/{synaplan.svg,groq.svg}`, `frontend/src/assets/vue.svg` | **Delete** unreferenced orphan assets | Verified zero references (incl. dynamic `.svg` paths); reversible via git |

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
