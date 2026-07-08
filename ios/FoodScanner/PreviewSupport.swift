#if DEBUG
import Foundation

/// Sample data for #Previews AND for the on-simulator screenshot harness
/// (see FoodScannerApp: launch with env `SHOW_SAMPLE_RESULT=1` to boot straight
/// into a populated ProductView so detail screens can be verified without a
/// live scan/tap). DEBUG-only — never compiled into release.
extension Product {
    static let sampleScored = Product(
        id: "sample-1",
        barcode: "5000159407236",
        name: "Sea Salt Popped Corn Chips",
        brand: "PopCorners",
        imageURL: "https://images.openfoodfacts.org/images/products/000/000/000/0000/front_en.400.jpg",
        score: ScoreResult(
            score: 51,
            band: .mid,
            confidence: "limited",
            factors: [
                ScoreFactor(
                    name: "Nutrition",
                    subScore: 30,
                    weight: 0.35,
                    detail: "Nutri-Score D maps to 30 out of 100 in our nutrient model.",
                    sources: [Source(name: "Nutri-Score nutrient model (via Open Food Facts)",
                                     url: "https://world.openfoodfacts.org/nutriscore")]
                ),
                ScoreFactor(
                    name: "Additives",
                    subScore: 94,
                    weight: 0.15,
                    detail: "One moderate-concern additive; well above the floor.",
                    sources: [Source(name: "Curated additive review table v1.0 (EFSA / FDA / JECFA)", url: nil)]
                ),
                ScoreFactor(
                    name: "Processing",
                    subScore: 55,
                    weight: 0.50,
                    detail: "NOVA 3 (processed food) maps to 55 out of 100.",
                    sources: [Source(name: "NOVA classification (via Open Food Facts)",
                                     url: "https://world.openfoodfacts.org")]
                ),
            ],
            scoreVersion: "1.0.0"
        ),
        ingredients: [
            Ingredient(
                name: "Corn",
                what: "A whole-grain cereal; the base of the chip.",
                whyUsed: "Forms the body and texture of the snack.",
                safety: "A common staple food, considered safe.",
                riskTier: "low",
                whoShouldAvoid: [],
                misconceptions: [],
                foundIn: ["snacks", "tortillas", "cereals"],
                sources: [Source(name: "USDA FoodData Central", url: "https://fdc.nal.usda.gov/")],
                confidence: "high"
            ),
            Ingredient(
                name: "Monosodium glutamate",
                what: "A flavour enhancer (the sodium salt of glutamic acid).",
                whyUsed: "Adds a savoury, umami taste.",
                safety: "Considered safe at typical intakes by EFSA and the FDA; an ADI exists.",
                riskTier: "moderate",
                whoShouldAvoid: ["people advised to limit sodium"],
                misconceptions: ["A general 'MSG sensitivity' is not supported by controlled studies."],
                foundIn: ["savoury snacks", "seasonings", "soups"],
                sources: [Source(name: "EFSA re-evaluation, 2017", url: "https://www.efsa.europa.eu/")],
                confidence: "high"
            ),
            Ingredient(
                name: "Natural flavouring",
                what: nil, whyUsed: nil, safety: nil, riskTier: nil,
                whoShouldAvoid: [], misconceptions: [], foundIn: [],
                sources: [], confidence: "limited"
            ),
        ],
        allergens: ["milk"],
        dataConfidence: "limited"
    )
}
#endif
