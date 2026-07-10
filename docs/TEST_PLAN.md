# Test Plan

**Version:** 1.0 (draft for build) · June 2026
**Stance:** test the scoring engine and AI grounding hardest — a wrong allergen "safe" or a hallucinated product is the one bug you can't quietly patch. Everything else can ship and be fixed in an update.

---

## 1. Test layers (what runs where) — native iOS
| Layer | Tool | Scope |
|---|---|---|
| Static | Swift compiler warnings-as-errors, SwiftLint | Every commit (CI) |
| Unit | **Swift Testing** (`@Test`/`#expect`) | Pure logic (scoring, Mifflin, swap ranking) |
| Integration | Swift Testing + mocked OFF/USDA/AI (URLProtocol stubs) | Service paths |
| Snapshot | pointfreeco/swift-snapshot-testing (MIT) | SwiftUI view regression |
| UI / E2E | **XCUITest** | Real flows on simulator/device |
| Purchases | StoreKit testing / RevenueCat sandbox | Subscribe/restore/cancel |
| Manual/device | Real iPhones + TestFlight | Camera, perf, real barcodes |
| AI safety | Adversarial + golden set (backend) | Planner guardrails |

CI gate: static + unit + integration + a core XCUITest smoke flow green before merge. (Backend tests run in their own suite.)

---

## 2. Critical test cases (must pass before release)

### Scoring engine (highest priority)
- Known products → expected score within tolerance; band correct.
- Missing NOVA → confidence = limited; no crash.
- No data → "Not enough data", no fabricated number.
- One higher-concern additive does NOT tank the score below the floor (anti-Yuka rule).
- `score_version` change → products re-scored; old results reproducible from `raw_off`.
- Property test: displayed sub-scores × weights = total (no rounding drift surprises).

### Allergens & restrictions (safety-critical)
- Allergen item is **blocked** from a plan with a clear reason — never added silently.
- Diet pattern (vegan etc.) filters all suggestions and AI candidates.
- AI output re-checked post-assembly: zero forbidden items across 100 adversarial generations.

### AI planner
- Every suggested item exists in the candidate set (no hallucination) — reject + regenerate otherwise.
- UI never shows an LLM-produced number (all from DB recompute).
- Banned-word filter catches "toxic/bad/cheat" etc.
- AI timeout/refusal → manual planner still works (graceful fallback).
- Golden-set regression flags drift after prompt/model changes.

### Scan & data
- Real grocery barcodes scan and return a scored product on a physical device.
- Not found → OCR fallback completes or shows clear "can't read".
- Barcode/label mismatch handled (show data confidence; allow report).
- Cached product served within TTL; refresh after TTL.

### Onboarding & trust
- ≤8 questions; health/weight skippable; no calorie number forced.
- `show_calories = false` honored on EVERY screen (search all surfaces).
- `score_display = hidden` honored everywhere.

### Subscriptions (sandbox)
- Subscribe → `pro` unlocks planner/swaps/AI.
- Restore purchases works on a fresh install.
- Cancel reachable in one tap; entitlement syncs via webhook.
- Price shown before signup; trial reminder fires.

### Accessibility
- Contrast ≥ AA on all score colors/backgrounds.
- VoiceOver reads score badge ("Score 38 of 100, higher-processed").
- Dynamic Type to XXL with no truncation on key screens.
- Touch targets ≥ 44×44pt.

### Resilience
- Offline → cached results shown; clear reconnect state.
- API down → no crash; retry affordance.
- Permission denied (camera) → explainer + Settings deep link, no crash.

---

## 3. Per-phase entry into the suite
- **Phase 1:** scoring-engine unit tests, scan integration, scan E2E, device camera matrix.
- **Phase 2:** Mifflin calc, swap-ranking, shopping-list de-dup, allergen block, purchase sandbox.
- **Phase 3:** AI grounding, adversarial guardrails, macro-recompute property test, golden set.
- **Phase 4:** full regression, device matrix, accessibility, crash-free target, TestFlight beta.

## 4. Release exit criteria
- Full suite green in CI; crash-free sessions ~99%+ across the device matrix.
- All safety-critical cases (allergens, AI guardrails, calorie-opt-out) pass.
- Subscriptions/restore/account-deletion verified in sandbox.
- External TestFlight beta run; top issues fixed.

