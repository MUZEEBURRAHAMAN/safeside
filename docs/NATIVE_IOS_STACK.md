# Native iOS Stack (Swift / SwiftUI)

**Version:** 1.0 · June 2026 · **Decision: build iOS-only, native Swift/SwiftUI** (no React Native, no Flutter, no Android for now).
**Supersedes** the React Native / Expo recommendation in `reference/build/Master_Build_Plan.docx` for the app layer. The backend, data model, scoring methodology, and AI planner specs are unchanged (they were always server-side).

> Repo facts live-verified on GitHub 2026-06-21. All third-party libs are MIT/Apache-2.0 (safe for a closed app). The only share-alike obligation is Open Food Facts **data** (ODbL: attribute + contribute back data/photos) — it does not affect your app code.

## Stack at a glance

| Need | Use | License | Notes |
|---|---|---|---|
| Barcode scan | **VisionKit `DataScannerViewController`** (iOS 16+); AVFoundation `AVCaptureMetadataOutput` fallback | Apple SDK | First-party, live highlight/tracking, barcodes + text in one API. Wrap in `UIViewControllerRepresentable` for SwiftUI. No third-party dep. |
| Label OCR | **Vision `VNRecognizeTextRequest`** (or the newer async `RecognizeTextRequest`) | Apple SDK | On-device, free, offline. DataScanner can also return text inline. |
| Product data | **OFF REST API via `URLSession`** (`/api/v2/product/{barcode}.json`) + `Codable` | data: ODbL | The official `openfoodfacts-swift` SDK is immature (no releases) — call the REST API directly; it returns `nutriscore_grade`, `nova_group`, `additives_tags`. |
| Clean nutrition | **USDA FoodData Central REST** via URLSession | public domain | Free api.data.gov key. Thin wrapper; no mature Swift client needed. |
| Subscriptions | **RevenueCat `purchases-ios`** (MIT, v5.78+, very active); or native **StoreKit 2** | MIT / Apple | RevenueCat adds entitlements, server validation, paywalls (RevenueCatUI). StoreKit 2 is the zero-dependency alternative. |
| Backend client | **`supabase-swift`** (MIT, v2.48+, active) | MIT | Auth + Postgres (PostgREST) + Edge Functions. Mirrors supabase-js. |
| Networking | **`URLSession` + async/await + `Codable`** | Apple SDK | Sufficient; add Alamofire only for complex multipart/retry. |
| Nutri-Score/NOVA | **Read precomputed values from OFF**; compute our own transparent score server-side | n/a | No mature Swift Nutri-Score/NOVA lib — don't adopt one. See `SCORING_METHODOLOGY.md`. |
| Diet optimizer | **Backend only** (Python OR-Tools/PuLP); iOS is a thin client | n/a | No production Swift LP solver. Plan returned as JSON. |
| AI planner | **iOS calls an authenticated backend route**; AI orchestration stays server-side | n/a | No Swift "Vercel AI SDK". Keeps keys safe + lets the DB do the math. Optional later: Apple **Foundation Models** (on-device, iOS 26+) for lightweight features — not a planner replacement. |
| Testing | **Swift Testing** (`@Test`/`#expect`) + **XCUITest** (UI) + **pointfreeco/swift-snapshot-testing** (MIT) | Apple / MIT | Swift Testing is the 2026 default for new unit tests; XCUITest for flows; snapshot for view regression. |
| Architecture | **SwiftUI + Observation (`@Observable`)**; MV for simple screens, MVVM where view logic is heavy | n/a | `@Environment` for injecting services (scanner, API client, store). |

## Architecture (native client + shared backend)

```
iOS app (SwiftUI)                         Backend (unchanged)
├─ DataScannerVC (barcode)  ──URLSession──> /product/:barcode  ──> OFF + USDA + Postgres cache
├─ Vision OCR (label)       ──URLSession──> /product/ocr
├─ supabase-swift (auth/data)              /plans/:id/ai  ──> LLM (Vercel AI SDK, Node/Py)
├─ RevenueCat (subscriptions)              /swaps, /shopping-list, OR-Tools solver
└─ SwiftUI views + @Observable services
```
All keys live on the backend. iOS never holds OFF/USDA/AI/secret keys. Scoring, optimization, and AI math all happen server-side and return JSON the app renders.

## What this changes vs the React Native plan
- **Scanner/OCR:** first-party VisionKit + Vision instead of `react-native-vision-camera` — fewer deps, better performance, no bridging. (A genuine win for a scanner app.)
- **OFF:** hand-written `URLSession` + `Codable` models instead of the JS SDK (the Swift SDK isn't ready). Slightly more networking code.
- **Subscriptions/backend:** same vendors, Swift SDKs (`purchases-ios`, `supabase-swift`).
- **AI/optimizer:** unchanged — always backend.
- **Testing/state:** Swift Testing + XCUITest + snapshot; SwiftUI `@Observable` instead of JS/React state.
- **Trade-off accepted:** no Android path and nothing to fork (smooth-app was Flutter), so the UI is built from scratch — but native scanning/OCR quality and platform fit are the payoff.

## Tooling
- Xcode (latest), Swift Package Manager for deps, EAS not used (native build). Apple Developer Program for device builds/TestFlight/submission.
- The `ios-app-developer` agent in `.claude/agents/` now applies directly (it assumes native Swift).

## Phased plan still applies (only the tooling changes)
`reference/build/Phased_Build_Plan_iOS.docx` Phase 0→4 **structure is unchanged and valid**. Swap the React Native tooling for native equivalents:

| Phase tool (RN, old) | Native iOS (use this) |
|---|---|
| obytes Expo template + EAS | Xcode project + Swift Package Manager |
| react-native-vision-camera | VisionKit `DataScannerViewController` |
| ML Kit OCR | Vision `VNRecognizeTextRequest` |
| Open Food Facts JS SDK | `URLSession` + `Codable` to OFF/USDA REST |
| react-native-purchases | `purchases-ios` (or StoreKit 2) |
| Supabase JS | `supabase-swift` |
| Jest + Maestro/Detox | Swift Testing + XCUITest + swift-snapshot-testing |
| React state (Zustand) | SwiftUI `@Observable` |

Phase 0 becomes: Xcode project, SPM deps, Supabase + RevenueCat wired, EAS→native build on a device, Swift Testing + a smoke XCUITest in CI.

## Open question
- StoreKit 2 vs RevenueCat: RevenueCat recommended for faster paywall/entitlement work + analytics; revisit if you want zero billing dependencies.
