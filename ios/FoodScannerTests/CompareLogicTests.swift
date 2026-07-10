import Testing
@testable import FoodScanner

/// `ComparePair` — the pure winner/alignment logic behind Compare v1
/// (SCREEN_SPECS §10). These rules decide which side reads higher per metric
/// over integers the backend already computed; they never re-score anything
/// (CLAUDE.md #5). An unscored side must never "win" (honest-state rule), and
/// rows must always align in a fixed order regardless of backend factor order.
@Suite("ComparePair")
struct CompareLogicTests {

    // MARK: Fixtures

    private func factor(_ name: String, _ subScore: Int) -> ScoreFactor {
        ScoreFactor(name: name, subScore: subScore, weight: 0.33,
                    detail: "", sources: [])
    }

    /// Minimal scored product. Pass `factors: nil` for a thin/unscored side.
    private func product(id: String, overall: Int?, factors: [ScoreFactor]?) -> Product {
        let score: ScoreResult? = overall.map { s in
            ScoreResult(score: s, band: ScoreBand.from(score: s), confidence: "high",
                        factors: factors ?? [], scoreVersion: "1.0.0")
        }
        return Product(id: id, barcode: nil, name: "P-\(id)", brand: nil,
                       imageURL: nil, score: score, ingredients: [],
                       allergens: [], dataConfidence: "high")
    }

    // MARK: winner(_:_:)

    @Test("Higher value wins; equal is a tie")
    func winnerBasics() {
        #expect(ComparePair.winner(90, 40) == .a)
        #expect(ComparePair.winner(40, 90) == .b)
        #expect(ComparePair.winner(50, 50) == .tie)
    }

    @Test("An unknown side never wins — honest-state rule")
    func winnerUnknown() {
        #expect(ComparePair.winner(nil, 40) == .tie)
        #expect(ComparePair.winner(40, nil) == .tie)
        #expect(ComparePair.winner(nil, nil) == .tie)
    }

    // MARK: rows

    @Test("Always 4 aligned rows in a fixed order, even with scrambled factors")
    func rowsFixedOrder() {
        // Feed factors in a deliberately scrambled order on both sides.
        let a = product(id: "a", overall: 51, factors: [
            factor("Processing", 55), factor("Nutrition", 30), factor("Additives", 94),
        ])
        let b = product(id: "b", overall: 78, factors: [
            factor("Additives", 100), factor("Processing", 80), factor("Nutrition", 72),
        ])
        let rows = ComparePair(a: a, b: b).rows
        #expect(rows.count == 4)
        #expect(rows.map(\.label) == ["Overall", "Nutrition", "Additives", "Processing"])
    }

    @Test("Per-metric winners read off the aligned rows")
    func rowWinners() {
        let a = product(id: "a", overall: 51, factors: [
            factor("Nutrition", 30), factor("Additives", 94), factor("Processing", 55),
        ])
        let b = product(id: "b", overall: 78, factors: [
            factor("Nutrition", 72), factor("Additives", 100), factor("Processing", 80),
        ])
        let rows = ComparePair(a: a, b: b).rows
        #expect(rows.first { $0.id == "Overall" }?.winner == .b)
        #expect(rows.first { $0.id == "Nutrition" }?.winner == .b)
        #expect(rows.first { $0.id == "Additives" }?.winner == .b)   // 94 vs 100
        #expect(rows.first { $0.id == "Processing" }?.winner == .b)
    }

    @Test("A missing factor on one side ⇒ nil value + tie for that row")
    func missingFactorIsTie() {
        let a = product(id: "a", overall: 51, factors: [
            factor("Nutrition", 30), factor("Processing", 55),   // no Additives
        ])
        let b = product(id: "b", overall: 78, factors: [
            factor("Nutrition", 72), factor("Additives", 100), factor("Processing", 80),
        ])
        let additives = ComparePair(a: a, b: b).rows.first { $0.id == "Additives" }
        #expect(additives?.valueA == nil)
        #expect(additives?.valueB == 100)
        #expect(additives?.winner == .tie)
    }

    @Test("A thin (unscored-factor) side yields nil factor values + ties")
    func thinSideTies() {
        let a = product(id: "a", overall: 51, factors: [
            factor("Nutrition", 30), factor("Additives", 94), factor("Processing", 55),
        ])
        // Overall present but no factor breakdown (mirrors a thin pantry entry).
        let b = product(id: "b", overall: 78, factors: [])
        let rows = ComparePair(a: a, b: b).rows
        #expect(rows.first { $0.id == "Overall" }?.winner == .b)     // overall still compares
        #expect(rows.first { $0.id == "Nutrition" }?.valueB == nil)
        #expect(rows.first { $0.id == "Nutrition" }?.winner == .tie)
        #expect(rows.first { $0.id == "Processing" }?.winner == .tie)
    }

    // MARK: overallWinner

    @Test("Overall winner is the higher-scoring side")
    func overallWinner() {
        let pair = ComparePair(a: .sampleScored, b: .sampleScoredHigh)  // 51 vs 78
        #expect(pair.overallWinner == .b)
        #expect(ComparePair(a: .sampleScoredHigh, b: .sampleScored).overallWinner == .a)
    }

    // MARK: ScoreBand.tint (single band→token color source)

    @Test("Each band maps to its non-alarmist Theme token")
    func bandTint() {
        #expect(ScoreBand.high.tint == Theme.scoreHigh)
        #expect(ScoreBand.mid.tint == Theme.scoreMid)
        #expect(ScoreBand.low.tint == Theme.scoreLow)      // clay, never red
        #expect(ScoreBand.unknown.tint == Theme.scoreUnknown)
    }
}
