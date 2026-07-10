# Chunk 1 — Result Screen Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline). Steps use checkbox syntax; do them in order, honoring the dependency notes.

**Goal:** Turn the Result screen (the flagship trust moment, SCREEN_SPECS §4) into the Oasis-beating surface: **Watch-outs / Benefits bar-meters** rendered from **real backend-computed nutrient data** (no client math), **additive severity-word + category-pill** rows, a **harmful/beneficial pre-read count** above the ingredient list, **named + dated** source rows, a **wired `ResultSkeletonView`**, and a **real "Report an issue"** round-trip (new `product-report` edge function + iOS submit sheet + thanks state).

**Architecture:** Split backend + client.
- **Backend (new, pure + tested):** a `_shared/scoring/meters.ts` module that turns the already-stored `products.nutrients` (per-100 g OFF/USDA macros) into a `highlights` object — `watchOuts[]`, `benefits[]` meter rows (label, value, unit, tier word, meter fraction 0–1, sources) plus `toKnowAboutCount` / `beneficialCount` — using deterministic, documented FSA/Nutri-Score-aligned thresholds. Wired into `product/handler.ts` `buildBody()` so it serves on **both** cache-hit and fresh paths (reads `product.nutrients`, which is present in both) — **no `score_version` bump, no re-score needed**. Additive **category** is derived server-side from the E-number (Codex INS class ranges) in the `ingredients` handler and returned on each additive row. A new **`product-report`** edge function (`POST`) validates a reason enum + optional free text and inserts into a new `product_reports` table (service-role write; RLS locked to insert-your-own).
- **Client (SwiftUI edits, no new files):** extend `Models.swift` (`NutrientHighlights`, `MeterRow`, `Product.fetchedAt`, `Ingredient.category`); build the two meter sections + pre-read + additive pill rows + dated source rows in `ResultComponents.swift`; wire them + `ResultSkeletonView` into `ProductView.swift`; replace the honest-stub `ReportIssueSheet` with a real submit/thanks/error sheet; add `APIClient.reportIssue(...)`.
- **Schema/RLS:** one new migration — `product_reports` table + insert-only RLS for `authenticated` (mirrors the `events` table policy). No changes to `products` / `score_results`.

**Tech Stack:** SwiftUI iOS 17+ (`@Observable`, `@ScaledMetric`, `ViewThatFits`), supabase-swift, XcodeGen; Deno + `supabase-js@2` edge functions, Postgres RLS; Swift Testing + Deno `jsr:@std/assert@1`.

