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
