# Chunk 3 — Swaps Engine: "See a better option" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline). Steps use checkbox syntax "- [ ]". Do tasks in order; each backend task writes its Deno test BEFORE the implementation (TDD). Do not skip the verification task.

**Goal:** Close the loop no competitor closes (principle #4): turn a verdict into a concrete, ranked, restriction-safe better option. New backend endpoint `GET /product/:id/swaps` + a real iOS Swaps sheet that replaces the honest stub (`NextActionSheet`). Every "why better" fact is a deterministic diff of DB fields (no LLM math, principle #5); allergen filtering runs against the caller's profile under RLS; empty results stay honest (never a dead-end / AVOID-14).

**Architecture:** One **new** Supabase edge function `supabase/functions/swaps/` (`index.ts` wiring + `handler.ts` pure logic + `handler_test.ts`), modeled exactly on the `chat` function's split (service-role client for the global `products`/`score_results` cache; a **user-scoped** client carrying the caller's JWT for the RLS-guarded `profiles` allergen read). Ranking is pure and unit-tested with fake deps. A **schema change** is required: `products` has no category column today, so swaps cannot group "same category" — add `categories_tags text[]` (migration), extend the OFF client to fetch/map it, and populate it on product upsert. **Current-score** is read as the latest `score_results` row per candidate by `computed_at desc` (this already IS the current score in `product/handler.ts`; Chunk 4 later swaps this for the `product_current_scores` view — see Dependencies). On iOS: **new** `SwapsView.swift` (sheet: ranked cards, mini rings, delta chip, sourced why-better line, Save-to-pantry, honest thin-results empty state), new models in `Models.swift`, new `APIClient.swaps(productID:)`, a small compact initializer on `ScoreBadge` for the mini rings, and rewiring `ProductView`'s primary CTA from `NextActionSheet` (stub) to `SwapsView`. No RLS policy changes (existing `products`/`score_results` global-read + `profiles` owner-read policies are exactly what we need).

**Tech Stack:** Deno + supabase-js v2 edge functions, Postgres (RLS), `@std/assert` Deno tests · SwiftUI iOS 17+, `@Observable`, `URLSession`/`Codable`, `@ScaledMetric`, Swift Testing/XCTest, XcodeGen.

---

## Dependencies & sequencing note (read before starting)

- **Depends on Chunk 4 (`product_current_scores` view) for "current, not highest-ever" scores — but does NOT block on it.** Chunk 4 lands after Chunk 3 per the master sequence (`0→1→2→3→4…`). Until the view exists, the swaps handler computes current-score **inline**: for each candidate it reads the single most-recent `score_results` row (`.order("computed_at", { ascending: false }).limit(1)`), which is the same "latest wins" rule `product/handler.ts:39-44` already uses. **When Chunk 4 lands:** replace the per-candidate latest-score query in `swaps/index.ts` with a single read from `product_current_scores` (leave `handler.ts` untouched — it only sees the injected `Deps.getCandidates` shape). Add a one-line TODO comment at the query site referencing this.
- **Builds on Chunk 2 (search / OFF category normalization).** Chunk 2 introduces OFF category handling; if Chunk 2's `categories_tags` plumbing already landed, **reuse it** and skip Task 1's OFF-mapping edits (verify with `grep -n categories_tags supabase/functions/_shared/off.ts`). If Chunk 2 is not yet merged, Task 1 adds the column + OFF mapping here and Chunk 2 reuses it.
- **Reuses Chunk 1's `ScoreBadge` ring** for the mini rings (Task 6 adds a compact initializer; if Chunk 1 already parameterized `ScoreBadge`, reuse that instead of re-adding).
- **Save-to-pantry reuses the existing `PantryService`** favorite/upsert path (`PantryService.swift:288 upsertStatus`) — no new persistence code; Task 7 adds one thin `saveToPantry(product:)` wrapper only if a non-favorite "owned/scanned" save is wanted distinct from favorite.

---