## 5. Test data
- A fixed fixture set of ~50 common products (with known expected scores) for regression — also used for the dietitian calibration review in SCORING_METHODOLOGY §10.
- A library of adversarial profiles (allergies, vegan, keto, GLP-1, low-budget) for AI tests.

---

## 6. Chunk 6 robustness/offline/a11y sweep — per-screen pass/fail (July 2026)

> Filed by Chunk 6 (`docs/superpowers/plans/2026-07-10-chunk-6-robustness-offline-a11y.md`). iOS-only, no backend change. Audited against `docs/SCREEN_SPECS.md` states + `docs/COPY_DECK.md`. **iOS build + 37 unit tests green; backend 212 deno tests green (untouched).**

**Legend:** ✅ pass (verified in code + simulator/preview) · ⚠️ gap fixed this chunk · 🔶 **GATE-ONLY** — implemented in code, final proof requires a physical device (VoiceOver swipe, real airplane mode, camera capture, on-device AX5) · ❌ open FAIL (needs a founder decision) · N/A — not applicable.

| Screen | Loading | Empty | Error+Retry | Offline (airplane) | VoiceOver | Dyn.Type XXL | Contrast (AA) | Portrait-lock | Result |
|---|---|---|---|---|---|---|---|---|---|
| **Home** | ✅ skeleton grid | ✅ StateCard | ✅ StateCard retry | ⚠️ `OfflineBanner` + Retry; cached grid still wins | 🔶 labels in code | ✅ 1-col reflow | ✅ | ✅ | ✅ |
| **Pantry** (Home grid) | ✅ | ✅ calm empty (offline cold-launch = empty, **not** error) | ✅ | ⚠️ cached entries render; banner explains | 🔶 combined cards | ✅ | ✅ | ✅ | ✅ |
| **Onboarding** | N/A (content-only) | N/A | N/A (fire-and-forget writes) | ✅ no spurious error | 🔶 | ✅ | ✅ | ✅ | ✅ |
| **Scan** | ✅ `.lookingUp` pill | ✅ scanning state | ✅ `.error` calm banner + manual-entry | ⚠️ offline scan line ("pantry still works"); manual entry reachable | 🔶 | ✅ | 🔶 lime-on-dark chrome (re-verify on device; no new fail) | ✅ | ✅ |
| **Result** | ✅ `ResultSkeletonView` | ✅ per-section | ✅ `IngredientsLoadErrorView` | ⚠️ ingredient offline variant ("You're offline"); score/details readable offline | 🔶 score reads as sentence | ✅ **sim-verified AX5, no clipping** | ✅ | ✅ | ✅ |
| **Ingredient sheet** | ✅ skeleton | ✅ "No vetted info yet" | ✅ | ⚠️ offline heading variant | 🔶 | ✅ | ✅ band-tint borders | ✅ | ✅ |
| **Chat** | ✅ typing indicator | ✅ starter chips | ✅ `ErrorBubble` retry | ⚠️ offline bubble + **full 429 path**: input+Retry disabled for `Retry-After` window, calm copy | 🔶 | ✅ | ✅ | ✅ | ✅ |
| **Me** | ✅ | ✅ | ✅ inline retry row (Chunk 0) | ✅ honest inline copy | 🔶 | ✅ | ✅ | ✅ | ✅ |
| **Plan** | N/A (calm placeholder) | ✅ placeholder | N/A (no fake loading) | ✅ static, no network | 🔶 | ✅ | ✅ | ✅ | ✅ |
| **Search** | ✅ "Searching…" | ✅ recents/no-results | ✅ "Search isn't available…" retry | ✅ error copy explicitly "check your connection" (offline maps here) | 🔶 | ✅ | ✅ | ✅ | ✅ |
| **Swaps** | ✅ "Finding…" | ✅ honest thin/empty | ✅ "Couldn't load better options…" retry | ✅ error copy covers offline | 🔶 | ✅ | ✅ delta chip never red | ✅ | ✅ |
| **Compare** | N/A (both pre-scored) | ✅ thin-partner honest | ✅ | ✅ pantry-picked partner is local; no live fetch | 🔶 aligned rows | ✅ A/B toggle reflow | ✅ subtle winner wash | ✅ | ✅ |

