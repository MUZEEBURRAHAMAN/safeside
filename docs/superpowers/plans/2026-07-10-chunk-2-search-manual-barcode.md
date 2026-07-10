# Chunk 2 — Search + Manual Barcode Entry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline). Steps use checkbox syntax "- [ ]". Query `ui-ux-pro-max` (`--stack swiftui`, `--domain ux`) before building the Search screen and run its Pre-Delivery Checklist + the teardown AVOID list as merge gates. New user-facing strings: implement the COPY_DECK §"Search & manual barcode" block verbatim; anything not in the deck goes through `/ux-writing` and into the deck first.

**Goal:** Kill the biggest dead-end (no camera / no barcode / broken label). Add a `GET /search?q=` edge function that maps Open Food Facts v2 search to our normalized product shape (attaching OUR cached scores only, never OFF's), plus a new Search screen (field + numeric-barcode-pad toggle, default state = recent scans, never blank) reachable from a Home field under the hero and an "Enter barcode manually" action in the Scan error/OCR banners. A typed barcode takes the exact same scored path as a live scan.

**Architecture:** One new Deno edge function (`supabase/functions/search/`: `index.ts` wiring + `handler.ts` logic + `handler_test.ts`) mirroring the injected-`Deps` / pure-handler pattern of `product/`. Shared OFF logic refactored: extract a per-product field mapper from `mapOffPayload` in `_shared/off.ts` and add `fetchOffSearch(query)` + `mapOffSearchPayload(payload)`, all unit-testable without network. Client: new `SearchView.swift` (screen + result rows + a barcode→product loader), a new `SearchResult` model + `APIClient.search(query:)` that builds a real query URL (the existing `request(_:)` helper appends path components and would percent-encode `?`/`=`, so a query-aware path is required), and small edits to `HomeView.swift` (search field entry point under the hero) and `ScannerView.swift`'s `ScanScreen` banners ("Enter barcode manually"). **No schema or RLS changes** — search reads existing `products` + `score_results` server-side with the service role (same as `/product`); barcode passthrough reuses the existing `/product/:barcode` endpoint unchanged. **Backend/client split:** all OFF calls + score attachment stay server-side (keys + math never leave the backend, CLAUDE.md principle 5); the client only renders and routes.

**Tech Stack:** Deno + supabase-js (edge, service role) · TypeScript strict · SwiftUI iOS 17+, `@FocusState`, `@Observable`, URLSession + Codable · XcodeGen · Deno tests (`@std/assert`) + Swift Testing (`import Testing`).

## Dependencies & sequencing note
- **Chunk 0 (UI hygiene) — assumed landed.** Uses `Theme.Space.s45`, `@ScaledMetric` glyph pattern, and honest-error-copy conventions established there. If any token is missing, add it per the Chunk 0 plan rather than inlining a literal.
- **Chunk 1 (Result upgrade) — MAY be built after this chunk.** Chunk 1 wires a top-level `ResultSkeletonView` "once Search/deep-links can open Result pre-fetch" (SCREEN_SPECS §4). This chunk **needs** a loading state when a search/manual-barcode row is tapped and `/product/:barcode` is in flight.
  - **If Chunk 1 has landed:** the `ProductLoaderView` (Task 8) reuses `ResultSkeletonView` for its loading state.
  - **If executed before Chunk 1:** `ProductLoaderView` ships its own calm inline loading state (centered `ProgressView().tint(Theme.greenDeep)` + "Loading…" on `Theme.canvas`). Leave a `// TODO(chunk-1): swap for ResultSkeletonView` marker. Do **not** block on Chunk 1.
- **Chunk 3 (Swaps) depends on THIS chunk**, not the reverse: swaps reuse the OFF search/category normalization landed here. Keep `_shared/off.ts` search helpers general (don't hard-code Search-screen assumptions).
- **Chunk 4 (`product_current_scores` view) — later.** Search attaches OUR cached score by reading the latest `score_results` row per barcode (same "latest by `computed_at`" logic `product/index.ts` already uses). When Chunk 4's current-score view lands, switch the search score lookup to read it (leave a `// TODO(chunk-4)` marker). Until then, "latest score_results row, current `score_version` only" is correct and honest.

## Global Constraints
- Tokens only — no raw hex/pt literals in views (`Theme.Space`, `Theme.Radius`, `DisplayType`).
- Copy from `docs/COPY_DECK.md` §"Search & manual barcode (Chunk 2)" — never "Something went wrong", never OFF's own Nutri-Score presented as ours.
- **Never show a score we didn't compute.** Search rows show a grade dot ONLY when we have a current-`score_version` cached score for that barcode; otherwise a neutral "Not scored yet" affordance (AVOID #5: no false-reassurance color, no OFF grade masquerading as ours).
- ED-safe/calm; AA contrast; VoiceOver labels on rows; Dynamic Type (single-column reflow at accessibility sizes).
- `cd ios && xcodegen generate` immediately before every `xcodebuild` (project file is regenerated — STATE.md gotcha).
- Verify iOS with: `cd ios && xcodegen generate && xcodebuild -project FoodScanner.xcodeproj -scheme FoodScanner -destination 'platform=iOS Simulator,name=<sim>' build`
- Verify backend with: `cd supabase/functions && deno test` (143 `Deno.test` blocks green today — must stay green + add new ones).

---

## Backend contract (new edge function)

**Endpoint:** `GET /search?q=<term>` (Supabase Edge Function `search`; platform path `/functions/v1/search`).
**Auth:** same as `/product` — require `Authorization` header (anon or linked JWT); 401 if absent. CORS: `GET, OPTIONS`, mirror `product/handler.ts` `CORS_HEADERS`.
**Query params:** `q` (required, trimmed). Empty/whitespace `q` → `400 { error: "empty_query" }`. `q` longer than 100 chars → truncate to 100.
**Behavior:**
1. Query OFF v2 search: `https://world.openfoodfacts.org/api/v2/search?search_terms=<q>&fields=<OFF_FIELDS>,code&page_size=20&sort_by=unique_scans_n` with `OFF_USER_AGENT`. OFF failure → `502 { error: "upstream_error" }`.
2. Map each `products[]` item via the shared per-product field mapper → `{ barcode, name, brand, imageURL }`. Drop items with a blank barcode or the `"Unknown product"` name fallback (no name = useless row).
3. Batch-look up our `products` + latest current-version `score_results` for the returned barcodes (service role). Attach `score: { score, band }` ONLY for barcodes we have already scored at the current `SCORE_VERSION`; omit `score` otherwise.
4. Return `200 { results: SearchResult[] }` (may be empty array → drives the client "No matches" state).
**Response shape (`SearchResult`, decodes into Swift `SearchResult`):**
```json
{ "results": [
  { "barcode": "3017620422003", "name": "Nutella", "brand": "Ferrero",
    "imageURL": "https://…/front.jpg", "score": { "score": 29, "band": "low" } },
  { "barcode": "0000000000000", "name": "Store Oats", "brand": null, "imageURL": null }
] }
```
**Barcode passthrough:** handled **client-side** (Task 6). A `q` matching `^\d{6,14}$` never hits `/search`; the client routes straight to the existing `/product/:barcode`, so a typed barcode is byte-for-byte the same scored/cached path as a live scan. `/search` stays name-search-only.
**RLS:** none added. `/search` reads `products`/`score_results` with the service role exactly like `/product`; clients still cannot read/write those tables directly.
**Deploy:** `supabase functions deploy search` (verify_jwt default on). **Test live:** `curl -sS "$FUNCTIONS_URL/search?q=nutella" -H "Authorization: Bearer $ANON_KEY" -H "apikey: $ANON_KEY" | jq`.

---

### Task 1: Refactor `_shared/off.ts` — extract per-product mapper + add search (TDD first)
**Files:** add cases to `supabase/functions/_shared/off_test.ts`; then modify `supabase/functions/_shared/off.ts`.
- [ ] **Test first** — in `off_test.ts` add `Deno.test` blocks:
  - `mapOffFields` maps a raw OFF product object + explicit code → the normalized `OffProduct` (nova/nutriscore/additives/allergens/image), reusing the existing Nutella-shaped fixture.
  - `mapOffSearchPayload` maps `{ products: [p1, p2], count: 2 }` → two `OffProduct`s; drops an item whose `code` is missing/blank; returns `[]` for `{ products: [] }` and for a malformed body.
  - `fetchOffSearch("nutella", fakeFetch)` builds the v2 search URL with `search_terms`, `fields`, `page_size`, `sort_by=unique_scans_n`, sends `OFF_USER_AGENT`, and returns the mapped array; throws on non-OK HTTP (so the handler can surface 502).
- [ ] Extract `export function mapOffFields(p: Record<string, unknown>, code: string): OffProduct` from the body of `mapOffPayload` (`off.ts:59-110`) — the nova/nutriscore/additives/allergens/image/nutriments logic. Have `mapOffPayload` call it with `body.product` + `body.code` (behavior unchanged — existing `off_test.ts` cases must stay green).
- [ ] Add `export function mapOffSearchPayload(payload: unknown): OffProduct[]` — read `payload.products` (array), map each non-blank-`code` item through `mapOffFields(item, item.code)`, filter out blank barcodes.
- [ ] Add `export async function fetchOffSearch(query: string, fetchImpl = fetch): Promise<OffProduct[]>` — build the URL from a new `OFF_SEARCH_BASE_URL = "https://world.openfoodfacts.org/api/v2/search"`, `encodeURIComponent(query)`, `fields=${OFF_FIELDS},code`, `page_size=20`, `sort_by=unique_scans_n`; same `OFF_USER_AGENT`/Accept headers; throw on `!res.ok`; return `mapOffSearchPayload(await res.json())`.
- [ ] Run `cd supabase/functions && deno test _shared/off_test.ts` → green.

### Task 2: Search handler — pure logic + Deps (TDD first)
**Files:** new `supabase/functions/search/handler_test.ts`, then `supabase/functions/search/handler.ts`.
- [ ] **Test first** — `search/handler_test.ts` (mirror `product/handler_test.ts:1-70` fixture/fake-deps style; inject `Deps`):
  - Missing `Authorization` header → 401 `{ error: "unauthorized" }`.
  - `?q=` empty/whitespace → 400 `{ error: "empty_query" }`.
  - Happy path: fake `searchOff` returns 2 `OffProduct`s; fake `getScoresForBarcodes` returns a current-version score for barcode A only → response `results` has A with `score:{score,band}` and B with `score` omitted.
  - Score attached ONLY when `score_version === SCORE_VERSION`: a stale-version cached score for B → `score` omitted for B.
  - Row with blank name/barcode from OFF is dropped.
  - OFF throws → 502 `{ error: "upstream_error" }`.
  - `OPTIONS` → 204 with CORS headers.
- [ ] Write `search/handler.ts`:
  - Reuse `CORS_HEADERS` + `json()` shape from `product/handler.ts` (copy locally — the two handlers stay decoupled, same as today).
  - `interface Deps { searchOff(query: string): Promise<OffProduct[]>; getScoresForBarcodes(barcodes: string[]): Promise<Map<string,{score:number;band:string;score_version:string}>>; }`
  - `extractQuery(url)` → `new URL(url).searchParams.get("q")?.trim() ?? ""`.
  - `handleSearch(req, deps)`: method/OPTIONS guard (GET only, else 405), auth guard, empty-`q` guard (400), truncate `q` to 100, `try { const offs = await deps.searchOff(q) } catch → 502`, batch score lookup, build `SearchResult[]` attaching `score` only when `score_version === SCORE_VERSION` and `band !== "unknown"`, return `json({ results })`.
- [ ] `cd supabase/functions && deno test search/handler_test.ts` → green.

### Task 3: Search edge function wiring
**Files:** new `supabase/functions/search/index.ts` (mirror `product/index.ts:1-85`).
- [ ] Create supabase client from `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` (no secrets in code).
- [ ] `Deps.searchOff = (q) => fetchOffSearch(q)`.
- [ ] `Deps.getScoresForBarcodes(barcodes)`: `products` select `id,barcode` for `.in("barcode", barcodes)`, then `score_results` latest-per-`product_id` (`order("computed_at",{ascending:false})`), fold into a `Map<barcode,{score,band,score_version}>` keeping the newest row per product. Leave `// TODO(chunk-4): read product_current_scores view once it lands`.
- [ ] `Deno.serve((req) => handleSearch(req, deps))`.
- [ ] `deno test` (whole suite) → all green (143 existing + new).

### Task 4: iOS `SearchResult` model + `APIClient.search`
**Files:** modify `ios/FoodScanner/Models.swift` (after `Product`, `Models.swift:78`); modify `ios/FoodScanner/APIClient.swift`.
- [ ] Add to `Models.swift`:
```swift
struct SearchResult: Codable, Identifiable {
    var id: String { barcode }
    let barcode: String
    let name: String
    let brand: String?
    let imageURL: String?
    let score: SearchScore?          // nil ⇒ not scored by us yet (neutral dot)
    struct SearchScore: Codable { let score: Int; let band: ScoreBand }
}
```
- [ ] Add `APIClient.search(query:)`. The existing `request(_:)` (`APIClient.swift:69-112`) appends the path via `appendingPathComponent`, which percent-encodes `?`/`=` — so add a query-aware sibling rather than reusing it as-is. Build the URL with `URLComponents` on `AppConfig.functionsBaseURL` + path `search`, `queryItems = [URLQueryItem(name:"q", value: query)]`; set the same `apikey`/`Authorization` headers as `request(_:)`; decode `{ results: [SearchResult] }`; map errors to `APIError` (`.transport`, `.badResponse`). Return `[SearchResult]`.
```swift
private struct SearchEnvelope: Decodable { let results: [SearchResult] }
func search(query: String) async throws -> [SearchResult] { … }
```
- [ ] (No change to `product(barcode:)` — barcode passthrough reuses it verbatim.)

### Task 5: Search query classification + logic tests (TDD)
**Files:** new `ios/FoodScannerTests/SearchLogicTests.swift`; new small helper in `SearchView.swift` (Task 6).
- [ ] **Test first** (`import Testing`, mirror `ScoreBandTests.swift`): a `SearchQuery.classify(_:)` helper returns `.barcode("3017620422003")` for 6–14 digit input (trimming whitespace), `.name("nutella")` for text, and `.empty` for blank/whitespace. Boundary cases: 5 digits → `.name` (too short for a barcode), 14 digits → `.barcode`, 15 digits → `.name`.
- [ ] Implement `enum SearchQuery { case empty, barcode(String), name(String); static func classify(_ raw: String) -> SearchQuery }` using regex `^\d{6,14}$` (same bounds as backend `BARCODE_RE`). Keep it a free, testable, `@testable`-visible type in `SearchView.swift`.
- [ ] `xcodegen generate && xcodebuild test -only-testing:FoodScannerTests/SearchLogicTests` → green.

### Task 6: `SearchView` screen
**Files:** new `ios/FoodScanner/SearchView.swift`.
Build the screen per **SCREEN_SPECS §9** (`docs/SCREEN_SPECS.md:89-92`) and teardown STEAL #22 (default state = useful recent list, not blank) / #21 (calm empties).
- [ ] `@Observable final class SearchViewModel` with `enum State { case recents, searching, results([SearchResult]), noResults(String), error }`, a debounced (~300ms) `run(query:api:)` that classifies via `SearchQuery`:
  - `.empty` → `.recents`.
  - `.barcode(code)` → set a `pendingBarcode` route (Task 8 loads `/product/:code`), don't hit `/search`.
  - `.name(q)` → `.searching`, `try api.search(query:q)` → `.results` (or `.noResults(q)` when empty); on throw → `.error`.
- [ ] `struct SearchView: View` params: `var startInBarcodeMode: Bool = false`.
  - `@Environment(SessionService.self)`, `@Environment(PantryService.self)`, `@Environment(\.dynamicTypeSize)`; `@FocusState private var fieldFocused`; `@State private var query = ""`; `@State private var barcodeMode = startInBarcodeMode`.
  - **Search field:** field-styled row, magnifier icon (scaled per Chunk-0 `@ScaledMetric` pattern), placeholder = barcodeMode ? "Barcode number" : "Search any product…". `.keyboardType(barcodeMode ? .numberPad : .default)`, `.textInputAutocapitalization(.never)`, `.submitLabel(.search)`, autofocus on appear (`fieldFocused = true`).
  - **Barcode toggle:** a quiet control labeled "Enter a barcode" (⇄ "Search by name" when active) that flips `barcodeMode` and clears `query`; a11y label describing the toggle.
  - **Body switch on VM state:**
    - `.recents` → header "Recent scans", list of `pantryService.entries.map { $0.asProduct() }` as rows; when that list is empty show a calm empty line (see Copy — needs `/ux-writing` draft) + a "Scan instead" way-out, never a blank screen (SCREEN_SPECS §9 "never blank").
    - `.searching` → inline spinner + "Searching Open Food Facts…".
    - `.results(rows)` → `SearchResultRow` list.
    - `.noResults(q)` → "No matches for '\(q)'. Try the barcode, or snap the label." + `[Scan instead]` button (dismisses to scanner / triggers scan).
    - `.error` → "Search isn't available right now. Check your connection and try again." + `[Retry]`.
  - Keyboard-safe insets (SCREEN_SPECS §9 "keyboard-safe insets"); `.navigationTitle("Search")`, inline.
- [ ] **`SearchResultRow`** (thumb via `ProductThumbnail`, name/brand, grade dot): show `GradeDot` only when `result.score != nil`; when `nil`, render a neutral "Not scored yet" caption + chevron instead of a colored dot (Global Constraint / AVOID #5). VoiceOver: combined label "\(name). \(brand). \(score/band or 'Not scored yet'). Opens product details." Tap → route to `ProductLoaderView(barcode:)` (Task 8).

### Task 7: Entry point — Home search field under the hero
**Files:** modify `ios/FoodScanner/HomeView.swift`.
Per SCREEN_SPECS §Home item 1 (`SCREEN_SPECS.md:32`): "tappable field-styled row ('Search any product…', magnifier icon) → pushes Search screen."
- [ ] Insert a `NavigationLink { SearchView() } label: { SearchFieldRow() }` between `heroHeader` and `ScanCTACard` in the body `VStack` (`HomeView.swift:97-99`). It rides inside Home's existing `NavigationStack` (`HomeView.swift:94`), so it pushes.
- [ ] Add a private `SearchFieldRow` view: magnifier glyph (`@ScaledMetric` per Chunk 0) + placeholder Text "Search any product…" (`Theme.textSecondary`), `.surfaceCard()` styling, min 44pt height; `.accessibilityAddTraits(.isButton)`, label "Search any product". Not an editable field — a button that looks like one (matches Oasis STEAL #22 pattern; keeps Home's single-focus hierarchy).

### Task 8: `ProductLoaderView` — barcode/row → scored Result
**Files:** new `ProductLoaderView` (in `SearchView.swift`).
Both a tapped search row and a typed barcode need to fetch `/product/:barcode` and land on the scored Result, on the same path as a scan.
- [ ] `struct ProductLoaderView: View { let barcode: String }` — `@Environment(SessionService.self)`, `@Environment(PantryService.self)`, `@State phase`. `.task`: `try await APIClient(session:).product(barcode:)` → on success show `ProductView(product:)`; on `.needsOCR`/`.notFound` show a calm "We don't have this one yet." state with a "Snap the label" way-out (route to scanner) — never a dead end (principle #4); on other error → calm retry.
- [ ] Loading state: **if Chunk 1 landed** use `ResultSkeletonView`; **else** centered `ProgressView().tint(Theme.greenDeep)` on `Theme.canvas` with `// TODO(chunk-1): swap for ResultSkeletonView`.
- [ ] Auto-save to pantry on success (fire-and-forget `pantryService.save(product:)`), matching `ScanViewModel.lookUpProduct` (`ScannerView.swift:630-636`) so search-found products behave exactly like scanned ones.
- [ ] Wire `SearchView`'s `pendingBarcode` route and `SearchResultRow` tap through a `.navigationDestination(item:)` presenting `ProductLoaderView`.

### Task 9: Entry point — "Enter barcode manually" in Scan banners
**Files:** modify `ios/FoodScanner/ScannerView.swift` (`ScanScreen`).
Per SCREEN_SPECS §Home item 2 (`SCREEN_SPECS.md:45`) + MASTER_PLAN Chunk 2: add the action inside `labelNotFound`/`needsOCR`/error banners so the last dead-end (broken/absent label) always has a way to type the barcode.
- [ ] Add `@State private var showManualEntry = false` to `ScanScreen` (near `ScannerView.swift:840-847`).
- [ ] Present Search as a sheet: `.sheet(isPresented: $showManualEntry) { NavigationStack { SearchView(startInBarcodeMode: true).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showManualEntry = false } } } } }` on `content` (`ScanScreen.body`, `ScannerView.swift:850`). Sheet (not push) keeps the immersive dark scan chrome intact underneath.
- [ ] Add an "Enter barcode manually" tertiary action to the OCR banners. In `ocrBanner` (`ScannerView.swift:1023-1051`) add an optional third action row (below the primary/secondary pill group) rendered as a quiet lime text button; pass `{ showManualEntry = true }` from both the `.needsOCR` (`:929-937`) and `.labelNotFound` (`:939-947`) call sites. In the `.error` `calmBanner` (`:948-954` / `:1002-1016`) add the same quiet action beneath Retry. Keep the accessibility-size vertical-stack behavior (banner already stacks at `dynamicTypeSize.isAccessibilitySize`).
- [ ] Verify no dead-end: every banner now offers forward (Snap/Retry) + out (Try another scan) + manual (Enter barcode manually).

### Task 10: Verify — build, tests, screenshot matrix, gates
- [ ] `cd supabase/functions && deno test` → all green (143 existing + Task 1/2 additions; report new count).
- [ ] `cd ios && xcodegen generate && xcodebuild -project FoodScanner.xcodeproj -scheme FoodScanner -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` → no new errors/warnings.
- [ ] `xcodebuild test -only-testing:FoodScannerTests` → green (SearchLogicTests + existing).
- [ ] Deploy `search` to Supabase; `curl` the live endpoint for a name (`nutella` → ≥1 result, scored ones carry `score`) and confirm a typed barcode in-app opens the identical scored Result a scan would.
- [ ] **6-shot screenshot matrix** — Search screen in each state (recents, searching, results, no-results, error) + Home-with-search-field + Scan banner with "Enter barcode manually": SE-proxy (**iPhone 17e** — no SE 3rd-gen sim installed, per Chunk 0 substitution) / iPhone 17 Pro / iPhone 17 Pro Max × default + AX5 (`accessibility-extra-extra-extra-large`) Dynamic Type. No clipping; rows reflow single-column at AX; grade dots scale with the row; keyboard never covers the active field.
- [ ] **Grep gate:** no raw size/padding literals introduced in `SearchView.swift` / edited views (`grep -n "font(.system(size\|padding(.*[0-9]" ios/FoodScanner/SearchView.swift` returns only `@ScaledMetric` vars).
- [ ] **Principle gates:** transparency (rows never show OFF's grade as ours; no client math); ED-safe/calm copy; never-a-dead-end (empty recents + no-results + loader-not-found all offer an action); AA contrast; VoiceOver reads rows sensibly.
- [ ] **Teardown AVOID gate:** #5 (no false-reassurance color on unscored rows, no green "unknown"), #14 (recents/empties are calm, not 70%-blank). Run `ui-ux-pro-max` Pre-Delivery Checklist (App UI: icons, interaction, light/dark contrast, layout, a11y) + `/ios-design-review` on the sim shots before device install.
- [ ] Device install + founder review; then MEMORY.md decision entry + STATE.md status-line update.

---

## Copy (from `docs/COPY_DECK.md` §"Search & manual barcode (Chunk 2)", lines 113–122 — implement verbatim)
- Home field placeholder: **"Search any product…"**
- Search screen title: **"Search"**
- Barcode toggle: **"Enter a barcode"**
- Barcode field label: **"Barcode number"**
- Default-state header: **"Recent scans"**
- Searching: **"Searching Open Food Facts…"**
- No results: **"No matches for '{query}'. Try the barcode, or snap the label."** — button **[Scan instead]**
- Search error: **"Search isn't available right now. Check your connection and try again."** — button **[Retry]**
- Scan-banner manual entry: **"Enter barcode manually"**

**MISSING strings to draft via `/ux-writing` and add to COPY_DECK before shipping:**
1. Empty **Recent scans** state (new user, no scans, must not be blank — SCREEN_SPECS §9 / teardown STEAL #21). Proposed draft (needs skill 4-phase pass + deck entry): *"No recent scans yet. Search a product name, or enter a barcode."* + reuse **[Scan instead]**.
2. `ProductLoaderView` not-found state when a searched/typed barcode isn't in OFF (reuse the scan-side line — *"We don't have this one yet. Snap the ingredients label and we'll score it."* — confirm it fits this non-camera context, or draft a Search-specific variant).
3. Search-row "not scored yet" caption (unscored rows). Proposed: *"Not scored yet"* — confirm via `/ux-writing` and add to deck.

## Verification / Exit criteria (mirrors MASTER_PLAN Chunk 2 Exit + standing gate)
- Search a **name** → result opens with the full score (via `/search` then `/product/:barcode` on tap).
- Barcode **typed** → same scored/cached path as a live scan (routes to `/product/:barcode`).
- Empty/error states per SCREEN_SPECS §9 (recents-never-blank, searching, no-results, error) all correct and calm.
- Scored rows show our grade dot; unscored rows show a neutral affordance (never OFF's grade, never false-green).
- Deno tests green (143 + new); iOS tests green (SearchLogicTests + existing); live `search` endpoint deployed and curl-verified.
- **6-shot screenshot matrix** pass (iPhone 17e / 17 Pro / 17 Pro Max × default / XXL) + device install.
- Principles gate + teardown AVOID gate + `ui-ux-pro-max` Pre-Delivery Checklist + `/ios-design-review` all pass.
- MEMORY.md entry + STATE.md status line updated.