## Global constraints (every task)
- Tokens only — no raw hex/pt literals in views (`Theme.Space`, `Theme.Radius`, band colors via `Theme.score*`). Delta chip / band tints use band colors, **never alarm red** (AVOID-1, AVOID-5).
- Copy verbatim from `docs/COPY_DECK.md` §Swaps (lines 124-132). Any string not in the deck must be drafted via `/ux-writing` (4-phase edit) and **added to the deck** before use — do not invent inline (Standing rule).
- **LLM never does the math (principle #5):** every "why better" fact is a deterministic comparison of stored DB fields (additive tags, `nutriments` per-100g). No LLM call in this chunk.
- **Every number is sourced (AVOID-2, principle #1):** why-better facts derive only from `products.additives_tags` and `products.nutrients` — both OFF/USDA-sourced and already attributed. Round nutrient deltas; never dump raw floats (AVOID-6).
- **Never a dead-end (principle #4):** thin/empty results show the honest empty state + "Scan another", not a blank sheet (AVOID-14).
- ED-safe tone (principle #2): descriptive, no shaming; "Better options" framing is opportunity, not judgment.
- AA contrast + Dynamic Type + VoiceOver: cards use combined a11y labels (spec §5 A11y).
- Backend: run `xcodegen generate` immediately before every `xcodebuild` (project file vanishes — STATE.md gotcha). Deno: `cd supabase/functions && deno task test`.

---

### Task 1: Schema + OFF category plumbing (`categories_tags`)

**Why:** `products` (migration `20260707000000_initial_schema.sql:53-71`) has no category column, and `_shared/off.ts` never fetches `categories_tags`. Swaps cannot group "same OFF category" without it.

**Files:** new `supabase/migrations/20260710000000_products_categories.sql`; modify `supabase/functions/_shared/off.ts:17-29` (OFF_FIELDS), `:32-46` (OffProduct), `:89-109` (mapOffPayload); modify `supabase/functions/product/handler.ts:38-55` (ProductRow), `:336-352` (upsertProduct call).

- [ ] **TEST FIRST** — add cases to `supabase/functions/_shared/off_test.ts`: `mapOffPayload` maps `categories_tags: ["en:breakfasts","en:chocolate-spreads"]` → `categoriesTags` array; missing/non-array → `[]`. Run `deno task test` → red.
- [ ] Migration: `alter table products add column categories_tags text[] not null default '{}';` + `create index products_categories_gin_idx on products using gin (categories_tags);` (GIN for the `&&` overlap query in Task 2). No RLS change (inherits `products` global-read policy).
- [ ] `off.ts`: add `"categories_tags"` to `OFF_FIELDS`; add `categoriesTags: string[]` to `OffProduct`; in `mapOffPayload` set `categoriesTags: Array.isArray(p.categories_tags) ? p.categories_tags.filter((t): t is string => typeof t === "string") : []`.
- [ ] `product/handler.ts`: add `categories_tags: string[]` to `ProductRow`; pass `categories_tags: off.categoriesTags` in the `upsertProduct({…})` object (`:336-352`).
- [ ] `product/index.ts:53-61` upsertProduct passthrough already spreads the row — confirm `categories_tags` flows; no change unless it enumerates columns.
- [ ] Re-run `deno task test` → green. **Note:** existing cached products carry `{}` until re-fetched; Task 8 seeds a fresh same-category cohort for the demo.

**Exit:** `mapOffPayload` test green; migration applies clean (`supabase db reset` locally or `supabase migration up`); a fresh scan writes a non-empty `categories_tags`.

---

### Task 2: Swaps ranking logic — pure handler (TDD)

**Files:** new `supabase/functions/swaps/handler_test.ts` (write first), then `supabase/functions/swaps/handler.ts`.

**Endpoint contract:**
```
GET /functions/v1/swaps/product/:id/swaps      (path mirrors product/:id; see routing note)
Auth: Authorization: Bearer <jwt>  (required; 401 without)
200 → {
  category:  string | null,     // display label derived from primary category tag, or null
  subjectScore: number,         // current score of the scanned product (for delta base)
  filteredForAllergies: boolean,// true when the caller profile's allergies removed ≥1 candidate
  swaps: [ {
    id: string, name: string, brand: string | null, imageURL: string | null,
    score: number, band: "high"|"mid"|"low",
    delta: number,                       // score - subjectScore (always > 0 here)
    inPantry: boolean,                   // in caller's pantry_items
    whyBetter: string[]                  // 0–3 sourced facts, deterministic (see below)
  } ],
  thin: boolean                 // true when < MIN_STRONG results → client shows honest note
}
404 → { error: "not_found" }   // subject id not in products
400 → { error: "invalid_id" }  // id not a uuid
401 → { error: "unauthorized" }
```

**Ranking algorithm (per SCREEN_SPECS §5 "Ranking" + user-flows §3), pure function `rankSwaps(subject, candidates, pantryIds, allergies)`:**
1. **Same category:** candidate `categories_tags` overlaps subject `categories_tags` (`&&`). If subject has no category → return `[]` + `thin:true` (honest empty).
2. **Better:** candidate current `score` strictly `> subjectScore` (skip null/unknown-band scores).
3. **Restriction-safe:** drop any candidate whose `allergens_tags` (prefix-normalized) intersects the caller's profile `allergies`. Track whether this removed anyone → `filteredForAllergies`.
4. **Pantry-first, then score:** stable sort — `inPantry` desc, then `delta` desc, then `score` desc, then `name` asc (deterministic tie-break so tests are stable).
5. Cap at `MAX_SWAPS = 5`. `thin = results.length < MIN_STRONG (2)` — but still return whatever we have (never a dead-end).

**Deterministic why-better (`whyBetter(subject, candidate)`), max 3 facts, sourced fields only — NO LLM:**
- **Additive absence:** additive tags present in `subject.additives_tags` but absent in `candidate.additives_tags`, mapped to a display token via the existing `additives_risk.json`/`mapAdditiveTiers` uppercase form (e.g. `en:e150d` → `E150d`). Copy pattern (COPY_DECK:128): `"No colours E150d"` — group by additive class where the risk table gives one, else `"No {CODE}"`. Emit only for tags at tier `moderate`/`higher` (don't tout removing a benign one).
- **Lower nutrient:** compare per-100g values in `nutriments` for an allowlist `{ "sugars_100g": "sugar", "saturated-fat_100g": "saturated fat", "salt_100g": "salt" }`. Emit `"lower {label}"` only when candidate value is meaningfully lower (`candidate < subject * 0.9` AND both present as finite numbers). Round for any displayed number (none shown here — just the word).
- Join with `" · "` per COPY_DECK:128 (`"No colours E150d · lower saturated fat"`). If no qualifying facts, `whyBetter: []` and the card shows only the delta chip (still honest — the score IS the fact).

- [ ] **TEST FIRST** `handler_test.ts` — fake `Deps` (no network/DB), `@std/assert@1`, mirror `product/handler_test.ts` fixture style. Cases:
  1. `extractSubjectId` parses `/product/<uuid>/swaps` (and behind `/functions/v1/…`).
  2. Higher-scored same-category candidate returned with correct `delta` and `whyBetter` (additive absent + lower saturated fat).
  3. Allergen-conflicting candidate (profile allergy `"milk"`, candidate `allergens_tags:["en:milk"]`) is dropped; `filteredForAllergies:true`.
  4. Lower/equal-scored candidates excluded; unknown-band candidates excluded.
  5. Pantry-first ordering: a pantry candidate with smaller delta sorts above a non-pantry larger delta.
  6. Subject with empty `categories_tags` → `swaps:[]`, `thin:true`, `category:null`.
  7. No candidates beat subject → `swaps:[]`, `thin:true` (honest empty, 200 not error).
  8. Missing subject id → 404; bad id → 400; missing Authorization → 401.
  9. `whyBetter` never exceeds 3 facts; benign-only additive removal produces no additive fact.
  10. Deterministic tie-break: two equal (inPantry, delta, score) candidates order by name.
  Run `deno task test` → red (module missing).
- [ ] Implement `handler.ts`: `CORS_HEADERS`/`json` helpers (copy from `product/handler.ts:94-106`, methods `GET, OPTIONS`), `extractSubjectId(url)`, pure `rankSwaps`, `whyBetter`, `handleSwaps(req, deps)`. `Deps` shape:
  ```ts
  interface Deps {
    getSubject(id: string): Promise<SwapProductRow | null>;              // products + current score
    getCandidates(categoriesTags: string[], excludeId: string): Promise<SwapProductRow[]>;
    getPantryProductIds(): Promise<Set<string>>;                         // caller pantry (user-scoped)
    getAllergies(): Promise<string[]>;                                   // caller profile (user-scoped, RLS)
    now(): number;
  }
  ```
  `SwapProductRow` = `{ id, name, brand, imageURL, categoriesTags, additivesTags, allergensTags, nutrients, score: number|null, band: string }`.
- [ ] Reuse additive display mapping: import the uppercase-normalization already in `product/handler.ts:139` (`replace(/^en:/,"").toUpperCase()`) or factor a tiny shared helper in `_shared/scoring/` — do NOT duplicate the risk table load.
- [ ] Run `deno task test` → all green (existing 121 + new).

**Exit:** all `handler_test.ts` cases green; ranking/why-better are pure and deterministic; no LLM import.

---

### Task 3: Swaps edge function wiring (`index.ts`)

**Files:** new `supabase/functions/swaps/index.ts`.

- [ ] Model on `chat/index.ts:26-117` exactly: service-role `supabase` client for `products`/`score_results`/pantry candidate reads; a **user-scoped** client (caller `Authorization` header + `SUPABASE_ANON_KEY`) for `getAllergies()` (reads `profiles.allergies` under RLS → `auth.uid()`) and `getPantryProductIds()` (reads `pantry_items` under RLS). Any auth problem → `[]`/empty set (guest still gets category-ranked swaps, just unfiltered — honest, never crashes; matches `ProductView`'s optional-profile stance at `ProductView.swift:18-22`).
- [ ] `getSubject`: service-role read of `products` by `id` + its latest `score_results` (`.order("computed_at",{ascending:false}).limit(1)`). **Chunk-4 TODO comment:** `// TODO(chunk-4): read current score from product_current_scores view instead of latest-by-computed_at`.
- [ ] `getCandidates`: service-role `products` query `.overlaps("categories_tags", categoriesTags)` + join latest score per candidate. Because PostgREST can't easily do per-row latest, fetch candidate products (limit ~40 by category), then batch-read their latest scores (either an RPC or `score_results` ordered read reduced in JS to latest-per-product). Keep it in `index.ts` (impure); `handler.ts` receives already-resolved `{score, band}`.
- [ ] `Deno.serve((req) => handleSwaps(req, buildDeps(req)))`.
- [ ] **Routing:** each function is deployed at its own name (`/functions/v1/swaps`). The client will call `swaps/product/<id>/swaps` (Task 5) so `extractSubjectId` finds the id as the second-to-last segment. Confirm `handleSwaps` OPTIONS returns 204 (CORS preflight) like `product/handler.ts:250-251`.
- [ ] Deploy: `supabase functions deploy swaps --project-ref usmdthxnxzdywtjgbokl` (append `swaps` to the STATE.md deploy line's function list going forward).

**Exit:** function deploys; `curl` with a valid anon JWT against a seeded low-score product id returns ≥1 swap (verified in Task 8); guest (anon) call returns category swaps with `filteredForAllergies:false`.

---

### Task 4: iOS models + APIClient

**Files:** modify `ios/FoodScanner/Models.swift` (append), `ios/FoodScanner/APIClient.swift:120-122` region (add method).

- [ ] `Models.swift`: append `SwapCandidate` + `SwapsResponse` (Codable, matching Task 2 response verbatim):
  ```swift
  struct SwapCandidate: Codable, Identifiable {
      let id: String
      let name: String
      let brand: String?
      let imageURL: String?
      let score: Int
      let band: ScoreBand
      let delta: Int
      let inPantry: Bool
      let whyBetter: [String]
  }
  struct SwapsResponse: Codable {
      let category: String?
      let subjectScore: Int
      let filteredForAllergies: Bool
      let swaps: [SwapCandidate]
      let thin: Bool
  }
  ```
- [ ] `APIClient.swift` (after `ingredients(productID:)`, ~line 122): add
  ```swift
  /// Ranked, restriction-safe better options in the same category
  /// (GET swaps/product/:id/swaps). Deterministic, sourced why-better facts
  /// computed server-side from DB diffs — the LLM never runs here.
  func swaps(productID: String) async throws -> SwapsResponse {
      try await request("swaps/product/\(productID)/swaps")
  }
  ```
  (`request` already injects `apikey` + bearer JWT — `APIClient.swift:83-85`.)

**Exit:** compiles; `SwapsResponse` decodes the Task 2 sample JSON (add a Swift Testing decode case in Task 7).

---

### Task 5: `SwapsView.swift` — the sheet (new file)

**Files:** new `ios/FoodScanner/SwapsView.swift`. Reference layout: SCREEN_SPECS §5; copy: COPY_DECK:124-132.

- [ ] `SwapsView` — a `@State`-driven `NavigationStack` sheet, `.presentationDetents([.medium, .large])`, `.presentationDragIndicator(.visible)`, radius/tokens like `NextActionSheet` (`ResultComponents.swift:1290-1353`) but real data. Inputs: `let product: Product`, `let onScanAnother: () -> Void`, `@Environment(APIClient…)`/services as injected elsewhere (match how `ProductView` gets `APIClient` — it's constructed from `session`; see `ProductView` usage / `refreshThinPantryDataIfNeeded`). Load phase enum `{ idle, loading, loaded(SwapsResponse), failed }`.
- [ ] **Title:** `"Better options in \(category)"` when `category != nil`, else `"Better options"` (COPY_DECK:37/125). Optional restriction note row under title when `filteredForAllergies`: `"Filtered for your allergies."` (COPY_DECK:132).
- [ ] **Loading:** skeleton cards + text `"Finding better options…"` (COPY_DECK:126).
- [ ] **Ranked cards** (`SwapCard`): product thumb, name + brand (2-line/truncate), **mini score ring** (Task 6), **delta chip** `"+\(delta) score"` (COPY_DECK:127) tinted with the candidate's band color (never red — AVOID-1/5), 1-line why-better `whyBetter.joined(separator: " · ")` (already server-formatted), `"In your pantry"` chip when `inPantry` (COPY_DECK:130). Per-card actions row: **View** (push `ProductView(product:)` built from the candidate — fetch full product via `APIClient.product` by barcode/id or navigate with a thin `Product`) and **Save to pantry** (Task 7). Labels verbatim `"View"` · `"Save to pantry"` (COPY_DECK:129).
- [ ] **Empty / thin (honest, principle #4 / AVOID-14):** when `swaps.isEmpty` (or as a footer note when `thin && !swaps.isEmpty`): `"Few close matches in this category yet. Here's the nearest — or scan another to compare."` + primary `"Scan another"` button (COPY_DECK:131) calling `onScanAnother`. This is where the retired stub's honest behavior now lives.
- [ ] **Error:** calm retry row (reuse the app's error copy conventions; `"Couldn't load better options. Check your connection and try again."` — if not already in the deck, draft via `/ux-writing` and add to COPY_DECK §Swaps before shipping).
- [ ] **A11y:** each card `.accessibilityElement(children: .combine)` with combined label per spec §5: `"Better option: \(name), score \(score), \(band.label)\(whyBetter.isEmpty ? "" : ", " + whyBetter.joined(separator: ", "))"`. Delta chip uses tabular figures (`make-interfaces-feel-better` gate). Mini ring is decorative-with-label (ScoreBadge already sets `.accessibilityLabel`).
- [ ] Responsive: card content reflows to vertical stack at accessibility Dynamic Type sizes (mirror `ProductView.swift:189-199` `dynamicTypeSize.isAccessibilitySize` pattern). Text capped for Max width per §5.

**Exit:** sheet renders loaded/loading/empty/error states from real API; VoiceOver reads one sensible sentence per card.

---

### Task 6: Mini score ring (compact `ScoreBadge`)

**Files:** modify `ios/FoodScanner/ScoreBadge.swift:13-21`.

- [ ] Add a compact initializer so the swaps cards reuse the exact same ring treatment (redundant number+word+arc, band tints, never color-only — the whole reason to reuse it). Parameterize the base diameter/lineWidth while keeping current call sites (default 108/9) unchanged:
  ```swift
  init(score: Int?, band: ScoreBand, diameter baseDiameter: CGFloat = 108, lineWidth baseLineWidth: CGFloat = 9)
  ```
  Back the two `@ScaledMetric` defaults with the passed base values (assign in `init` via `_diameter = ScaledMetric(wrappedValue: baseDiameter, relativeTo: .title2)` etc.). Swaps cards call `ScoreBadge(score:band:diameter: 52, lineWidth: 5)`. **If Chunk 1 already parameterized `ScoreBadge`, reuse it and skip this task.**
- [ ] Verify existing `#Preview`s (`ScoreBadge.swift:87-103`) still compile; add one compact preview.

**Exit:** mini ring renders at 52pt in swaps cards, full ring unchanged on Result.

---

### Task 7: Save-to-pantry + Result CTA rewire

**Files:** modify `ios/FoodScanner/ProductView.swift:38` (state), `:134-136` (CTA), `:152-157` (sheet); reuse `ios/FoodScanner/PantryService.swift:201-208` (`save`) / `:288` (`upsertStatus`).

- [ ] **Save-to-pantry action** in `SwapCard`: call the existing `PantryService.save(product:)` (fire-and-forget, `PantryService.swift:201`) with the candidate as a `Product`, then reflect a saved state on the card (`"Save to pantry"` → checkmark/"Saved", optimistic). No new persistence code. If a distinct non-favorite "owned" status is wanted later, add a thin `saveToPantry` wrapper — not required for this chunk.
- [ ] **Rewire Result CTA:** keep the primary button label `"See a better option"` and icon `arrow.triangle.2.circlepath` (`ProductView.swift:134`) but present `SwapsView(product: workingProduct, onScanAnother: { showBetterOptionSheet = false; dismiss() })` from the `.sheet(isPresented: $showBetterOptionSheet)` at `ProductView.swift:152-157`, replacing `NextActionSheet(band:onScanAnother:)`.
- [ ] **Retire the stub:** remove `NextActionSheet` (`ResultComponents.swift:1290-1353`) and its preview usage (`:1509`), OR keep it only if another caller exists (grep: `grep -rn NextActionSheet ios/` — only `ProductView` + the preview reference it, so delete both). Its honest empty-state behavior now lives in `SwapsView`'s empty state (Task 5). Leave `NextActionButton` (`ResultComponents.swift:1259`) — still used for the CTA.

**Exit:** tapping "See a better option" opens the real swaps sheet; Save-to-pantry writes a `pantry_items` row and updates Home on next load; no dangling `NextActionSheet` references (build clean).

---

### Task 8: Seed a same-category demo cohort + manual endpoint verification

**Why:** products only enter the DB on scan, and existing rows have empty `categories_tags` (Task 1). Swaps needs multiple same-category products with current scores to return real results.

- [ ] Scan/`curl` `GET /product/:barcode` for ~5 barcodes in ONE OFF category spanning score bands (e.g. chocolate-spreads or breakfast-cereals: a NOVA-4 low-score item as the SUBJECT + higher-scored alternatives). This populates `products` (with `categories_tags`) + `score_results`. Record the low-score subject's `products.id`.
- [ ] `curl "$FUNCTIONS_URL/swaps/product/<subjectId>/swaps"` with `apikey` + a valid `Authorization` bearer → assert ≥1 swap with a non-empty `whyBetter` and correct `delta` (exit criterion). Repeat with a test profile carrying an allergy present in one candidate → assert that candidate is filtered and `filteredForAllergies:true`.
- [ ] Confirm the honest empty path: a product with a unique/absent category → `swaps:[]`, `thin:true`.

**Exit:** low-score demo product returns ≥1 real better option with a sourced reason; allergen-safe filtering verified with a test profile; empty state honest (mirrors MASTER_PLAN Chunk 3 Exit).

---

### Task 9: iOS unit tests

**Files:** new/append `ios/FoodScannerTests/…` (Swift Testing; `FoodScannerTests` target currently has 0 tests per chunk-0 notes — add the first real ones here).

- [ ] `SwapsResponse`/`SwapCandidate` decode a canonical Task 2 JSON sample (including `whyBetter:[]`, `category:null`, `thin:true`).
- [ ] `ScoreBand` from candidate `band` string round-trips (`"mid"` → `.mid`).
- [ ] Any client-side formatting helper (delta chip string `"+22 score"`, why-better join) has a unit test if it lives in a testable type; keep formatting in the view otherwise and rely on the decode test.

**Exit:** `xcodebuild test -only-testing:FoodScannerTests` green.

---

### Task 10: Verify — build, tests, screenshot matrix, gates

- [ ] `cd supabase/functions && deno task test` → all green (121 existing + new swaps/off cases).
- [ ] `cd ios && xcodegen generate && xcodebuild -project FoodScanner.xcodeproj -scheme FoodScanner -destination 'platform=iOS Simulator,name=<sim>' build` → clean (regenerate project immediately before build — STATE.md gotcha).
- [ ] `xcodebuild test -only-testing:FoodScannerTests` → green.
- [ ] **6-shot screenshot matrix** of the Swaps sheet — loaded (≥2 cards), thin/empty, and error — on **iPhone 17e (SE-proxy)** / **17 Pro** / **17 Pro Max** × **default** / **XXL (AX5)** Dynamic Type. No clipping; mini rings + delta chips scale; card reflows to vertical at AX sizes; long product names truncate gracefully. (Artifacts to `ios/Generated/screenshots/`, gitignored.)
- [ ] Device install + founder review of the real sheet on a physical iPhone (Standing rule: device review before merge-to-main).
- [ ] **Gate — principles:** transparency (why-better sourced from DB, no LLM math), ED-safe tone, honest empty state, never-a-dead-end, AA a11y — all pass.
- [ ] **Gate — teardown AVOID list** (`design-teardown.md:91-105`): no alarm-red delta/band tint (#1/#5), why-better facts all sourced (#2), no raw floats (#6), no empty 70% screen — thin state has calm content + action (#14). Confirm STEAL #15 (mini ring on thumbnails) is present.
- [ ] **Gate — ui-ux-pro-max Pre-Delivery Checklist** (App UI: icons scaled, interaction feedback on Save, light/dark contrast on chips, layout reflow, a11y labels) + `make-interfaces-feel-better` (tabular numbers on score/delta digits, Save micro-interaction). Query rules first: `python3 ~/.claude/skills/ui-ux-pro-max/scripts/search.py "list card ranking" --stack swiftui`. **Never adopt its palette/fonts** — brand locked to DESIGN_SYSTEM_V3.
- [ ] `/ios-design-review` on the sim screenshots before device install.
- [ ] Commit + `MEMORY.md` decision entry + `STATE.md` status line update (add `swaps` to the deployed-endpoints + deploy-command lists); mark Chunk 3 done.

---

## Verification / Exit criteria (mirrors MASTER_PLAN Chunk 3 + standard gate)
- Low-score demo product returns **≥1 real better option with a sourced why-better reason**.
- **Allergen-safe filtering verified** with a test profile (conflicting candidate dropped, `filteredForAllergies:true`).
- **Empty state honest** (thin/no-category → calm note + "Scan another", never blank/dead-end).
- **Deno tests for ranking green** (pure `rankSwaps`/`whyBetter` + edge/auth cases) alongside the existing 121.
- **iOS tests green**; **6-shot screenshot matrix** (17e / 17 Pro / 17 Pro Max × default / XXL) clean; **device install** reviewed.
- Principles gate + teardown-AVOID gate + ui-ux-pro-max Pre-Delivery Checklist all pass.
