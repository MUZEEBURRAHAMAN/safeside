# Chunk 7 — Analytics + Feedback + Legal Surfaces Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline). Steps use checkbox syntax. Also query `ui-ux-pro-max` (`--stack swiftui`, `--domain ux`) for the logger/gate rules and run its Pre-Delivery Checklist as a merge gate; draft any *new* string via `/ux-writing`; run `/ios-design-review` on the sim shots before device install.

**Goal:** Instrument the core loop with privacy-safe analytics events, add a post-3rd-scan emoji sentiment gate that routes unhappy users to feedback and happy users to the App Store (never mid-onboarding), and ship real Privacy Policy + Terms + OFF/ODbL+USDA attribution screens in the Me tab — all on the same DESIGN_SYSTEM_V3 tokens, all copy verbatim from `docs/COPY_DECK.md`.

**Architecture:** Client-heavy chunk.
- **New files:** `ios/FoodScanner/AnalyticsLogger.swift` (batched event logger + `EventName` enum + injectable `EventSink`), `ios/FoodScanner/FeedbackGate.swift` (scan-count controller + sentiment sheet), `ios/FoodScanner/LegalViews.swift` (`PrivacyPolicyView`, `TermsView`, `AttributionView`), and one backend migration `supabase/migrations/20260710120000_events_hardening_feedback.sql`.
- **Edits:** `FoodScannerApp.swift` (inject logger + gate into the environment; present the gate sheet from `RootTabView`; flush on scenePhase→background), `ScannerView.swift` (scan_started/succeeded/failed + latency + scan-count increment), `ProductView.swift` (score_viewed, chat_opened, swap_shown, data_reported call sites), `ResultComponents.swift` (add optional `onExpandChanged` to `CollapsibleSection`; `WhyScoreSection` fires `why_score_expanded`), `MeView.swift` (About/Legal rows + sheet routing; replace placeholder `PrivacySheet`/`DataSourcesSheet`).
- **Backend/client split:** the `events` table **already exists** (`20260707000000_initial_schema.sql:104-110`) with an **owner-only INSERT RLS policy** (`with check (auth.uid() = user_id)`, lines 217-221). Anonymous Supabase sessions carry the `authenticated` role, so the client inserts its own events **directly via PostgREST** — exactly the pattern `ProfileService`/`PantryService` already use — **no edge function needed**. The migration only (a) adds a funnel index + a name-length guard on `events`, and (b) adds a new owner-only `app_feedback` table so the sentiment gate's *free-text* has a real home **outside** the analytics table (keeps PII out of `events.props`). All nutrition/score math stays server-side (unchanged) — analytics never computes anything.
- **Schema/RLS changes:** `events` gets `events_name_ts_idx` + `check (char_length(name) <= 64)`; new `app_feedback(user_id, sentiment, message, ts)` with RLS owner-only insert/select, no update/delete (mirrors `events`).

**Tech Stack:** SwiftUI iOS 17+, `@Observable`, `supabase-swift` (PostgREST `.from("events").insert([...])`), `@Environment(\.requestReview)` / `StoreKit` `AppStore.requestReview`, `@Environment(\.scenePhase)`, `UserDefaults` (scan counter), Swift Testing (`import Testing`), Postgres/Supabase migrations, XcodeGen. New `.swift` files under `ios/FoodScanner/` are auto-included (project.yml `sources: - path: FoodScanner`).

---

## Dependencies & sequencing note

Per `MASTER_PLAN_PRE_D.md` sequencing (`0 → 1 → … → 6 → 7`), Chunk 7 is **last**, so event names are frozen here and every surface it instruments *should* already exist. Because chunks can run out of order, wire each call site defensively:

