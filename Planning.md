---
name: Synaplan Mobile App — Master Plan (INDEX)
overview: Ship the existing Vue 3 SPA as native iOS + Android apps via Capacitor 8, as part of the Synaplan v4.0 release. Apps are minimal (bundle the existing dist/), but four cross-cutting "publishing problems" turn this into real platform work: a "Synaplan Mobile Vx.x" client identity, config-driven white-label branding for open-source hosters, single-source-of-truth subscriptions (web=Stripe / app=Apple|Google, 30% fee), and a properly sorted graphics/logo set. Work is split into sequential "vibing sprints" (one epic doc each).
isProject: true
todos:
  - id: epic-0-preparation
    content: "Epic 0 — Preparation & Foundations: confirm decisions, dev accounts, private repo + submodule, bundle IDs, asset inventory, compatibility matrix, v4.0 release context. See planning/planning_0_preparation.md"
    status: pending
  - id: epic-1-capacitor-shell
    content: "Epic 1 — Capacitor Shell & Minimal Native App: Capacitor 8 scaffold, native plugins, CSP/origin, just enough native value for Guideline 4.2. See planning/planning_1_capacitor_shell.md"
    status: pending
  - id: epic-2-app-identity
    content: "Epic 2 — App Identity & 'Synaplan Mobile Vx.x' User-Agent (ASPECT 1): WebView appendUserAgent + backend detection + version surfacing. See planning/planning_2_app_identity_useragent.md"
    status: pending
  - id: epic-3-connectivity-auth
    content: "Epic 3 — Cross-Origin Connectivity & Auth: Bearer-token path, CORS, SSE/WebSocket in WebView, OAuth via system browser + deep links. See planning/planning_3_connectivity_auth.md"
    status: pending
  - id: epic-4-branding
    content: "Epic 4 — White-Label Branding & Attribution (ASPECT 2): config-driven brand name/logo/color + configurable 'powered by' so hosters can show 'Synaplan powered by <Name>'. See planning/planning_4_branding_whitelabel.md"
    status: pending
  - id: epic-5-payments
    content: "Epic 5 — Payments & Subscription Source Gating (ASPECT 3): subscription is single ACTIVE state with explicit source (stripe|apple|google); web=Stripe only, app=IAP only (30% fee), block-cross, anti-steering. See planning/planning_5_payments_subscription.md"
    status: pending
  - id: epic-6-graphics
    content: "Epic 6 — Graphics, Logos & Store Assets (ASPECT 4): commit + organize logo/icon set, generate app icons + splash, brandable asset slots, store screenshots. See planning/planning_6_graphics_logos.md"
    status: pending
  - id: epic-7-native-features
    content: "Epic 7 — Native Device Features & Lifecycle: camera/file/mic permissions, secure storage, resume-reconnect, network/offline, reCAPTCHA/CSP. See planning/planning_7_native_features.md"
    status: pending
  - id: epic-8-ota-versioning
    content: "Epic 8 — OTA, Versioning & Forced Update: Capgo live updates, min-version gate, compatibility matrix. See planning/planning_8_ota_versioning.md"
    status: pending
  - id: epic-9-compliance
    content: "Epic 9 — Store Compliance & UX: in-app account deletion, Apple PrivacyInfo.xcprivacy, privacy/data-safety labels, Guideline 4.2 minimum functionality. See planning/planning_9_store_compliance.md"
    status: pending
  - id: epic-10-release
    content: "Epic 10 — Release Engineering & Delivery: signing/fastlane, crash reporting, TestFlight / Play Internal Testing, store metadata, CI. See planning/planning_10_release_engineering.md"
    status: pending
  - id: epic-11-v4-stabilization
    content: "Epic 11 — v4.0 Platform Stabilization & Joint Release Gate: bug-bash, regression sweep, single go/no-go gate for platform + app. See planning/planning_11_v4_stabilization.md"
    status: pending
---

# Synaplan Mobile App — Master Plan (INDEX)

