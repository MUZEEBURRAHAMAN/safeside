import Testing
@testable import FoodScanner

/// `ScoreBand` display mapping. The backend always sends the real `band` on
/// a `ScoreResult` — `ScoreBand.from(score:)` is a defensive/preview helper,
/// not a second scoring engine, but its boundaries must match
/// docs/SCORING_METHODOLOGY.md exactly (75–100 / 45–74 / 0–44) or the app and
/// backend would visually disagree.
@Suite("ScoreBand")
struct ScoreBandTests {

    @Test("Each band has the non-alarmist label from docs/COPY_DECK.md")
    func labels() {
        #expect(ScoreBand.high.label == "Lower-processed")
        #expect(ScoreBand.mid.label == "Moderately processed")
        #expect(ScoreBand.low.label == "Higher-processed")
        #expect(ScoreBand.unknown.label == "Not enough data")
    }

    @Test(
        "Boundary scores map to the bands in docs/SCORING_METHODOLOGY.md",
        arguments: [
            (75, ScoreBand.high),
            (74, ScoreBand.mid),
            (45, ScoreBand.mid),
            (44, ScoreBand.low),
            (0, ScoreBand.low),
        ]
    )
    func boundaries(score: Int, expectedBand: ScoreBand) {
        #expect(ScoreBand.from(score: score) == expectedBand)
    }
}
