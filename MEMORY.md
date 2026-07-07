# MEMORY.md — Long-Term Project Memory

> A running log of decisions, why we made them, and open questions. Append-only; newest at top. This is what keeps context across sessions.

## Decisions log

### 2026-07 · Build started: repo, fixtures, scoring rule locked, parallel tracks
- **Git repo initialized** (was folder-only). `.gitignore` excludes secrets (`.env*`), Xcode user state, generated `.xcodeproj` (regenerated via XcodeGen).
- **Calibration extracted to fixtures:** `tools/extract_calibration.py` (stdlib-only) parses `docs/Scoring_Calibration.xlsx` → `supabase/functions/_shared/scoring/{weights,calibration}.json`. Verified the formula reproduces **all 50 expected scores exactly**.
- **Scoring rounding rule locked:** final score uses **half-up rounding** (96.5→97), matching Excel `ROUND`. Python's banker's rounding gives off-by-one on *.5 values — don't use it. Additive penalties count first/additional **per tier** (e.g. higher+moderate = −15−6 = 79).
- **Scoring-engine test conflict resolved (founder OK'd):** KICKOFF said Swift Testing for the engine, but BACKEND_SPEC puts the engine server-side (TypeScript/Deno Edge Function). Decision: **engine tests in Deno** against the calibration fixtures; Swift Testing covers client model decoding + band mapping.
- **Xcode project via XcodeGen** (`ios/project.yml`) instead of a committed binary `.xcodeproj` — reviewable in git, regenerable. Xcode itself not yet installed on this Mac (founder installing); all non-Xcode work proceeds in parallel.
- Tooling installed via brew: deno 2.9.1, supabase CLI 2.109.1, xcodegen 2.45.4.
- Unknown additives (not in our curated risk table) score as **low tier but labeled "unknown"** in the breakdown — we never invent risk (spec §5 governance).

### 2026-06 · Apple HIG made an explicit principle
- Made "native-first, brand-skinned (Apple HIG)" a first-class design principle (`DESIGN_SYSTEM.md` §1 #5) with a concrete defer-vs-override table (§11.1) and a `DESIGN.md` foundation note. Previously HIG alignment was present but implicit (SF Pro, SF Symbols, Dynamic Type, VoiceOver, native SwiftUI components). Rule: defer to Apple for behavior/navigation/gestures/accessibility; brand overrides color/type/Score Badge/spacing; on conflict, HIG wins behavior, brand wins visuals.

### 2026-06 · iOS-only reconfirmed; Android = explicit future
- Founder reaffirmed **iOS-only, SwiftUI now; Android later (after iOS PMF)**. Captured explicitly in `MASTER_PLAN.md` (principle 1 + Roadmap → Future) so it's a planned future item, not an open question. No Android work in any current phase.
- Recheck done: core plan/specs/scaffold are cleanly iOS-only. Cleaned residual mentions: agents README now flags "ignore the agents' Android/Material guidance — iOS-only"; DESIGN_SYSTEM font note de-emphasized cross-platform. Master_Build_Plan.docx stays bannered/superseded.
- Added a "Current state & next action" snapshot at the top of MASTER_PLAN.

### 2026-06 · Build-readiness gaps closed + Phase 0 scaffold started
- Added `docs/BACKEND_SPEC.md` (Supabase Edge Functions + product-data pipeline + endpoints + cost/observability) and `docs/AI_INGREDIENT_EXPLANATION.md` (curated ingredient KB → retrieval → LLM rewrites, never invents; the core credibility feature).
- Calibrated scoring: `docs/Scoring_Calibration.xlsx` (50 products, tunable weights, edge cases pass) + `tools/off_live.py` to pull real OFF data by barcode (run locally). Inputs in the workbook are representative pending a live pull.
- Scaffolded the iOS app: `ios/FoodScanner/` (SwiftUI — app entry, Theme tokens, Models, guest-first SessionService, APIClient, ScoreBadge, Home/Scanner/Product views) + `ios/README.md`. Not an .xcodeproj — create in Xcode, add SPM deps, run on device.
- Verdict: ready to build the MVP. Remaining pre-ship items are already scheduled in Phase 4 (legal, assets, a11y). Validation (Phase 1) still recommended in parallel.

### 2026-06 · Auth: guest-first, optional sign-in
- No login wall. App runs on an anonymous session from first launch (Supabase anonymous auth or local); onboarding + scanning + pantry all work with no account.
- Sign in with Apple is offered later as a benefit ("save/sync across devices") and links the anonymous account without data loss. No Google sign-in in MVP. Account deletion required when sign-in ships (Apple rule).
- Rationale: auth before value kills activation and would confound Phase 1 validation. Add real auth only when there's a reason (cross-device sync, scaled personalization). Reflected in `MASTER_PLAN.md` (principle 7 + Phase 2) and `docs/product-requirements.md` (Epic E).

### 2026-06 · Master Plan v3 (phase-wise) + scope reset
- Rewrote the master plan as `MASTER_PLAN.md` (root), phase-wise, native iOS, incorporating the founder's "AI consumer-health platform, food-first" vision.
- Platform: imported founder context specifies SwiftUI → confirms **native iOS, iOS-only** (closes the open Android question unless explicitly reopened).
- **MVP scope sharpened:** true MVP = scan → AI ingredient explanation + deterministic verdict + one next action + pantry. Comparison, AI chat, alternatives, search moved to Phase 3. Diet planner is **not** in the food MVP (revisit post-PMF).
- **Rejected the "150–200 docs before building" idea** as analysis paralysis; right-sized to ~30 decision-driving docs (most already exist).
- Restored ED-safe design + health-claim guardrails, which the imported context had dropped.
- Highest-value pre-build task reaffirmed: calibrate the scoring model on ~50 real products.

### 2026-06 · Platform DECIDED: native iOS only (Swift/SwiftUI)
- Founder chose to build **iOS-only, pure native Swift** for now — superseding the earlier React Native/Expo recommendation and the smooth-app (Flutter) fork option. No Android.
- Verified native stack in `docs/NATIVE_IOS_STACK.md`: VisionKit DataScanner (barcode) + Vision OCR (both first-party, a win for a scanner), URLSession+Codable for OFF/USDA REST, RevenueCat purchases-ios (MIT) or StoreKit 2, supabase-swift (MIT), SwiftUI `@Observable`, Swift Testing + XCUITest + swift-snapshot-testing.
- Backend unchanged (scoring, OR-Tools optimizer, AI route stay server-side; iOS is a thin client). The `ios-app-developer` agent now applies directly.
- Trade-off accepted: no Android path, nothing to fork (smooth-app was Flutter) — more UI built from scratch, but better native scanning/OCR and platform fit.

### 2026-06 · Added specialist agents (expertise)
- Placed 5 Claude Code subagents in `.claude/agents/` (ux-researcher, ux-product-designer, ui-designer, app-ui-designer, ios-app-developer) + a screensdesign scraper in `.claude/tools/`. Indexed in `.claude/agents/README.md`; referenced from `CLAUDE.md`. Use them during build, routed research → product → UI → iOS. ios-app-developer assumes native Swift — which is now the decided stack, so it applies directly.

### 2026-06 · Brand direction: bold green (ChemZero-inspired)
- Founder chose a vivid green / green-black identity with a lime accent (ref: ChemZero, Zentrix brand kits in `reference/moodboards/branding/`). `DESIGN_SYSTEM.md` updated to v2.0 with the green palette + a full Brand Kit section; `DESIGN.md` synced.
- **Guardrail kept:** the brand is bold, but food **scores remain non-alarmist** (brand-green/amber/clay, never "toxic" red) per the ED-safe principle in CLAUDE.md. Lime is an accent on dark surfaces only (contrast).
- Note (my flag, founder's call): bold lime risks reading like the ChemZero alarmist app we position against — recommend validating the palette reads as *trustworthy* with the Skeptic/Parent personas before launch.

### 2026-06 · Adopt structured project layout
- Reorganized the repo into `CLAUDE.md` / `DESIGN.md` / `MEMORY.md` + `docs/` + `reference/`. Skipped team-only Claude Code scaffolding (agents/, settings.local.json) and `.mcp.json` until needed (solo founder, pre-build).

### 2026-06 · Product thesis locked
- Building a food scanner **and** diet planner as **one connected loop**, not two features. The Pantry (auto-filled by scans) is the bridge object.
- **Wedge:** transparency + calm/non-shaming tone + honest pricing + verdict→action. Competitors are distrusted and judgmental.

### 2026-06 · Tech direction (SUPERSEDED — see native-iOS entry above)
- ~~**Recommended:** React Native / Expo path (obytes template).~~ Superseded by the native-iOS Swift decision.
- ~~**Fast alternative:** fork `openfoodfacts/smooth-app` (Flutter).~~ Not applicable (native iOS).
- Data: Open Food Facts (ODbL — attribute + share-alike) + USDA FoodData Central (public domain). Scoring engine is our own code and is reused by scanner + planner.
- **Avoid copying** GPL/AGPL apps (OpenNutriTracker, wger, Mealie, Tandoor) into the closed app — reference only.

### 2026-06 · AI planner rule
- The LLM **selects and explains only**; it may not invent products or compute nutrition. All numbers come from the DB; optional OR-Tools/PuLP solver for hard constraints.

### 2026-06 · Trust & safety stance
- ED-safe design is a first-class requirement: qualitative framing by default, calories opt-in, no good/bad/toxic language, no streaks/shaming, soft off-ramp to support.
- Honest billing: transparent price, real 7-day trial, one-tap cancel. Free = scan + score; Pro = planner + swaps + AI.

### 2026-06 · Build sequencing
- Phase 0 foundation → 1 scanner MVP → 2 manual planner → 3 AI + connected loop → 4 harden/test/ship iOS. Each phase ships something usable; testing built into every phase.

## Open questions (validate with primary research)
- Are the persona segment sizes (~35/30/25/10) accurate? → run the survey.
- Will users connect scan↔plan on their own, or must we teach it? → usability test the handoff.
- Does the transparent score actually read as credible to skeptics? → prototype test.
- Real willingness-to-pay at honest pricing? → survey + beta.
