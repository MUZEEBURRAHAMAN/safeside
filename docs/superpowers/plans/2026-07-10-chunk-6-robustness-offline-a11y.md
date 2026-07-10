# Chunk 6 — Robustness, Offline & Accessibility Sweep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline). Steps use checkbox syntax `- [ ]`. This is a **sweep + hardening chunk**: most surfaces already exist — the job is to *audit against SCREEN_SPECS states, close the gaps found, add first-class offline handling, fix the shatter-frame orientation edge, lock portrait, run a full on-device a11y pass, and file a written pass/fail checklist as a `docs/TEST_PLAN.md` addendum.* The checklist is the primary deliverable.

**Goal:** Every screen passes its 4 states (empty/loading/error/content) per SCREEN_SPECS; airplane mode never dead-ends (calm offline copy + retry everywhere, cached pantry/products stay browsable); the scan-success shatter frame is never rotated on a non-portrait capture; portrait lock is explicit; VoiceOver + Dynamic Type XXL + AA contrast verified **on a physical device**; a per-screen pass/fail checklist lands in `docs/TEST_PLAN.md`.

**Architecture:** Mostly SwiftUI/service edits inside existing files plus **one new file** (`NetworkMonitor.swift`, an `@Observable` `NWPathMonitor` wrapper) and **one new reusable view** (`OfflineBanner`, added to `HomeView.swift`'s shared components or `ResultComponents.swift`). Client-only: **no backend, no schema, no RLS, no edge-function changes** in this chunk (chat 429 rate-limit is Chunk 4; this chunk only handles the *client copy* if 429 is already returned). The one non-code artifact is the `docs/TEST_PLAN.md` addendum. Verification = `xcodebuild` + Swift Testing units + the 6-shot screenshot matrix + a documented manual device walk.

**Tech Stack:** SwiftUI iOS 17+, `@Observable`, `Network.framework` (`NWPathMonitor`), `URLError`, `@ScaledMetric`, AVFoundation (`AVCaptureConnection`/`CGImagePropertyOrientation`), supabase-swift, XcodeGen, Swift Testing (`@Test`/`#expect`). Skills: `ios-networking`, `ios-accessibility`, `ios-simulator`, `vision-framework`, plus review gates `/accessibility-audit` + `/frontend-a11y` + `/ios-design-review` + `/design-review`.

---

## Dependencies & sequencing note

- **Runs after Chunks 0–5** in the master sequence (`0 → 1 → 2 → 3 → 4 → 5 → 6`). Rationale (MASTER_PLAN §Sequencing): "6 sweeps everything after feature churn stops." Chunk 6 audits the *final* surface set, so it must see Search (§9), Swaps (§5), Compare (§10), and the Result meters (§1) in place.
- **If executed before some of 1/2/3/5 have landed** (chunks may be built out of order): **audit and harden only the screens that exist.** For each not-yet-built screen (Search, Swaps sheet, Compare), add a **stub row** to the `TEST_PLAN.md` checklist marked `N/A — screen not built (Chunk N)` rather than inventing states. Do **not** scaffold those screens here. The offline monitor, shatter-orientation fix, portrait lock, and the a11y sweep of *existing* screens are all independent of those chunks and should still ship.
- **Chunk 0 dependency (hard):** this chunk assumes `Theme.Space.s45`, the scaled glyphs, and the Me/pantry error rows from Chunk 0 exist. If Chunk 0 has **not** landed, do those fixes first (they are cheap) — do not duplicate them here.
- **Chunk 4 dependency (soft):** the chat 429 rate-limit endpoint is Chunk 4. Here we only wire the **client-side** 429 → calm copy path (COPY_DECK "Chat rate-limit"). If `/chat` never returns 429 yet, the mapping is dormant but correct; add a unit test with a synthetic 429 response so it's verified regardless.
- **No downstream chunk depends on this one** except the pre-Phase-D exit gate, which consumes the `TEST_PLAN.md` addendum.

---

## Global constraints

- Tokens only — no raw hex/pt literals in views (`Theme.Space`, `Theme.Radius`). Reuse existing `StateCard` (`HomeView.swift:597`) and `IngredientsLoadErrorView` (`ResultComponents.swift:1050`) rather than new one-off cards.
- **Copy from `docs/COPY_DECK.md`, verbatim.** The phrase **"Something went wrong"** is a COPY_DECK-banned pattern (§Errors: "never 'Something went wrong'") and currently appears in 8 places — this chunk eliminates every one. Any string with no COPY_DECK entry is flagged for `/ux-writing` (see Task 3) and added to the deck **before** it ships.
- ED-safe / calm tone unchanged. AA contrast is re-verified, not changed — if a token fails AA, file it, don't silently recolor.
- `xcodegen generate` immediately before every `xcodebuild` (the `.xcodeproj` is gitignored and regenerated — STATE.md gotcha).
- Verify build: `cd ios && xcodegen generate && xcodebuild -project FoodScanner.xcodeproj -scheme FoodScanner -destination 'platform=iOS Simulator,name=<sim>' build`
- Teardown AVOID list is a blocking gate — especially **AVOID #5** (color-semantics: offline/error states use neutral gray, never alarm-red) and **AVOID #14** (no 70%-empty screens: offline states stay dense with cached content, not blank).

---

### Task 1 (TDD): First-class offline detection in `APIClient`

**Why:** `APIClient.request` currently collapses *every* `URLSession` throw into `.transport` (`APIClient.swift:90–94`) and every non-2xx/404 into `.badResponse`, whose copy is the banned **"Something went wrong. Try again."** (`APIClient.swift:48`). Offline is indistinguishable from a server error, so we can't show the calm airplane-mode copy the chunk requires.

**Test file (write FIRST):** `ios/FoodScannerTests/APIErrorMappingTests.swift` (new). Swift Testing `@Test`:
- [ ] `offlineURLErrorMapsToOffline` — a `URLError(.notConnectedToInternet)` (and `.timedOut`, `.networkConnectionLost`, `.cannotConnectToHost`) maps to `APIClient.APIError.offline`.
- [ ] `otherURLErrorMapsToTransport` — an unrelated `URLError(.badURL)` maps to `.transport`.
- [ ] `offlineCopyIsCalmAndActionable` — `APIError.offline.errorDescription` == the COPY_DECK Network string (below) and contains no banned word (`bad`, `toxic`, "Something went wrong").
- [ ] `badResponseCopyIsNotBanned` — `.badResponse.errorDescription` and `.decoding.errorDescription` no longer contain "Something went wrong".
- [ ] `rateLimitedMapsFrom429` — a synthetic `HTTPURLResponse` statusCode 429 maps to `APIError.rateLimited` (dormant until Chunk 4, verified now).

Factor the mapping into a testable pure function so tests don't need a live socket:
```swift
static func mapURLError(_ error: Error) -> APIError   // URLError.Code → .offline | .transport
```

**Implementation (`ios/FoodScanner/APIClient.swift`):**
- [ ] Add cases to the `APIError` enum (`APIClient.swift:34–41`): `case offline` and `case rateLimited`.
- [ ] `errorDescription` (`APIClient.swift:43–56`):
  - `.offline` → COPY_DECK §Errors Network, verbatim: **"You're offline. We'll show saved results; reconnect to scan new items."**
  - `.rateLimited` → COPY_DECK §Offline & limits chat: **"You've asked a lot in a short time. Give it a minute and try again."**
  - `.badResponse` / `.decoding` → **flagged copy (Task 3)** — replace "Something went wrong. Try again." with the drafted server-hiccup string; do NOT ship "Something went wrong".
  - `.transport` stays: "Couldn't reach the server. Check your connection and try again."
- [ ] In the `catch` at `APIClient.swift:92`, replace `throw APIError.transport` with `throw APIError.mapURLError(error)`.
- [ ] After the `http` cast (`APIClient.swift:96`), add: `if http.statusCode == 429 { throw APIError.rateLimited }` **before** the 404 branch.

**Verify:** `xcodebuild test -only-testing:FoodScannerTests/APIErrorMappingTests` green.

---

### Task 2 (TDD): Live connectivity monitor + reusable `OfflineBanner`

**Why:** `SessionService.isBackendReachable` (`SessionService.swift:24`) is set **once at bootstrap** and never updates when the user toggles airplane mode mid-session, so views can't react to going offline/online. The chunk needs a *live* signal to show/hide calm offline banners and keep cached content browsable.

**Test file (write FIRST):** `ios/FoodScannerTests/NetworkMonitorTests.swift` (new). Because `NWPathMonitor` needs a real interface, test the **observable state transitions** via an injectable path-status closure:
- [ ] `startsOptimisticallyOnline` — initial `isOnline == true` (avoid a false offline flash before the first path callback).
- [ ] `satisfiedPathIsOnline` / `unsatisfiedPathIsOffline` — feeding `.satisfied` / `.unsatisfied` updates `isOnline`.
- [ ] `publishesOnMainActor` — state mutations are `@MainActor` (no UI-thread violation).

**Implementation:**
- [ ] New file `ios/FoodScanner/NetworkMonitor.swift`: `@MainActor @Observable final class NetworkMonitor` wrapping `NWPathMonitor` (queue = a private serial queue), exposing `private(set) var isOnline: Bool = true`, updated in `pathUpdateHandler`. Inject a seam for tests (`init(statusStream:)` or a settable handler). Follow the `ios-networking` skill's reachability pattern; do **not** use it to *gate* requests (offline-first: still attempt, fall back to cache) — only to *inform the UI*.
- [ ] Register one instance in `FoodScannerApp.swift` (alongside `SessionService`) and inject via `.environment(...)` so every tab can read it.
- [ ] New reusable view **`OfflineBanner`** (add to `HomeView.swift` near `StateCard:597`, or `ResultComponents.swift` shared section): a slim, **neutral-gray** (not red — AVOID #5) inline pill: SF `wifi.slash` (scaled glyph, Chunk-0 pattern) + short line + optional trailing "Retry". Copy driven by call site (see Task 4). `accessibilityElement(children: .combine)`, announces via `.accessibilityLabel`.

**Verify:** `xcodebuild test -only-testing:FoodScannerTests/NetworkMonitorTests` green.

---

### Task 3: Eliminate every "Something went wrong" + draft the one missing string

**Why:** COPY_DECK bans the phrase; it appears in 8 sites. Most already have honest-copy neighbors — swap in the correct COPY_DECK string or the `APIError.errorDescription` (now honest after Task 1).

- [ ] **Draft the missing string via `/ux-writing`** and add to `docs/COPY_DECK.md` §Errors *before* using it. Needed: a calm line for a genuine *server/parse hiccup* (not offline, not not-found). Proposed seed (must pass the skill's 4-phase edit): **"That didn't load right. Give it a moment and try again."** — pattern `[what happened]. [what to do]`, 8–14 words, no blame. Once approved, it becomes the copy for `APIError.badResponse`/`.decoding`.
- [ ] `APIClient.swift:48` — replaced in Task 1 with the drafted string.
- [ ] `ChatView.swift:329` and `:331` — the `?? "Something went wrong. Try again."` fallbacks → `?? APIClient.APIError.badResponse.errorDescription!` (single source of truth), or the drafted string. Also map `APIError.rateLimited`/`.offline` here so chat shows COPY_DECK §Offline & limits: **"Chat needs a connection. Your product details are still here."** when offline.
- [ ] `HomeView.swift:744` — this is a `#Preview`/placeholder `StateCard`; update its sample message to the drafted string so previews model honest copy.
- [ ] `ResultComponents.swift:1055` (`IngredientsLoadErrorView`) — replace `"Something went wrong."` heading with an honest heading; keep the existing body "We couldn't load ingredient details. Try again." (already COPY_DECK-shaped). Add an offline variant: when the failure is `APIError.offline`, show "You're offline" framing so the ingredient sheet doesn't imply a server fault.
- [ ] `ScannerView.swift:642, :645, :694, :696` — the `.error(...)` fallbacks → the drafted string (or the mapped `APIError` copy). When the thrown error is `.offline`, show COPY_DECK §Offline & limits scan line instead: **"You're offline. Scanning needs a connection — your pantry still works."**
- [ ] `ScannerView.swift:950` — `ContentUnavailableView` title "Something went wrong." → honest title from the drafted string.

**Verify (grep gate):** `grep -rn "Something went wrong" ios/FoodScanner/*.swift` returns **zero** hits.

---

### Task 4: Offline never dead-ends — cached browsing + banners on every network surface

**Why (Exit criteria):** "offline never dead-ends" and "cached pantry/products still browsable." Today, offline cold-launch fails `PantryService.load` (`PantryService.swift:52` guards `isBackendReachable`) and shows only `loadError` in a `StateCard` — a dead-end if nothing was cached, and no banner tells the user *why*. Products already viewed should remain openable.

Per-surface audit + fixes (each verified in airplane mode on device, Task 8/9):
- [ ] **Home / Pantry (`HomeView.swift:218–234`):** when `NetworkMonitor.isOnline == false`, show `OfflineBanner` above the pantry grid with COPY_DECK Network copy + Retry (`await pantryService.loadRecent()`). **Cached entries must still render** — the grid is already in-memory after a prior load; confirm `pantrySection` shows `filteredEntries` when non-empty even while `loadError` is set (reorder the `if` ladder so a populated grid wins over the error card). If the pantry was never loaded (fresh install offline), the `StateCard` empty copy stays, plus the banner.
- [ ] **Result / Product (`ProductView`):** a product reached from a cached pantry entry must open and show its stored score/details offline. The ingredient fetch (`ProductView.loadIngredientsIfNeeded`, `ProductView.swift:413`) will fail offline → `IngredientsLoadErrorView` now shows the offline variant (Task 3), with the rest of the Result screen fully readable (COPY_DECK §Offline & limits: "Showing saved details. Reconnect for the latest.").
- [ ] **Scan (`ScannerView`):** offline lookup → `.error` phase shows the scan offline line (Task 3). Keep the "Enter barcode manually" affordance reachable (Chunk 2) so scan isn't a dead-end even offline (search of cached/typed will still fail offline but with calm copy).
- [ ] **Chat (`ChatView`):** offline send → offline bubble copy (Task 3), retry preserved (`ChatView.swift:113–115`).
- [ ] **Search / Swaps / Compare (Chunks 2/3/5):** if built, add `OfflineBanner` + Search-error COPY_DECK copy ("Search isn't available right now. Check your connection and try again." [Retry]); if not built, mark `N/A` in the checklist (Dependencies note).
- [ ] **Me / Onboarding:** already have quiet inline retry rows (Chunk 0). Verify they render offline and use honest copy; no change expected.

**No new caching layer** is introduced here (out of scope) — this task ensures already-in-memory/session-cached data stays visible and every network surface carries a calm banner + retry. If the audit reveals a screen that *drops* cached content on error, fix only that reorder.

---

### Task 5 (TDD): Camera video-frame orientation edge (shatter frame)

**Why (chunk scope):** `captureSnapshotForShatter` (`ScannerView.swift:385–398`) builds `UIImage(cgImage: cgImage)` with the **default `.up` orientation** from the latest `videoDataOutput` sample buffer. The buffer is only rotated to portrait **if** `connection.isVideoOrientationSupported` was true when configured (`ScannerView.swift:249–251`). On hardware/edge where that connection flag is unsupported or the capture happens with the device rotated, the shatter snapshot renders **sideways/landscape** — a visible "shatter frame on non-portrait capture" glitch. Fix: make the snapshot orientation-correct regardless of the connection's rotation state.

**Test file (write FIRST):** `ios/FoodScannerTests/ShatterOrientationTests.swift` (new). Test the **pure helper**, not the camera:
- [ ] Factor a helper `static func shatterImageOrientation(connectionApplied portrait: Bool) -> UIImage.Orientation` (or a `CGImagePropertyOrientation` → `UIImage.Orientation` mapping mirroring `VisionOCR.swift:84`/`ScannerView.swift:798`).
- [ ] `portraitConnectionYieldsUp` — when the connection already rotated to portrait, orientation is `.up`.
- [ ] `unrotatedBufferYieldsRight` — when the connection did **not** rotate (landscape sensor native), orientation is `.right` (portrait-corrected).
- [ ] Reuse/verify the existing `CGImagePropertyOrientation` init pattern already present at `ScannerView.swift:798` so the mapping stays consistent.

**Implementation (`ios/FoodScanner/ScannerView.swift`):**
- [ ] Store whether the video connection's portrait rotation was actually applied (a `private let/var videoConnectionRotated: Bool` set at `ScannerView.swift:249–251`), OR read the connection's current `videoOrientation` at snapshot time.
- [ ] In `captureSnapshotForShatter` (`:396`), replace `UIImage(cgImage: cgImage)` with `UIImage(cgImage: cgImage, scale: 1, orientation: shatterImageOrientation(connectionApplied: videoConnectionRotated))` so the shard grid always renders upright.
- [ ] Belt-and-suspenders: if `isVideoOrientationSupported` was false at config time (`:249`), the fallback orientation keeps the snapshot upright rather than silently landscape.

**Verify:** `xcodebuild test -only-testing:FoodScannerTests/ShatterOrientationTests` green; on-device visual confirm in Task 8 (scan a barcode; shatter frame is upright).

---

### Task 6: Confirm portrait lock is explicit

**Why (Exit + chunk scope):** "confirm portrait lock explicit, nothing crashes." `ios/project.yml` `info.properties` (`project.yml:59–71`) has **no `UISupportedInterfaceOrientations` key** — the app currently inherits the default (all orientations), so a rotated launch of the camera/Result screens is untested and can mis-lay-out or crash. Lock to portrait.

- [ ] Add to `project.yml` under `targets.FoodScanner.info.properties` (after `UILaunchScreen`, `project.yml:62`):
```yaml
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
        UISupportedInterfaceOrientations~ipad:
          - UIInterfaceOrientationPortrait
          - UIInterfaceOrientationPortraitUpsideDown
```
  (Portrait-only on iPhone; iPad keeps both portrait variants since `TARGETED_DEVICE_FAMILY: "1,2"`.)
- [ ] `cd ios && xcodegen generate` and confirm the generated `Generated/FoodScanner-Info.plist` contains the key.
- [ ] Manual: rotate the device/simulator on every tab (Home, Scan, Result, Chat, Me, Plan) — UI stays portrait, **no crash, no clipped layout**. Record in the checklist (Landscape row).

---

### Task 7: Empty / loading / error state gap-close audit (all screens vs SCREEN_SPECS)

**Why (Exit):** "Empty/loading/error pass across ALL screens against SCREEN_SPECS states (most exist — close gaps found in audit)." This task is a **structured audit**: for each screen, confirm all 4 states exist, match COPY_DECK, and never dead-end. Fix only genuine gaps; do not rebuild working states.

For each screen below, verify (and fix gaps in) **{loading skeleton · empty · error+retry · content}** against its SCREEN_SPECS section:
- [ ] **Home / Pantry (§2, §8)** — skeleton `ProductGridSkeleton` (`HomeView.swift:220`), empty `StateCard` (`:229`), favorites-empty (`:233`), error+retry (`:221`). Gap check: trending rail has its own error/empty; offline banner (Task 4). ✅ mostly built.
- [ ] **Onboarding (§1)** — content-only by design (writes fire-and-forget); verify no spurious error UI. ✅
- [ ] **Scan (§3)** — all phases: `.scanning`, `.lookingUp` pill, `.needsOCR`/`labelNotFound` two-action banner, `.error` retry, permission-denied `ContentUnavailableView` (`ScannerView.swift:1056`), offline (Task 4). Confirm each names the thing + gives an action (§13 global rule).
- [ ] **Result (§4)** — per-section states + `IngredientsLoadErrorView` (`ResultComponents.swift:1050`); top-level `ResultSkeletonView` wiring is Chunk 1 (mark `N/A` if Chunk 1 unshipped).
- [ ] **Ingredient sheet (§6)** — "No vetted info yet" honest KB-miss state present.
- [ ] **Chat (§7)** — typing indicator (loading), starter chips (empty), `ErrorBubble` retry (`ChatView.swift:113`), offline/429 (Tasks 1/3).
- [ ] **Me (§12)** — profile load-error inline retry row (Chunk 0, `MeView.swift:71`); verify offline path.
- [ ] **Plan (§11)** — calm placeholder is the intended "state"; confirm no fake loading.
- [ ] **Search (§9) / Swaps (§5) / Compare (§10)** — audit if built (skeletons, honest empties, error retry, offline); else `N/A — Chunk N` in the checklist.

Every gap found → fix with the **existing** `StateCard`/`OfflineBanner`/`IngredientsLoadErrorView` components + COPY_DECK copy. Record the pass/fail of each cell in Task 9's table.

---

### Task 8: Full accessibility device sweep (VoiceOver + Dynamic Type XXL + contrast)

**Why (Exit):** "zero clipped layouts at XXL"; SCREEN_SPECS global rules (VoiceOver, XXL reflow, 44pt, AA). Run on a **physical iPhone**, not just the simulator (chunk scope: "Dynamic Type XXL on device"). Drive with the `ios-accessibility` skill and the `/accessibility-audit` + `/frontend-a11y` review gates.

- [ ] **VoiceOver walk of every flow**, on device: Onboarding → Home → Scan → Result (incl. meters, sources, report row) → Ingredient sheet → Chat → Swaps → Compare → Me → Plan. For each, confirm: focus order is logical; every control has a label; score badge reads as a sentence ("Score 38 of 100, higher-processed" — TEST_PLAN §Accessibility); combined-label cards (product cards, offline banner) read as one element; allergen banner announces.
- [ ] **Dynamic Type XXL (AX5) on device** — set the largest accessibility text size in iOS Settings and walk every screen: **no clipped/truncated key content**, grids reflow to 1-col, chips wrap, option cards grow, scaled glyphs (Chunk 0) grow with their circles, 44pt targets hold.
- [ ] **Contrast re-verify** — check the color-critical pairs against AA (4.5:1 text / 3:1 large+UI): green fills with white/deep-green text, **lime-on-dark** scan chrome, band-tint borders on ingredient cards, offline-banner gray, score-ring numerals. Use `/accessibility-audit`'s contrast pass. Any pair below AA → **file it in the checklist as FAIL** (do not silently recolor; brand tokens are locked to DESIGN_SYSTEM_V3 — a real failure is a separate decision).
- [ ] **Reduce Motion** — confirm the shatter transition and any meter animations honor Reduce Motion (already built; re-verify after Task 5's snapshot change).
- [ ] **44pt targets** — spot-check the new/edited controls (offline-banner Retry, sort menu, remove/confirm from Chunk 0).

Record every result in Task 9's table (VoiceOver / XXL / Contrast columns).

---

### Task 9: Write the `docs/TEST_PLAN.md` addendum — per-screen pass/fail checklist (THE DELIVERABLE)

**Why (Exit):** "written pass/fail checklist per screen filed in `docs/TEST_PLAN.md` addendum."

- [ ] Append a new section to `docs/TEST_PLAN.md` (after §5, so §1–5 stay intact): **"## 6. Chunk 6 robustness/offline/a11y sweep — per-screen pass/fail (July 2026)"**.
- [ ] Include a **per-screen table** with columns: `Screen · Loading · Empty · Error+Retry · Offline (airplane) · VoiceOver · Dynamic Type XXL · Contrast (AA) · Portrait-lock · Result`. One row per screen from Task 7 (Home, Pantry, Onboarding, Scan, Result, Ingredient sheet, Chat, Me, Plan, Search, Swaps, Compare). Cells = ✅ / ⚠️ (fixed this chunk) / ❌ (open, with a filed follow-up) / `N/A — Chunk N`.
- [ ] Add a short **"Offline pass"** subsection: the airplane-mode script (toggle airplane → cold launch → browse cached pantry → open a cached product → attempt scan → attempt chat → reconnect), with expected calm copy at each step (cite the exact COPY_DECK §Offline & limits strings).
- [ ] Add a **"Shatter-orientation & portrait-lock"** subsection recording the on-device result of Tasks 5 & 6.
- [ ] Add an **"Accessibility sweep"** subsection: device model + iOS version, VoiceOver/XXL/contrast findings, any AA failures filed as follow-ups.
- [ ] Reference the screenshot-matrix artifacts (Task 10) by path.

---

### Task 10: Verify — build, tests, screenshot matrix, review gates, device install

- [ ] `cd ios && xcodegen generate && xcodebuild … build` (sim) — zero new errors/warnings.
- [ ] `xcodebuild test -only-testing:FoodScannerTests` — green, incl. the 3 new suites (`APIErrorMappingTests`, `NetworkMonitorTests`, `ShatterOrientationTests`) + existing `ModelsDecodingTests`/`ScoreBandTests`.
- [ ] **Backend:** no backend changes in this chunk — confirm the existing Deno suite still passes unchanged (`deno test` in `supabase/functions`) as a regression guard; **121+ deno tests green** (no new endpoint tests, none owed).
- [ ] **6-shot screenshot matrix** (MASTER_PLAN standard): SE-proxy **iPhone 17e** (no SE 3rd-gen sim installed — STATE.md substitution) / iPhone 17 Pro / 17 Pro Max × **default + XXL (AX5)** Dynamic Type. Capture every screen incl. the new offline banners and error states (force offline via `xcrun simctl` network condition or airplane on device). No clipping, glyphs scale, layouts reflow, offline copy calm.
- [ ] **Grep gate:** `grep -rn "Something went wrong" ios/FoodScanner/*.swift` → 0 hits.
- [ ] **Review gates (blocking):** `/ios-design-review` on the matrix; `/accessibility-audit` + `/frontend-a11y` WCAG 2.1 AA pass; `/design-review` (or `/ux-audit`) full-app against DESIGN.md + **teardown AVOID list** (esp. #5 color semantics, #14 no-blank-screens); `ui-ux-pro-max` **Pre-Delivery Checklist** (App UI: icons, interaction, light/dark contrast, layout, a11y). All green.
- [ ] **Principles gate:** transparency, ED-safe (neutral offline/error tone), honest states (no "Something went wrong"), never-a-dead-end (offline always offers cached content or retry), AA a11y.
- [ ] **Device install** on a physical iPhone; run the Task 8 VoiceOver/XXL walk and the Task 9 airplane-mode script for real.
- [ ] Commit + `MEMORY.md` decision entry + `STATE.md` status line update on completion.

---

## Verification / Exit criteria (from MASTER_PLAN Chunk 6 + standing gate)

- **Written pass/fail checklist per screen filed in `docs/TEST_PLAN.md` addendum** (Task 9). ← primary deliverable.
- **Zero clipped layouts at XXL** across the 6-shot matrix + on-device (Tasks 8, 10).
- **Offline never dead-ends** — every network surface shows calm COPY_DECK offline copy + retry; cached pantry/products stay browsable in airplane mode (Task 4).
- Shatter frame upright on non-portrait capture (Task 5); portrait lock explicit and crash-free (Task 6).
- No "Something went wrong" anywhere (Task 3 grep gate).
- deno tests green (regression, no new owed); iOS tests green incl. 3 new suites; 6-shot matrix pass; device install + manual a11y walk done; principles + teardown-AVOID + `ui-ux-pro-max` Pre-Delivery checklist gates all pass.
