---
epic: 11
title: v4.0 Platform Stabilization & Joint Release Gate
sprint: "Sprint 11 (release gate)"
aspect: null
status: planned
depends_on: [10]
repos:
  - synaplan (public)
  - synaplan-apps (private)
estimate: L
---

# Epic 11 — v4.0 Platform Stabilization & Joint Release Gate

> v4.0 ships **two things at once**: a *pretty bug-free platform* and a *mobile app*. This epic is
> the deliberate stabilization pass on the platform plus the single **go/no-go gate** that
> releases the platform and the app together.

## Goal

Drive the platform to a known-good, low-bug state and run one coordinated release gate that signs
off platform v4.0 + the iOS/Android apps as a unit.

## v4.0 context / Why

The mobile app is a long-lived client against an evolving backend; shipping it on top of a shaky
platform multiplies risk. A focused bug-bash + a shared gate ensures the new app launches on a
stable base and that the four Aspects didn't regress the web.

## Scope

### In scope

- A time-boxed **bug-bash / triage** on the platform (web + backend).
- Regression sweep of the four Aspects' platform-side changes (they all touched shared code).
- A documented **release gate checklist** with explicit go/no-go criteria.
- Coordinated tagging: pin the app's submodule to the exact v4.0 release tag.

### Out of scope

- New features. This is stabilization + release only.

## Tasks

### 11.1 — Bug-bash & triage

- [ ] Time-boxed bug-bash across core flows (chat/SSE, RAG, widgets, auth, billing, admin).
      Triage into must-fix-for-v4.0 vs later; fix the must-fixes.
- [ ] Prioritize regressions introduced by the Aspect work (Epics 2, 4, 5) since they edited
      shared frontend/backend code.

### 11.2 — Aspect regression sweep (web must be unaffected)

- [ ] **Aspect 1 (UA):** web User-Agent unchanged; backend client-detection defaults to web.
- [ ] **Aspect 2 (branding):** unconfigured deployment looks identical to pre-v4.0 (the default
      regression test from Epic 4); all four locales intact.
- [ ] **Aspect 3 (payments):** web Stripe checkout + portal + webhooks still fully work; existing
      subscriptions report `source: 'stripe'`; open-source (no-billing) mode unaffected.
- [ ] **Aspect 4 (assets):** web favicons/PWA icons present + correct; brand color consistent.

### 11.3 — Full quality gates (both repos)

- [ ] Backend: `make -C backend lint && make -C backend phpstan && make -C backend test`
      (full suite, unfiltered; re-record characterization snapshots only after reviewing the diff).
- [ ] Frontend: `make -C frontend lint`, `docker compose exec -T frontend npm run check:types`,
      `make -C frontend test`. If runtime-config schema changed (Epics 2/4/8):
      `make -C frontend generate-schemas` then re-run type check.
- [ ] App: Epic 3 (auth) + Epic 5 (IAP) acceptance re-verified in **release/TestFlight + Play
      Internal** builds.

### 11.4 — Release gate checklist + coordinated tag

- [x] Produce a `docs/RELEASE_GATE_v4.md` with explicit go/no-go items pulling from every epic's
      acceptance criteria (auth, IAP source-gating, branding default-safety, privacy manifest,
      assets, OTA, forced-update). _Drafted: decision-oriented gate with engineering gates (§1),
      Aspect default-safety regression (§2), per-epic acceptance (§3), store/assets (§4),
      accounts/secrets (§5), crash reporting (§6), coordinated tagging (§7), sign-off + waivers
      (§8). Cross-links QUALITY_GATES / LAUNCH_CHECKLIST / COMPATIBILITY instead of duplicating._
- [ ] Confirm `docs/COMPATIBILITY.md` (Epic 8) is accurate; pin the app submodule to the exact
      v4.0 release tag; tag platform + app together.

## Acceptance criteria (Definition of Done)

- Must-fix bug list is closed; remaining issues are explicitly deferred with owners.
- All four Aspects' platform changes are confirmed **no-ops for the web** when the app/branding
  isn't configured.
- Full backend + frontend gates green (unfiltered); app auth + IAP green in beta tracks.
- `docs/RELEASE_GATE_v4.md` is complete and every go item is checked.
- Platform v4.0 and the apps are tagged consistently and the submodule is pinned to that tag.

## Test notes (for the QA person)

- Run the **full** automated suites (not filtered subsets) on a clean checkout (mind the
  Docker-restart cache-permission trap noted in the repo's AGENTS guide).
- Manually exercise the web app end-to-end to confirm no Aspect regressed it.
- Re-run the app's critical paths (Epic 3 auth, Epic 5 IAP) one final time in release tracks.

## Risks & mitigations

- **Aspect changes silently regressing web:** dedicated regression sweep (11.2) + default-safety
  tests baked into Epics 2/4/5.
- **Scope creep during stabilization:** strict "no new features" rule; triage discipline.
- **Mismatched tags App↔platform:** coordinated tagging + compatibility matrix as the gate.

## Open questions

- Hard launch date for v4.0, and is the app a same-day launch or a fast-follow after the platform?
