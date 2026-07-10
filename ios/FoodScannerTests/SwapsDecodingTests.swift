import Foundation
import Testing
@testable import FoodScanner

/// Locks the Chunk-3 wire contract: the `GET swaps/product/:id/swaps` body
/// decodes into `SwapsResponse` / `SwapCandidate` exactly. The client never
/// computes `delta` or the `whyBetter` facts (CLAUDE.md #5) — the backend does,
/// from DB diffs — so these tests assert the decode + band mapping only, never
/// any score math.
@Suite("Swaps response decoding")
struct SwapsDecodingTests {

    @Test("Decodes a loaded response with ranked candidates")
    func decodesLoaded() throws {
        let json = """
        {
          "category": "Chocolate spreads",
          "subjectScore": 29,
          "filteredForAllergies": true,
          "thin": false,
          "swaps": [
            {
              "id": "prod-a",
              "barcode": "9990000000002",
              "name": "Simple Hazelnut Butter",
              "brand": "DemoBrand",
              "imageURL": null,
              "score": 78,
              "band": "high",
              "delta": 49,
              "inPantry": true,
              "whyBetter": ["No colours E150d", "lower saturated fat"]
            },
            {
              "id": "prod-b",
              "barcode": "9990000000004",
              "name": "Almond Choc Spread",
              "brand": null,
              "imageURL": null,
              "score": 71,
              "band": "mid",
              "delta": 42,
              "inPantry": false,
              "whyBetter": []
            }
          ]
        }
        """.data(using: .utf8)!

        let resp = try JSONDecoder().decode(SwapsResponse.self, from: json)
        #expect(resp.category == "Chocolate spreads")
        #expect(resp.subjectScore == 29)
        #expect(resp.filteredForAllergies == true)
        #expect(resp.thin == false)
        #expect(resp.swaps.count == 2)

        let first = resp.swaps[0]
        #expect(first.id == "prod-a")
        #expect(first.barcode == "9990000000002")
        #expect(first.score == 78)
        #expect(first.band == .high)          // "high" → .high round-trip
        #expect(first.delta == 49)
        #expect(first.inPantry == true)
        #expect(first.whyBetter == ["No colours E150d", "lower saturated fat"])

        let second = resp.swaps[1]
        #expect(second.band == .mid)          // "mid" → .mid round-trip
        #expect(second.brand == nil)
        #expect(second.whyBetter.isEmpty)
    }

    @Test("Decodes the honest empty / thin response (null category, no swaps)")
    func decodesEmpty() throws {
        let json = """
        {
          "category": null,
          "subjectScore": 40,
          "filteredForAllergies": false,
          "thin": true,
          "swaps": []
        }
        """.data(using: .utf8)!

        let resp = try JSONDecoder().decode(SwapsResponse.self, from: json)
        #expect(resp.category == nil)
        #expect(resp.thin == true)
        #expect(resp.filteredForAllergies == false)
        #expect(resp.swaps.isEmpty)
    }
}
