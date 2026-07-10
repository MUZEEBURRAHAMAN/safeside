import Foundation
import Observation
import Supabase

// =============================================================================
// AnalyticsLogger — batched, best-effort, privacy-safe event logging (Chunk 7)
//
// Design contract (docs/ANALYTICS_METRICS.md §4/§8):
//   • Event names are stable snake_case, from the canonical taxonomy (§4).
//   • NO PII in `events.props`. Props hold enums/ids/numbers/bools ONLY — the
//     `AnalyticsValue` type makes free text (emails, OCR label text, typed
//     messages) structurally impossible to attach. Sentiment free text goes to
//     the separate `app_feedback` table (see FeedbackGate), never here.
//   • Best-effort: logging never throws, never blocks the UI, never delays
//     navigation. Events buffer and flush in batches; a failed flush re-buffers
//     (bounded) and is retried on the next flush.
//   • The `events` table already has an owner-only INSERT RLS policy, so the
//     client inserts directly via PostgREST — there is no analytics edge fn.
// =============================================================================

/// Canonical event names — the snake_case taxonomy from ANALYTICS_METRICS §4
/// (the doc is authoritative; the Chunk 7 plan's shorthand maps onto these).
/// Shorthand → canonical: result_viewed→score_viewed, why_expanded→
/// why_score_expanded, swap_viewed→swap_shown, swap_saved→swap_accepted,
/// report_submitted→data_reported.
enum EventName: String {
    case scanStarted = "scan_started"
    case scanSucceeded = "scan_succeeded"
    case scanFailed = "scan_failed"
    case scoreViewed = "score_viewed"
    case whyScoreExpanded = "why_score_expanded"
    case swapShown = "swap_shown"
    case swapAccepted = "swap_accepted"
    case chatOpened = "chat_opened"                    // appended to §4 (Chunk 7)
    case dataReported = "data_reported"
    case feedbackSentiment = "feedback_sentiment"      // appended to §4 (Chunk 7)
    case appReviewRequested = "app_review_requested"   // appended to §4 (Chunk 7)
}

/// Where a scan originated. `.manual` (typed barcode) and `.search` are
/// pre-included so Chunk 2's entry points log without a later logger edit —
/// only `.camera`/`.gallery` have call sites today.
enum ScanSource: String { case camera, gallery, manual, search }

/// The ONLY value shape allowed in `events.props`. Restricting props to these
/// four scalar cases is the enforcement mechanism for the no-PII rule: there is
/// no `.text`/`.freeform`/`.dictionary` case, so arbitrary user text simply
/// cannot be encoded into an event. Free text has one home only — `app_feedback`.
enum AnalyticsValue: Encodable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        }
    }
}

/// Props are string-keyed scalars only (see `AnalyticsValue`).
typealias EventProps = [String: AnalyticsValue]

/// One row destined for the `events` table. `user_id` is the pseudonymous
/// Supabase session id — the only identifier ever attached.
struct EventRecord: Encodable, Sendable {
    let user_id: String
    let name: String
    let props: EventProps
}

/// Injectable delivery boundary — the real one inserts via PostgREST; tests use
/// a fake that records batches. Kept a protocol so the logger has zero Supabase
/// coupling and stays unit-testable.
protocol EventSink: Sendable {
    func send(_ batch: [EventRecord]) async throws
}

/// Batched, best-effort event logger. `@MainActor` so call sites can fire it
/// from view code without hopping actors; the work it does (append to an
/// in-memory buffer, occasionally hand a batch to the sink) is trivial and
/// never blocks.
@Observable
@MainActor
final class AnalyticsLogger {
    /// Pending, not-yet-delivered events. Bounded by `maxBuffer`.
    private var buffer: [EventRecord] = []
    private let sink: EventSink
    private let userID: () -> String

    /// Flush once the buffer reaches this many events (amortizes network calls).
    private let flushThreshold: Int
    /// Hard cap on retained events so a persistently failing/offline sink can
    /// never grow the buffer without bound — oldest events are dropped first.
    private let maxBuffer: Int

    /// The most recent threshold-triggered flush. Exposed (internal) so tests
    /// can deterministically await the async flush that `log(_:_:)` kicks off.
    private(set) var pendingFlush: Task<Void, Never>?

    /// Number of not-yet-delivered events. Internal — for tests/diagnostics only.
    var bufferedCount: Int { buffer.count }

    init(
        sink: EventSink,
        userID: @escaping () -> String = { "" },
        flushThreshold: Int = 10,
        maxBuffer: Int = 200
    ) {
        self.sink = sink
        self.userID = userID
        self.flushThreshold = flushThreshold
        self.maxBuffer = maxBuffer
    }

    /// Records an event. Never throws, never blocks. Flushes automatically once
    /// the buffer reaches `flushThreshold`.
    func log(_ name: EventName, _ props: EventProps = [:]) {
        buffer.append(EventRecord(user_id: userID(), name: name.rawValue, props: props))
        capBuffer()
        if buffer.count >= flushThreshold {
            pendingFlush = Task { await self.flush() }
        }
    }

    /// Drains the buffer in a single batch. On failure the batch is re-buffered
    /// (bounded) for the next attempt; the error is swallowed — analytics must
    /// never surface an error to the UI.
    func flush() async {
        guard !buffer.isEmpty else { return }
        let batch = buffer
        buffer.removeAll(keepingCapacity: true)
        do {
            try await sink.send(batch)
        } catch {
            // Re-buffer ahead of anything logged during the await, then cap.
            buffer = batch + buffer
            capBuffer()
        }
    }

    /// Keeps the buffer at or below `maxBuffer`, dropping the oldest events.
    private func capBuffer() {
        if buffer.count > maxBuffer {
            buffer.removeFirst(buffer.count - maxBuffer)
        }
    }
}

/// Real sink: inserts events straight into the `events` table via PostgREST,
/// exactly like `ProfileService`/`PantryService` write their own tables. Guards
/// on the same conditions those services do (backend reachable, client present,
/// non-empty session id) and returns quietly when unconfigured/offline — it
/// never throws upward past `AnalyticsLogger.flush`, which already swallows
/// errors, but returning early avoids a doomed network round-trip.
struct SupabaseEventSink: EventSink, @unchecked Sendable {
    /// `SessionService` is a `@MainActor`-confined reference type (not `Sendable`);
    /// `@unchecked Sendable` is safe here because every access below hops onto
    /// `MainActor` before touching it. Nothing else is stored.
    private let session: SessionService

    init(session: SessionService) { self.session = session }

    func send(_ batch: [EventRecord]) async throws {
        let ctx = await MainActor.run {
            (session.isBackendReachable, session.userID, session.supabaseClient)
        }
        guard ctx.0, !ctx.1.isEmpty, let client = ctx.2 else { return }
        // Re-stamp every row with the current session id: events buffered before
        // the anonymous sign-in resolved carry "" and would otherwise be rejected
        // by the owner-only RLS check (`auth.uid() = user_id`).
        let stamped = batch.map { EventRecord(user_id: ctx.1, name: $0.name, props: $0.props) }
        try await client.from("events").insert(stamped).execute()
    }
}
