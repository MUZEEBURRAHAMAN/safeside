# MEMORY.md — Long-Term Project Memory

> A running log of decisions, why we made them, and open questions. Append-only; newest at top. This is what keeps context across sessions.

## Decisions log

### 2026-07 · Scanner rebuilt (real zoom + shatter), grounded AI chat, USDA live
- **Scanner core replaced: DataScannerViewController → custom AVCaptureSession.** DataScanner has NO zoom API (why zoom "did nothing"). New pipeline: virtual multi-camera (`builtInTripleCamera`/dual → real optical lens switching) + `AVCaptureMetadataOutput` (barcodes) + `AVCapturePhotoOutput` (OCR stills) + `AVCaptureVideoDataOutput` (shatter frame). `cycleZoom` 1×/2×/3× clamped to device max, applied to the exact session device. Session work serialized on a private queue, UI hopped to main.
- **Right-edge control cluster** (zoom / gallery / torch) + instruction pill moved below the reticle (was colliding with nav). **Gallery** = pick a photo → VNDetectBarcodes → live-lookup, else OCR.
- **Scan-success "shatter" animation** (founder request, from a web ref): on lock, the frozen camera frame breaks into a 5×8 grid of shards that fly out + fade 0.45s (Reduce Motion → lime flash). Doesn't gate lookup.
- **Grounded AI chat** (Phase 3, pulled before Phase D): `POST /chat` grounds on the product's DB data + score breakdown + ingredient KB + (RLS) profile; bounded LLM (Groq), banned-word filter, **always "not medical advice"**, sources from data not the model, graceful without a key. iOS `ChatView` sheet from Result ("Ask about this product"). 121 deno tests. Live-verified: "safe for my kid?" → factual + sourced + declines medical verdict. **Legal/FTC review of claim language still required before this ships publicly** (Phase 3 exit criterion).
- **USDA enrichment now LIVE** — `USDA_API_KEY` set as a Supabase secret (key valid; rotate — pasted in chat). Applies on fetch-path scans; score_version 1.1.0 means re-scans re-enrich.
- **Note:** the gitignored `ios/FoodScanner.xcodeproj` keeps getting deleted between build steps by something in the env — always `xcodegen generate` immediately before `xcodebuild`, and confirm it exists, or the build reinstalls a stale binary.

