# Master Plan — AI Consumer Health Intelligence Platform

**Version:** 3.0 · June 2026 · Phase-wise · **native iOS (Swift/SwiftUI)**
**Supersedes:** `reference/build/Master_Build_Plan.docx` (React Native) and prior versions.
**Reads with:** `CLAUDE.md` (principles), `docs/NATIVE_IOS_STACK.md` (stack), `docs/SCORING_METHODOLOGY.md` (the moat), the specs in `docs/`, and `reference/` (research).

> **North star:** not "the best food scanner" — the **most trusted AI consumer-health intelligence layer**, starting with food. Trust and personalization are the moat, not the category list.

---

## Current state & next action (June 2026)
- **Planning:** complete. Research, specs (scoring, data model, backend, ingredient-AI, API, test), design system + brand, copy deck, native stack — all done.
- **Scoring:** calibrated on 50 products (`docs/Scoring_Calibration.xlsx`); edge cases pass. Inputs representative until a live OFF pull (`tools/off_live.py`).
- **Code:** Phase 0 SwiftUI scaffold exists in `ios/FoodScanner/` (not yet an Xcode project).
- **Next action:** create the Xcode project from the scaffold **and** build the backend `GET /product/:barcode` (lookup → cache → score) so one real scan returns a scored product end-to-end. Run cheap Phase-1 validation in parallel. **Stop writing strategy docs.**

---

## 0. Founding decisions (locked — change only with evidence)
1. **Platform:** native iOS, Swift/SwiftUI — **iOS-only now**. Android is planned **later, after iOS product-market fit** (see Roadmap → Future). Native Swift does not produce Android, so it will be its own effort (native Kotlin, or a cross-platform reassessment) decided at that point. **Do not add any Android work to the current phases.**
2. **Food-only MVP.** Beauty/supplements/household/pet/baby are the *vision*, explicitly **not** the MVP — and are also incumbent territory (Oasis already spans them), so we earn the right to expand by winning trust in food first.
3. **Deterministic scoring; AI only explains.** The score is computed in code from data (`SCORING_METHODOLOGY.md`). The LLM explains, personalizes, compares, recommends — it never invents the score or the science.
4. **Trust > breadth.** We compete on understanding products better, never on having more products.
5. **ED-safe by design.** Neutral language (no good/bad/toxic), calories opt-in, no shaming. Non-negotiable — it's both ethics and differentiation. (This was missing from the imported context; it is restored here.)
6. **Honest monetization.** Price shown pre-signup, real trial, one-tap cancel.
7. **Guest-first, auth-optional.** No login wall. The app runs on an anonymous session from first launch; sign-in is offered later as a benefit ("save/sync across devices"), never as a gate. (See Phase 2.)
8. **Evidence-driven.** Every feature answers: what user problem, what business value, what's the cheapest way to validate it.

### A note on documentation (challenging the imported plan)
The imported context proposed 150–200 documents before building. **We reject that.** Linear/Notion/Airbnb did not do this; it's analysis paralysis. We already have ~20 solid docs — enough to build. This plan right-sizes the knowledge base to **~30 focused, decision-driving documents** (mapped in the Appendix). We optimize for *learning speed*, not doc count.

---

## Phase 0 — Foundation & Strategy  *(mostly DONE)*
**Goal:** know who we build for, what we're betting, and why — before any screen.
**Status:** largely complete. What exists: market research, UX research, personas, competitor teardown, pain points, scoring methodology, data model, API/AI/test specs, design system + brand, copy deck, the specialist agents.

**Remaining in Phase 0 (do these, then stop researching):**
- Write a 1-page **Vision & North-Star** doc and a 1-page **Problem/Hypothesis** doc (the two things the imported context is right to want).
- **Calibrate the scoring model** against ~50 real products (the single highest-value pre-build task — the moat is only as good as this).
- Lock the **positioning line** ("Your AI Nutrition Expert" / "AI Consumer Health Intelligence").

**Exit:** vision + hypothesis written; scoring calibrated and sanity-checked; positioning locked.

---

## Phase 1 — Validate the Core Hypothesis  *(before full build)*
**Hypothesis to test:** *People will trust and value AI-explained ingredient analysis enough to scan repeatedly.*
**Goal:** cheap evidence before committing months of build. Don't skip to features.

