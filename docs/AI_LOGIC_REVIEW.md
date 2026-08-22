# AI Logic Review — Gate 5 (Epic 12.6)

> A linter proves style; this gate proves **logic, regression, blast-radius, security, and
> store-policy correctness** that a linter can't see. Run it on **every PR in both repos**
> (`synaplan-apps` and the `synaplan` submodule) and **record the result on the PR**. Use the
> Bugbot review subagent and/or paste the prompt below; gates 1–4 must already be green.

## How to run it

1. Make sure gates 1–4 pass (`npm run ci-local` for the app; the `make` gate for the submodule).
2. Run a Cursor AI review of the **diff** (Bugbot subagent, or paste the prompt below into a
   review chat with the diff attached).
3. Walk every checklist item. For each, the review must state **pass / fail / N-A + why**.
4. Paste the summarized result (and any follow-ups) as a PR comment. A fail blocks merge.

## Review prompt (copy-paste)

```
Review this diff as Gate 5 of the Synaplan mobile-app quality gates. Gates 1–4 (lint,
click, parse, format) are already green — focus ONLY on what they can't catch. For each
item below answer pass / fail / N-A with a one-line reason, then give a short verdict.

1. DEFAULT-SAFETY / BLAST RADIUS (Epic 13)
   - Does every change to the public `synaplan` submodule stay a NO-OP for the unconfigured
     web / self-host product (no branding, no app client, no IAP config)?
   - Is each shared-file edit the smallest possible guarded hook (prefer a new file)? Is it
     listed in docs/SYNAPLAN_BLAST_RADIUS.md with a guard + default?
   - Does it carry the `// MOBILE-APP SEAM (Epic N)` marker and a guard
     (`isNativeApp()`/`Capacitor.isNativePlatform()`, server `client.isMobileApp`, BCONFIG
     default, or subscription `source`)?
   - Are contract changes ADDITIVE only (new optional keys with safe defaults; nothing
     removed/repurposed)? If a runtime-config schema changed, were schemas regenerated?

2. REGRESSION RISK in shared Aspect code (Epics 2/4/5)
   - Could this regress the web UA (must stay WITHOUT `Synaplan Mobile`), the default brand
     look (name/color/font/route), or the Stripe web checkout/portal/webhooks?
   - Does open-source/no-billing mode still work (billing disabled, unlimited, no purchase UI)?

3. STORE-POLICY LOGIC (Epics 5/8/9)
   - Anti-steering: NO in-app link/CTA to a web checkout for digital goods, no advertising of
     cheaper web prices. "Restore purchases" + manage-via-store present where expected.
   - IAP-only-in-app: the Stripe redirect is unreachable in the native client; entitlement is
     granted ONLY after server-side validation, bound to the user id (never device-only).
   - OTA: NO payment or behavior logic shipped via OTA (conforming web-asset fixes only).

4. SECURITY LOGIC (Epics 2/3)
   - The Bearer token is never logged and never put in localStorage/preferences (secure store
     only), and is stored/sent keyed PER configured server — server A's token never goes to B.
   - The User-Agent is treated as an identity HINT only — never as an auth/authorization control.
   - No secrets, keys, or `.env` values introduced into the diff.

5. i18n COMPLETENESS (Epic 4 / gate 4 cross-check)
   - Any new user-facing string is added to ALL four locales (en/de/es/tr), not just English.

VERDICT: block / approve-with-followups / approve, plus the must-fix list.
```

## Notes

- This checklist is derived from the encapsulation contract
  (Epic 13, realized in `docs/SYNAPLAN_BLAST_RADIUS.md`) and the store-compliance
  epics (5/8/9). Keep it specific — a rubber-stamp review defeats the gate.
- For purely app-repo (`synaplan-apps`) diffs that don't touch the submodule, items 1–2 mostly
  collapse to "N-A (no submodule change)", but still verify store-policy (3), security (4), and
  i18n (5) where relevant.
- The per-criterion → gate mapping lives in [`docs/QUALITY_GATES.md`](QUALITY_GATES.md).
