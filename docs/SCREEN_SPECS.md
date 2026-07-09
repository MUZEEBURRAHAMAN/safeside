# SCREEN_SPECS.md — screen-by-screen design specs (v1, July 2026)

> Every screen, first-run to settings. Grounded in: `DESIGN.md` v2 (charter + responsive system) · `docs/DESIGN_SYSTEM_V3.md` (tokens/components) · `reference/competitors/design-teardown.md` (pattern sources, cited as [T-n] = Master STEAL #n) · a full audit of the current SwiftUI code (July 2026). Each spec: **Purpose → Layout → Current state → Changes → States → Responsive → A11y.**
>
> Global rules apply to every screen and are not repeated: 4 states, Dynamic Type XXL reflow, VoiceOver, 44pt targets, tokens-only, next-action law, COPY_DECK vocabulary, SE/Pro Max/XXL screenshot matrix before merge.

**Audit headline (what the code already does well):** trust footer, next-action CTA, confidence chips, allergen banner + VO announcement, skeletons on Home/ingredients, Reduce-Motion everywhere, grid reflow at a11y sizes. **Cross-cutting fixes owed:** fixed icon glyph sizes → `@ScaledMetric`/semantic fonts (HomeView 250/293/362/491, OnboardingView 402/423, MeView 76, PlanView 19, ProductView 243, ResultComponents 535) · off-grid padding literals (`20` in HomeView:87, MeView:29; `32` in PlanView:41) → add `Theme.Space.s45=20` token or move to s5 · no global search (biggest gap).

---

## 0. Launch / first-run
**Purpose:** instant, quiet start; no marketing carousel [T: FS splash].
**Layout:** brand mark centered on `canvas`, nothing else. Anonymous auth resolves in background; land on Onboarding (first run) or Home.
**Current:** no dedicated splash beyond system launch screen — fine. **Change:** none (keep quiet). If auth exceeds ~1.5s, show one specific line ("Setting up your private profile…") [T-14].

## 1. Onboarding (8Q, skippable)
**Purpose:** personalize (allergens/diet/goals) with zero pressure; every step skippable (ED-safe).
**Layout (per V3 §5.10):** slim progress bar + "Step N of M" → big display question → option cards / multi-select chips / steppers → quiet "Skip this question" → footer Back + pill Continue. "Skip for now" in nav.
**Current:** built to spec, strong a11y. **Changes (polish only):**
1. Fixed glyphs (L402 17pt, L423 12pt) → scaled.
2. Multi-select steps: verify selection indicator reads as *multi* (checkbox affordance, not radio) — Ivy's confusion fault [AVOID-11].
3. Add one-line benefit microcopy under allergen question ("So scans can flag these automatically — change anytime") [T: Ivy 56 benefit-first].
4. Final step: calm summary card ("You can edit all of this in Me") — closes the loop, no dead-end.
**States:** content only (writes fire-and-forget) — correct.
**Responsive:** option cards minHeight 64 OK; chips wrap; verify SE at XXL = 2-line options don't clip (they wrap — confirm in matrix).

## 2. Home
**Purpose:** re-entry point: scan fast, resume pantry, discover trending.
**Layout:** hero header ("What's really in your food?") → **search field (NEW, directly under hero)** → Scan CTA card (green anchor) → optional daily-insight tile → Pantry header + Recent/Favorites filter chips → 2-col product grid (grade dots, hearts) → Trending healthy rail.
**Current:** all built except search; states complete with skeletons.
**Changes:**
1. **Add search entry** — tappable field-styled row ("Search any product…", magnifier icon) → pushes Search screen (§9). The single biggest missing entry point; also serves no-camera/no-barcode cases [T-22].
2. Consider mini progress-ring variant of GradeDot on cards (ui-screens 5) — optional, only if it stays calm at 28pt.
3. Fixed glyphs → scaled; padding literal → token.
4. Daily-insight tile: keep neutral ("3 scans this week"), never streak framing.
**States:** built (loading skeletons, per-section errors w/ retry, calm empties). Keep.
**Responsive:** grid `adaptive(min 160)`; 16pt margins on Compact; trending fixedWidth 172 OK (h-scroll). Grid → 1-col at a11y sizes (built).

## 3. Scan (the dark moment)
**Purpose:** point → lock → result; fast, confident, never a dead-end.
**Layout (per V3 §5.9):** dark camera, green corner-bracket reticle (240pt), instruction pill below reticle, right control cluster (zoom 1×/2×/3× · gallery · torch), phase banners bottom.
**Current:** rebuilt on AVCaptureSession; all phases handled (lookingUp spinner pill, OCR two-action banner, error retry, permission ContentUnavailableView, shatter success w/ Reduce-Motion fallback).
**Changes (small):**
1. "Identifying" style lookup pill already non-blocking [T-13] — keep.
2. Add "Enter barcode manually" quiet action inside `labelNotFound`/error banners → Search screen with numeric pad (closes last dead-end).
3. Permission-denied copy: verify concrete benefit phrasing ("SafeSide uses the camera to read barcodes and labels — nothing is recorded") [T-11].
**Responsive:** reticle 240 fixed = correct (camera target); SE leaves 40pt margins — acceptable. Control cluster stays 44pt targets.

## 4. Result (the trust moment — flagship screen)
**Purpose:** verdict + evidence + action in one scroll. Where we beat everyone.
**Layout (top→bottom):**
1. Identity header: floating product image, name/brand, **score ring** (number+word+arc), trust chips (source, confidence, lab-style "OFF verified" style facts).
2. Allergen alert banner (conditional, calm caution, never red-block).
3. **Confidence caveat callout** (conditional, amber): "Estimated — fiber % not on the label" / OCR provisional note [T-4].
4. Tri-metric row: Nutrition · Additives · Processing.
5. **Watch-outs / Benefits meters (NEW):** two calm sections of labeled bar meters with values ("Saturated fat 26.7 g — high" / "Fiber 4.5 g — good source") [T-5, T-8]. Absorbs "why this score" factor rows into visual meters; sourced rows expand on tap.
6. "What's inside" ingredient cards — thin band-tint **border** + 1-line why + expand [T-1]. Additive summary rows: neutral severity word + category pill [T-9]. Harmful/beneficial count pre-read above list [T-6].
7. Sources (collapsible): named DB + date ("Open Food Facts · fetched 2026-07-09", "EFSA 2023 opinion") [T-3].
8. **Trust footer:** How this score works · Report an issue [T-2] — built; wire report endpoint (roadmap A).
9. Actions: "Ask about this product" (secondary) + "See a better option" (primary, → Swaps §5).
10. Attribution footer (ODbL).
**Current:** 1–4, 6(partial), 7, 8(UI only), 9, 10 built. Gaps: Watch-outs/Benefits meters absent (factor rows are text), additive severity-word rows partial, report endpoint unwired, swaps honest stub, `ResultSkeletonView` designed but unwired.
**Changes:** build §5 meters; upgrade additive rows; wire report; wire result skeleton when deep-link/search entry lands (product arrives in-flight); favorite glyph 18pt → scaled.
**States:** per-section states built; add top-level skeleton once Search/deep-links can open Result pre-fetch.
**Responsive:** identity header → VStack at a11y sizes (built); tri-metric 3-up → vertical via ViewThatFits (verify); meters full-width, text-capped 560pt on Max.

## 5. Swaps sheet — "See a better option" (NEW, roadmap A flagship)
**Purpose:** close the loop: verdict → concrete better choice. No competitor does this.
**Layout:** sheet (radius 28, detents half→full): header "Better options in [category]" → ranked product cards (image, name, score ring mini, **delta chip** "+22 score", 1-line why-better sourced: "no colours E150d, lower saturated fat") → per-card actions: View · Save to pantry → footer honest note when thin ("Few close matches in this category yet — here's the nearest").
**Ranking (per user-flows §3):** same category → better band/score → restriction-safe (allergen-filtered via profile) → pantry-first.
**States:** loading skeleton cards · empty = honest tip + "Scan another" (current stub behavior becomes the empty state, not the default) · error retry.
**A11y:** cards combined-label ("Better option: X, score 78, high band, no artificial colours").

## 6. Ingredient detail sheet
**Purpose:** per-ingredient evidence (KB + guardrailed LLM prose).
**Layout:** sheet detents half→full [T: Oasis drag-handle pattern]: name + risk-tier chip (band tint word) → What it is / Why it's used / Safety summary (KB-vetted prose) → sources list (verbatim KB) → "No vetted info yet" honest state for KB misses.
**Current:** built (cards + sheet). **Changes:** verify sheet detents (half→full drag); tier chip uses border-tint style consistent with cards.

## 7. Chat — "Ask about this product"
**Purpose:** grounded Q&A; never medical advice.
**Layout:** product header + "Grounded in this product's data" → starter chips (empty state) → bubbles w/ inline sources → persistent disclaimer row → input bar.
**Current:** built, strong (typing indicator, error bubble retry, VO announcements). **Changes:** none visual. Backend: rate-limit /chat (roadmap B) before public; FTC language review gate stands.

## 8. Pantry / Favorites (within Home; list view)
**Purpose:** everything scanned, refindable; favorites filter.
**Current:** grid + filter chips + hearts built; thin-pantry rows re-enrich in background.
**Changes:** 1. Swipe-to-remove row action + confirm (currently no way to remove a pantry item — user-control gap). 2. Sort control (recent / score) — small menu, calm.

## 9. Search (NEW screen, roadmap A)
**Purpose:** find products without a barcode; manual barcode entry; feeds Compare.
**Layout:** search field autofocused + numeric-pad toggle for barcode → default state = recent scans list (never blank) [T-22] → results list (product rows: thumb, name/brand, grade dot) → row tap → Result. Empty: "No matches — try the barcode or scan the label" + Scan CTA. Backend: OFF search endpoint (`GET /search?q=` new edge function) or client OFF API v2 search with same normalization.
**Responsive:** plain list; keyboard-safe insets.

## 10. Compare (NEW, roadmap A — v1 minimal)
**Purpose:** two products side-by-side; the Skeptical Optimizer's tool.
**Layout:** entry = "Compare" action on Result overflow + Search multi-select → two-column header (images + rings) → aligned tri-metric rows → aligned Watch-outs/Benefits meters (shared scale!) → per-row winner tint (subtle, band colors, never red) → CTA "Pick this one → save".
**v1 scope:** 2 products, static compare. No carts/lists yet.
**Responsive:** Compact = stacked cards with sticky segmented toggle (A/B) instead of side-by-side; side-by-side ≥ Standard width.

## 11. Plan tab
**Purpose (now):** honest coming-soon; **(later, pre-Phase-D optional):** planner v1 per `AI_PLANNER_SPEC.md`.
**Current:** calm placeholder, correct. **Changes now:** padding literal → token; glyph scaled. Planner build itself is chunk-gated (see MASTER_PLAN_PRE_D §chunk 6) — spec lives in AI_PLANNER_SPEC.md; do not start until swaps ship.

## 12. Me tab
**Purpose:** profile, ED-safe display settings, trust/legal.
**Current:** built — profile rows + editors, calories/scores toggles, methodology/privacy/data-sources sheets, honest "Coming soon" rows.
**Changes:** 1. Profile load error → quiet inline retry row (currently silent defaults). 2. Legal/ODbL attribution screen completion (launch item D): Privacy Policy + Terms + full OFF/ODbL attribution text — same tokens, no boilerplate look [AVOID-12]. 3. Glyphs scaled, padding token.

## 13. System moments
- **Camera permission:** prime-then-ask built; usage string concrete [T-11].
- **Notifications (future):** prime with concrete payoff + "Not now" — never ask cold [T: Oasis 04].
- **Rating prompt (pre-launch):** emoji sentiment gate after 3rd successful scan, routes unhappy → feedback [T-18]. Never mid-onboarding [AVOID-8].
- **Errors global:** every error names the thing + gives an action (retry/settings/scan another). No bare "Something went wrong".

## 14. Paywall (Phase D — spec'd now, built LAST)
Price on first screen, both tiers with per-month equivalents, trial toggle default ON with post-trial price same type size as CTA, cancel-anytime + Restore visible, verdicts never paywalled (premium = swaps depth/plan) [T-19; AVOID-7]. Full spec when Phase D starts.

---

## Build order for the revamp (feeds MASTER_PLAN_PRE_D)
1. Cross-cutting fixes (glyph scaling, padding tokens, detents, Me error row) — small, everywhere.
2. Result upgrades (meters, additive rows, skeleton wiring) — flagship first.
3. Search screen + manual barcode entry (+ Home field, Scan banner action).
4. Swaps engine UI + backend.
5. Compare v1.
6. Pantry management (remove, sort).
7. Report-issue wiring + rating gate + legal screens.