- **Concierge / prototype test:** a clickable prototype (or even manual "text us a photo, we reply with analysis") with 10–15 target users from the personas. Watch whether the *explanation* lands and is believed.
- **Landing test:** a simple waitlist page with the positioning; measure interest/sign-ups from the target communities (r/nutrition, clean-eating, parents, GLP-1).
- **Success signal:** users say the explanation is trustworthy and useful even when they disagree; they'd scan again; they'd pay.

**Exit:** clear signal (go / pivot / kill) on the core hypothesis. If weak, fix positioning or the explanation UX *before* building.

---

## Phase 2 — MVP Build (the sharp core)  *(native iOS)*
**Goal:** the *smallest* product that proves the hypothesis exceptionally well. Ruthlessly scoped.

**In scope (the true MVP):**
- **Identity (guest-first):** launch straight into an **anonymous session** (Supabase anonymous auth or local) — no login wall. Sign in with Apple is offered later as an optional benefit ("save/sync your scans across devices") and silently *links* the anonymous account so no data is lost. No Google sign-in in MVP. When sign-in is added: Sign in with Apple only, plus in-app account deletion (Apple requirements). Note: this de-risks Phase 1 validation — we measure whether the product is compelling, not whether people tolerate a signup form.
- **Onboarding (≤8 Q, skippable):** goal, diet pattern, allergies, meals/day, cook time, dislikes, budget, optional health/GLP-1. Calories opt-in. Collected into the anonymous session — **no account required** to complete onboarding or scan.
- **Home:** big Scan button, recent scans, a couple of trending healthy products.
- **Scanner:** VisionKit `DataScannerViewController` (barcode) + Vision OCR (label fallback), flash, crop.
- **AI Ingredient Analysis:** for each ingredient — what it is, why it's used, safety (dose- and risk-based, sourced), who should avoid, common misconceptions. Plain language. **Sourced, never fear-based.**
- **Product Summary:** deterministic Health / Nutrition / Ultra-processed scores (`SCORING_METHODOLOGY.md`), key nutrients, additives, allergens, "Good for / Watch out for," plain-language summary, and **one next action** (never a dead-end).
- **Pantry/History + Favorites** (auto-saved — the bridge to future personalization).

**Explicitly deferred to Phase 3 (not MVP):** product comparison, AI chat, better-alternatives engine, product search, weekly reports. These are valuable but are *not* needed to test the core hypothesis.

**Backend (unchanged, server-side):** Supabase (auth + Postgres cache) + OFF/USDA data + the scoring engine + the AI route. iOS is a thin client; keys and math live on the server.

**Testing (per `TEST_PLAN.md`):** Swift Testing (scoring engine hardest) + XCUITest smoke flow + device camera matrix.

**Exit:** a real user can scan a product and get a trustworthy, sourced explanation + verdict + next action on a physical iPhone, with the scoring engine unit-tested.

---

## Phase 3 — Depth & Trust Features
**Goal:** add the features that deepen trust and daily value — once the core loop lands.

- **AI Chat** (grounded): "Is this safe? Can my kid eat this? Better alternatives?" — answers grounded in the product's real data + user profile; **health-claim guardrails** (informational, "not medical advice," no diagnosis/treatment claims).
- **Product Comparison:** A vs B on sugar/protein/fiber/additives + a reasoned recommendation.
- **Better Alternatives engine:** reuses the scoring engine to rank swaps (lower sugar, higher protein, kids, diabetic-friendly framed carefully, budget).
- **Search:** products, ingredients, brands, additives.

**Guardrail:** every "good for [condition]" statement is framed as general information with evidence and confidence, never medical advice. Legal/FTC review of claim language before shipping this phase.

**Exit:** the "understand → compare → act" loop works and is trusted; guardrails verified.

---

## Phase 4 — Harden, Test & Launch (iOS)
**Goal:** a polished, stable, App-Store-ready release.

- Empty/loading/error states everywhere; performance; accessibility (WCAG 2.1 AA, Dynamic Type, VoiceOver).
- Final ED-safe review; health-claim + allergen + "not medical advice" disclaimers; Privacy Policy + Terms + App Store privacy labels; OFF (ODbL) attribution.
- Monetization: transparent price, real trial, one-tap cancel, Restore (RevenueCat/StoreKit sandbox tested).
- Full suite green (unit + integration + XCUITest + snapshot); crash-free ~99%+; TestFlight internal → external beta; App Store submission.

**Exit:** submitted (ideally approved), with metrics instrumented (`ANALYTICS_METRICS.md`): loop-completion north star, activation funnel, retention.

---

