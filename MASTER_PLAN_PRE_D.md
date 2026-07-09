# MASTER_PLAN_PRE_D.md — everything before Phase D (July 2026)

> **The single ordered plan for all remaining work before Phase D** (Phase D = Sign in with Apple, RevenueCat paywall, App Store submission — LAST, founder's call). Combines the UI/UX revamp with roadmap items A/B/C from `STATE.md`. Design authority: `DESIGN.md` v2 + `docs/SCREEN_SPECS.md` + `docs/DESIGN_SYSTEM_V3.md` + `reference/competitors/design-teardown.md`.
>
> **Process per chunk:** write a detailed TDD implementation plan (superpowers:writing-plans → `docs/superpowers/plans/`) when the chunk starts → execute task-by-task → verify (deno tests + iOS unit tests + **6-shot screenshot matrix**: SE 3rd gen / 17 Pro / 17 Pro Max × default / XXL Dynamic Type) → device install → founder review → commit + MEMORY.md entry. A chunk is DONE only when its exit criteria all pass.

---

## Chunk 0 — Cross-cutting UI hygiene (small, do first)
Fixes every screen inherits. From the July 2026 code audit.
- Scaled icon glyphs: replace `.font(.system(size:N))` on functional SF Symbols with `@ScaledMetric`/semantic fonts — HomeView:250,293,362,491 · OnboardingView:402,423 · MeView:76 · PlanView:19 · ProductView:243 · ResultComponents:535.
- Spacing tokens: add `Theme.Space.s45 = 20`; replace literals (HomeView:87, MeView:29, PlanView:41).
- Me tab: profile load-error → quiet inline retry row (currently silent defaults).
- Ingredient sheet: half→full detents verified.
- Onboarding: multi-select affordance check (checkbox not radio), allergen benefit microcopy, final summary card.
- Pantry: swipe-to-remove + confirm; sort menu (recent/score).
**Exit:** all screens pass the 6-shot matrix; no raw size/padding literals in view files; deno + iOS tests green.

## Chunk 1 — Result screen upgrade (flagship trust moment)
Per SCREEN_SPECS §4. The screen that wins reviews.
- **Watch-outs / Benefits bar-meter sections** (teardown steal #5/#8): labeled meters with real values from the score breakdown; tap → sourced detail. Neutral headers per COPY_DECK.
- Additive rows → severity-word + category-pill format, neutral tier words (steal #9).
- Harmful/beneficial count pre-read above ingredient list (steal #6).
- Sources rows: named DB + fetch date (steal #3).
- Wire `ResultSkeletonView` (needed once Search/deep-links open Result pre-fetch).
- **Report an issue → real endpoint**: `POST /product/:id/report` edge function (reason enum + free text + reporter anon id; RLS insert-only) + iOS submit sheet + thanks state. [roadmap A]
**Exit:** meters render from real breakdown data (no client math); report row round-trips to DB; 121+ deno tests still green + new endpoint tests; matrix pass.

## Chunk 2 — Search + manual barcode entry [roadmap A]
Kills the biggest dead-end (no camera / no barcode / broken label).
- Backend: `GET /search?q=` edge function → OFF search API v2, normalized to our product shape; barcode passthrough to existing `/product/:barcode`.
- iOS: Search screen (SCREEN_SPECS §9) — field + numeric barcode pad toggle, default state = recent scans (never blank), result rows → Result screen.
- Entry points: Home field under hero · "Enter barcode manually" action in Scan error/labelNotFound banners.
**Exit:** search a name → result opens with full score; barcode typed → same path as scan; empty/error states per spec; matrix pass.

## Chunk 3 — Swaps engine: "See a better option" [roadmap A flagship]
Closes the loop no competitor closes (principle #4). SCREEN_SPECS §5.
- Backend: `GET /product/:id/swaps` — rank candidates: same OFF category → better band/score (current score, not highest-ever — depends on Chunk 4 view if sequenced after; otherwise compute inline) → restriction-safe vs profile allergens (RLS) → pantry-first. Deterministic, sourced "why better" facts from DB diffs (no LLM math).
- iOS: swaps sheet — ranked cards, mini rings, delta chip, sourced why-better line, Save-to-pantry; honest thin-results empty state (current stub copy moves here).
- Result CTA switches from stub tip → real sheet.
**Exit:** low-score demo product returns ≥1 real better option with sourced reason; allergen-safe filtering verified with a test profile; empty state honest; deno tests for ranking; matrix pass.

## Chunk 4 — Data & correctness wave [roadmap B]
- **Current-score DB view**: `product_current_scores` (top-1 per product by scored_at) → trending + swaps + search read from it (fixes highest-ever bug).
- OCR parser: drop redundant parenthetical orphan ("colour (E150d)" → no stray "Colour" entry) + regression tests.
- **Rate-limit `/chat`** (per-user sliding window, 429 + calm client copy) — required before chat ships publicly.
- Re-score cron on `score_version` bump (Supabase scheduled function; re-runs cached products).
- Dietitian weight review: export current factor weights + calibration sheet → flag for founder's reviewer; no code change unless weights change.
**Exit:** trending shows current scores (verify vs score_results history); OCR regression tests green; chat returns 429 under burst; cron dry-run re-scores a stale product.

## Chunk 5 — Compare v1 [roadmap A]
SCREEN_SPECS §10. Two products side-by-side, shared-scale meters, subtle winner tint, "Pick this one → save". Entry from Result overflow + Search multi-select. Compact = A/B segmented stack.
**Exit:** two demo products compare correctly on SE and Pro Max; VoiceOver reads aligned rows sensibly; matrix pass.

## Chunk 6 — Robustness, offline, a11y sweep [roadmap C]
- Empty/loading/error pass across ALL screens against SCREEN_SPECS states (most exist — close gaps found in audit).
- Offline: airplane-mode pass — every network surface gets calm offline copy + retry; cached pantry/products still browsable.
- Camera video-frame orientation edge (shatter frame on non-portrait capture).
- Full a11y device sweep: VoiceOver walk of every flow + Dynamic Type XXL on device (not just sim), contrast re-verify (green fills, lime-on-dark).
- Landscape: confirm portrait lock explicit, nothing crashes.
**Exit:** written pass/fail checklist per screen filed in `docs/TEST_PLAN.md` addendum; zero clipped layouts at XXL; offline never dead-ends.

## Chunk 7 — Analytics + feedback + legal surfaces [roadmap A/D-adjacent, pre-D]
- Analytics events per `docs/ANALYTICS_METRICS.md`: scan_started/succeeded/failed, result_viewed, why_expanded, swap_viewed/saved, chat_opened, report_submitted → Supabase `events` table (anon id, no PII), batched client logger.
- Rating prompt: emoji sentiment gate after 3rd successful scan (teardown steal #18; never mid-onboarding).
- Legal: Privacy Policy + Terms screens + full OFF/ODbL attribution page (Me tab) — same tokens, no boilerplate look.
- COPY_DECK pass over all new copy (swaps, search, compare, reports, offline states).
**Exit:** events visible in DB from a device session; legal screens reviewed by founder; copy deck updated.

## Chunk 8 — Planner v1 (OPTIONAL pre-D, founder's call)
Per `docs/AI_PLANNER_SPEC.md` + user-flows §4–5: weekly grid, add-from-pantry/search, optimizer backend (OR-Tools/PuLP), AI assist layer (suggestions editable, LLM never does math), shopping list with have/need. **Gate: start only after Chunks 1–3 shipped and founder green-lights.** If skipped, Plan tab keeps the calm placeholder into Phase D.
**Exit (if built):** plan a week from pantry + swaps; list generates; ED-safe review (no calorie surfacing to opted-out users).

---

## Sequencing & rationale
```
0 → 1 → 2 → 3 → 4 → 5 → 6 → 7 → (8?) → Phase D
```
- 0 first: cheap, de-risks every later screenshot review.
- 1 before 2/3: Result is where search/swaps land users; upgrade the destination first.
- 2 before 3: search infra (OFF category/product normalization) is reused by swaps ranking; manual entry also unblocks demo/testing of swaps without a camera.
- 4 after 3 but swaps must read *current* scores — if 3 lands first it computes current-score inline, then switches to the view in 4 (note in both plans).
- 5 after meters exist (1) — compare reuses the meter component.
- 6 sweeps everything after feature churn stops; 7 last because analytics wants final event names.

## Skills toolchain (use these, every chunk)

| Skill | When | How |
|---|---|---|
| **`ui-ux-pro-max`** (installed `~/.claude/skills/ui-ux-pro-max`) | Design + build + review of every UI chunk | Query the DB before building: `python3 ~/.claude/skills/ui-ux-pro-max/scripts/search.py "<topic>" --stack swiftui` (SwiftUI do/don't rules) and `--domain ux` (99 UX guidelines). Run its **Pre-Delivery Checklist** (App UI section: icons, interaction, light/dark contrast, layout, a11y) as a merge gate alongside our teardown AVOID list. ⚠️ **Never adopt its palette/font suggestions** — brand is locked to DESIGN_SYSTEM_V3 (mint canvas, bold green, Space Grotesk); use it for rules, stack guidance, and checklists only. |
| **`/ux-writing`** | All new user-facing copy (Chunks 1, 2, 3, 5, 7) | Patterns: errors = `[what failed]. [why]. [what to do]`, 8–14-word sentences, verbs first, no blame, no dead-ends, no "Something went wrong". New-surface copy already drafted in `docs/COPY_DECK.md` §New surfaces — implement those strings verbatim; any *new* string goes through the skill's 4-phase edit (purposeful → concise → conversational → clear) and into the deck. |
| **`/ios-design-review`** | End of every UI chunk | Screen-level review on the sim screenshots before device install. |
| **`/accessibility-audit`** + **`/frontend-a11y`** | Chunk 6 sweep (and spot-checks per chunk) | Structured WCAG 2.1 AA pass; complements the manual VoiceOver walk. |
| **`/design-review` / `/ux-audit`** | Chunk 6 + pre-Phase-D exit | Full-app audit against DESIGN.md laws + teardown AVOID list. |
| **`superpowers:writing-plans`** | Start of every chunk | Detailed TDD implementation plan per chunk (already standing process). |

## Standing rules (every chunk)
- UI/UX never compromised (founder directive) — matrix screenshots before device, device review before merge-to-main.
- Principles gate: transparency, ED-safe, honest states, never-a-dead-end, LLM-never-does-math, AA a11y.
- Teardown AVOID list (`design-teardown.md`) + ui-ux-pro-max Pre-Delivery Checklist are blocking review gates.
- All new copy from `docs/COPY_DECK.md` §New surfaces (drafted via /ux-writing); new strings go through the deck, never invented inline.
- Keys stay out of repo; **rotate the pasted Cerebras/Groq/USDA keys + Supabase access token before Chunk 7 analytics work** (STATE.md warning stands).
- Each chunk: MEMORY.md decision entry + STATE.md status line update on completion.

## Explicitly deferred to Phase D
Sign in with Apple + account linking + in-app deletion · RevenueCat paywall (spec in SCREEN_SPECS §14) · App Store branding/screenshots/submission · prod Supabase project migration + key rotation finale.
