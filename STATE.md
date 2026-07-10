# STATE — resume brief for SafeSide

**Read this first to continue work.** Pairs with `MEMORY.md` (full decisions log, newest at top), `CLAUDE.md` (principles), `MASTER_PLAN.md` (phases), `docs/DESIGN_SYSTEM_V3.md` (the live UI system). Last updated: 2026-07 (native iOS build well underway).

> App name: **SafeSide** (display name; internal Xcode target/bundle id still `FoodScanner` / `io.omnisai.foodscanner` — don't rename those, it breaks signing).

---

## What SafeSide is
Native **iOS** (Swift/SwiftUI, iOS 17+) food-ingredient scanner: scan a barcode → deterministic, sourced health/processing score + transparent "why" + AI ingredient explanations + grounded AI chat. Guest-first (anonymous Supabase auth, no login wall). ED-safe, non-alarmist. Backend = Supabase (Postgres + Edge Functions). See `CLAUDE.md` for the non-negotiable principles.

## Status: MVP + Phase-3 depth largely BUILT and running on a physical iPhone
**Working end-to-end (deployed + on device):**
- Guest anonymous auth; **onboarding** (8Q skippable, ED-safe); **Home** (scan CTA, recent-scans grid, trending); **Scanner** (AVFoundation, real 1×/2×/3× optical zoom, torch, gallery photo-scan, OCR label fallback, scan-success "shatter" animation); **Result** screen (circular score ring, tri-metric Nutrition/Additives/Processing, sourced "why this score", calm color-coded ingredient cards, allergen alerts); **AI ingredient explanations** (KB + LLM, guardrailed); **grounded AI chat** ("Ask about this product"); **pantry** auto-save + **favorites**; **Me** tab (profile edit, ED-safe settings) + **Plan** placeholder; brand **app icon**.
- Backend: Postgres schema + RLS, deterministic **scoring engine** (calibrated to 50 products, `score_version 1.1.0`), **174-entry ingredient KB** (regulator-sourced), OFF client, **USDA enrichment**, endpoints `GET /product/:barcode`, `POST /product/ocr`, `GET /product/:id/ingredients`, `POST /chat`. **121 Deno tests green.** Design system v3 (light-first, bold-green, Space Grotesk) applied across all screens.

## Revamp progress
- **Chunk 3 (Swaps engine — "See a better option") — BUILT & TESTS GREEN, deploy pending (2026-07-10).** New `swaps` edge fn (`GET swaps/product/:id/swaps`): pure `rankSwaps`/`whyBetter` (same OFF category via `categories_tags` `&&` → strictly-higher current-`SCORE_VERSION` score → allergen-safe against the caller's `profiles.allergies` under RLS → pantry-first stable sort, cap 5, honest `thin`/empty), deterministic **DB-diff** why-better (`"No colours E150d · lower saturated fat"`, no LLM). Service-role reads the global `products`/`score_results`; user-scoped (JWT) client reads pantry + allergies. Schema: migration adds `products.categories_tags` (+GIN) mapped in `_shared/off.ts`; seed `20260710010000_swaps_demo_seed.sql` writes a chocolate-spreads cohort so a low-score demo returns real options. iOS: `SwapCandidate`/`SwapsResponse` + `APIClient.swaps`, new `SwapsView` sheet (ranked cards, mini `ScoreBadge` ring via new compact init, band-tinted delta chip never red, sourced why-better, Save-to-pantry via `PantryService.saveToPantry`, honest empty state), CTA rewired from the retired `NextActionSheet` stub. `deno task test` **195 passed** (+3 off, +16 swaps); iOS BUILD + TEST SUCCEEDED (new `SwapsDecodingTests`). COPY_DECK §Swaps got the 1 missing error string. **NOT deployed** — need `supabase db push` (categories migration + demo seed) + `supabase functions deploy swaps`, then curl-smoke (subject `aaaaaaaa-0000-4000-8000-000000000001` → ≥1 sourced swap; milk-allergy profile filters the milk candidate) + device install + 6-shot matrix + founder review. Plan: `docs/superpowers/plans/2026-07-10-chunk-3-swaps-engine.md`. **Next: Chunk 4 (current-score view — the `// TODO(chunk-4)` markers in `swaps/index.ts` + `search/index.ts`).**
- **Chunk 2 (Search + manual barcode) — BUILT & TESTS GREEN, deploy pending (2026-07-10).** New `search` edge fn over OFF v2 (`_shared/off.ts` refactored: shared `mapOffFields` + `fetchOffSearch`/`mapOffSearchPayload`, kept general for Chunk 3 Swaps) attaching ONLY our current-`SCORE_VERSION` cached score (never OFF's Nutri-Score; unscored → "Not scored yet"). iOS: `SearchResult` model + `APIClient.search` (URLComponents, not the path helper), `SearchView` (name/barcode field, 300 ms debounce, `SearchQuery.classify` regex `^\d{6,14}$`), `ProductLoaderView` (barcode/row → identical scored `/product/:barcode` path, real `ResultSkeletonView` now production-live, never a dead-end), Home search-field entry, and "Enter barcode manually" in the Scan banners (sheet). `deno task test` **176 passed**; iOS BUILD + TEST SUCCEEDED (new `SearchLogicTests`). COPY_DECK §Search got the 3 missing strings. **NOT deployed** — need `supabase functions deploy search` (+ still the Chunk 1 deploy). Then curl-smoke + device install + 6-shot matrix + founder review. Plan: `docs/superpowers/plans/2026-07-10-chunk-2-search-manual-barcode.md`. **Next: Chunk 3 (Swaps).**
- **Chunk 1 (Result upgrade) — BUILT & TESTS GREEN, deploy pending (2026-07-10).** Watch-outs/Benefits bar-meters computed server-side (`_shared/scoring/meters.ts`, FSA + Nutri-Score thresholds) on `score.highlights` (serves on cache + fresh paths, no re-score); additive INS-class category pills (`_shared/additives/category.ts`); harmful/beneficial pre-read counts; named+dated source rows (`fetchedAt`); `ResultSkeletonView` wired (dormant `isResolving`, Chunk 2 flips on); real Report-an-issue round-trip (`product_reports` table + `product-report` fn + iOS submit/thanks/Retry sheet). `deno task test` **157 passed**; iOS BUILD + TEST SUCCEEDED (new `HighlightsDecodingTests`). COPY_DECK §Result upgrades got severity words + INS pill labels + tier-word ladder. **NOT deployed** — still need `supabase db push` (migration `20260710000000`) + `supabase functions deploy product-report product ingredients`, then device install + 6-shot matrix + founder review. Plan: `docs/superpowers/plans/2026-07-10-chunk-1-result-upgrade.md`. **Next: Chunk 2 (Search).**
- **Chunk 0 (UI hygiene) — DONE & VERIFIED (2026-07-10).** Space.s45=20 token + padding literals fixed; 4 banned "Something went wrong" strings → honest copy; `@ScaledMetric` glyphs across 9 sites (ScanCTA, InsightTile, GradeDot, hearts, OptionCard, Me avatar, Plan icon; ProductView nav-heart → semantic `.body`); Me profile load-error retry row; Onboarding allergen subline + "change anytime in Me" note; `PantryService.remove()` + context-menu remove-with-confirm + sort menu (recent/score). Build + tests green; AX5 screenshot matrix clean. Commit `cfbcd78`. Plan: `docs/superpowers/plans/2026-07-09-chunk-0-ui-hygiene.md`. **Next: Chunk 1 (Result upgrade).**
  - Sim note: no "iPhone SE (3rd gen)" installed — used **iPhone 17e** as small-screen proxy for the matrix.

## What's LEFT (do next)
**→ `MASTER_PLAN_PRE_D.md` is now the single ordered plan for everything before Phase D** (chunks 0–8: UI hygiene → Result upgrade → Search → Swaps → data fixes → Compare → robustness → analytics/legal → optional Planner). Design authority: `DESIGN.md` v2 + `docs/SCREEN_SPECS.md` + `reference/competitors/design-teardown.md` (82-image competitive scan, July 2026). The A–E list below is the raw inventory that plan absorbs:
**A. Complete the loop:** real "See a better option" swaps engine (currently honest stub) · wire report-issue endpoint (`POST /product/:id/report`) · analytics events logging · search · comparison.
**B. Data/correctness:** trending current-score DB view (uses highest-ever now) · OCR redundant parenthetical entry · dietitian weight review · rate-limit `/chat` · re-score cron on version bump.
**C. Robustness:** empty/loading/error pass · full a11y + Dynamic Type XXL sweep on device · offline handling · camera video-frame orientation edge.
**D. Launch-necessary:** legal (Privacy/Terms, OFF/ODbL attribution screen) · FTC/health-claim language review (before chat ships publicly) · SafeSide store branding · tests/CI/stability · rotate keys + move to a prod Supabase project.
**E. Phase D (LAST, founder's call):** Sign in with Apple + account linking + in-app account deletion · RevenueCat paywall (price-before-signup, trial, one-tap cancel, Restore) · App Store submission.

---

## How to build / run (macOS + Xcode 26.6)
Project is generated by **XcodeGen** from `ios/project.yml` (the `.xcodeproj` is gitignored — regenerate it).

```sh
brew install xcodegen deno supabase/tap/supabase   # if missing
cd ios
cp Config-example.xcconfig Config.xcconfig         # then fill in values (below)
xcodegen generate                                  # ALWAYS regenerate before building
open FoodScanner.xcodeproj                          # or use xcodebuild
```
Signing: Personal Team `JPS4HAKT9Z` is baked into `project.yml` (swap for a paid team before TestFlight). Device: enable Developer Mode + Trust the developer cert once.

CLI build/install to the physical device (bundle `io.omnisai.foodscanner`):
```sh
cd ios && xcodegen generate            # gotcha: the .xcodeproj sometimes vanishes between steps — regenerate + confirm it exists right before xcodebuild
xcodebuild -project FoodScanner.xcodeproj -scheme FoodScanner \
  -destination 'platform=iOS,id=<DEVICE_UDID>' -allowProvisioningUpdates build
xcrun devicectl device install app --device <DEVICE_UDID> \
  ~/Library/Developer/Xcode/DerivedData/FoodScanner-*/Build/Products/Debug-iphoneos/FoodScanner.app
```
**Screenshot-verify workflow (DEBUG):** launch on the simulator with `SIMCTL_CHILD_SHOW_SCREEN=me|plan|onboarding|result|scan` (or `SHOW_SAMPLE_RESULT=1`) to boot straight into one screen, then `xcrun simctl io booted screenshot`. Verify layouts on the sim BEFORE pushing to device. The scanner overlay needs a real camera (sim can't show it).

## Config / secrets (NOT in the repo)
Recreate `ios/Config.xcconfig` from `Config-example.xcconfig`:
- `SUPABASE_URL = https:/$()/usmdthxnxzdywtjgbokl.supabase.co`  (note the `$()` escape for the `//`)
- `SUPABASE_ANON_KEY = <publishable key>` — the publishable/anon key (safe in the binary); ask the founder or read from the Supabase dashboard → API settings.

**Supabase project ref:** `usmdthxnxzdywtjgbokl`. Deploy backend:
```sh
export SUPABASE_ACCESS_TOKEN=<sbp_… personal access token>   # from Supabase dashboard → Access Tokens
supabase functions deploy product ingredients product-ocr chat search swaps --project-ref usmdthxnxzdywtjgbokl
# migrations/seed applied via the Management API SQL endpoint (see MEMORY.md) or `supabase db push`
#   Chunk 3 adds migrations 20260710000000_products_categories + seed 20260710010000_swaps_demo_seed.
```
**Edge-function secrets already set on the project (values are secret — rotate the pasted ones):** `LLM_BASE_URL` + `LLM_API_KEY` + `LLM_MODEL` (currently Cerebras `gpt-oss-120b`; OpenAI-compatible, swappable to Groq/OpenRouter/Gemini), `USDA_API_KEY`, plus the platform `SUPABASE_*`. **⚠️ Rotate the Cerebras / Groq / USDA keys and the Supabase access token** — they were pasted in chat during development.

## Key gotchas
- **`ios/FoodScanner.xcodeproj` disappears** between build steps in this environment — always `xcodegen generate` and confirm it exists immediately before `xcodebuild`, or you'll reinstall a stale binary.
- **AVCaptureSession:** never call `startRunning()` between `beginConfiguration`/`commitConfiguration` (crashes signal 6). Commit explicitly before start.
- **Scoring rounding** is half-up (Excel `ROUND`), not banker's. Additive penalties count first/additional per tier.
- **LLM never invents** scores/nutrition/ingredient facts — it only rewrites vetted KB/DB data. Keep it that way.
- Full deno tests: `cd supabase/functions && deno task test`. iOS unit tests: `-only-testing:FoodScannerTests` (full `test` incl. XCUITest can time out on sim boot).