## Phase 5 — Learn, Personalize & Build the Moat  *(post-launch)*
**Goal:** turn usage into the defensible asset — this is where a "scanner" becomes an "intelligence platform."

- Instrument and study the scan→understand→act loop; fix the biggest drop-off.
- **Personalization / recommendation engine** driven by behavioral data (what users scan, save, swap) + profile — the real moat, not OCR/GPT.
- Begin the **consumer-health graph** (what people buy + why + goals) as the long-term asset.
- Weekly health report, shopping-assistant experiments (V2 territory) — only if retention justifies them.

**Exit:** evidence of retention + personalization value; a data asset competitors can't copy.

---

## Phase 6 — Category Expansion  *(only after food PMF)*
**Goal:** extend the intelligence layer beyond food — the billion-dollar vision.
**Order (hypothesis-gated, each validated before build):** supplements → beauty/skincare → household → pet → baby → restaurant menus.
**Honest caveat:** this is where incumbents (Oasis, Think Dirty) already play. Enter a category only when (a) food PMF is proven, (b) users pull you there, and (c) the scoring/trust engine transfers. Breadth is not the moat; trust + personalization is.

## Roadmap → Future — Android (deferred, explicit)
**Not now. Planned for after iOS product-market fit.** The whole backend (scoring, data pipeline, AI, ingredient KB) is platform-agnostic and already server-side, so it is reused as-is when Android comes. Only the *client* is rebuilt. When the time comes, decide the Android client approach then (native Kotlin/Jetpack Compose for parity with the native-iOS quality bar, vs. a cross-platform reassessment) based on team size and traction. Until iOS PMF, **no Android work enters any phase** — this keeps the MVP focused and avoids the stack-thrash that cross-platform-too-early causes.

---

## Appendix A — Right-sized knowledge base (~30 docs, not 200)
Mapped to the 15-folder structure from the imported context, but scoped to what actually drives decisions. Most already exist.

| Folder | Docs that earn their place | Status |
|---|---|---|
| 01 Vision | Vision & North-Star (1p), Problem/Hypothesis (1p) | to write (Phase 0) |
| 02 Market | Market research | ✅ `reference/research/` |
| 03 User | UX research, personas, JTBD, flows | ✅ |
| 04 Competitor | Competitor teardown + notes + screenshots | ✅ (add ChemZero/Food Scanner detail) |
| 05 Problem validation | Pain points (in UX research) + Phase 1 test results | partial → Phase 1 |
| 06 Strategy | This master plan; positioning; roadmap | ✅ (this doc) |
| 07 Feature research | Product requirements + per-feature notes as needed | ✅ `docs/product-requirements.md` |
| 08 UX | IA, flows, copy deck | ✅ |
| 09 Design | Design system + brand kit | ✅ `docs/DESIGN_SYSTEM.md` |
| 10 Technical | Native stack, data model, **backend spec, ingredient-AI spec**, API, AI planner | ✅ (`docs/NATIVE_IOS_STACK`, `BACKEND_SPEC`, `AI_INGREDIENT_EXPLANATION`, `DATA_MODEL`, `API_INTEGRATION`) |
| 11 Business | Pricing/monetization (in market research) → expand pre-launch | partial |
| 12 Fundraising | Pitch deck + one-pager | later (post-validation) |
| 13 Documentation | Scoring spec + **calibration workbook**, PRD (product-requirements), test plan | ✅ (`SCORING_METHODOLOGY`, `Scoring_Calibration.xlsx`) |
| 14 Development | Phased plan (native) + **iOS scaffold** (`ios/FoodScanner/`) + `tools/off_live.py` | ✅ `reference/build/Phased_Build_Plan_iOS.docx` |
| 15 Launch | Launch checklist (in Phase 4) | to write (Phase 4) |

**Rule:** write a document only when a decision needs it. A doc nobody reads is a liability, not an asset.

## Appendix B — What we are NOT building in MVP
Social, community, gamification, water/exercise tracking, meal planning, beauty/supplements/household — all deferred. (Note: an earlier concept included a diet planner; per this plan it is **not** in the food MVP — revisit post-PMF.)

## Appendix C — Open risks to watch
- **Scoring credibility** (calibrate; the whole brand rests on it).
- **Health-claim/regulatory exposure** (Phase 3 legal review).
- **ED-safety** (enforce in code, not just copy).
- **Over-documentation / analysis paralysis** (this plan's biggest cultural risk).
- **Expansion too early** (don't chase categories before food PMF).