- **Chunk 1 (real Report endpoint + `ReportIssueSheet`):** `data_reported` fires on a *successful* report submit. If Chunk 1 has NOT landed, `ReportIssueSheet` is still the "not live yet" stub (`ResultComponents.swift:1213`) — in that case fire `data_reported` on the sheet's `onAppear` guarded by a `// TODO(chunk-1): move to submit success` and log `{product_id}` only. Do **not** block the logger on Chunk 1.
- **Chunk 3 (real swaps sheet):** `swap_shown` fires when the better-options sheet appears; `swap_accepted` fires on Save-to-pantry from a swap card. Today the CTA opens the `NextActionSheet` stub (`ResultComponents.swift:1290`). Wire `swap_shown` on that sheet's `onAppear` now (works for stub and real); wire `swap_accepted` only where a real swap-save action exists — if Chunk 3 hasn't landed, leave a `// TODO(chunk-3): swap_accepted on save` and ship without it.
- **Chunk 2 (search + manual barcode):** the logger's `ScanSource` enum must already include `.manual` and `.search` so those entry points log without a later edit; only `.camera`/`.gallery` have call sites today.
- **Chunk 4 (`product_current_scores` view / rate-limit):** no coupling — analytics reads nothing from scoring.

If executed *before* 1/3/2, the four always-present events (`scan_*`, `score_viewed`, `why_score_expanded`, `chat_opened`) plus the feedback gate and legal screens are fully shippable on their own; the swap/report events attach to whatever surface exists.

## Prerequisite gate — KEY ROTATION (blocking, do first)

Per `STATE.md` + `MASTER_PLAN_PRE_D.md` Standing rules: **rotate the pasted Cerebras/Groq/USDA keys + the Supabase access token before any Chunk 7 work.**
- [ ] Rotate Cerebras, Groq, USDA keys in the Supabase Function secrets; rotate the Supabase personal access token used by the CLI.
- [ ] Confirm `Config.xcconfig` and function secrets reference the new values; confirm no key appears in git history added this session (`git log -p | grep -iE 'sk-|key' ` spot-check).
- [ ] Verify existing edge functions still deploy/run with rotated secrets (`supabase functions deploy product` dry check or local serve) — analytics work starts only after this is green.

## Global Constraints