## Global constraints (every task)
- **LLM/client never does the math (CLAUDE.md #5).** Every meter value, unit, tier word, meter fraction, and both pre-read counts are computed **on the backend** from `products.nutrients` and returned ready-to-render. The client only maps an enum tier → color and renders strings it was given. Enum→display-word maps that already exist on-client (e.g. `ScoreBand.label`) are fine; **numeric derivation is not.**
- **Transparent scoring (#1):** every meter row and additive row carries a source; no unsourced number reaches the UI (teardown AVOID #2).
- **ED-safe (#2):** neutral tier words only — no "bad/toxic/junk", no alarm-red fills, no sad faces (AVOID #1/#3). Watch-outs/Benefits headers per COPY_DECK (never "Negatives/Positives").
- **Never a dead-end (#4):** the report sheet always ends on a next step; error state offers Retry.
- **Copy:** only strings from `docs/COPY_DECK.md` §New surfaces → Result upgrades. Any *new* string (see Task 4 flags) goes through `/ux-writing`'s 4-phase edit and is added to the deck **before** it ships — never invented inline.
- **Tokens only** — `Theme.Space`, `Theme.Radius`, `Theme.score*`; no raw hex/pt literals in views. AA contrast: reuse `Theme.ResultScreen.warningTextOnLight` for amber-on-light text; never `scoreMid` as small text.
- `xcodegen generate` immediately before every `xcodebuild` (project file vanishes — STATE.md gotcha). Build sim command:
  `cd ios && xcodegen generate && xcodebuild -project FoodScanner.xcodeproj -scheme FoodScanner -destination 'platform=iOS Simulator,name=<sim>' build`
- Backend test command: `cd supabase/functions && deno test --allow-none` (or the repo's existing `deno test` invocation). Baseline must stay green (121+) plus the new tests.
- Skills toolchain: query `ui-ux-pro-max` (`--stack swiftui`) for meter/bar + list-row rules before building; run its Pre-Delivery Checklist + teardown AVOID list as the merge gate; `make-interfaces-feel-better` polish gate (tabular-number meter/value digits, calm meter fill animation). Never adopt its palette/fonts.

---

## Dependencies & sequencing note (READ FIRST — chunks may be built out of order)

Per MASTER_PLAN_PRE_D "Sequencing & rationale":

- **Chunk 0 (UI hygiene) should land first.** It adds `Theme.Space.s45 = 20` and scales glyphs. This chunk touches `ProductView.swift:243` (favorite heart) — Chunk 0 already migrated it to semantic `.body`; if Chunk 0 is **not** yet merged, do that one-line change here (`.font(.system(size: 18…))` → `.font(.body.weight(.semibold))`) as part of Task 8 and note it. Do **not** re-introduce raw glyph size literals in any new meter/pill/pre-read view — use semantic fonts / `@ScaledMetric` from the start.
- **This chunk (1) comes BEFORE Chunk 2 (Search) and Chunk 3 (Swaps).** `ResultSkeletonView` is wired here but only *needed* once Search/deep-links can open Result on an in-flight product (Chunk 2). Wiring it now is safe: `ProductView` still always receives a fully-fetched `Product`, so the skeleton path is exercised via a preview + a new optional in-flight init that Chunk 2 will call. Build the skeleton wiring so Chunk 2 can flip it on with zero rework (Task 7).
- **Chunk 4 (current-score DB view) comes AFTER this.** This chunk does **not** depend on it: `highlights` is computed from `product.nutrients` at response-shaping time, independent of which score row is "current". No inline-vs-view switch is needed here.
- **Compare (Chunk 5) reuses the meter component.** Build `MeterRow`/`MetersSection` as standalone, reusable views (own file section, `Source`-driven, no `ProductView` coupling) so Chunk 5 can drop them into a shared-scale two-column layout. Keep the meter's max-scale (the "full bar" reference) a parameter, not a hardcode, so Compare can pass a shared scale later.

---

### Task 1 (TDD, backend): nutrient-highlights builder — tests first
**New files:** `supabase/functions/_shared/scoring/meters.ts`, `supabase/functions/_shared/scoring/meters_test.ts`

The builder is a **pure function** — no I/O, no LLM — so it runs fully offline in the suite. It is the single place the "math" for meters lives (principle #5).

- [ ] **Write `meters_test.ts` first.** Fixtures use the OFF/USDA per-100 g key names already normalized in the codebase (`_shared/usda.ts:30-51`): `saturated-fat_100g`, `sugars_100g`, `salt_100g` (and `sodium_100g`), `fiber_100g`, `proteins_100g`, `energy-kcal_100g`. Cases:
  - `buildNutrientHighlights({})` → `{ watchOuts: [], benefits: [], toKnowAboutCount: 0, beneficialCount: 0 }` (thin data never fabricates a meter).
  - High-fat/sugar/salt fixture (e.g. `saturated-fat_100g: 26.7, sugars_100g: 40, salt_100g: 1.8`) → three `watchOuts` rows; assert **value is rounded once** (`26.7`, never `26.7000001` — AVOID #6 raw floats), `unit === "g"`, `tier === "high"`, `meterFraction` in `[0,1]`, and a non-empty `sources[0].name`.
  - Good-fiber/protein fixture (`fiber_100g: 4.5, proteins_100g: 12`) → `benefits` rows with `tier: "good source"` for fiber; `beneficialCount` = count of benefit rows at the positive tier.
  - Boundary cases at each documented threshold (just-below vs just-at) to lock the classifier: assert the tier flips exactly at the threshold (half-up on the display value must not move the tier).
  - `salt` present as `sodium_100g` only → salt derived via the existing `SALT_PER_SODIUM = 2.5` convention (mirror `usda.ts`), value rounded, unit `g`.
  - `toKnowAboutCount` = number of moderate/higher additive tiers passed in (see signature below), asserted independent of nutrient rows.
  - Energy/calorie fields are **never** emitted as a meter (ED-safe: calories are opt-in per profile, principle #2; the Result screen must not surface calorie numbers here).
- [ ] **Then implement `meters.ts`.** Export:
  ```ts
  export type MeterKind = "watchOut" | "benefit";
  export interface MeterRow {
    label: string;          // "Saturated fat" | "Sugars" | "Salt" | "Fiber" | "Protein"
    value: number;          // rounded ONCE, backend-owned
    unit: string;           // "g"
    tier: string;           // watch-outs: "low"|"moderate"|"high"; benefits: "low"|"some"|"good source"
    meterFraction: number;  // 0..1, value / rowMaxScale, clamped — backend-owned
    kind: MeterKind;
    sources: ScoreSource[]; // reuse ScoreSource from engine.ts
  }
  export interface NutrientHighlights {
    watchOuts: MeterRow[];
    benefits: MeterRow[];
    toKnowAboutCount: number;
    beneficialCount: number;
  }
  export function buildNutrientHighlights(
    nutrients: Record<string, unknown>,
    additiveTiers: AdditiveTier[],
  ): NutrientHighlights
  ```
  - Thresholds table lives at the top of the module as a documented `const`, one entry per nutrient: `{ key, label, kind, unit, maxScale, tiers: [{ upTo, word }] }`. Use **FSA front-of-pack traffic-light 100 g thresholds** for sat fat / sugars / salt and **Nutri-Score fiber/protein points thresholds** for benefits — cite the source in a header comment and in `MeterRow.sources` (`name: "FSA nutrient thresholds (via Open Food Facts)"` / `"Nutri-Score nutrient model (via Open Food Facts)"`, reuse the URLs from `engine.ts:74-93`). No new hardcoded numbers without a cited basis (AVOID #2).
  - `value = roundHalfUp1dp(raw)` — round to one decimal exactly once; import/reuse the rounding intent from `engine.ts:roundHalfUp` (add a 1-dp variant local to the module). Missing/non-numeric key → skip that row entirely (never emit a `0 g` phantom).
  - `meterFraction = clamp(value / maxScale, 0, 1)`.
  - `beneficialCount = benefits.filter(r => r.tier === "good source" || r.tier === "high").length`; `toKnowAboutCount = additiveTiers.filter(t => t === "moderate" || t === "higher").length`.
- [ ] Run `deno test _shared/scoring/meters_test.ts` → green.

### Task 2 (TDD, backend): wire highlights into the product response
**Files:** modify `supabase/functions/product/handler.ts` (interfaces `ScoreBody` L166-172, `ProductBody` L174-184, `buildBody` L190-229), extend `supabase/functions/product/handler_test.ts`.

- [ ] **Extend `handler_test.ts` first.** Add cases to the existing suite (fake deps, no network):
  - Cache-hit path (`cachedRow` fixture, give its `product.nutrients` real macros): assert the response body's `score.highlights` is present with the expected `watchOuts`/`benefits`/counts. This proves highlights serve **without** a re-score.
  - Fresh path (OFF fixture with `nutriments`): assert `score.highlights` present and matches `buildNutrientHighlights` output.
  - `band === "unknown"` (no `score`): assert **no** `highlights` leak (they hang off `score`, which is omitted) — an unknown product shows no meters.
  - `fetchedAt` is present on the body and equals `product.fetched_at` (for Task 6 dated sources).
- [ ] **Then implement.** In `handler.ts`:
  - Import `buildNutrientHighlights` + `NutrientHighlights` from `_shared/scoring/meters.ts`.
  - Add `highlights?: NutrientHighlights` to `ScoreBody` (L166-172) and `fetchedAt: string` to `ProductBody` (L174-184).
  - In `buildBody` (L190-229): the additive tiers — on the **fresh** path use the `tiers` computed at L324; on the **cache** path recompute via `mapAdditiveTiers(product.additives_tags)` (already exported, L124) so the count is available without a re-score. Compute `highlights = buildNutrientHighlights(product.nutrients, tiers)` and attach to `body.score` **only when `body.score` is set**. Set `body.fetchedAt = product.fetched_at`.
  - `buildBody` currently takes `product` + a score union; thread the additive tiers in (add a param or compute inside from `product.additives_tags` for both branches to keep one code path). Keep it pure/deterministic.
- [ ] `deno test product/handler_test.ts` → green; full `deno test` still green (121+).

### Task 3 (TDD, backend): additive category from E-number
**Files:** new `supabase/functions/_shared/additives/category.ts` + `category_test.ts`; modify `supabase/functions/ingredients/handler.ts` (`buildCandidates` L141-175, output shaping).

- [ ] **Write `category_test.ts` first.** Cases mapping the Codex/EU **INS class ranges** to a display label:
  - `additiveCategory("E150d")` / `"en:e150d"` → `"Colours"` (E100–199).
  - `"E322"` → `"Thickeners & emulsifiers"` (E400–499… note E322 lecithin is E300s antioxidant/emulsifier — assert the range you implement; pick the standard mapping and lock it in the test).
  - `"E211"` → `"Preservatives"` (E200–299); `"E621"` → `"Flavour enhancers"` (E600–699); `"E951"` → `"Sweeteners"` (in E900–999 range per your table); unmapped/non-E token → `null` (no pill for non-additives).
  - Case-insensitive, tolerant of `en:` prefix and trailing letters (`E150d`).
- [ ] **Then implement `additiveCategory(raw: string): string | null`** — parse the integer E-number, bucket by INS class range, return the display label or `null`. Header comment cites the INS/E-number classification as the source. **No per-entry data-entry** — pure range math, deterministic.
- [ ] In `ingredients/handler.ts`: when a candidate resolved from an additive tag has an E-number (KB id like `en:eNNN`, or the display token like `E150d`), attach `category = additiveCategory(...)` to that ingredient's output; text-token ingredients get `category: null`. Extend the returned `IngredientOut` shape (and any `unknownIngredient` builder in `_shared/kb/kb.ts`) with an optional `category`. Add a `handler_test.ts` case asserting an additive row carries its category and a plain food token carries `null`.
- [ ] `deno test ingredients/handler_test.ts _shared/additives/category_test.ts` → green.

### Task 4 (copy gate): confirm/draft strings via `/ux-writing`
Do this **before** building the UI (Tasks 5–9) so no string is invented inline.

- [ ] **Verbatim from `docs/COPY_DECK.md` §New surfaces → Result upgrades (implement exactly):**
  - Section headers: `"Watch-outs"` · `"Benefits"`.
  - Meter row pattern: `"{Nutrient} {value}{unit} — {tier word}"` (e.g. "Saturated fat 26.7 g — high", "Fiber 4.5 g — good source").
  - Pre-read: `"{n} ingredients to know about · {n} beneficial"`.
  - Confidence caveat (estimated): `"Estimated — {field} isn't on the label."` · (OCR): `"Scored from a label photo. Some details may be missing."`
  - Source row pattern: `"{Source name} · updated {date}"`.
  - Report row: `"Report an issue"` · sheet title `"What looks wrong?"` · reasons `"Score seems off"` · `"Wrong product info"` · `"Missing ingredient"` · `"Something else"` · free-text label `"Tell us more (optional)"` · submit `"Send report"` · success `"Thanks — we'll review it."` · error `"Couldn't send your report. Check your connection and try again."` [Retry].
- [ ] **MISSING — must be drafted via `/ux-writing` and added to the deck before shipping (flag, do not invent):**
  1. **Additive severity words** for `riskTier` low/moderate/higher. The scoring engine already uses "lower-concern / moderate-concern / higher-concern additive" (`engine.ts:additivesDetail` L148-173) — propose the neutral display words `"Lower concern"` / `"Moderate concern"` / `"Higher concern"` (ED-safe, mirrors existing in-product language, teardown #9 neutral tiers). Add to COPY_DECK §Result upgrades.
  2. **Additive category pill labels** (factual INS class names, still user-facing): `"Colours"`, `"Preservatives"`, `"Antioxidants"`, `"Thickeners & emulsifiers"`, `"Acidity regulators"`, `"Flavour enhancers"`, `"Sweeteners"`, `"Other"`. Confirm wording via `/ux-writing`; add to the deck.
  3. **Meter tier-word ladder** (COPY_DECK gives only the examples "high" / "good source"): confirm the full set — watch-outs `"low"` · `"moderate"` · `"high"`; benefits `"low"` · `"some"` · `"good source"`. Add the full ladder to the deck. **These words must match Task 1's `meters.ts` `tier` strings exactly** (backend is the source of truth for the word; the client only interpolates it).

### Task 5 (TDD, iOS models): decode highlights, category, fetchedAt
**Files:** modify `ios/FoodScanner/Models.swift`; add `ios/FoodScannerTests/HighlightsDecodingTests.swift` (Swift Testing).

- [ ] **Write the decoding test first.** Feed a JSON blob matching the Task 2 response body (a `score.highlights` object + `fetchedAt` + an additive ingredient with `category`) into `JSONDecoder().decode(Product.self, …)`; assert `product.score?.highlights?.watchOuts.first?.value == 26.7`, tier/unit/fraction decode, `beneficialCount`, `product.fetchedAt`, and `ingredient.category == "Preservatives"`. Add a second blob with **no** `highlights` / `category` / `fetchedAt` keys and assert decoding still succeeds with `nil`s (backward compatible with pre-Task-2 cached responses and OCR products).
- [ ] **Then edit `Models.swift`:**
  - Add `struct MeterRow: Codable, Identifiable { var id: String { label }; let label, unit, tier: String; let value: Double; let meterFraction: Double; let kind: String; let sources: [Source] }`.
  - Add `struct NutrientHighlights: Codable { let watchOuts: [MeterRow]; let benefits: [MeterRow]; let toKnowAboutCount: Int; let beneficialCount: Int }`.
  - Add `let highlights: NutrientHighlights?` to `ScoreResult` (L46-52). **Make it optional and update every `ScoreResult(...)` construction site** (the `#if DEBUG` samples in `ProductView.swift:506-616`, `PreviewSupport.swift`, and `ResultComponents.swift` previews) — either add the arg or give it a default via a memberwise-preserving initializer. Confirm the compiler flags all call sites; fix each.
  - Add `let fetchedAt: String?` to `Product` (L68-78) — update its construction sites the same way (notably `ProductView.mergeFullProduct` L396-406 and `PantryEntry.asProduct()`).
  - Add `let category: String?` to `Ingredient` (L54-66) — update its construction sites (the many preview `Ingredient(...)` literals in `ResultComponents.swift`, `ProductView.swift:536`, `PreviewSupport.swift`).
- [ ] `xcodebuild test -only-testing:FoodScannerTests` → green. (Note: `FoodScannerTests` currently has 0 tests per Chunk 0; this adds the first real ones.)

### Task 6 (iOS): meter sections, pre-read, additive pills, dated sources
**Files:** modify `ios/FoodScanner/ResultComponents.swift` (new sections near `WhyScoreSection` L403 and `SourcesSection` L1080); reuse tokens from `Theme.swift` / `Theme+Result.swift`.

Build these as **standalone reusable views** (Compare reuses them — see dependency note):

- [ ] **`MeterRowView`** — a labeled bar meter. Layout: label (`.subheadline`) + right-aligned `"{value} {unit}"` (tabular figures — `.monospacedDigit()`, per make-interfaces-feel-better) on the top line; a `ProgressView(value: row.meterFraction, total: 1)` tinted by tier; the tier word (`.caption.weight(.bold)`) in the tier color. Tier→color map: watch-out `high`→`Theme.scoreLow` (clay, never red), `moderate`→`Theme.scoreMid`, `low`→`Theme.scoreUnknown`/secondary; benefit `good source`→`Theme.scoreHigh`, `some`→`Theme.scoreMid`, `low`→secondary. Reuse the `ScoreFactorRow` bar idiom (L336-350) for visual consistency. `meterFraction` and `value` come pre-computed — **the view does zero arithmetic** (assert this in review). Tap → the row's `sources` in a small popover/disclosure (teardown #5: "sourced rows expand on tap"). Accessibility: `.accessibilityElement(children: .ignore)` + label `"{label}, {value} {unit}, {tier word}"`.
- [ ] **`MetersSection`** — takes `title: String` ("Watch-outs" / "Benefits" verbatim), `rows: [MeterRow]`, `maxScale` unused-for-now-but-parameterized (Compare passes a shared scale later; today each row already carries its own fraction). Renders the header + a `VStack` of `MeterRowView`. Renders **nothing** when `rows` is empty. Text capped at 560 pt on wide screens (SCREEN_SPECS §4 Responsive) via `.frame(maxWidth: 560)`.
- [ ] **`IngredientCountPreRead`** — one calm row above the ingredient list: `"{toKnowAboutCount} ingredients to know about · {beneficialCount} beneficial"` (COPY_DECK verbatim). Counts come straight from `highlights` — no client counting. Neutral styling (`.subheadline`, secondary text + small dots colored by band, never red). Hidden when both counts are 0 and there are no ingredients.
- [ ] **`AdditiveSummaryRow`** — severity-word + category-pill format (teardown #9). For each ingredient with a non-nil `category` (i.e. an additive): name + a severity chip (word from Task 4.1 map, tinted by `riskTier` using the same band colors as `IngredientCard.accentColor` L876-884) + a neutral category pill (`category`, `Theme.surface`/border pill). This is the compact summary; the full `IngredientCard` still renders below. Compose these into an `AdditivesSummarySection` shown only when ≥1 additive is present.
- [ ] **Dated source rows** — update `SourcesSection` (L1080-1102) / `SourceLink` (L377-397) so a source line reads `"{name} · updated {date}"` (COPY_DECK source-row pattern) when a formatted date is available. Add a `fetchedDate: String?` parameter to `SourcesSection`; format `Product.fetchedAt` (ISO) → medium date via a `Date`/`ISO8601DateFormatter` + `.formatted(date: .abbreviated, time: .omitted)`. The static additive-table source keeps its versioned name (no date). Never show "updated (nil)".
- [ ] Add `#Preview`s for `MetersSection` (watch-outs + benefits), `AdditiveSummaryRow`, and `IngredientCountPreRead` using inline sample `MeterRow`s, matching the existing preview style at the file tail (L1420+).

### Task 7 (iOS): compose into ProductView + wire ResultSkeletonView
**Files:** modify `ios/FoodScanner/ProductView.swift`.

- [ ] Insert the new sections into the `body` VStack (L100-141) in SCREEN_SPECS §4 top→bottom order: after `triMetricSectionOrNone` (L108) and before/around `whyScoreOrNote`, add **Watch-outs** then **Benefits** `MetersSection`s (fed from `workingProduct.score?.highlights`), rendered only when their arrays are non-empty. Add the **`IngredientCountPreRead`** + **`AdditivesSummarySection`** directly above the existing `ingredientsSection` (L112). Keep `whyScoreOrNote` (the meters "absorb" the factor rows visually but the sourced factor breakdown stays available — do not delete `WhyScoreSection`; SCREEN_SPECS §4.5 says meters *absorb* the factor rows into visual meters while §4.7 keeps sources — verify with the founder whether `WhyScoreSection` collapses by default now that meters lead; default: keep it, collapsible, below the meters).
- [ ] Pass `workingProduct.fetchedAt` into `SourcesSection` (L116-118) for dated rows.
- [ ] **Wire `ResultSkeletonView` (L1379).** Add an optional in-flight init so Chunk 2 (Search/deep-link) can construct `ProductView` before the product resolves, without reworking this later:
  - Add `init(product: Product)` (unchanged, existing) **and** `init(barcode: String, apiClient loader:…)` OR simplest: add `@State private var isResolving` + an optional `Product?` path. Minimal viable wiring now: add a computed `showsSkeleton` that is `true` only while an in-flight fetch is running; today `product` is always present so `showsSkeleton` is always `false` and behavior is unchanged. In `body`, wrap the scroll content: `if showsSkeleton { ResultSkeletonView() } else { … existing VStack … }`. Leave a `// Chunk 2: set isResolving=true when opened pre-fetch from Search/deep-link` marker.
  - Add a `#Preview("Loading skeleton via ProductView")` that forces `showsSkeleton = true` so the matrix captures it.
- [ ] Confirm the identity header, tri-metric `ViewThatFits` reflow (SCREEN_SPECS §4 Responsive) still holds with the added sections at XXL.

### Task 8 (TDD, backend + iOS): Report-an-issue round-trip
**Backend new files:** `supabase/migrations/20260710000000_product_reports.sql`, `supabase/functions/product-report/{handler.ts,index.ts,handler_test.ts}`.
**iOS:** modify `ios/FoodScanner/APIClient.swift`, `ios/FoodScanner/ResultComponents.swift` (`ReportIssueSheet` L1213-1253), `ios/FoodScanner/ProductView.swift` (sheet call L161-163).

**Migration (`product_reports`):**
- [ ] Table:
  ```sql
  create type report_reason_type as enum ('score_off','wrong_info','missing_ingredient','other');
  create table product_reports (
    id           uuid primary key default gen_random_uuid(),
    product_id   uuid not null references products (id) on delete cascade,
    reporter_id  uuid references auth.users (id) on delete set null,  -- anon JWT user; kept after deletion
    reason       report_reason_type not null,
    detail       text check (char_length(detail) <= 1000),
    created_at   timestamptz not null default now()
  );
  create index product_reports_product_id_idx on product_reports (product_id, created_at desc);
  alter table product_reports enable row level security;
  -- insert-only for the authenticated (incl. anonymous) role; no select/update/delete to clients.
  create policy "users can file reports"
    on product_reports for insert
    to authenticated
    with check (auth.uid() = reporter_id);
  ```
  Mirrors the `events` insert-only pattern (initial schema L217-226). The edge function writes with the **service-role** key (bypasses RLS) but the policy is defense-in-depth so a leaked anon key still can't read others' reports.

**Edge function contract:**
- [ ] `POST product-report` (client path `POST /functions/v1/product-report`, body `{ productId, reason, detail? }`). Model wiring on `chat/index.ts` (service-role client + a user-scoped client to read the caller's JWT).
  - Validate `reason ∈ {score_off,wrong_info,missing_ingredient,other}` → else `400 {error:"invalid_reason"}`. Validate `productId` is a UUID → else `400`. `detail` optional, trim + cap at 1000 chars.
  - Require `Authorization` header → else `401` (matches `product/handler.ts:259`).
  - Derive `reporter_id` from the verified JWT (user-scoped `supabase.auth.getUser(token)`; null on failure is acceptable — column is nullable).
  - Insert via service role; on success `201 {ok:true}`; on DB error `500 {error:"insert_failed"}`. CORS: `POST, OPTIONS` (mirror `chat/handler.ts:44-48`).
- [ ] **Write `product-report/handler_test.ts` first** (fake deps, no DB): valid insert → 201 + asserts the row passed to the fake `insertReport` (productId, reason, trimmed detail, reporter_id); invalid reason → 400; missing auth → 401; bad UUID → 400; `detail` > 1000 chars → trimmed/rejected per your choice (assert it); OPTIONS → 204. Then implement `handler.ts` (pure, injected `Deps`) + `index.ts` (real supabase-js wiring).
- [ ] `deno test product-report/` → green; full suite green.

**iOS client + sheet:**
- [ ] `APIClient.swift`: add
  ```swift
  enum ReportReason: String, CaseIterable { case score_off, wrong_info, missing_ingredient, other }
  func reportIssue(productID: String, reason: ReportReason, detail: String?) async throws {
      struct Body: Encodable { let productId: String; let reason: String; let detail: String? }
      let data = try JSONEncoder().encode(Body(productId: productID, reason: reason.rawValue, detail: detail))
      let _: EmptyResponse = try await request("product-report", method: "POST", body: data)
  }
  ```
  Add a tiny `struct EmptyResponse: Decodable {}` (or decode `{ok:true}`) — reuse the existing generic `request(_:method:body:)` (L69-112). Errors surface as `APIError.transport` for the offline case.
- [ ] Replace `ReportIssueSheet` (L1213-1253) — it currently says "In-app reporting isn't live yet" (honest stub). New sheet (title `"What looks wrong?"`):
  - Reason picker: 4 tappable rows/chips → `"Score seems off"`, `"Wrong product info"`, `"Missing ingredient"`, `"Something else"` mapped to the enum. Radio-style single-select **is correct here** (single choice) — but ensure it does NOT read as a multi-select (AVOID #11 is about multi-select lists; a single-select needs a clear selected state).
  - Free-text `TextField`/`TextEditor` labeled `"Tell us more (optional)"`.
  - Primary `"Send report"` button (disabled until a reason is chosen); on tap → `phase = .sending`, call `apiClient.reportIssue(...)`.
  - States (`enum Phase { case editing, sending, done, failed }`): `.done` → thanks state `"Thanks — we'll review it."` + a Close/Done that dismisses (never a dead-end). `.failed` → `"Couldn't send your report. Check your connection and try again."` + `[Retry]` (re-submits). `.sending` → disabled controls + progress.
  - Pass `productID` in (currently only `productName`): change the initializer to `ReportIssueSheet(productID:productName:)` and the call site at `ProductView.swift:161-163` (it already has `workingProduct.id`). Inject `APIClient`/`SessionService` via `@Environment(SessionService.self)` (as ProductView does, L16) and build `APIClient(session:)`.
- [ ] Update the `#Preview("Report issue sheet")` (file tail ~L1521) to pass a `productID`.

### Task 9 (iOS): favorite glyph + no-new-literals sweep
- [ ] If Chunk 0 has **not** landed: `ProductView.swift:243` favorite heart → `.font(.body.weight(.semibold))` (SCREEN_SPECS §4 "favorite glyph 18pt → scaled"). If Chunk 0 landed, verify it's already semantic and skip.
- [ ] Grep gate: `grep -rn "font(.system(size" ios/FoodScanner/ResultComponents.swift ios/FoodScanner/ProductView.swift` — every new meter/pill/pre-read/report view uses semantic fonts or `@ScaledMetric`; the only permitted literal remains the documented `ResultComponents.swift:535` shippingbox placeholder (fixed-size container). No new raw pt/hex literals in the new views (`grep -n "padding(.*[0-9]\{2\}\|Color(hex"`).

### Task 10: Verify — build, tests, screenshot matrix, gates
- [ ] `cd supabase/functions && deno test` → **all green** (121+ baseline + new `meters_test`, `category_test`, extended `product`/`ingredients` tests, new `product-report` tests). Record the new total.
- [ ] **Deploy + smoke the backend:** apply the migration (`supabase db push` / migration up) and deploy functions (`supabase functions deploy product-report` and re-deploy `product`, `ingredients`). Smoke: `curl` the report endpoint with a valid anon JWT → 201; confirm a row lands in `product_reports`; `curl` `product/:barcode` for a real barcode → response includes `score.highlights` + `fetchedAt`.
- [ ] `cd ios && xcodegen generate && xcodebuild … build` (sim) — zero new errors/warnings.
- [ ] `xcodebuild test -only-testing:FoodScannerTests` → green (new decoding tests run).
- [ ] **6-shot screenshot matrix** (SCREEN_SPECS global rule): Result screen on **SE-proxy (iPhone 17e — no SE 3rd-gen sim installed, per Chunk 0 substitution)** / **iPhone 17 Pro** / **iPhone 17 Pro Max** × **default** and **XXL (`accessibility-extra-extra-extra-large`)** Dynamic Type. Capture: full Result (meters + pre-read + additive pills + dated sources), the Report sheet (editing / thanks / error), and the `ResultSkeletonView` preview. Verify: meters/pills/counts reflow without clipping, tabular value digits align, tri-metric `ViewThatFits` still vertical at XXL, text caps at 560 pt on Max, no alarm-red, no raw floats.
- [ ] **Gates (blocking):** principles (transparency / ED-safe / honest states / never-a-dead-end / **LLM-never-does-math** — confirm the meter/count views do zero arithmetic) · teardown **AVOID** list (esp. #1 no red/sad, #2 every number sourced, #6 no raw floats/API dumps) · `ui-ux-pro-max` Pre-Delivery Checklist (App UI: icons, interaction, light/dark contrast, layout, a11y) · `/ios-design-review` on the sim screenshots before device install.
- [ ] Device install on the physical iPhone; founder review.
- [ ] `MEMORY.md` decision entry (meters computed server-side from `products.nutrients`, additive category via INS ranges, `product_reports` table + endpoint) + `STATE.md` status-line update.

---

## Exit criteria (mirrors MASTER_PLAN_PRE_D Chunk 1)
- [ ] **Meters render from real breakdown data (no client math):** Watch-outs/Benefits bar-meters on Result show real per-100 g values + tier words + fractions, all computed in `_shared/scoring/meters.ts` and served on `score.highlights`; the SwiftUI views perform zero arithmetic (verified in review).
- [ ] Additive rows show neutral **severity word + category pill**; **harmful/beneficial pre-read count** sits above the ingredient list, fed from backend counts.
- [ ] Source rows are **named + dated** (`"{name} · updated {date}"`).
- [ ] `ResultSkeletonView` is wired into `ProductView` (dormant today, flip-on-ready for Chunk 2).
- [ ] **Report row round-trips to DB:** `POST product-report` inserts into `product_reports`; iOS sheet shows editing → sending → `"Thanks — we'll review it."` (and an honest Retry error state).
- [ ] **121+ deno tests still green + new endpoint/meters/category tests green**; iOS `FoodScannerTests` green.
- [ ] **6-shot screenshot matrix passes**; device install + founder review done; principles + teardown-AVOID + ui-ux-pro-max checklist gates all pass; `MEMORY.md` + `STATE.md` updated.

## Files touched
- **New (backend):** `supabase/functions/_shared/scoring/meters.ts` (+`_test`), `supabase/functions/_shared/additives/category.ts` (+`_test`), `supabase/functions/product-report/{handler.ts,index.ts,handler_test.ts}`, `supabase/migrations/20260710000000_product_reports.sql`.
- **New (iOS test):** `ios/FoodScannerTests/HighlightsDecodingTests.swift`.
- **Edited (backend):** `supabase/functions/product/handler.ts` (+`handler_test.ts`), `supabase/functions/ingredients/handler.ts` (+`handler_test.ts`), `supabase/functions/_shared/kb/kb.ts` (optional `category` on ingredient output).
- **Edited (iOS):** `ios/FoodScanner/Models.swift`, `ios/FoodScanner/ResultComponents.swift`, `ios/FoodScanner/ProductView.swift`, `ios/FoodScanner/APIClient.swift`, plus every `ScoreResult(...)` / `Product(...)` / `Ingredient(...)` construction site the new optional fields touch (`PreviewSupport.swift`, `PantryModels.swift` `asProduct()`).
- **Edited (docs):** `docs/COPY_DECK.md` (Task 4 additions), `MEMORY.md`, `STATE.md`.
