import Testing
@testable import FoodScanner

/// `SearchQuery.classify` decides whether typed input is a barcode (route
/// straight to the scored `/product/:barcode` path — identical to a live
/// scan), a name (hit `/search`), or empty (show recents). The digit bounds
/// (6–14) must match the backend `BARCODE_RE` exactly, so a typed barcode and
/// a scanned one are treated the same everywhere.
@Suite("SearchQuery.classify")
struct SearchLogicTests {

    @Test("6–14 digit input is a barcode (whitespace trimmed)")
    func barcodes() {
        #expect(SearchQuery.classify("3017620422003") == .barcode("3017620422003"))
        #expect(SearchQuery.classify("  3017620422003  ") == .barcode("3017620422003"))
        #expect(SearchQuery.classify("123456") == .barcode("123456"))       // 6 = lower bound
        #expect(SearchQuery.classify("12345678901234") == .barcode("12345678901234")) // 14 = upper bound
    }

    @Test("Text input is a name")
    func names() {
        #expect(SearchQuery.classify("nutella") == .name("nutella"))
        #expect(SearchQuery.classify("  Greek Yogurt ") == .name("Greek Yogurt"))
        #expect(SearchQuery.classify("7up") == .name("7up"))        // mixed digits+letters
        #expect(SearchQuery.classify("100% juice") == .name("100% juice"))
    }

    @Test("Blank / whitespace is empty")
    func empties() {
        #expect(SearchQuery.classify("") == .empty)
        #expect(SearchQuery.classify("    ") == .empty)
        #expect(SearchQuery.classify("\n\t") == .empty)
    }

    @Test("Digit-count boundaries: 5 too short, 15 too long → name")
    func boundaries() {
        #expect(SearchQuery.classify("12345") == .name("12345"))                 // 5 digits: too short
        #expect(SearchQuery.classify("123456789012345") == .name("123456789012345")) // 15 digits: too long
    }
}