> **This is the index.** Each epic below is a self-contained "vibing sprint" in its own
> `planning_<n>_*.md` file: goal, scope, the exact files to touch (with paths), acceptance
> criteria, test notes, and risks. Work them roughly in order — dependencies are listed in
> each doc's front-matter (`depends_on`).
>
> Language note: these planning docs are in **English** (open-source / self-hoster audience).
> The original German `Planning.md` content is superseded by — and fully carried into — the
> epic docs below.

## Mission (the v4.0 framing)

Synaplan **v4.0** has two goals that ship together:

1. **A pretty bug-free platform** — a deliberate stabilization pass (Epic 11).
2. **A mobile app** for **iOS and Android**, offered **"flexible" and Open Source**.

The app itself is intentionally **minimal**: we wrap the existing Vue 3 SPA
(`synaplan/frontend/dist/`) with **Capacitor 8** — **no new UI**. The real work is four
cross-cutting "publishing problems" that an open-source, store-distributed app forces on the
**platform** side. Those are the four **Aspects** below.

## The four Aspects (hard requirements) → where they live

| # | Aspect (requirement) | Owning epic |
|---|----------------------|-------------|
| 1 | **App client must call the platform with a `Synaplan Mobile Vx.x` User-Agent.** | [Epic 2](planning/planning_2_app_identity_useragent.md) |
| 2 | **The platform must emit its branding; open-source hosters can show e.g. "Synaplan powered by Cristian".** | [Epic 4](planning/planning_4_branding_whitelabel.md) |
| 3 | **Payment is single-source-of-truth: a subscription is `ACTIVE` and owned by exactly one channel — web = Stripe, app = Apple/Google Pay (≈30% fee). Must be clearly configured & planned.** | [Epic 5](planning/planning_5_payments_subscription.md) |
| 4 | **Graphics and logos must be well sorted for the app release.** | [Epic 6](planning/planning_6_graphics_logos.md) |

