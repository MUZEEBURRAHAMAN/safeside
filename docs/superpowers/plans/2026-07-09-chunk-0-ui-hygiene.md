# Chunk 0 — Cross-cutting UI Hygiene Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline). Steps use checkbox syntax.

**Goal:** Fix the cross-cutting UI debts every later chunk inherits: Dynamic-Type-scaled glyphs, spacing tokens, honest error copy, Me load-error retry, onboarding polish, pantry remove/sort.

**Architecture:** Pure SwiftUI edits inside existing files + one new PantryService method (Supabase delete). No new files, no schema changes. Verification = xcodebuild on sim + existing unit tests + screenshot matrix (SE 3rd gen / iPhone 17 Pro / Pro Max × default / XXL Dynamic Type).

**Tech Stack:** SwiftUI iOS 17+, `@ScaledMetric`, supabase-swift, XcodeGen.

## Global Constraints
- Tokens only — no raw hex/pt literals in views (`Theme.Space`, `Theme.Radius`).
- Copy from `docs/COPY_DECK.md` — never "Something went wrong".
- ED-safe/calm rules; AA contrast unchanged (no color changes in this chunk).
- `xcodegen generate` immediately before every `xcodebuild` (project file vanishes — STATE.md gotcha).
- Verify with: `cd ios && xcodegen generate && xcodebuild -project FoodScanner.xcodeproj -scheme FoodScanner -destination 'platform=iOS Simulator,name=<sim>' build`

---

### Task 1: Spacing token + padding literals
**Files:** Modify `ios/FoodScanner/Theme.swift:33-34`, `HomeView.swift:87`, `MeView.swift:29`, `PlanView.swift:41`
- [ ] Add `s45: CGFloat = 20` to `Theme.Space` (screen-margin token per DESIGN.md §3.2):
```swift
enum Space { static let s1: CGFloat = 4, s2: CGFloat = 8, s3: CGFloat = 12,
             s4: CGFloat = 16, s45: CGFloat = 20, s5: CGFloat = 24,
             s6: CGFloat = 32, s7: CGFloat = 48 }
```
- [ ] `HomeView.swift:87` + `MeView.swift:29`: `.padding(.horizontal, 20)` → `.padding(.horizontal, Theme.Space.s45)`
- [ ] `PlanView.swift:41`: `.padding(.horizontal, 32)` → `.padding(.horizontal, Theme.Space.s6)`

### Task 2: Honest error copy in services
**Files:** Modify `PantryService.swift:111,188`, `ProfileService.swift:35,60,97`
- [ ] `PantryService.swift:111`: `"Something went wrong. Try again."` → `"Couldn't load your pantry. Check your connection and try again."`
- [ ] `PantryService.swift:188`: → `"Couldn't load trending products right now."`
- [ ] `ProfileService.swift` (all three): → `"Couldn't load your profile. Check your connection and try again."` (35, 60) / keep save-path message calm-specific (97 — check context first; if save: `"Couldn't save that change. It'll retry next time you edit."` — verify wording fits call site)

### Task 3: Dynamic-Type-scaled glyphs (10 sites)
Pattern: pair `@ScaledMetric(relativeTo:)` for glyph AND its container circle so they grow together; keep 44pt tap-target floors with `max(44, …)`.
**Files:** Modify `HomeView.swift` (ScanCTACard, DailyInsightTile, GradeDot, FavoriteHeartInline), `OnboardingView.swift` (OptionCard), `MeView.swift` (guest avatar), `PlanView.swift` (hero icon), `ProductView.swift:243` (nav heart → semantic font)
- [ ] ScanCTACard: add `@ScaledMetric(relativeTo: .title3) private var iconCircle: CGFloat = 56` + `@ScaledMetric(relativeTo: .title3) private var iconGlyph: CGFloat = 26`; use in frame + `.font(.system(size: iconGlyph, weight: .semibold))`
- [ ] DailyInsightTile: same pattern, `.subheadline`, circle 40 / glyph 15
- [ ] GradeDot: `@ScaledMetric(relativeTo: .caption) private var scale: CGFloat = 1`; frame `diameter * scale`, font `.system(size: 13 * scale, weight: .bold, design: .rounded)`
- [ ] FavoriteHeartInline: `.subheadline`, visual circle 32 / glyph 15 scaled; outer target `max(44, circle)`
- [ ] OptionCard: `.body`, icon circle 40 / glyph 17; check disc 24 / check glyph 12 (relativeTo `.caption`)
- [ ] MeView avatar: `.subheadline`, circle 40 / glyph 16
- [ ] PlanView icon: `.largeTitle`, circle 88 / glyph 34
- [ ] ProductView:243: `.font(.system(size: 18, weight: .semibold))` → `.font(.body.weight(.semibold))` (nav-bar glyph, semantic)
- [ ] EXCLUDED (intentional): `ResultComponents.swift:535` shippingbox placeholder — decorative inside a *fixed-size* image container; scaling the glyph without the container would clip. `ScanOverlay` reticle/torch glyphs — camera chrome, correctly fixed.

