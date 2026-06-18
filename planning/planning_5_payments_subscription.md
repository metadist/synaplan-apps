---
epic: 5
title: Payments & Subscription Source Gating
sprint: "Sprint 5"
aspect: 3
status: planned
depends_on: [3]
repos:
  - synaplan-apps (private)
  - synaplan (public, submodule)
estimate: XL
---

# Epic 5 — Payments & Subscription Source Gating

> **Owns Aspect 3:** *"Payment for web can't be done via web inside the app anymore. A
> subscription is either `ACTIVE` or not, and it can only be owned by one channel — from the web
> with Stripe, or from the app via Apple Pay / Google Pay (which costs us ≈30%). This must be
> clearly configured and planned."* This is the largest, highest-stakes epic: real money, store
> rejection risk, and tax implications.

## Goal

A single, authoritative subscription state (`ACTIVE` / not) with an explicit **`source`**
(`stripe` | `apple` | `google`). Web buys via Stripe only; the app buys via native IAP only; an
active sub from one channel **blocks** purchase from another. The 30% store commission is an
explicit, configured part of pricing. The server is the only source of truth for entitlement.

## v4.0 context / Why

Apple **and** Google treat AI subscriptions as digital goods → **IAP is mandatory** in the app
(15–30%, worldwide). The existing Stripe hosted-checkout **redirect**
(`SubscriptionView.vue` → `window.location.href`) is **not allowed** in the app. v4.0 needs the
billing model to be channel-aware and store-compliant, and clearly configurable for the SaaS vs
self-hosters (who may run Stripe-only, or no billing at all).

## Current state (what we're changing)

- Tier lives in `BUSER.BUSERLEVEL` (`NEW/PRO/TEAM/BUSINESS/ADMIN`); Stripe state in
  `BUSER.BPAYMENTDETAILS` JSON. **There is no `source` field today** — provenance is only
  inferred. `User::hasActiveSubscription()` = Stripe status `active` AND unexpired end.
- `BillingService::isEnabled()` gates SaaS-vs-open-source mode (off if Stripe keys are
  placeholders → unlimited limits, subscription UI hidden).
- Web flow: `SubscriptionController` (checkout/status/sync/portal/cancel) + `StripeWebhookController`.
- Frontend: `SubscriptionView.vue`, `subscriptionApi.ts`, success page calls
  `syncFromStripe()` then refreshes `user.level`.

## Scope

### In scope

- **Subscription `source` model**: explicit channel on every active subscription; unified
  `ACTIVE` status + status endpoint that returns `{ active, tier, source, manageUrl }`.
- **Channel gating**: web = Stripe checkout only; app = IAP only; cross-channel purchase blocked.
- **Native IAP frontend** (cordova-plugin-purchase / CdvPurchase) with restore + store pricing.
- **Self-hosted IAP backend validation** (Apple App Store Server API v2 + ASSN V2; Google
  subscriptionsv2.get + RTDN via Pub/Sub + acknowledge).
- **30% commission configuration**: explicit price-point config per channel, documented and
  store-product-mapped.
- Anti-steering + manage-via-store deep links.

### Out of scope (deferred)

- Yearly IAP products (only if business confirms; monthly first).
- B2B IAP invoicing (accepted limitation — see Tax).

## Tasks

### 5.1 — Subscription `source` + unified ACTIVE model (backend, synaplan submodule)

- [ ] Add an explicit **`source`** to the subscription record in `BPAYMENTDETAILS.subscription`
      (`stripe` | `apple` | `google`), set by each channel's handler. Backfill existing Stripe
      subs to `source: 'stripe'`.
- [ ] Extend `User` subscription helpers (`getSubscriptionData`, `hasActiveSubscription`,
      `getRateLimitLevel`) to be source-aware; entitlement is unified — `ACTIVE` if **any** valid
      channel is active, but **only one** channel may own it at a time.
- [ ] `BillingService`: know the source, compute a single status, and expose a **`manageUrl`**
      hint per source (Stripe portal vs iOS/Android system subscription settings).
- [ ] Update the status endpoint (`SubscriptionController` `GET /subscription/status`) to return
      `{ active, tier, source, manageUrl, cancelAtPeriodEnd, ... }`.

### 5.2 — Channel gating + anti-steering (backend + frontend)

- [ ] **Web/Stripe path stays web-only**: keep `SubscriptionController` checkout for the browser.
      Using the platform's `client` flag (Epic 2) + `Capacitor.isNativePlatform()`, ensure the
      Stripe **redirect is never invoked inside the app**.
- [ ] **App/IAP path is app-only**: the app shows IAP purchase, never the Stripe redirect; hide
      Stripe-specific UI in `SubscriptionView.vue` when native.
- [ ] **Block-cross**: if a user already has an `ACTIVE` sub from source A, block purchasing via
      source B (server-enforced on both the Stripe checkout endpoint and the IAP validation
      endpoint). UI explains where to manage the existing sub.
- [ ] **Anti-steering**: in the app, do **not** advertise cheaper web prices or link to web
      checkout for digital goods (Apple/Google rule). Informational mention is fine; active
      steering is not.

### 5.3 — Native IAP frontend (synaplan-apps + submodule glue)

- [ ] Integrate an IAP plugin (`cordova-plugin-purchase` / CdvPurchase) — **must use Google Play
      Billing Library v7+ (prefer v8)**, mandatory since 31.08.2026 or the update is rejected.
- [ ] Subscription UI platform switch (in `SubscriptionView.vue` via native flag): IAP purchase
      sheet instead of Stripe redirect; show **store-localized price/duration** from product data.
- [ ] **"Restore purchases" button** (Apple-mandatory) + a "manage subscription" link to the
      system subscription settings.