- **Copy:** every user-facing string comes from `docs/COPY_DECK.md` verbatim (§Feedback gate, §Legal & attribution, §New surfaces). The full *body* of the Privacy Policy and Terms is **not** in the deck — see Task 8's copy note (must be drafted via `/ux-writing` + founder/legal review before merge).
- **Privacy (ANALYTICS_METRICS §4/§8):** event names are stable `snake_case`; **no PII in `events.props`** — props hold enums/ids/numbers only, never free text, emails, or label OCR text. `user_id` = the pseudonymous Supabase session id (`session.userID`). Analytics is **best-effort**: it must never throw, block UI, or delay navigation.
- **ED-safe / never-a-dead-end:** the sentiment gate has no shame framing, offers an equal-weight "Not now", never triggers mid-onboarding, and appears at most once. No streaks, no guilt copy (teardown AVOID #8/#9).
- **Tokens only** — `Theme.Space`, `Theme.Radius`, `Theme` colors, `DisplayType`. No raw hex/pt literals in the new views. Legal/auth screens must NOT look boilerplate (teardown AVOID #12).
- **Build:** `xcodegen generate` immediately before every `xcodebuild` (project file is generated — STATE.md gotcha). Verify with: `cd ios && xcodegen generate && xcodebuild -project FoodScanner.xcodeproj -scheme FoodScanner -destination 'platform=iOS Simulator,name=<sim>' build`.

---

### Task 1 (TDD): Backend migration — events hardening + app_feedback table

**File:** New `supabase/migrations/20260710120000_events_hardening_feedback.sql`

- [ ] Write the migration (additive only — never rewrites existing policies):
```sql
-- Chunk 7 analytics: index the funnel query path and cap event-name length.
create index if not exists events_name_ts_idx on events (name, ts desc);
alter table events add constraint events_name_len check (char_length(name) <= 64);

-- Sentiment-gate free text lives OUTSIDE events (keeps PII out of analytics props).
create type feedback_sentiment_type as enum ('not_great', 'okay', 'good', 'great');

create table app_feedback (
  id        uuid primary key default gen_random_uuid(),
  user_id   uuid references auth.users (id) on delete set null,
  sentiment feedback_sentiment_type not null,
  message   text,                                    -- optional free text; owner-only
  ts        timestamptz not null default now()
);
create index app_feedback_ts_idx on app_feedback (ts desc);

alter table app_feedback enable row level security;
create policy "users can submit own feedback"
  on app_feedback for insert to authenticated
  with check (auth.uid() = user_id);
create policy "users can read own feedback"
  on app_feedback for select to authenticated
  using (auth.uid() = user_id);
-- no update/delete policies (append-only, mirrors events)
```
- [ ] **Test/verify (no edge function ⇒ no new Deno test; the deno suite stays a regression gate).** Apply + prove RLS locally:
  - `supabase db reset` (or `supabase migration up`) applies cleanly with no error.
  - RLS proof via `psql` against the local db: as a JWT with `sub = user A`, `insert into events(user_id,name) values (auth.uid(),'scan_started')` succeeds; `insert ... values (<user B uuid>, ...)` is rejected by RLS; `select` returns only user A's rows. Same three checks for `app_feedback`. Record the psql transcript in the PR.
  - Confirm the existing 121+ Deno tests still pass unchanged: `cd supabase/functions && deno test -A`.

### Task 2 (TDD): AnalyticsLogger — event enum, batching, PII guard

**File:** New `ios/FoodScanner/AnalyticsLogger.swift`; test `ios/FoodScannerTests/AnalyticsLoggerTests.swift`

- [ ] **Write tests first** (`import Testing`, `@Suite("AnalyticsLogger")`), against a fake `EventSink`:
  - `func eventNamesAreSnakeCaseAndStable()` — every `EventName.rawValue` matches `^[a-z][a-z_]*$` and equals the canonical spec name (table below).
  - `func buffersUntilThreshold()` — logging 9 events flushes 0 batches; the 10th triggers exactly one `flush` batch of 10.
  - `func flushGroupsIntoOneBatch()` — buffered events flush as a single `insert([...])` call, not N calls.
  - `func flushOnDemandDrainsBuffer()` — `await flush()` on a partial buffer sends remaining events and empties it.
  - `func propsCarryNoFreeText()` — a helper `EventProps` only accepts `AnalyticsValue` (`.string/.int/.double/.bool`); assert the encoded batch for a `data_reported` event contains `product_id`/`reason` keys and no `message`/`text` key (guards the no-PII rule).
  - `func failedFlushKeepsBufferBounded()` — a sink that throws leaves events buffered but caps total retained at `maxBuffer` (e.g. 200), never unbounded.
- [ ] Implement:
```swift
enum EventName: String {           // canonical = ANALYTICS_METRICS §4 snake_case
    case scanStarted = "scan_started"
    case scanSucceeded = "scan_succeeded"
    case scanFailed = "scan_failed"
    case scoreViewed = "score_viewed"          // chunk's "result_viewed"
    case whyScoreExpanded = "why_score_expanded" // chunk's "why_expanded"
    case swapShown = "swap_shown"              // chunk's "swap_viewed"
    case swapAccepted = "swap_accepted"        // chunk's "swap_saved"
    case chatOpened = "chat_opened"            // NEW — append to §4
    case dataReported = "data_reported"        // chunk's "report_submitted"
    case feedbackSentiment = "feedback_sentiment"  // NEW — append to §4
    case appReviewRequested = "app_review_requested" // NEW — append to §4
}
enum ScanSource: String { case camera, gallery, manual, search }
enum AnalyticsValue: Encodable { case string(String), int(Int), double(Double), bool(Bool) }
typealias EventProps = [String: AnalyticsValue]

protocol EventSink { func send(_ batch: [EventRecord]) async throws }   // injectable
struct EventRecord: Encodable { let user_id: String; let name: String; let props: EventProps }

@Observable @MainActor
final class AnalyticsLogger {
    private var buffer: [EventRecord] = []
    private let sink: EventSink
    private let flushThreshold = 10
    private let maxBuffer = 200
    init(sink: EventSink) { self.sink = sink }
    func log(_ name: EventName, _ props: EventProps = [:]) { /* append; flush if >= threshold */ }
    func flush() async { /* drain; on throw, re-buffer up to maxBuffer, swallow error */ }
}
```
- [ ] Real sink `SupabaseEventSink(session:)` — guards `session.isBackendReachable`, `supabaseClient`, non-empty `userID`; stamps `user_id = session.userID`; `try await client.from("events").insert(batch).execute()`. Returns quietly (no throw upward) when unconfigured/offline (matches `ProfileService` guards). Never surfaces errors to the UI.

### Task 3: Inject logger + flush lifecycle

**File:** Modify `ios/FoodScanner/FoodScannerApp.swift:14-20`, `:60-73`, `RootTabView` `:77-94`

- [ ] Add `@State private var analytics: AnalyticsLogger` and construct in `init()` alongside the other services: `_analytics = State(initialValue: AnalyticsLogger(sink: SupabaseEventSink(session: session)))`.
- [ ] Inject `.environment(analytics)` in both `harness(_:)` (`:51-57`) and `appBody` (`:60-72`) so previews/screenshot-harness roots and the real tree both have it.
- [ ] Flush on background: add `@Environment(\.scenePhase)` observation at the `WindowGroup`/`RootTabView` level → on `.background` call `Task { await analytics.flush() }` (best-effort delivery before suspend).

### Task 4: Scan events + scan-count increment

**File:** Modify `ios/FoodScanner/ScannerView.swift` — `handle(barcode:)` `:599-620`, `lookUpProduct` `:628-647`, `analyzeLabelText` `:680-698`

- [ ] Thread the `AnalyticsLogger` into `ScanViewModel` calls (the VM is `@Observable`, not in the environment — pass `analytics` as a parameter to `handle`/`captureLabel`/`analyzeGalleryPhoto` the same way `api`/`pantryService` are already passed; the call sites in `ScanScreen` read it from `@Environment(AnalyticsLogger.self)`).
- [ ] `scan_started`: in `handle(barcode:)` right after the guards pass (`:604`, before/at the `phase = .lookingUp` at `:612`) → `analytics.log(.scanStarted, ["source": .string(ScanSource.camera.rawValue)])`. Capture `let t0 = Date()` here for latency.
- [ ] `scan_succeeded`: in `lookUpProduct` success branch (`:630-636`, after `showProduct = true`) → `analytics.log(.scanSucceeded, ["source": .string("camera"), "latency_ms": .int(Int(Date().timeIntervalSince(t0)*1000)), "found": .bool(true)])`, then `FeedbackGate.recordSuccessfulScan()` (Task 6). Mirror in `analyzeLabelText` success (`:682-690`) with `source:"camera"` (OCR path).
- [ ] `scan_failed`: `.needsOCR` catch (`:637-639`) → `analytics.log(.scanFailed, ["source": .string("camera"), "reason": .string("not_found")])`; `APIError` catch (`:640-642`) → `reason:"network"`; generic catch (`:643-645`) → `reason:"error"`. In `analyzeLabelText` failure (`:691-697`) → `reason:"label_error"`; `captureLabel`'s `.labelNotFound` → `reason:"label_not_found"`.
- [ ] Gallery path (`analyzeGalleryPhoto`, `:715+`): reuse the same events with `source:"gallery"`.

### Task 5: Result / why / chat / swap / report events

**File:** Modify `ios/FoodScanner/ProductView.swift` + `ios/FoodScanner/ResultComponents.swift`

- [ ] Add `@Environment(AnalyticsLogger.self) private var analytics` to `ProductView`.
- [ ] `score_viewed`: in `ProductView` `.task { }` (`:167`), once per appearance → `analytics.log(.scoreViewed, ["product_id": .string(workingProduct.id), "band": .string(band.rawValue), "score": .int(workingProduct.score?.score ?? -1), "confidence": .string(workingProduct.score?.confidence ?? "unknown")])`. (Fires for scan- *and* pantry-originated opens — correct.)
- [ ] `chat_opened`: in `askAboutProductButton` action (`:255-257`, where `showChat = true`) → `analytics.log(.chatOpened, ["product_id": .string(workingProduct.id)])`.
- [ ] `swap_shown`: on the "See a better option" sheet. Add `.onAppear` to the sheet content in `.sheet(isPresented: $showBetterOptionSheet)` (`:152-157`) → `analytics.log(.swapShown, ["from_score": .int(workingProduct.score?.score ?? -1)])`. `// TODO(chunk-3): swap_accepted on real swap save`.
- [ ] `data_reported`: with Chunk 1 landed, fire in `ReportIssueSheet`'s submit-success closure with `["product_id": .string(workingProduct.id), "reason": .string(selectedReason.rawValue)]`. If the stub is still present (`ResultComponents.swift:1213`), fire on the sheet's `.onAppear` with `["product_id": ...]` and mark `// TODO(chunk-1): move to submit success`.
- [ ] `why_score_expanded`: add an optional callback to `CollapsibleSection` (init `:110-119`) — `onExpandChanged: ((Bool) -> Void)? = nil` — and invoke it inside the toggle action right after `isExpanded.toggle()` (`:145`) as `onExpandChanged?(isExpanded)`. In `WhyScoreSection` (`:403-442`) pass `onExpandChanged: { expanded in if expanded { onExpand?() } }` and add a `var onExpand: (() -> Void)? = nil` stored property; `ProductView` supplies it via the `whyScoreOrNote` builder (`:300`) to `analytics.log(.whyScoreExpanded, ["product_id": .string(workingProduct.id)])`. Default-nil keeps every other `CollapsibleSection` caller unchanged.

### Task 6 (TDD): Feedback gate — controller + sentiment sheet

**File:** New `ios/FoodScanner/FeedbackGate.swift`; test `ios/FoodScannerTests/FeedbackGateTests.swift`

- [ ] **Write tests first** (`@Suite("FeedbackGate")`) using an injected `UserDefaults(suiteName:)`:
  - `func promptsExactlyOnThirdScan()` — `recordSuccessfulScan()` ×2 ⇒ `shouldPrompt == false`; the 3rd ⇒ `true`; the 4th ⇒ stays `false` (fires once).
  - `func neverPromptsDuringOnboarding()` — with `hasOnboarded == false`, three scans ⇒ `shouldPrompt == false`; flips true only after onboarding completes + a scan tips it to the threshold.
  - `func neverRepromptsAfterShown()` — once `markPrompted()` runs, further scans never set `shouldPrompt`.
  - `func countPersists()` — count survives a new controller reading the same defaults.
- [ ] Implement `@Observable @MainActor final class FeedbackGate` with `successfulScanCount` + `feedbackPrompted` in `UserDefaults` (keys `feedback.scanCount`, `feedback.prompted`; onboarding read from existing `hasOnboarded`). `recordSuccessfulScan()` increments, and sets `shouldPrompt = true` iff `count == 3 && hasOnboarded && !feedbackPrompted`. Inject into the environment in `FoodScannerApp` (Task 3 pattern).
- [ ] Build `FeedbackGateSheet` (copy VERBATIM from COPY_DECK §Feedback gate):
  - Prompt title "How's SafeSide so far?"; four equal-weight buttons: "Not great" · "Okay" · "Good" · "Great" (chip/segmented row, 44pt targets, tokenized).
  - **Not great / Okay →** "What should we fix?" free-text field → button "Thanks — this goes straight to the team." *(display copy)*; on submit: `client.from("app_feedback").insert(sentiment,message)` (Task 1 table) **and** `analytics.log(.feedbackSentiment, ["sentiment": .string("not_great"|"okay")])` — the message goes to `app_feedback`, NEVER to `events.props`.
  - **Good / Great →** "Glad it helps. Mind rating us on the App Store?" with `[Rate SafeSide]` `[Not now]`. `Rate SafeSide` → `requestReview()` (`@Environment(\.requestReview)`) + `analytics.log(.appReviewRequested)`. `Not now` dismisses. Log `feedback_sentiment` with `good`/`great` on selection.
  - Always call `gate.markPrompted()` on dismiss so it never re-shows. ED-safe: no shame, no forced choice, dismissible.
- [ ] Present from `RootTabView` (`FoodScannerApp.swift:77-94`): `@Environment(FeedbackGate.self)` → `.sheet(isPresented: bound to gate.shouldPrompt)` on the `TabView`. Because it's presented from the tab shell (not the onboarding `fullScreenCover`), it structurally can't appear mid-onboarding. Guard `.presentationDetents([.medium])`.

### Task 7: Legal + attribution screens

**File:** New `ios/FoodScanner/LegalViews.swift`; modify `ios/FoodScanner/MeView.swift`

- [ ] Build three token-styled screens in `LegalViews.swift` (light canvas, `SectionCard`, `DisplayType` headers, `Link` in `Theme.greenDeep`, "Close" toolbar — match the existing `DataSourcesSheet` shape at `MeView.swift:747-795`, NOT a boilerplate wall):
  - `PrivacyPolicyView` — full policy body (see copy note); **must disclose analytics** (ANALYTICS_METRICS §8: "no third-party ad/tracking SDKs", data minimization, guest-first, `app_feedback`/`events` usage) and keep the footer disclaimer "Information only — not medical advice. Allergen data may be incomplete; check labels."
  - `TermsView` — Terms of use body (see copy note).
  - `AttributionView` — intro (VERBATIM COPY_DECK §Legal): "Product data comes from Open Food Facts, available under the Open Database License (ODbL)." + linked `world.openfoodfacts.org` + share-alike note + USDA line VERBATIM: "Nutrition enrichment from USDA FoodData Central (public domain)."
- [ ] `MeView.swift` About section (`:336-350`): update rows to COPY_DECK §Legal labels and route to the new screens. Replace "Privacy" (`:342`) → **"Privacy policy"** → `.privacyPolicy`; keep "How scoring works" (`:338`); rename "Data sources" (`:346`) → **"Data sources & attribution"** → `.dataSources`→`AttributionView`; **add** a **"Terms of use"** `UtilityRow` → `.terms`. (Row order per deck: Privacy policy · Terms of use · Data sources & attribution.)
- [ ] `MeView.swift` `MeSheet` enum (`:402-406`): add `case terms`, keep `privacy`/`dataSources`; update `sheetContent` (`:467-473`): `.privacy` → `PrivacyPolicyView()`, `.terms` → `TermsView()`, `.dataSources` → `AttributionView()`.
- [ ] **Delete** the now-superseded placeholder `PrivacySheet` (`:706-742`) and `DataSourcesSheet` (`:747-795`) structs (their honest-placeholder copy is replaced by the real screens).

### Task 8: COPY_DECK pass + doc updates

- [ ] **Verify verbatim implementation** of every COPY_DECK string this chunk touches: §Feedback gate (all six lines), §Legal & attribution (rows + intro + USDA line). Grep each string against the deck; zero paraphrase.
- [ ] **Missing body copy (flag → draft):** the deck provides the attribution intro/rows and the feedback-gate microcopy, but **NOT** the full Privacy Policy or Terms of use body text. Draft both via `/ux-writing` (calm/neutral voice; disclose analytics + `app_feedback`; no dark patterns), add them to `docs/COPY_DECK.md` under a new "§Legal bodies (Chunk 7)" block, then implement verbatim. These screens require **founder/legal review** before merge (chunk Exit line: "legal screens reviewed by founder").
- [ ] **Update `docs/ANALYTICS_METRICS.md` §4:** append the three events not in the current taxonomy — `chat_opened {product_id}`, `feedback_sentiment {sentiment}`, `app_review_requested {}` — and add a one-line note reconciling the chunk's shorthand names (`result_viewed`→`score_viewed`, `why_expanded`→`why_score_expanded`, `swap_viewed/saved`→`swap_shown/accepted`, `report_submitted`→`data_reported`).
- [ ] Run `ui-ux-pro-max` search for logger/consent + rating-prompt UX rules and `/ux-writing` 4-phase pass on any drafted string; record the deck diff in the PR.

### Task 9: Verify — build, tests, screenshot matrix, gates

- [ ] `cd ios && xcodegen generate && xcodebuild … build` on the sim — zero new errors/warnings; new files compiled in.
- [ ] `xcodebuild test -only-testing:FoodScannerTests` — green, incl. new `AnalyticsLoggerTests` + `FeedbackGateTests`.
- [ ] Backend: migration applies (`supabase db reset`/`migration up`); RLS psql proof for `events` + `app_feedback` (Task 1); existing Deno suite still green (`deno test -A`, 121+).
- [ ] **Events-in-DB proof (chunk Exit):** run a real device session (scan → open result → expand why → open chat → report) and confirm rows land in `events` with correct names, `user_id = session id`, and **no PII in props** (inspect the JSON). Confirm the sentiment gate appears only after the 3rd successful scan and never during onboarding, and that a "Not great" submit writes to `app_feedback` (not `events`).
- [ ] **6-shot screenshot matrix** (SE-proxy iPhone 17e / iPhone 17 Pro / 17 Pro Max × default / XXL Dynamic Type) for the NEW surfaces: FeedbackGateSheet (sentiment + free-text + rating variants), PrivacyPolicyView, TermsView, AttributionView, and the updated Me About/Legal rows. No clipping; reflow at XXL; contrast AA (green fills, lime-on-dark).
- [ ] **Gates:** principles (transparency, ED-safe, honest states, never-a-dead-end, LLM-never-does-math, AA a11y) + teardown-AVOID list (esp. #8 no rating-prompt-before-value/guilt, #9 no gamification, #12 legal screens on-brand tokens) + `ui-ux-pro-max` Pre-Delivery Checklist + `/ios-design-review` on the sim shots.
- [ ] Device install → founder review of legal screens → commit + `MEMORY.md` decision entry + `STATE.md` status line.

---

## Verification / Exit criteria

Mirrors `MASTER_PLAN_PRE_D.md` Chunk 7 Exit + the standard gate:
- **Events visible in DB from a device session** — real device run produces `scan_started/succeeded/failed`, `score_viewed`, `why_score_expanded`, `chat_opened`, `swap_shown` (+ `data_reported`/`swap_accepted` where Chunks 1/3 have landed), `feedback_sentiment`, `app_review_requested` rows with pseudonymous `user_id` and **no PII in props**.
- **Batched, best-effort logger** — flushes at threshold + on background; offline/unconfigured never throws or blocks UI; buffer bounded.
- **Sentiment gate** — fires exactly once after the 3rd successful scan, never mid-onboarding, equal-weight dismiss, routes unhappy→`app_feedback`, happy→App Store review; ED-safe copy.
- **Legal screens reviewed by founder** — Privacy Policy (discloses analytics), Terms, and OFF/ODbL + USDA attribution live in Me on shared tokens (no boilerplate look).
- **Copy deck updated** — feedback + legal strings implemented verbatim; drafted Privacy/Terms bodies added to the deck; ANALYTICS_METRICS §4 extended.
- **Standard gate green** — existing Deno tests (121+) unchanged/green; new iOS unit tests green; migration + RLS proof pass; 6-shot matrix pass; principles + teardown-AVOID + ui-ux-pro-max checklist + `/ios-design-review` all pass; device install + founder review before merge-to-main.
