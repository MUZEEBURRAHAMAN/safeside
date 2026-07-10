import Foundation
import Testing
@testable import FoodScanner

/// The batched, best-effort event logger (Chunk 7). These lock in the two
/// properties that matter most: the event names match the canonical taxonomy
/// (ANALYTICS_METRICS §4) and are stable snake_case, and the no-PII rule is
/// structurally enforced — props can only carry `AnalyticsValue` scalars, so a
/// typed message can never ride along in `events.props`.
@Suite("AnalyticsLogger")
struct AnalyticsLoggerTests {

    /// Records every batch handed to it, for assertions. An actor so the
    /// `@MainActor` logger can hand batches across the isolation boundary safely.
    actor RecordingSink: EventSink {
        private(set) var batches: [[EventRecord]] = []
        func send(_ batch: [EventRecord]) async throws { batches.append(batch) }
        func count() -> Int { batches.count }
        func all() -> [[EventRecord]] { batches }
    }

    /// Always fails — for the bounded-buffer / re-buffer path.
    struct ThrowingSink: EventSink {
        struct Boom: Error {}
        func send(_ batch: [EventRecord]) async throws { throw Boom() }
    }

    @Test("Event names are snake_case and equal the canonical spec names")
    func eventNamesAreSnakeCaseAndStable() {
        let regex = try! NSRegularExpression(pattern: "^[a-z][a-z_]*$")
        let expected: [EventName: String] = [
            .scanStarted: "scan_started",
            .scanSucceeded: "scan_succeeded",
            .scanFailed: "scan_failed",
            .scoreViewed: "score_viewed",
            .whyScoreExpanded: "why_score_expanded",
            .swapShown: "swap_shown",
            .swapAccepted: "swap_accepted",
            .chatOpened: "chat_opened",
            .dataReported: "data_reported",
            .feedbackSentiment: "feedback_sentiment",
            .appReviewRequested: "app_review_requested",
        ]
        for (event, name) in expected {
            #expect(event.rawValue == name)
            let range = NSRange(name.startIndex..., in: name)
            #expect(regex.firstMatch(in: name, range: range) != nil, "\(name) is not snake_case")
        }
    }

    @Test("Buffers until the threshold, then flushes exactly one batch")
    @MainActor
    func buffersUntilThreshold() async {
        let sink = RecordingSink()
        let logger = AnalyticsLogger(sink: sink, flushThreshold: 10)

        for _ in 0..<9 { logger.log(.scanStarted) }
        #expect(await sink.count() == 0)          // 9 buffered, nothing sent
        #expect(logger.bufferedCount == 9)

        logger.log(.scanStarted)                  // 10th trips the threshold
        await logger.pendingFlush?.value

        let batches = await sink.all()
        #expect(batches.count == 1)               // exactly one flush
        #expect(batches.first?.count == 10)       // of all 10 events
        #expect(logger.bufferedCount == 0)
    }

    @Test("Buffered events flush as a single insert, not N calls")
    @MainActor
    func flushGroupsIntoOneBatch() async {
        let sink = RecordingSink()
        let logger = AnalyticsLogger(sink: sink, flushThreshold: 10)

        logger.log(.scanStarted)
        logger.log(.scoreViewed)
        logger.log(.chatOpened)
        await logger.flush()

        let batches = await sink.all()
        #expect(batches.count == 1)
        #expect(batches.first?.count == 3)
    }

    @Test("On-demand flush drains a partial buffer and empties it")
    @MainActor
    func flushOnDemandDrainsBuffer() async {
        let sink = RecordingSink()
        let logger = AnalyticsLogger(sink: sink, flushThreshold: 10)

        logger.log(.scanStarted)
        logger.log(.scanSucceeded)
        await logger.flush()
        #expect(await sink.count() == 1)
        #expect(logger.bufferedCount == 0)

        await logger.flush()                      // buffer empty → no-op, no new batch
        #expect(await sink.count() == 1)
    }

    @Test("Props carry ids/enums only — never free text (no-PII guard)")
    func propsCarryNoFreeText() throws {
        let record = EventRecord(
            user_id: "session-uuid",
            name: EventName.dataReported.rawValue,
            props: ["product_id": .string("abc-123"), "reason": .string("score_off")]
        )
        let data = try JSONEncoder().encode(record)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let props = try #require(json["props"] as? [String: Any])

        #expect(props["product_id"] as? String == "abc-123")
        #expect(props["reason"] as? String == "score_off")
        // The sentiment gate's free text lives in `app_feedback`, never here.
        #expect(props["message"] == nil)
        #expect(props["text"] == nil)
        #expect(props.count == 2)
    }

    @Test("A failing sink re-buffers but never grows the buffer past maxBuffer")
    @MainActor
    func failedFlushKeepsBufferBounded() async {
        let logger = AnalyticsLogger(sink: ThrowingSink(), flushThreshold: 10, maxBuffer: 50)
        for _ in 0..<200 { logger.log(.scanStarted) }
        await logger.pendingFlush?.value
        #expect(logger.bufferedCount <= 50)       // bounded despite every flush failing
        #expect(logger.bufferedCount > 0)         // and it keeps the most recent events
    }
}
