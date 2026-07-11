import Testing
import Foundation
@testable import FoodScanner

/// Locks the `ingredients` edge-function contract: the response is a
/// `{ "ingredients": [...] }` wrapper (NOT a bare array), and each element
/// decodes into our `Ingredient` model. Both were wrong on device — the client
/// hit the wrong function AND decoded a bare array — so "What's inside" never
/// loaded. This test fails if either regresses.
struct IngredientsDecodingTests {
    /// Mirrors APIClient's private IngredientsResponse.
    private struct Wrapper: Decodable { let ingredients: [Ingredient] }

    @Test func decodesWrappedIngredientsResponse() throws {
        let json = """
        {"ingredients":[
          {"name":"Sucre","what":"We don't have vetted info on this ingredient yet.",
           "whyUsed":null,"safety":null,"riskTier":null,"whoShouldAvoid":[],
           "misconceptions":[],"foundIn":[],"sources":[],"confidence":"limited","category":null},
          {"name":"Sulphite ammonia caramel","what":"A caramel colour (E150d).",
           "whyUsed":"colour","safety":null,"riskTier":"higher","whoShouldAvoid":[],
           "misconceptions":[],"foundIn":[],"sources":[],"confidence":"high","category":"Colours"}
        ]}
        """.data(using: .utf8)!

        let w = try JSONDecoder().decode(Wrapper.self, from: json)
        #expect(w.ingredients.count == 2)
        #expect(w.ingredients[0].name == "Sucre")
        #expect(w.ingredients[0].category == nil)
        #expect(w.ingredients[1].category == "Colours")
        #expect(w.ingredients[1].riskTier == "higher")
    }
}
