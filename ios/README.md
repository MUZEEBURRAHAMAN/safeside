# iOS App — Phase 0 Scaffold (SwiftUI)

Starter SwiftUI source for the AI Food Scanner. These are real, compilable-intent source files — **not** an `.xcodeproj` (that's binary; create it in Xcode). Follow the steps below to get a running app.

> Stack & rationale: `docs/NATIVE_IOS_STACK.md`. Design tokens: `docs/DESIGN_SYSTEM.md`. Endpoints: `docs/BACKEND_SPEC.md`.

## Setup (15 min)
1. **Xcode → New Project → App** (SwiftUI, Swift, iOS 17+). Name it e.g. `FoodScanner`.
2. Delete the default `ContentView.swift`; drag the files from `FoodScanner/` here into the project.
3. **Add Swift Packages** (File → Add Package Dependencies):
   - `https://github.com/supabase/supabase-swift` (auth + data)
   - `https://github.com/RevenueCat/purchases-ios` (subscriptions — wire later)
4. **Info.plist:** add `NSCameraUsageDescription` = "Scan product barcodes and labels." (required or the app crashes on camera).
5. Set your backend base URL in `APIClient.swift` and Supabase keys where noted.
6. Build & run on a **real device** (the scanner needs a camera; the Simulator has none).

## What's here (Phase 0 skeleton)
| File | Purpose |
|---|---|
| `FoodScannerApp.swift` | App entry; injects the session + a tab shell |
| `Theme.swift` | Design tokens (bold-green palette, spacing) from the design system |
| `Models.swift` | `Product`, `ScoreResult`, `ScoreBand`, `Ingredient` (match `DATA_MODEL.md`) |
| `SessionService.swift` | Guest-first anonymous session (`@Observable`); link-to-Apple later |
| `APIClient.swift` | `URLSession` async client hitting the backend endpoints |
| `ScoreBadge.swift` | The signature score component (non-alarmist, 3 redundant signals) |
| `HomeView.swift` | Big Scan button + recent scans |
| `ScannerView.swift` | VisionKit `DataScannerViewController` wrapped for SwiftUI |
| `ProductView.swift` | Score badge + "why this score" + ingredients (stubbed) |

## Phase 0 exit (per the build plan)
App builds in Xcode, launches on a real iPhone, opens into a guest session, and the scan screen opens the camera and detects a barcode (logs it). Wiring the barcode → backend lookup is the first Phase 1 task.

## Guardrails baked in
- **Guest-first:** no login wall (`SessionService` starts anonymous).
- **Non-alarmist scores:** `ScoreBadge` uses the ordinal green/amber/clay scale + text + icon; no "toxic" red.
- **Tokens, not hex:** views use `Theme`, never raw colors.
