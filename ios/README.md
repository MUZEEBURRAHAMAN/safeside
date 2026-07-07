# iOS App — FoodScanner (SwiftUI)

Native SwiftUI source for the AI Food Scanner (iOS 17+). This directory is a real,
buildable app **spec** (`project.yml` for XcodeGen) + source — **not** a checked-in
`.xcodeproj` (that's generated locally and gitignored; never commit it).

> Stack & rationale: `docs/NATIVE_IOS_STACK.md`. Design tokens: `docs/DESIGN_SYSTEM.md`.
> Endpoints: `docs/BACKEND_SPEC.md`.

## Setup

1. **Install Xcode** (latest, from the App Store or developer.apple.com). Launch it once
   so it finishes installing additional components.
2. **Install XcodeGen** (if you haven't already):
   ```bash
   brew install xcodegen
   ```
3. **Backend config** — copy the template and fill in your real Supabase project values:
   ```bash
   cd ios
   cp Config-example.xcconfig Config.xcconfig
   ```
   Edit `Config.xcconfig` and set `SUPABASE_URL` / `SUPABASE_ANON_KEY` (find these in your
   Supabase project → Settings → API). **Read the comment in `Config-example.xcconfig`
   about escaping `//` in xcconfig files** — it's a real gotcha.
   `Config.xcconfig` is gitignored and already pre-seeded with placeholders, so skipping
   this step won't block a build — the app still launches and the scanner still works;
   backend calls just fail with a calm "not connected yet" message until you fill it in.
4. **Generate the Xcode project:**
   ```bash
   cd ios
   xcodegen generate
   ```
   This resolves the SPM packages (`supabase-swift`, `purchases-ios`) and creates
   `FoodScanner.xcodeproj`.
5. **Open it:** `open FoodScanner.xcodeproj`
6. **Set your team:** select the `FoodScanner` target → *Signing & Capabilities* → pick
   your Apple Developer Team (Automatic signing is already on). Alternatively, set
   `DEVELOPMENT_TEAM` in `Config.xcconfig` before generating.
7. **Run** on the Simulator (camera scanning won't work there — you'll see the calm
   "Camera unavailable" state) or on a real iPhone (needed to actually test scanning).

Whenever you edit `project.yml`, `Config.xcconfig`, or add/remove Swift files, re-run
`xcodegen generate` and Xcode will pick up the changes (close/reopen the project if Xcode
doesn't refresh automatically).

## What's here
| File | Purpose |
|---|---|
| `project.yml` | XcodeGen spec — targets, SPM packages, Info.plist, signing settings |
| `Config-example.xcconfig` | Tracked template for backend config (placeholder values) |
| `Config.xcconfig` | **Gitignored.** Your real Supabase URL/anon key, injected into Info.plist at build time |
| `FoodScanner/FoodScannerApp.swift` | App entry; injects the session + a tab shell |
| `FoodScanner/AppConfig.swift` | Reads `SUPABASE_URL`/`SUPABASE_ANON_KEY` from Info.plist (see `Config.xcconfig`) |
| `FoodScanner/Theme.swift` | Design tokens (bold-green palette, spacing) from the design system |
| `FoodScanner/Models.swift` | `Product`, `ScoreResult`, `ScoreBand`, `Ingredient` (match `DATA_MODEL.md`) |
| `FoodScanner/SessionService.swift` | Guest-first anonymous Supabase session (`@Observable`); link-to-Apple later |
| `FoodScanner/APIClient.swift` | `URLSession` async client hitting the backend's Supabase Edge Functions |
| `FoodScanner/ScoreBadge.swift` | The signature score component (non-alarmist, 3 redundant signals) |
| `FoodScanner/HomeView.swift` | Big Scan button + recent scans (empty state for now) |
| `FoodScanner/ScannerView.swift` | VisionKit `DataScannerViewController` wrapped for SwiftUI + `ScanScreen` states |
| `FoodScanner/ProductView.swift` | Score badge + "why this score" + ingredients |
| `FoodScannerTests/` | Swift Testing unit tests (models decoding, score bands) |
| `FoodScannerUITests/` | XCUITest smoke test |

## How config gets from `Config.xcconfig` into the app
`Config.xcconfig` defines build settings `SUPABASE_URL` / `SUPABASE_ANON_KEY`.
`project.yml`'s `info.properties` writes `"$(SUPABASE_URL)"` / `"$(SUPABASE_ANON_KEY)"`
into `ios/Generated/FoodScanner-Info.plist` (written by `xcodegen generate` — gitignored,
regenerated every run) — Xcode substitutes those `$(VAR)` references with the active
build setting at build time. `AppConfig.swift` reads the resulting values from
`Bundle.main.infoDictionary` at runtime. No secrets are ever committed; the anon key is
publishable-tier but still kept out of the repo since it's project-specific.

## Phase 0/1 exit criteria
App builds in Xcode, launches into a guest (anonymous Supabase) session, and the Scan
tab opens the camera and looks up a real barcode against the backend end-to-end (score +
"why this score" + ingredients), with calm error/needs-OCR/loading states.

## Guardrails baked in
- **Guest-first:** no login wall (`SessionService` starts anonymous via Supabase).
- **Non-alarmist scores:** `ScoreBadge` uses the ordinal green/amber/clay scale + text +
  icon; no "toxic" red.
- **Tokens, not hex:** views use `Theme`, never raw colors.
- **Calm errors, never dead-ends:** every error/empty state offers a next action (Retry,
  "Try another scan", Open Settings) using the exact copy in `docs/COPY_DECK.md`.
- **Secrets stay out of the bundle's source:** Supabase config comes from a gitignored
  xcconfig, not hardcoded Swift.
