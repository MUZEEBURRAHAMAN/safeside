import Foundation
import Testing
@testable import FoodScanner

/// Locks the Chunk-1 wire contract: `score.highlights` (Watch-outs / Benefits
/// meters + counts), `fetchedAt`, and an ingredient `category` all decode from
/// what the backend now sends — and a response WITHOUT those keys still decodes
/// (backward compatible with pre-Chunk-1 cached responses and OCR products).
///
/// The client never computes these numbers (CLAUDE.md #5); it only decodes and
/// renders what the backend computed. These tests assert the decode, not any math.
@Suite("Highlights / category / fetchedAt decoding")
struct HighlightsDecodingTests {

    @Test("Decodes score.highlights, fetchedAt, and an additive category")
    func decodesHighlights() throws {
        let json = """
        {
          "id": "prod_hl",
          "barcode": "3017620422003",
          "name": "Hazelnut Spread",
          "brand": "Acme",
          "imageURL": null,
          "fetchedAt": "2026-07-08T12:00:00Z",
          "score": {
            "score": 29,
            "band": "low",
            "confidence": "high",
            "factors": [],
            "scoreVersion": "1.1.0",
            "highlights": {
              "watchOuts": [
                {
                  "label": "Saturated fat",
                  "value": 26.7,
                  "unit": "g",
                  "tier": "high",
                  "meterFraction": 1.0,
                  "kind": "watchOut",
                  "sources": [
                    { "name": "FSA nutrient thresholds (via Open Food Facts)", "url": "https://world.openfoodfacts.org/nutriscore" }
                  ]
                }
              ],
              "benefits": [
                {
                  "label": "Fiber",
                  "value": 4.5,
                  "unit": "g",
                  "tier": "good source",
                  "meterFraction": 0.75,
                  "kind": "benefit",
                  "sources": [
                    { "name": "Nutri-Score nutrient model (via Open Food Facts)", "url": null }
                  ]
                }
              ],
              "toKnowAboutCount": 2,
              "beneficialCount": 1
            }
          },
          "ingredients": [
            {
              "name": "Sodium benzoate",
              "what": "A preservative.",
              "whyUsed": null,
              "safety": null,
              "riskTier": "moderate",
              "whoShouldAvoid": [],
              "misconceptions": [],
              "foundIn": [],
              "sources": [],
              "confidence": "high",
              "category": "Preservatives"
            }
          ],
          "allergens": [],
          "dataConfidence": "high"
        }
        """.data(using: .utf8)!

        let product = try JSONDecoder().decode(Product.self, from: json)

        #expect(product.fetchedAt == "2026-07-08T12:00:00Z")

        let highlights = try #require(product.score?.highlights)
        let watchOut = try #require(highlights.watchOuts.first)
        #expect(watchOut.label == "Saturated fat")
        #expect(watchOut.value == 26.7)
        #expect(watchOut.unit == "g")
        #expect(watchOut.tier == "high")
        #expect(watchOut.meterFraction == 1.0)
        #expect(watchOut.kind == "watchOut")
        #expect(watchOut.sources.first?.name == "FSA nutrient thresholds (via Open Food Facts)")

        let benefit = try #require(highlights.benefits.first)
        #expect(benefit.tier == "good source")
        #expect(benefit.meterFraction == 0.75)

        #expect(highlights.toKnowAboutCount == 2)
        #expect(highlights.beneficialCount == 1)

        let ingredient = try #require(product.ingredients.first)
        #expect(ingredient.category == "Preservatives")
    }

    @Test("A response without highlights / category / fetchedAt still decodes (nil)")
    func decodesWithoutNewKeys() throws {
        let json = """
        {
          "id": "prod_old",
          "barcode": "0000000000000",
          "name": "Legacy Cached Product",
          "brand": null,
          "imageURL": null,
          "score": {
            "score": 82,
            "band": "high",
            "confidence": "high",
            "factors": [],
            "scoreVersion": "1.1.0"
          },
          "ingredients": [
            {
              "name": "Oats",
              "what": null,
              "whyUsed": null,
              "safety": null,
              "riskTier": "low",
              "whoShouldAvoid": [],
              "misconceptions": [],
              "foundIn": [],
              "sources": [],
              "confidence": "high"
            }
          ],
          "allergens": [],
          "dataConfidence": "high"
        }
        """.data(using: .utf8)!

        let product = try JSONDecoder().decode(Product.self, from: json)
        #expect(product.fetchedAt == nil)
        #expect(product.score?.highlights == nil)
        #expect(product.ingredients.first?.category == nil)
    }
}