**Counts:** applicable cells — **PASS/⚠️-fixed: majority green**; **GATE-ONLY: 12** (one VoiceOver row per screen + the on-device AX5 walk + lime-on-dark scan-chrome contrast re-verify); **AA contrast FAILs filed: 0** (see below).

### Offline pass (airplane-mode script — GATE-ONLY, run on device)
1. Toggle airplane mode → **cold launch**. Expected: Home shows the `OfflineBanner` ("You're offline. We'll show saved results; reconnect to scan new items.") with Retry; a fresh install shows the **calm empty pantry** ("Your pantry's empty — scan your first product."), **not** an error.
2. Browse cached pantry → cards still open (in-memory after a prior online load).
3. Open a cached product → score + details render; ingredient sheet shows the **offline variant** ("You're offline — reconnect for the latest"), rest of Result readable.
4. Attempt a scan → `.error` shows "You're offline. Scanning needs a connection — your pantry still works." Manual-entry affordance still reachable.
5. Attempt chat → offline bubble "Chat needs a connection. Your product details are still here."; input stays usable copy-wise, retry preserved.
6. Reconnect (`NetworkMonitor` flips online) → banner disappears; Retry reloads pantry/trending.
*(Exact strings: COPY_DECK §Errors Network + §Offline & limits.)*

### 429 rate-limit client path (Chunk 6 owns the full path)
- `APIClient` decodes the **429 body** (`retryAfterSeconds`) **and** the `Retry-After` header via pure `parseRetryAfter(header:bodySeconds:)` (body wins; non-positive/garbage → nil → 60 s default). Unit-tested (`APIErrorMappingTests`).
- `ChatViewModel` starts a per-second countdown (`rateLimitSecondsRemaining`) on a 429; while it's > 0 the **input field, Send, and the Retry button are all disabled** with the calm COPY_DECK line "You've asked a lot in a short time. Give it a minute and try again." Re-enables automatically when the window clears.

### Shatter-orientation & portrait-lock (GATE-ONLY visual on device)
- **Shatter orientation:** pure `CameraViewController.shatterImageOrientation(connectionApplied:)` (unit-tested: portrait-applied→`.up`, unrotated landscape-native→`.right`). `captureSnapshotForShatter` now stamps that orientation so the shard grid is upright even when `isVideoOrientationSupported` was false at config time. **Device proof:** scan a barcode; confirm the shatter frame is upright (not sideways).
- **Portrait lock:** `UISupportedInterfaceOrientations` (iPhone = Portrait only; iPad = both portrait variants) now in `project.yml` → confirmed present in generated `FoodScanner-Info.plist`. **Device proof:** rotate on every tab (Home/Scan/Result/Chat/Me/Plan) → stays portrait, no crash/clip.

### Accessibility sweep (GATE-ONLY on device)
- **VoiceOver walk** of every flow (labels + focus order + combined cards + score-as-sentence + allergen announce) — labels are present in code; the swipe-through must be run on a physical iPhone.
- **Dynamic Type AX5** — Result sim-verified this chunk (no clipping, name truncates by design). Full on-device AX5 walk of every screen is GATE-ONLY.
- **Contrast** — the new `OfflineBanner` (textSecondary `#5A6B60` on surfaceAlt `#EEF6EA`) computes to **≈5.1:1 → passes AA**. Green fills / lime-on-dark scan chrome / score-ring numerals are on locked DESIGN_SYSTEM_V3 tokens verified in prior chunk matrices; **no new AA failure surfaced this chunk.** Per policy, a real AA fail on a locked token would be filed here (not silently recolored) — **none to file.**
- **Reduce Motion** — shatter + meter animations already gated; re-confirmed after the snapshot-orientation change (no animation added).

### Screenshot matrix artifacts (this chunk)
- `Result` @ default and @ AX5 (iPhone 17 Pro, `SHOW_SCREEN=result`) — clean, ring/meters intact, no clipping. (Offline banner + camera orientation + VoiceOver are device-only — see GATE-ONLY rows.)
