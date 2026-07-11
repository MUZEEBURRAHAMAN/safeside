import Foundation
import Testing
@testable import FoodScanner

/// `CategoryService.rank` is the pure heart of the Categories feature: join
/// products to their current score, keep ONLY high-confidence, current-version
/// rows, dedup by product, and sort best-first. "Best in category" is defined
/// entirely here — by OUR sourced score, never a lab/agency verdict. These tests
/// pin every honesty rule (drop limited-confidence, drop stale versions,
/// score-desc, unique, capped).
@Suite("CategoryService.rank")
struct CategoryRankingTests {

    private let version = Scoring.currentVersion

    private func product(_ id: String, name: String) -> ProductRow {
        ProductRow(
            id: id,
            barcode: "barcode-\(id)",
            name: name,
            brand: "Brand",
            images: nil,
            allergensTags: nil,
            dataConfidence: "high"
        )
    }

    private func score(
        _ productID: String,
        _ value: Int,
        confidence: String = "high",
        version: String? = nil
    ) -> ScoreResultRow {
        ScoreResultRow(
            id: "score-\(productID)",
            productID: productID,
            score: value,
            band: ScoreBand.from(score: value),
            confidence: confidence,
            scoreVersion: version ?? Scoring.currentVersion,
            computedAt: Date()
        )
    }

    @Test("Ranks best-first")
    func sortsScoreDescending() {
        let products = [product("a", name: "Cola"), product("b", name: "Zero"), product("c", name: "Water")]
        let scores = [score("a", 28), score("b", 41), score("c", 97)]

        let ranked = CategoryService.rank(products: products, scores: scores)

        #expect(ranked.map(\.id) == ["c", "b", "a"])
        #expect(ranked.map(\.score) == [97, 41, 28])
    }

    @Test("Drops limited-confidence rows (high-confidence only)")
    func dropsLimitedConfidence() {
        let products = [product("a", name: "A"), product("b", name: "B")]
        let scores = [score("a", 80), score("b", 90, confidence: "limited")]

        let ranked = CategoryService.rank(products: products, scores: scores)

        #expect(ranked.map(\.id) == ["a"])
    }

    @Test("Drops stale-version scores (current version only)")
    func dropsStaleVersion() {
        let products = [product("a", name: "A"), product("b", name: "B")]
        let scores = [score("a", 70), score("b", 95, version: "0.9.0")]

        let ranked = CategoryService.rank(products: products, scores: scores)

        #expect(ranked.map(\.id) == ["a"])
    }

    @Test("Dedups by product id — a product matching two tags appears once")
    func dedupsByProduct() {
        // The overlap query can return the same product twice; the latest score
        // view yields one score row. Result must contain the product once.
        let products = [product("a", name: "A"), product("a", name: "A")]
        let scores = [score("a", 55)]

        let ranked = CategoryService.rank(products: products, scores: scores)

        #expect(ranked.count == 1)
        #expect(ranked.first?.id == "a")
    }

    @Test("Products with no current score are excluded")
    func excludesUnscored() {
        let products = [product("a", name: "A"), product("b", name: "B")]
        let scores = [score("a", 60)] // b has no score

        let ranked = CategoryService.rank(products: products, scores: scores)

        #expect(ranked.map(\.id) == ["a"])
    }

    @Test("Caps the result count")
    func capsResults() {
        let products = (0..<80).map { product("p\($0)", name: "P\($0)") }
        let scores = (0..<80).map { score("p\($0)", $0 % 100) }

        let ranked = CategoryService.rank(products: products, scores: scores, limit: 50)

        #expect(ranked.count == 50)
    }

    @Test("Ties break deterministically by name")
    func stableTieBreak() {
        let products = [product("a", name: "Beta"), product("b", name: "Alpha")]
        let scores = [score("a", 50), score("b", 50)]

        let ranked = CategoryService.rank(products: products, scores: scores)

        // Equal score → alphabetical name, so order is stable across runs.
        #expect(ranked.map(\.name) == ["Alpha", "Beta"])
    }

    @Test("verifiedBy is empty — no fabricated agency claim")
    func verifiedByIsAlwaysEmpty() {
        let ranked = CategoryService.rank(
            products: [product("a", name: "A")],
            scores: [score("a", 88)]
        )
        #expect(ranked.first?.verifiedBy.isEmpty == true)
    }

    @Test("Empty input yields empty output (honest empty state)")
    func emptyInput() {
        #expect(CategoryService.rank(products: [], scores: []).isEmpty)
    }
}