### Task 4: Me tab — profile load-error retry row
**Files:** Modify `MeView.swift` (body VStack, after `guestSection`)
- [ ] Insert quiet inline error row shown only when load failed AND nothing loaded:
```swift
if let error = profileService.loadError, profile == nil {
    HStack(spacing: Theme.Space.s3) {
        Image(systemName: "wifi.exclamationmark")
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
        Text(error)
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)
        Spacer(minLength: Theme.Space.s2)
        Button("Try again") { Task { await profileService.load() } }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.greenDeep)
    }
    .surfaceCard()
    .accessibilityElement(children: .combine)
}
```

### Task 5: Onboarding polish
**Files:** Modify `OnboardingView.swift`
- [ ] Allergies subline (L51): append editability → `"Optional — we'll flag these clearly on scanned products. Change anytime in Me."`
- [ ] Final-step summary note: append to `.healthAndCalories` VStack (after `caloriesToggleCard`):
```swift
Text("You can change all of this anytime in the Me tab.")
    .font(.caption)
    .foregroundStyle(Theme.textSecondary)
```
- [ ] Multi-select affordance: VERIFIED already correct (checkmark pill chips, `.isSelected` traits) — no change.
- [ ] Ingredient sheet detents: VERIFIED already `[.medium, .large]` (ResultComponents:1197) — no change.

### Task 6: Pantry management — remove + sort
**Files:** Modify `PantryService.swift` (new method), `HomeView.swift` (sort state, menu, context menu + confirm)
- [ ] `PantryService.remove(productID:)` — optimistic local removal, Supabase delete, reload-on-failure to restore truth:
```swift
/// Removes a product from the pantry entirely (user-control: SCREEN_SPECS §8).
/// Optimistic: drops the local entry immediately; on failure reloads from the
/// server so the UI never lies. Also clears any favorite mark.
@MainActor
func remove(productID: String) async {
    guard session.isBackendReachable, let client = session.supabaseClient,
          !session.userID.isEmpty else { return }
    let backup = entries
    entries.removeAll { $0.product.id == productID }
    favoriteProductIDs.remove(productID)
    do {
        try await client.from("pantry_items")
            .delete()
            .eq("user_id", value: session.userID)
            .eq("product_id", value: productID)
            .execute()
    } catch {
        entries = backup
        favoriteProductIDs = Set(entries.filter { $0.status == .favorited }.map { $0.product.id })
    }
}
```
- [ ] HomeView sort: `@State private var pantrySort: PantrySort = .recent` with `enum PantrySort { case recent, scoreHighFirst }`; apply in `filteredEntries` (`.scoreHighFirst` sorts by `entry.score?.score ?? -1` descending, stable).
- [ ] Sort control: small `Menu` (SF `arrow.up.arrow.down`, 44pt target, a11y label "Sort pantry") on the chips row (trailing).
- [ ] Remove flow: `.contextMenu` on pantry-grid cards only (NOT trending) with `Button("Remove from pantry", systemImage: "trash", role: .destructive)` → sets `pendingRemoval` → `.confirmationDialog("Remove \(name) from your pantry?", "Remove"/"Keep")` → `await pantryService.remove(productID:)`. Copy per COPY_DECK cautious-tone rules.

### Task 7: Verify — build, tests, screenshot matrix
- [ ] `cd ios && xcodegen generate && xcodebuild … build` (sim) — zero errors/warnings introduced
- [ ] `xcodebuild test -only-testing:FoodScannerTests` on one sim — green
- [ ] Screenshot matrix: Home, Onboarding, Me, Plan, Result(sample) on SE 3rd gen + 17 Pro + 17 Pro Max at default; repeat at XXL Dynamic Type (`SIMCTL_CHILD_SHOW_SCREEN` harness + `xcrun simctl ui booted appearance`/content-size override) — no clipping, glyphs scale, layouts reflow
- [ ] Grep gate: `grep -rn "font(.system(size" ios/FoodScanner/*.swift` returns only the 2 documented exclusions + camera chrome
- [ ] Commit + MEMORY.md entry + STATE.md status line
