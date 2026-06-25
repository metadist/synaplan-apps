---
epic: 12
title: Quality Gates & Testable Merge Process (cross-cutting)
sprint: "Cross-cutting (applies to every epic)"
aspect: null
status: in-progress
depends_on: []
repos:
  - synaplan-apps (private)
  - synaplan (public, submodule)
estimate: M
---

# Epic 12 — Quality Gates & Testable Merge Process (cross-cutting)

> **This is not a sequential sprint — it is the merge gate that every other epic must pass.**
> "Make everything testable." Before any code merges (in `synaplan-apps` **or** in the public
> `synaplan` submodule), it must clear **five gates**: **lint**, **click**, **parse**, **format**,
> and an **AI logic review in Cursor**. Each epic's acceptance criteria map onto these five gates.

## Goal

Every change is mergeable only when it is **green on all five gates**, locally and in CI, with **no
filtered subsets** and **no `--no-verify` bypass**. The default-safety guarantee (the web /
self-host product looks and behaves exactly as before when the app/branding isn't configured) is an
explicit, tested part of the gate.

## The five gates (mandatory before merge)

| # | Gate | What it proves | Primary tools |
|---|------|----------------|---------------|
| 1 | **Lint** | Code style + static safety; no `any`, no dead config | ESLint, Prettier (lint mode), `vue-tsc`, PHPStan, PHP-CS-Fixer/PSR-12, markdownlint, `office-addin`-style config validation, `capacitor.config` typecheck |
| 2 | **Click** | The thing actually works when a human/agent uses it | Playwright (web SPA), component interaction tests (Vitest + Testing Library), native click-through (Maestro/Appium) on the app shell, manual reviewer path |
| 3 | **Parse** | Every config/contract parses + validates | Zod runtime-config parse tests, branding-config parse, server-config (URL) parse/normalize, UA-parser unit test, `capacitor.config.ts` + manifest/`Info.plist`/`PrivacyInfo.xcprivacy` validation |
| 4 | **Format** | Deterministic, reviewable, complete | `prettier --check`, `php-cs-fixer --dry-run`, `markdownlint`, JSON validity, **i18n completeness across all locales** |
| 5 | **AI logic review (Cursor)** | Logic, regression, blast-radius, security, store-policy correctness a linter can't see | A Cursor agent review of the diff (e.g. Bugbot + a checklist prompt), required and recorded on the PR |

## Tasks

### 12.1 — Wire the five gates to existing commands (no new CI without sign-off)

- [ ] **`synaplan` submodule** changes reuse the repo's own gate (do **not** invent a parallel one):
      `make -C backend lint && make -C backend phpstan && make -C backend test` and, for frontend,
      `make -C frontend lint`, `docker compose exec -T frontend npm run check:types`,
      `make -C frontend test`. After any runtime-config schema change:
      `make -C frontend generate-schemas` then re-run the type check. Run the **full** suite,
      unfiltered (see the repo's "`--filter` ≠ `make test`" trap).
- [x] **`synaplan-apps`** repo gets its own `npm run ci-local` (gate 1 typecheck + gate 3
      parse/config tests), documented in the README. **Dependency-free** by design: uses the
      bundled `tsc` (`tsconfig.json` typechecks `capacitor.config.ts`) + Node's built-in test
      runner (`node --test tests/*.test.mjs`) covering the Epic 10.1 build-identity resolver.
      _Still open (needs new dev-deps → sign-off): ESLint/Prettier (gate 1 lint + gate 4 format)
      and Playwright/Maestro click tests (gate 2)._
- [ ] **Pre-commit / pre-push hooks** enforce the gate so it can't be silently skipped; **never**
      bypass with `--no-verify` on a branch headed for `main`.

### 12.2 — Gate 1: Lint

- [ ] App repo: ESLint + Prettier (lint) + TypeScript strict on all `synaplan-apps` TS;
      `capacitor.config.ts` typechecks.
- [ ] Submodule changes: PSR-12 + PHPStan (backend), ESLint + `vue-tsc` (frontend), markdownlint
      (docs). No new lint suppressions without a tracked reason.

### 12.3 — Gate 2: Click (interaction / E2E)

- [ ] **Web SPA (Playwright)** scenarios for the platform-side features this program adds:
      - Branding: default deployment vs a branded deployment (name, color, **font**, **start
        page**, attribution) — Epic 4.
      - Auth + subscription UI gating (web = Stripe path visible, no IAP) — Epic 5.
- [ ] **Component interaction tests (Vitest + Testing Library)** for new components (e.g.
      `<BrandAttribution>`), stubbing heavy deps per the repo's frontend-test guidance.
- [ ] **Native click-through** of the app shell (Maestro or Appium): launch → **change server →
      save → reset to default** (Epic 3 §3.0), log in, open chat, background/resume. Runs on the
      beta tracks for the release gate (Epic 10/11), smoke-level locally.
- [ ] A short, written **reviewer click-path** (the Guideline-4.2 "why this is an app in 30s" walk,
      Epic 9) that QA repeats each release.

### 12.4 — Gate 3: Parse (config & contract validation)

- [ ] **Runtime-config Zod parse** tests: `branding` block (name/colors/**fonts**/logo/**start
      page**/attribution) and the `client` block (Epic 2) parse with defaults and reject malformed
      input.
- [ ] **Server-config parse** (Epic 3 §3.0): URL normalize (`https://`, trailing slash), accept
      valid Synaplan server, reject bogus/non-Synaplan/`http://`.
- [ ] **UA parser** unit test (Epic 2): `V4.0`, `V4.0.1` accepted; spoof-ish strings rejected.
- [ ] **Native manifests** validate in CI: `capacitor.config.ts`, Android manifest,
      iOS `Info.plist` purpose strings (Epic 7), `PrivacyInfo.xcprivacy` incl. all SDK manifests
      (Epic 9).

### 12.5 — Gate 4: Format

- [ ] `prettier --check`, `php-cs-fixer --dry-run`, `markdownlint` all clean.
- [ ] **i18n completeness**: a test fails if any key is missing from any locale —
      `synaplan` set `{en,de,es,tr}`; the Synamail-style set is out of scope here. (A missing key
      silently falls back to English — treat it as a format failure.)
- [ ] JSON/YAML config files are valid and stably ordered.

### 12.6 — Gate 5: AI logic review in Cursor (required before merge)

- [ ] Every PR (both repos) gets a **Cursor AI review of the diff** before merge — run the Bugbot
      review subagent and/or a fixed review prompt, and record the result on the PR. It must
      explicitly check:
      - **Default-safety / blast radius:** does the change stay a no-op for the unconfigured web /
        self-host product? (cross-check [Epic 13](planning_13_synaplan_encapsulation.md)).
      - **Regression risk** in shared code touched by Aspects 1/2/3 (Epics 2/4/5).
      - **Store-policy logic:** anti-steering, IAP-only-in-app, no payment logic via OTA
        (Epics 5/8/9).
      - **Security logic:** Bearer never logged, per-server identity isolation (Epic 3), no UA used
        as an auth control (Epic 2).
- [ ] Record a short, repeatable **review prompt/checklist** in `docs/` so any reviewer (human or
      agent) runs the same logic review.

### 12.7 — Per-epic test matrix (make "everything testable" concrete)

- [ ] Each `planning_<n>_*.md` "Test notes" section maps its checks to the five gates above. Keep a
      single matrix (in this repo's `docs/QUALITY_GATES.md`) so it's obvious which gate covers which
      acceptance criterion, and which are still manual-only (with a reason).

## Acceptance criteria (Definition of Done)

- A documented `make ci-local` (app) and the submodule's existing gate together cover gates 1–4;
  both are wired into pre-commit/pre-push and CI.
- No epic can be marked done unless its acceptance criteria are mapped to (and passing on) the five
  gates, including the **default-safety** regression for the platform.
- The AI logic review (gate 5) is a recorded, required step on every PR in both repos.
- `docs/QUALITY_GATES.md` (the per-epic test matrix) exists and is kept current.
- The full suites run **unfiltered** and green on a clean checkout (mind the Docker cache-perm trap
  noted in the `synaplan` AGENTS guide).

## Test notes (for the QA person)

- Try to merge a deliberately-breaking change for each gate (a lint error, a broken click flow, a
  malformed config, an unformatted file, a logic regression) and confirm the gate **blocks** it.
- Confirm the default (unconfigured) web product is byte-for-byte unchanged by the program's
  platform-side changes (the standing regression test).

## Risks & mitigations

- **"Green locally, red in CI" from filtered tests:** always run unfiltered (`make test`), per the
  repo trap list.
- **Gate fatigue → bypass:** hooks enforce it; `--no-verify` is forbidden on `main`-bound branches.
- **AI review as rubber-stamp:** keep the checklist specific (blast radius, store policy, security)
  so it catches real issues, not just style.

## Open questions

- Native click-through tool: Maestro vs Appium (or Playwright-mobile) for the app shell?
- Does gate 5 (AI review) block merge hard, or advise + require a human ack? (Proposed: required +
  recorded.)