> Reality check from the codebase: **none of these exist yet.** There is no custom User-Agent,
> no white-label config (everything is a hardcoded `Synaplan` + "Powered by synaplan"), the
> Stripe flow has **no subscription `source` field**, and the app icon PNGs aren't even committed
> (they're generated by a script). So each Aspect is a genuine epic, not a packaging detail.

## Repo split (unchanged, confirmed)

- **`synaplan-apps` (private, this repo):** `capacitor.config.ts`, native `ios/`+`android/`
  projects, IAP frontend glue, `build.sh`, signing/store configs, app assets. Pulls the public
  `synaplan` repo as a **Git submodule** pinned to a **release tag/SHA** and builds its `dist/`.
- **`synaplan` (public):** unavoidable product-side changes (Bearer auth path, CORS, branding
  config, subscription `source`, IAP validation controller, native switches via
  `Capacitor.isNativePlatform()`). These are no-ops while the app isn't running, so they don't
  disturb self-hosters.

**Why submodule, not a CI artifact:** pinning to tags makes the frontend↔app version
reproducible; a local build only needs Node 22 (`git clone --recursive` → `./build.sh`).

## Roadmap / sprint order

```mermaid
flowchart TD
    E0[Epic 0: Preparation] --> E1[Epic 1: Capacitor Shell]
    E1 --> E2[Epic 2: App Identity / User-Agent]
    E1 --> E3[Epic 3: Connectivity & Auth]
    E2 --> E4[Epic 4: White-Label Branding]
    E3 --> E5[Epic 5: Payments & Source Gating]
    E0 --> E6[Epic 6: Graphics & Logos]
    E3 --> E7[Epic 7: Native Features]
    E1 --> E8[Epic 8: OTA & Versioning]
    E4 --> E9[Epic 9: Store Compliance]
    E5 --> E9
    E6 --> E9
    E7 --> E9
    E9 --> E10[Epic 10: Release Engineering]
    E8 --> E10
    E10 --> E11[Epic 11: v4.0 Stabilization & Joint Release Gate]
```

Suggested grouping into delivery waves:

- **Wave A (foundations):** Epic 0 → 1 → 3. App boots, talks to the backend, you can log in.
- **Wave B (the Aspects):** Epic 2, 4, 6 (largely parallel) + Epic 5 (the big one).
- **Wave C (hardening):** Epic 7, 8, 9.
- **Wave D (ship):** Epic 10, then Epic 11 as the single go/no-go gate.

## How to read a "vibing sprint" doc

Every `planning_<n>_*.md` has the same shape so an agent can pick it up cold:

- **Front-matter:** `epic`, `depends_on`, `repos`, `estimate`, `aspect` (if it owns one).
- **Goal / v4.0 context / Scope (in & out).**
- **Prerequisites.**
- **Tasks** — the vibe-coding checklist, with **exact file paths** from the current codebase.
- **Acceptance criteria (Definition of Done).**
- **Test notes** (for the separate QA person).
- **Risks & mitigations / Open questions.**

## Epic index

| Epic | File | Aspect | Est. |
|------|------|--------|------|
| 0 — Preparation & Foundations | [planning_0_preparation.md](planning/planning_0_preparation.md) | — | M |
| 1 — Capacitor Shell & Minimal Native App | [planning_1_capacitor_shell.md](planning/planning_1_capacitor_shell.md) | — | M |
| 2 — App Identity & `Synaplan Mobile Vx.x` User-Agent | [planning_2_app_identity_useragent.md](planning/planning_2_app_identity_useragent.md) | **1** | S |
| 3 — Cross-Origin Connectivity & Auth | [planning_3_connectivity_auth.md](planning/planning_3_connectivity_auth.md) | — | L |
| 4 — White-Label Branding & Attribution | [planning_4_branding_whitelabel.md](planning/planning_4_branding_whitelabel.md) | **2** | L |
| 5 — Payments & Subscription Source Gating | [planning_5_payments_subscription.md](planning/planning_5_payments_subscription.md) | **3** | XL |
| 6 — Graphics, Logos & Store Assets | [planning_6_graphics_logos.md](planning/planning_6_graphics_logos.md) | **4** | M |
| 7 — Native Device Features & Lifecycle | [planning_7_native_features.md](planning/planning_7_native_features.md) | — | M |
| 8 — OTA, Versioning & Forced Update | [planning_8_ota_versioning.md](planning/planning_8_ota_versioning.md) | — | M |
| 9 — Store Compliance & UX | [planning_9_store_compliance.md](planning/planning_9_store_compliance.md) | — | M |
| 10 — Release Engineering & Delivery | [planning_10_release_engineering.md](planning/planning_10_release_engineering.md) | — | L |
| 11 — v4.0 Platform Stabilization & Joint Release Gate | [planning_11_v4_stabilization.md](planning/planning_11_v4_stabilization.md) | — | L |

## Confirmed decisions (carried from the original plan)

- Bundled `dist/` (no remote `server.url` in production).
- Native IAP worldwide; **self-hosted** server-side validation.
- Private `synaplan-apps` repo; frontend via **Git submodule** pinned to a release tag.
- Cross-platform subscriptions: an active sub from one source **blocks** purchase via another.
- **All tiers** purchasable via IAP (B2B-invoice-via-IAP not possible = accepted risk).
- **No push notifications** in v1.
- **OTA / live updates from day one** (Capgo).
- Apple Developer ($99/yr) + Google Play ($25 once) accounts — **must be set up** (Epic 0).

## Open questions tracked across epics

- Final production API/WS domain for `setApiBaseUrl` (Epic 3).
- Exact app name + bundle/app IDs + icon/splash source art (Epic 0 + 6).
- Yearly IAP products in addition to monthly? (Epic 5).
- Git host/org for the private repo + submodule access (HTTPS token vs SSH deploy key) (Epic 0).
- Google Cloud project + Pub/Sub topic for RTDN; Apple private key + Google service-account key (Epic 5).
- Tax advisor sign-off on channel-separated revenue (Stripe/Apple/Google) + B2B invoicing (Epic 5).