### 5.4 — Self-hosted IAP validation (backend, synaplan submodule)

- [ ] New `MobilePurchaseController` + service: accept the app's receipt/token + the
      authenticated user (Bearer), validate **server-side**, set `BUSERLEVEL` + `BPAYMENTDETAILS`
      analogous to `StripeWebhookController`. **Never** grant entitlement from a client success
      callback — server is the single source of truth, **bound to the user ID** (never just the
      device).
- [ ] **Apple**: App Store Server API **v2** (JWS verification of the StoreKit 2 transaction;
      `verifyReceipt` is deprecated) + an **App Store Server Notifications V2** endpoint for
      renew/cancel/refund. Use the App Store Server Library / `SignedDataVerifier` for cert-chain
      checks (don't hardcode certs). PHP candidate: `readdle/app-store-server-library-php`.
- [ ] **Google**: Play Developer API (`purchases.subscriptionsv2.get`) via `google/apiclient` +
      **Real-time Developer Notifications** over a Pub/Sub push endpoint. **`acknowledge` within 3
      days** of granting entitlement (else auto-refund). **Do not** unlock `PENDING` purchases
      (wait for RTDN). Use **Play Integrity** to confirm requests come from the real app binary.
- [ ] **Performance/quota**: do **not** re-verify with the store on every app start — the local
      DB is the working copy; sync via RTDN/ASSN + on new purchase only.
- [ ] **Replay protection**: a receipt/transaction grants entitlement to exactly one user, once;
      detect sandbox vs prod server-side.
- [ ] **Refund/Grace/Hold**: process refund, grace period, billing retry, account hold
      notifications → revoke/hold entitlement.

### 5.5 — Store products + 30% commission configuration (the "clearly configured" part)

- [ ] Create store products in App Store Connect + Play Console; map product IDs to tiers
      (PRO/TEAM/BUSINESS, monthly; yearly optional). Existing reference price points ≈ €19.95 /
      €49.95 / €99.95.
- [ ] **Configure pricing channel-aware**: a config block (BCONFIG) that records, per tier, the
      **Stripe price** and the **store price tier**, and documents that the store price **bakes in
      the ≈30% commission** (15% may apply: first $1M/yr, or Google subs in year 2+). Make the
      assumption explicit so finance can reason about net.
- [ ] Map store product IDs → tiers in the backend (mirror `mapPriceIdToLevel()` for IAP).

### 5.6 — Infra & secrets (handoff to Epic 10/SECRETS)

- [ ] Provision a Google Cloud project + Pub/Sub topic for RTDN; manage Apple private key +
      Google service-account key as secrets (record in `docs/SECRETS.md`).

## Acceptance criteria (Definition of Done)

- The status endpoint returns a single `ACTIVE` truth with an explicit `source` and a correct
  `manageUrl`; existing Stripe subs report `source: 'stripe'`.
- In the **app**: a sandbox IAP purchase grants the right tier **only after server validation**,
  the entitlement is bound to the user, "Restore purchases" works, and **no Stripe redirect is
  reachable**.
- On the **web**: Stripe checkout still works and is the only purchase path.
- **Block-cross verified**: a user with an active Stripe sub cannot buy via IAP (and vice-versa),
  server-enforced, with a clear "manage where you bought it" message.
- Apple ASSN V2 + Google RTDN update entitlement on renew/cancel/refund **without** the app open.
- Google purchases are `acknowledge`d < 3 days; `PENDING` not unlocked.
- The 30%/15% commission assumption and channel price mapping are documented in config + a doc.
- Open-source mode (no Stripe keys, no store config) still works: billing disabled, unlimited
  limits, no purchase UI.

## Test notes (for the QA person)

- Use Apple **Sandbox testers** + Google **license-testing** accounts (no real charges).
- Real device recommended (iOS simulator IAP coverage is limited); Android emulator API 24+ with
  current System WebView.
- Send the stores' **test notification payloads** to the ASSN V2 / RTDN webhooks: renewal,
  cancel, refund, grace period, account hold.
- **Cross-channel conflict**: active Stripe-web user → IAP purchase must be blocked, and vice-versa.
- **Google acknowledge**: don't acknowledge → confirm auto-refund; simulate a `PENDING` purchase.
- Backend unit tests with **mocked store APIs** (no real store calls in tests).
- Run the full backend gate: `make -C backend lint && make -C backend phpstan && make -C backend test`.

## Risks & mitigations

- **Store rejection (steering / external payment in app):** strict IAP-only + anti-steering;
  reviewed against Epic 9.
- **Entitlement spoofing:** server-only validation, user-bound, replay-protected, Play Integrity /
  Apple JWS verification.
- **Billing-library version reject (Google):** ensure the IAP plugin uses Billing v7+/v8.
- **Quota/perf from over-verifying:** sync via notifications, not per-start polling.
- **Tax/accounting complexity:** see below; get advisor sign-off.

## Tax & accounting (advisor to confirm)

- **Web (Stripe):** Synaplan is Merchant of Record → owes/remits VAT (Stripe Tax/OSS).
- **App (IAP):** Apple/Google are MoR → collect/remit consumer VAT, keep **15–30%**, pay net.
  Booked as revenue; corporate/trade tax applies.
- **Channel-separated bookkeeping:** the same tier can arrive via Stripe/Apple/Google → split
  revenue cleanly per channel with separate reports/currencies.
- **B2B (accepted risk):** all tiers are IAP-purchasable, but IAP issues only simple consumer
  receipts — no B2B invoice with VAT + buyer VAT-ID. Company buyers needing a proper invoice
  should buy via Web/Stripe (inform in-app, don't actively steer).

## Open questions

- Add yearly IAP products at launch, or monthly only first?
- Exact store price tiers per region once the commission is baked in?
