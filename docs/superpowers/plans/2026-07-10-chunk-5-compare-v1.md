# Chunk 5 — Compare v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline). Steps use checkbox syntax `- [ ]`. Run `xcodegen generate` immediately before every `xcodebuild` (the `.xcodeproj` is generated and vanishes — STATE.md gotcha).

**Goal:** Ship SCREEN_SPECS §10 Compare v1 — two already-scored products side by side, aligned tri-metric rows, aligned **shared-scale** bar-meters, a subtle per-row winner tint (band colors, never red), and a "Pick this one" CTA that saves to pantry. Entry from the Result overflow menu (build now) and Search multi-select (wire only if Chunk 2's `SearchView` has landed). Compact/accessibility width = stacked cards behind a sticky A/B segmented toggle.

**Architecture:** Pure-client SwiftUI. Compare consumes two `Product` values that are *already fetched and scored* — it never fetches, never scores, never computes a nutrition number (principle #5: LLM/client never does the math; all `subScore`/`score` values come from the backend `ScoreResult`). Winner determination is a pure comparison of backend-computed integers — display logic, not scoring. **No backend, no edge function, no schema, no RLS change.** New file `CompareView.swift`. One new *reusable* primitive `SharedScaleMeter` added to `ResultComponents.swift` (the "meter component" Chunk 1 will also consume — see Dependencies). Edits to `ProductView.swift` (overflow menu + partner-picker sheet + navigation), `PreviewSupport.swift` (a second sample product + a compare-logic model), and one new pure-logic type `ComparePair` in `Models.swift`. Verification = `xcodebuild` on sim + new Swift Testing suite + the 6-shot screenshot matrix.

**Tech Stack:** SwiftUI iOS 17+, `@Observable`, `@ScaledMetric`, Swift Testing (`@Suite`/`@Test`), XcodeGen. No new dependencies.

---

## Dependencies & sequencing note (READ FIRST — chunks may build out of order)

Per MASTER_PLAN_PRE_D "Sequencing & rationale": **`0 → 1 → 2 → 3 → 4 → 5`**. Chunk 5 nominally depends on:

1. **Chunk 1 (meter component)** — *"5 after meters exist (1) — compare reuses the meter component."* **Current repo state (verified 2026-07-10): Chunk 1 has NOT landed.** `docs/superpowers/plans/` contains only chunk 0; grep for `Watch-out|Benefits|Meter` in `ios/FoodScanner/*.swift` returns nothing. The only bar-like primitives today are raw `ProgressView(value:)` inside `TriMetricRow`/`TriMetricTile` (`ResultComponents.swift:222-306`) and `ScoreFactorRow` (`:314-372`).
   - **Therefore:** this plan **creates the canonical reusable primitive `SharedScaleMeter` in `ResultComponents.swift` now** (Task 2), with the API Chunk 1's Watch-outs/Benefits sections will consume. When Chunk 1 is executed, it MUST reuse `SharedScaleMeter` rather than defining a second meter. If Chunk 1 *has already landed* when you execute this chunk, **do not redefine it** — read Chunk 1's plan, confirm the primitive it built (expected name `SharedScaleMeter`; if it named it differently, use that), and delete Task 2 here.
   - **v1 data reality:** `Models.swift` (`ScoreFactor`, `:32-39`) has no per-nutrient values yet — only the three normalized factor `subScore`s (Nutrition / Additives / Processing, each 0–100, *higher = better*). Chunk 1 introduces nutrient-level meters (raw values + tier words). **Compare v1 therefore renders shared-scale meters over the three factor sub-scores** (already a clean 0–100 shared scale) plus the overall score — the honest v1 the spec calls "static compare." When Chunk 1's nutrient meters exist, a future Compare v1.1 can add per-nutrient rows; the winner direction for those MUST come from the tier/band (lower saturated fat wins), NOT raw magnitude — noted inline in Task 3.

2. **Chunk 2 (`SearchView`)** — provides the "Search multi-select" entry point. **`SearchView.swift` does not exist yet** (grep confirms). **Therefore:** build the **Result-overflow entry point now** (Task 4a) — it is self-sufficient for the exit criteria. Task 4b (Search multi-select) is **gated**: implement it only if `ios/FoodScanner/SearchView.swift` exists at execution time; otherwise leave the `TODO(chunk-2)` marker described in Task 4b and record in MEMORY.md that the Search entry point ships with Chunk 2.

Nothing else blocks. Chunk 0 (spacing tokens, scaled glyphs) is landed and its tokens (`Theme.Space.s45`, etc.) are available.

---

## Global constraints (every task)

- **Tokens only** — colors from `Theme` (`ios/FoodScanner/Theme.swift`), spacing from `Theme.Space`, cards via `.surfaceCard()`. No raw hex or pt literals in the new view.
- **Copy from `docs/COPY_DECK.md` §New surfaces → Compare (lines 134–139) verbatim.** No invented strings. Any genuinely new string goes through `/ux-writing` and into the deck first.
- **Principles gate:** transparency (every metric already sourced on the Result screen; Compare links back, never re-derives), ED-safe (neutral words, no "worse/loser", no red), honest states (thin/unknown product handled), never-a-dead-end (CTA saves + a way back), LLM-never-does-math, WCAG 2.1 AA.
- **Teardown gates:** STEAL #5 (Negatives/Positives dual bar-meter, *shared scale*) and #8 (per-metric row) are the pattern being reused. **AVOID list is blocking:** #1 no alarm-red fills / no "loser" shaming — winner tint is a *subtle band-color wash on the winning side only*, never a penalty color on the other; #4 no badge soup (one ring per product, sub-metrics demoted to meters); #5 no color-semantics violations (never green under a low band — the winner tint uses the winning side's own *band* color, so a "higher of two low scores" row tints clay, not green); #6 round every displayed number (no raw floats); #14 no 70%-empty screen (two dense columns).
- **ui-ux-pro-max:** before building, query the rule DB — `python3 ~/.claude/skills/ui-ux-pro-max/scripts/search.py "side by side comparison table mobile" --stack swiftui` and `--domain ux`. Run its App-UI Pre-Delivery Checklist (icons/interaction/light contrast/layout/a11y) as a merge gate. **Never adopt its palette/fonts** — brand is locked to DESIGN_SYSTEM_V3.
- Build/verify: `cd ios && xcodegen generate && xcodebuild -project FoodScanner.xcodeproj -scheme FoodScanner -destination 'platform=iOS Simulator,name=<sim>' build`

---

### Task 1 (TDD FIRST): Pure compare-logic type + tests

Model the comparison as a pure, testable value type so the winner rules are covered before any pixels exist. No SwiftUI in this task.

**New file:** `ios/FoodScanner/Models.swift` — append after `Product` (currently ends `ios/FoodScanner/Models.swift:78`).

- [ ] Add a pure comparison model:
```swift
/// A side-by-side comparison of two already-scored products. Pure value type:
/// it reads backend-computed integers (`ScoreResult.score`, `ScoreFactor.subScore`)
/// and decides which side reads higher per metric. It NEVER computes a nutrition
/// number or a score (principle #5). "Higher is better" holds for every metric in
/// v1 because our factor sub-scores are normalized so up = better; a nil/unknown
/// side never "wins".
struct ComparePair {
    let a: Product
    let b: Product

    enum Side { case a, b, tie }

    /// One aligned metric row: a shared-scale label + each side's 0–100 value
    /// (nil when that side is unscored) + the winning side.
    struct MetricRow: Identifiable {
        let id: String          // metric name, stable
        let label: String       // "Overall", "Nutrition", "Additives", "Processing"
        let valueA: Int?
        let valueB: Int?
        let winner: Side
    }

    /// Fixed display order so rows always align across both products.
    private static let factorOrder = ["Nutrition", "Additives", "Processing"]

    static func winner(_ x: Int?, _ y: Int?) -> Side {
        guard let x, let y else { return .tie }   // any unknown side => no winner
        if x == y { return .tie }
        return x > y ? .a : .b
    }

    /// Overall row first, then the three factors in fixed order.
    var rows: [MetricRow] { /* build Overall from a.score?.score / b.score?.score,
        then each factor via subScore lookup by name; winner via winner(_:_:) */ }

    /// Overall winner drives which "Pick this one" CTA carries the subtle emphasis.
    var overallWinner: Side { Self.winner(a.score?.score, b.score?.score) }
}
```
(Implement `rows` to emit exactly 4 rows: Overall + Nutrition + Additives + Processing, looking up each factor by case-insensitive name like `TriMetricRow.factor(named:)` at `ResultComponents.swift:230`; a missing factor on a side → that side's value is `nil`.)

**New test file:** `ios/FoodScannerTests/CompareLogicTests.swift` (Swift Testing, mirror the style of `ios/FoodScannerTests/ScoreBandTests.swift`). Needs a second fixture — add it in Task-1's PreviewSupport step below, or inline minimal `Product`s in the test.

- [ ] Write these `@Test` cases and confirm they FAIL before implementing `rows`/`winner`:
  - `winner(90, 40) == .a`; `winner(40, 90) == .b`; `winner(50, 50) == .tie`.
  - `winner(nil, 40) == .tie` and `winner(40, nil) == .tie` (unknown never wins — honest-state rule).
  - `rows.count == 4` and `rows.map(\.label) == ["Overall","Nutrition","Additives","Processing"]` (fixed alignment regardless of backend factor order — feed factors in scrambled order).
  - A product missing the "Additives" factor → that row's `valueA`/`valueB` is `nil` and `winner == .tie`.
  - `overallWinner` on `.sampleScored` (score 51) vs a higher fixture (see below) returns the higher side.
- [ ] Add the second fixture to `ios/FoodScanner/PreviewSupport.swift` (after `sampleScored`, file currently ends `:82`): `static let sampleScoredHigh` — same shape, `id: "sample-2"`, a different name/brand, `score: ScoreResult(score: 78, band: .high, …)` with the three factors all higher than `sampleScored`'s, so it is an unambiguous overall winner and gives every screenshot a real two-column contrast. Keep it DEBUG-only (inside the existing `#if DEBUG`).

**Exit for Task 1:** `xcodebuild test -only-testing:FoodScannerTests` green; all winner/row cases pass.

---

### Task 2: `SharedScaleMeter` reusable primitive (the Chunk-1 meter)

> **Skip this task entirely if Chunk 1 already shipped a meter primitive** — reuse theirs (see Dependencies). Otherwise build the canonical one here.

**File:** append to `ios/FoodScanner/ResultComponents.swift` (currently ends `:1525`), near the existing bar components so Chunk 1 finds it.

- [ ] Add a single horizontal 0–100 bar-meter — the shared-scale primitive both Compare rows and Chunk-1 Watch-outs/Benefits rows consume:
```swift
/// A single labeled bar on a fixed 0–100 shared scale — the reusable meter
/// primitive (teardown STEAL #5/#8). Band-tinted, never alarm-red; the value
/// is backend-computed (never derived here). Reused by Compare (Chunk 5) and by
/// the Result Watch-outs/Benefits sections (Chunk 1). `emphasized` draws the
/// subtle winner wash for Compare — off by default.
struct SharedScaleMeter: View {
    let value: Int?          // 0–100, nil = unscored (dashed/empty track)
    let band: ScoreBand
    var trailingText: String? = nil   // e.g. "51/100" or a Chunk-1 tier word
    var emphasized: Bool = false

    @ScaledMetric(relativeTo: .footnote) private var barHeight: CGFloat = 8
    // body: rounded track (Theme.border) + fill trimmed to value/100 in the
    // band tint (scoreHigh/scoreMid/scoreLow/scoreUnknown, Theme.swift:24-27);
    // nil value => dashed track like ScoreBadge's unknown ring (ScoreBadge.swift:60-64);
    // emphasized => a low-opacity band-tint wash behind the row (never red,
    // never green-under-low — uses THIS value's own band color).
    // .accessibilityHidden(true) — the enclosing Compare row owns the a11y label.
}
```
- [ ] Reuse the existing band→color mapping (copy the switch from `TriMetricTile` `ResultComponents.swift:250-257`) or factor it into a small `ScoreBand.tint` computed property in `Models.swift` and adopt it in both places (preferred — removes the 3rd copy of that switch; `ScoreFactorRow:319-326` and `TriMetricTile:250-257` are the existing two). If you extract `ScoreBand.tint`, add a `@Test` asserting each band maps to its `Theme` color and update those two call sites.

**Exit for Task 2:** compiles; a `#Preview` renders four meters (high/mid/low/nil) + one `emphasized`. No new `font(.system(size:` literals (Chunk-0 grep gate stays clean).

---

### Task 3: `CompareView.swift` — the screen

**New file:** `ios/FoodScanner/CompareView.swift`. Pushed onto the existing `NavigationStack` (ProductView already lives in one — `FoodScannerApp.swift:31`, `HomeView.swift:94`, `ScannerView.swift:854`).

Layout per SCREEN_SPECS §10 (lines 94–98):

- [ ] **Signature:** `struct CompareView: View { let pair: ComparePair }` (or `init(a:b:)` building the pair). Pull `pantryService` via `@Environment(PantryService.self)`, `@Environment(\.dynamicTypeSize)`, `@Environment(\.dismiss)`.
- [ ] **`.navigationTitle("Compare")`** (COPY_DECK §Compare line 136) `.navigationBarTitleDisplayMode(.inline)`; `.background(Theme.canvas)`.
- [ ] **Two-column header:** for each side, `FloatingProductImage(urlString:)` (`ResultComponents.swift:501`) + name/brand (reuse the `titleBlock` pattern, `ProductView.swift:205-219`) + `ScoreBadge(score:band:)` (`ScoreBadge.swift:13`). Two equal columns via `HStack` with `.frame(maxWidth: .infinity)` each.
- [ ] **Aligned metric rows:** `ForEach(pair.rows)` — each row is a full-width block with the metric `label` centered/leading and, beneath it, the two products' `SharedScaleMeter`s stacked (A then B) on the **same 0–100 scale** so bar lengths are directly comparable (this IS the "shared scale!" requirement). Round any displayed number; show `"{value}/100"` as `trailingText`, `"—"` when nil.
- [ ] **Winner tint (subtle, per row):** pass `emphasized: true` to the winning side's meter only (`row.winner == .a`/`.b`). Tie → neither emphasized. The wash uses the winning value's own band color (so two low scores → clay wash, honoring AVOID #5; never red per AVOID #1). Keep opacity low (~0.10–0.14) — "subtle" per spec.
  - **Chunk-1 forward note (do not implement now):** when per-nutrient Watch-outs rows are added, "winner" for a watch-out (e.g. saturated fat) is the *lower* raw value → derive winner from the tier/band, not `>`. v1 has no such rows.
- [ ] **CTA per column:** `"Pick this one"` (COPY_DECK line 138) → `pantryService.save(product:)` (`PantryService.swift:201`) → toast/inline `"Saved to pantry."` (COPY_DECK line 138) → then `dismiss()` (never-a-dead-end: user lands back on Result/list). Primary green button (`Theme.greenDeep`, `Theme.swift:8`) for the overall winner's column; the other column's CTA is the secondary outline style (reuse the `askAboutProductButton` outline pattern, `ProductView.swift:255-270`) — quiet, never a "loser" penalty. On a tie, both are secondary.
- [ ] **Compact / accessibility reflow (spec §10 "Responsive"):** when `dynamicTypeSize.isAccessibilitySize` (match the existing reflow guard at `ProductView.swift:189`), **stack** the two products vertically behind a **sticky segmented `Picker`** (`.pickerStyle(.segmented)`) whose two options are the product names truncated to 18 chars + ellipsis (COPY_DECK line 139: *"Compact toggle labels: product names (truncate at 18 chars + ellipsis)"*). Selecting A/B swaps which single-column card is shown; meters still render on the shared 0–100 scale so switching preserves comparability. Side-by-side otherwise. (v1 uses the accessibility-size guard as the "compact" proxy — there is no split-view width class on iPhone; note this in MEMORY.md.)
- [ ] **VoiceOver (exit criterion "reads aligned rows sensibly"):** make each metric row a single `.accessibilityElement(children: .combine)` reading `"{label}. {A name} {valueA} of 100. {B name} {valueB} of 100."` and, when there's a winner, append the COPY_DECK a11y string **"{Product} scores higher on {metric}"** (line 137). Header rings already self-label (`ScoreBadge:82-84`).
- [ ] **Thin/unknown handling (honest state):** if a side has no `score` or empty `factors` (mirror `ProductView.hasThinScore`, `ProductView.swift:55-57`), its meters show the nil/dashed state and every row involving it is a `tie`; the CTA still works (saves the product). Never fabricate a sub-score.
- [ ] `#Preview` blocks: side-by-side default (`sampleScored` vs `sampleScoredHigh`) and one at `.dynamicTypeSize(.accessibility3)` to exercise the segmented-stack path (mirror `ScoreBadge.swift:98-103`).

---

### Task 4: Entry points

#### 4a — Result overflow "Compare" (build now)

The ProductView toolbar today holds only the favorite heart (`ProductView.swift:147-151`, `favoriteButton` at `:237-248`). Add an overflow menu and a partner picker.

- [ ] **Overflow menu:** add a second `ToolbarItem(placement: .topBarTrailing)` — a `Menu { Button("Compare", systemImage: "square.split.2x1") { showComparePicker = true } } label: { Image(systemName: "ellipsis.circle").font(.body.weight(.semibold)).foregroundStyle(Theme.greenDeep).frame(width: 44, height: 44) }` with `.accessibilityLabel("More")`. Entry action label **"Compare"** (COPY_DECK line 135). Keep the heart as its own item so both stay 44pt targets.
- [ ] **State:** add `@State private var showComparePicker = false` and `@State private var comparePartner: Product?` near the other `@State` flags (`ProductView.swift:38-41`).
- [ ] **Partner picker sheet:** `.sheet(isPresented: $showComparePicker)` presenting a small `NavigationStack` list of recent scans from `pantryService.entries` (`PantryService.swift:23`; each `entry.product`), excluding the current `workingProduct.id`. Row = thumbnail + name/brand + grade dot (reuse existing row visuals). Tapping a row sets `comparePartner = entry.product` and dismisses the sheet. Empty state (no other scans yet): calm one-liner + Scan CTA — reuse the existing empty-state pattern, no new copy invented (if a Compare-specific empty string is needed, draft via `/ux-writing` and add to COPY_DECK first; otherwise reuse Pantry empty line 45).
- [ ] **Navigate to Compare:** add `.navigationDestination(item: $comparePartner) { partner in CompareView(pair: ComparePair(a: workingProduct, b: partner)) }` on the ProductView `ScrollView`/body. (`ProductView` is always inside a `NavigationStack`, so `navigationDestination` resolves — verified callers above.)

#### 4b — Search multi-select (GATED on Chunk 2)

- [ ] **If `ios/FoodScanner/SearchView.swift` exists:** add a multi-select mode — a "Compare" affordance that lets the user tick exactly two result rows, then pushes `CompareView(pair:)`. Follow SearchView's existing selection/nav conventions.
- [ ] **If it does not exist:** add a single-line `// TODO(chunk-2): Search multi-select → CompareView (SCREEN_SPECS §10 entry)` at the top of `CompareView.swift` and record in MEMORY.md that Compare's Search entry ships with Chunk 2. Do NOT stub a fake SearchView.

---

### Task 5: Copy audit

- [ ] Confirm every user-facing string is verbatim from `docs/COPY_DECK.md` §Compare (lines 134–139): entry action **"Compare"**, title **"Compare"**, a11y winner **"{Product} scores higher on {metric}"**, CTA **"Pick this one"** → **"Saved to pantry."**, compact toggle = names truncated at 18 chars + ellipsis. Metric labels **"Overall / Nutrition / Additives / Processing"** are structural (match `TriMetricRow.displayOrder`, `ResultComponents.swift:228`), not marketing copy.
- [ ] Banned-word grep on the new file: `grep -niE "worse|loser|bad|toxic|winner\b" ios/FoodScanner/CompareView.swift` returns only internal identifiers (`overallWinner`, `winner` enum), zero user-facing strings. No comparative shaming.
- [ ] Any string NOT already in the deck must go through `/ux-writing` (4-phase: purposeful → concise → conversational → clear) and be added to COPY_DECK §Compare before use.

---

### Task 6: Verify / Exit criteria

**Chunk exit line (MASTER_PLAN_PRE_D:53):** *"two demo products compare correctly on SE and Pro Max; VoiceOver reads aligned rows sensibly; matrix pass."* Plus the standard gate:

- [ ] `cd ios && xcodegen generate && xcodebuild … build` on iPhone 17 Pro sim — zero new errors/warnings.
- [ ] `xcodebuild test -only-testing:FoodScannerTests` — green, including the new `CompareLogicTests` suite (and the `ScoreBand.tint` test if Task 2 extracted it).
- [ ] **Deno backend tests:** unchanged by this chunk (no backend). Run the suite once to confirm still-green (the standing "121+ deno tests" gate) — Compare adds none.
- [ ] **6-shot screenshot matrix:** Compare screen with `sampleScored` vs `sampleScoredHigh` on **SE-proxy (iPhone 17e, per Chunk-0 substitution note) / iPhone 17 Pro / iPhone 17 Pro Max × default + XXL (AX5, `accessibility-extra-extra-extra-large`)**. Verify: two columns fit at Pro Max default; at XXL the sticky **A/B segmented stack** engages (no clipped rings, no clipped bars, names truncate at 18 chars); winner tint is visibly subtle and never red; meters share one scale (equal-value rows → equal bar lengths). Artifacts to `ios/Generated/screenshots/` (gitignored).
- [ ] **Device install** on the physical iPhone; tap Result → overflow **"Compare"** → pick a recent scan → confirm side-by-side, **"Pick this one"** saves (appears in pantry) and returns without a dead-end.
- [ ] **VoiceOver walk** on device: swipe through the metric rows — each reads "{label}. {A} {n} of 100. {B} {n} of 100. {winner} scores higher on {metric}" in order; rings self-describe; CTAs are reachable.
- [ ] **Gate checklists (blocking):** principles (transparency / ED-safe / honest state / never-a-dead-end / LLM-never-does-math / AA); teardown **AVOID** #1/#4/#5/#6/#14 re-checked against the built screen; **ui-ux-pro-max App-UI Pre-Delivery Checklist**; `/ios-design-review` on the sim shots before device; `/accessibility-audit` spot-check.
- [ ] **Grep gate (Chunk-0 standard):** `grep -rn "font(.system(size" ios/FoodScanner/CompareView.swift` → only `@ScaledMetric` variables, no literals.
- [ ] Commit + `MEMORY.md` decision entry (Compare v1 approach: shared-scale over factor sub-scores in v1; `SharedScaleMeter` is the shared Chunk-1 primitive; Search entry gated on Chunk 2) + `STATE.md` status-line update.

---

## File-touch summary

| File | Change |
|---|---|
| `ios/FoodScanner/CompareView.swift` | **NEW** — the screen (Task 3) |
| `ios/FoodScanner/Models.swift` | append `ComparePair` (+ optional `ScoreBand.tint`) (Task 1/2) |
| `ios/FoodScanner/ResultComponents.swift` | append `SharedScaleMeter` primitive (Task 2) |
| `ios/FoodScanner/ProductView.swift` | overflow menu + partner-picker sheet + `navigationDestination` (Task 4a) |
| `ios/FoodScanner/PreviewSupport.swift` | add `sampleScoredHigh` fixture (Task 1) |
| `ios/FoodScanner/SearchView.swift` | multi-select entry — **only if it exists** (Task 4b) |
| `ios/FoodScannerTests/CompareLogicTests.swift` | **NEW** — Swift Testing suite (Task 1) |

No backend / SQL / edge-function / RLS / schema changes in this chunk.