### 2026-07 · UI/UX overhaul (Design System v3) + functionality wave
- **Founder directive locked:** UI/UX is priority #1, never compromised; launch + payment (Sign in with Apple, RevenueCat) go LAST. Build-to-spec + review-on-device; keep+elevate bold-green; references Yuka/Cal AI/Oasis/Ingrex. See [[ui-ux-first-directive]].
- **Design System v3** (`docs/DESIGN_SYSTEM_V3.md`): resolved light-vs-dark → **light-first** (mint canvas #F4F8F1, white flat cards, radius 20, pill CTAs, Space Grotesk display font bundled OFL) + bold-green accent + dark only for the scan moment. Studied the founder's `reference/moodboards` + `reference/screenshots` (Ingrex/Ivy/Oasis). Theme tokens rewritten light-first.
- **Screenshot-verify workflow** (key process fix): a DEBUG harness in FoodScannerApp (`SHOW_SAMPLE_RESULT`, `SHOW_SCREEN=me|plan|onboarding|result`) boots straight into any screen so screens are verified via `xcrun simctl` screenshots on the simulator BEFORE hitting the device — stops the founder seeing broken layouts. To seed a populated sim state: reset sim keychain → capture the fresh anon user id → insert pantry rows via Management API.
- **Screens rebuilt to v3 (all verified on sim):** Home (flat cards, product-card grid, grade dots, scan-CTA anchor), Result (Oasis-level: floating image + circular score RING + trust chips + tri-metric Nutrition/Additives/Processing + sourced "why" + calm color-coded ingredient cards, never alarm-red), Scan (green reticle/torch/pill banners), Onboarding (option cards + slim progress + pill CTAs), Me tab (profile edit + ED-safe settings + about/ODbL), Plan (calm coming-soon). Brand **app icon** (scan brackets + leaf, green-black) added.
- **Home layout fixes** the founder caught: removed card shadows (flat), fixed filter chips wrapping (own row + fixedSize), hid redundant "Home" nav title (killed the ghost), bottom padding to clear the tab bar.
- **Allergen alerts:** scanned product matched against the user's onboarding allergies (literal normalized matching, 7 conservative synonym groups) → calm caution banner + flagged chips + neutral ingredient notes. Never alarm-red block. Health-flag→ingredient mapping deliberately NOT done (would need a medical inference table = fabrication risk).
- **Data quality:** ingredient KB 73→174 (regulator-sourced), 73 new additives added to the scoring table (KB↔scoring tier parity kept), USDA FoodData Central enrichment on thin-data cache-misses (OFF precedence). **score_version 1.0.0→1.1.0** (additive table changed → cached products re-score; calibration scores unchanged). 97 deno tests. Deployed + KB seed applied (174 rows live). USDA_API_KEY not set yet (graceful OFF-only).

### 2026-07 · Phase 2 wave 2: OCR fallback, favorites, trending, next-action, additives fix
- **4 parallel agents, strict file ownership + a pinned favorites API contract** (`isFavorite(_:)` / `toggleFavorite(productID:) async`) shared verbatim between the result-page and home agents so they interlocked. `ProductView(product:)` init frozen so no agent broke others' call sites. All 4 merged and compiled clean first try; on device.
- **Additives "bug" was a stale deployment**, not code — the mapping already existed. Redeployed `ingredients`; Coca-Cola now surfaces E150d/E338 with sources + risk tier. Added prefix-tolerance (`e338` == `en:e338`) + 6 regression tests (78 total).
- **On-device OCR shipped:** `needsOCR` → "Snap the label" → `DataScannerViewController.capturePhoto()` (verified against the SDK swiftinterface — reuses the scanner's own session, avoids a second contending AVCaptureSession) → `VNRecognizeTextRequest .accurate` → `POST /product/ocr`. New phases `.capturingLabel` / `.labelNotFound`; lighting-fail vs network-fail get different honest copy.
- **Favorites:** optimistic in-memory `Set` (sync `isFavorite`), status flips scanned↔favorited; works on never-scanned products (trending cards). Home has Recent/Favorites filter + heart on rows/cards.
- **Trending healthy:** top `band=high` products, horizontal cards. KNOWN LIMITATION: takes highest-ever high score per product from a fetched window (score_results keeps history; PG can't do top-1-per-group in one call) — proper fix is a backend view exposing the current score per product.
- **Next-action** is honest: no fabricated swaps (engine is Phase 3) — a band-specific tip + real "scan another" CTA. Copy is new, needs a COPY_DECK pass.
- Follow-ups noted: ingredient-load error needs manual retry (auto-retry?); OCR parenthetical `colour (E150d)` yields a redundant orphan "Colour" entry; trending current-score view.

### 2026-07 · Phase 2 wave 1: pantry, onboarding, AI ingredient KB, OCR (deployed + on device)
- **Four features shipped in parallel** (2 backend + 2 iOS agents): pantry auto-save, Home recent-scans, skippable onboarding, AI ingredient explanations, OCR endpoint. All committed; app rebuilt + installed on the iPhone 13.
- **AI ingredient KB is live and guardrailed.** `ingredient_kb` (73 curated entries: 51 additives from the scoring table + 22 common ingredients, every claim regulator-sourced) + `ingredient_explanations` cache. `GET /product/:id/ingredients`: KB retrieval → cache → bounded LLM rewrite of **only** the what/whyUsed/safety prose; riskTier/sources/etc are verbatim from the KB so the LLM can't move risk. KB miss → "no vetted info yet" (never fabricates). 72 deno tests incl. all 5 §7 guardrails. Live-verified: "Sugar" → WHO/USDA-sourced explanation; unknown token → limited state.
- **LLM is provider-agnostic** (OpenAI-compatible). Using **Groq** (`llama-3.3-70b-versatile`) via free key — stored as Supabase secrets `LLM_API_KEY/LLM_BASE_URL/LLM_MODEL`, never in repo. Google AI Studio key the founder gave was an `AQ.`-prefixed OAuth token, not a usable `AIza` Gemini API key — rejected. **Both pasted keys must be rotated** (chat logs persist).
- **KNOWN GAP (follow-up):** the ingredients endpoint explains `ingredients_text` tokens but does NOT yet map `additives_tags` (e.g. `en:e150d`, `en:e338`) to their KB entries, so additives with real KB entries don't surface on the result screen. Pipeline is otherwise sound. Fix next.
- **OCR endpoint** `POST /product/ocr`: label text (on-device Vision does the OCR) → parse → same scoring engine (always unknown/limited, honest) → provisional `source=ocr` product. iOS Vision capture not wired yet.
- **Cache seeded** with 10 real barcodes across the spectrum (28–97) for demo/instant re-scan.
- **Pantry detail is thin:** pantry-tapped products show score but empty "why"/ingredients (list read selects few columns); needs a re-fetch-by-id later. `save()` is update-then-insert (not upsert) to preserve `first_scanned_at`.
- **Test note:** full `xcodebuild test` (incl. XCUITest) times out ~10min on sim boot; run `-only-testing:FoodScannerTests` for fast unit runs (5 pass).

### 2026-07 · First vertical slice LIVE (backend deployed + iOS builds/tests green)
- **Backend deployed to Supabase** (`usmdthxnxzdywtjgbokl`): schema migration applied via Management API (5 tables, RLS verified), anonymous sign-ins enabled, `product` Edge Function deployed. **Live end-to-end test passed:** anonymous JWT → `GET /functions/v1/product/3017624010701` → Nutella scored 38/"low" with sourced factor breakdown; cached row + score persisted; second call = cache hit.
- **Real-world data gap surfaced:** OFF currently returns no `nova_group` and empty `additives_tags` for Nutella — the renormalization path (nutrition 0.70 / additives 0.30, "limited" confidence) fired in production on scan #1. Validates the design; also confirms USDA enrichment + OFF data-quality handling matter early.
- **iOS builds + all tests green** on iPhone 17 Pro simulator (Xcode 26.6, supabase-swift 2.50.0, RevenueCat 5.80.2). Two first-build fixes: (1) VisionKit `DataScannerViewController.isSupported` is MainActor-isolated → `CameraAvailability.current` marked `@MainActor`, availability resolved `.onAppear` (`@State` defaults evaluate off-main); (2) test targets need `GENERATE_INFOPLIST_FILE: YES` in project.yml or signing fails.
- **SPM gotcha:** killing xcodebuild mid-resolve corrupts the package cache ("Couldn't get the list of tags: fatal: not a git repository") → delete the project's DerivedData and re-resolve.
- Secrets: Supabase URL/anon key in `ios/Config.xcconfig` (gitignored) + `~/.env`; access token (30-day expiry) in `~/.env`. Nothing in the repo.
- Remaining for milestone: run on a physical iPhone (needs device + team in Xcode) + real camera scan.

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
