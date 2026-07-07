import Foundation
import Testing
@testable import FoodScanner

/// Decodes canned backend responses per docs/BACKEND_SPEC.md /
/// docs/DATA_MODEL.md into our client models. Scoring math itself is the
/// backend's job (never the LLM, never the client) — these tests only cover
/// the wire contract: does `Product`/`ScoreResult` decode what the backend
/// actually sends?
@Suite("Product / ScoreResult decoding")
struct ModelsDecodingTests {

    @Test("Decodes a fully-scored product")
    func decodesScoredProduct() throws {
        let json = """
        {
          "id": "prod_123",
          "barcode": "0123456789012",
          "name": "Rolled Oats",
          "brand": "Acme Foods",
          "imageURL": "https://images.example.com/oats.jpg",
          "score": {
            "score": 82,
            "band": "high",
            "confidence": "high",
            "factors": [
              {
                "name": "Processing",
                "subScore": 90,
                "weight": 0.5,
                "detail": "Minimally processed whole grain.",
                "sources": [
                  { "name": "Open Food Facts", "url": "https://world.openfoodfacts.org" }
                ]
              }
            ],
            "scoreVersion": "1.0.0"
          },
          "ingredients": [
            {
              "name": "Whole grain oats",
              "what": "Oats, rolled.",
              "whyUsed": null,
              "safety": null,
              "riskTier": "low",
              "whoShouldAvoid": [],
              "misconceptions": [],
              "foundIn": ["cereal", "granola"],
              "sources": [],
              "confidence": "high"
            }
          ],
          "allergens": [],
          "dataConfidence": "high"
        }
        """.data(using: .utf8)!

        let product = try JSONDecoder().decode(Product.self, from: json)

        #expect(product.id == "prod_123")
        #expect(product.barcode == "0123456789012")
        #expect(product.name == "Rolled Oats")
        #expect(product.brand == "Acme Foods")
        #expect(product.imageURL == "https://images.example.com/oats.jpg")
        #expect(product.dataConfidence == "high")

        let score = try #require(product.score)
        #expect(score.score == 82)
        #expect(score.band == .high)
        #expect(score.confidence == "high")
        #expect(score.scoreVersion == "1.0.0")

        let factor = try #require(score.factors.first)
        #expect(factor.name == "Processing")
        #expect(factor.subScore == 90)
        #expect(factor.weight == 0.5)
        #expect(factor.sources.first?.name == "Open Food Facts")

        let ingredient = try #require(product.ingredients.first)
        #expect(ingredient.name == "Whole grain oats")
        #expect(ingredient.riskTier == "low")
        #expect(ingredient.foundIn == ["cereal", "granola"])
    }

    @Test("Decodes a product with an unknown band (no score object at all)")
    func decodesUnscoredProduct() throws {
        // Per docs/BACKEND_SPEC.md: the backend omits `score` entirely rather
        // than send a fabricated/placeholder score when the band is unknown.
        let json = """
        {
          "id": "prod_456",
          "barcode": "9876543210987",
          "name": "Mystery Snack",
          "brand": null,
          "imageURL": null,
          "ingredients": [],
          "allergens": ["milk"],
          "dataConfidence": "limited"
        }
        """.data(using: .utf8)!

        let product = try JSONDecoder().decode(Product.self, from: json)

        #expect(product.score == nil)
        #expect(product.brand == nil)
        #expect(product.ingredients.isEmpty)
        #expect(product.allergens == ["milk"])
        #expect(product.dataConfidence == "limited")
    }

    @Test("The needs-OCR 404 body decodes as documented")
    func decodesNeedsOCRErrorShape() throws {
        // Standalone fixture (not `@testable`-reaching into APIClient's private
        // ErrorBody) so this test documents/locks the wire contract itself:
        // a 404 with {"error":"not_found","needsOcr":true} means "prompt OCR",
        // which APIClient.APIError maps to `.needsOCR`.
        struct WireErrorBody: Decodable { let error: String; let needsOcr: Bool }

        let json = #"{"error":"not_found","needsOcr":true}"#.data(using: .utf8)!
        let body = try JSONDecoder().decode(WireErrorBody.self, from: json)

        #expect(body.error == "not_found")
        #expect(body.needsOcr == true)
    }
}
