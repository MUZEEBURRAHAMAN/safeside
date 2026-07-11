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
            scoreVersion: "1.0.0",
            highlights: NutrientHighlights(
                watchOuts: [
                    MeterRow(label: "Saturated fat", value: 3.1, unit: "g", tier: "moderate",
                             meterFraction: 0.62, kind: "watchOut",
                             sources: [Source(name: "FSA nutrient thresholds (via Open Food Facts)",
                                              url: "https://world.openfoodfacts.org/nutriscore")]),
                    MeterRow(label: "Salt", value: 1.2, unit: "g", tier: "moderate",
                             meterFraction: 0.8, kind: "watchOut",
                             sources: [Source(name: "FSA nutrient thresholds (via Open Food Facts)", url: nil)]),
                ],
                benefits: [
                    MeterRow(label: "Fiber", value: 3.4, unit: "g", tier: "good source",
                             meterFraction: 0.57, kind: "benefit",
                             sources: [Source(name: "Nutri-Score nutrient model (via Open Food Facts)", url: nil)]),
                ],
                toKnowAboutCount: 1,
                beneficialCount: 1
            )
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
                confidence: "high",
                category: "Flavour enhancers"
            ),
            Ingredient(
                name: "Sulphite ammonia caramel",
                what: "A caramel colour (E150d) made with ammonium and sulphite compounds.",
                whyUsed: "Gives cola and snack coatings their brown colour.",
                safety: "An ADI is set; some processing by-products are under ongoing review.",
                riskTier: "higher",
                whoShouldAvoid: ["people advised to limit sulphites"],
                misconceptions: [],
                foundIn: ["colas", "sauces", "savoury snacks"],
                sources: [Source(name: "EFSA re-evaluation of caramel colours, 2011", url: "https://www.efsa.europa.eu/")],
                confidence: "high",
                category: "Colours"
            ),
            Ingredient(
                name: "Natural flavouring",
                what: nil, whyUsed: nil, safety: nil, riskTier: nil,
                whoShouldAvoid: [], misconceptions: [], foundIn: [],
                sources: [], confidence: "limited"
            ),
        ],
        allergens: ["milk"],
        dataConfidence: "limited",
        fetchedAt: "2026-07-08T12:00:00Z"
    )

    /// A clearly higher-scoring second product, so Compare (Chunk 5) previews
    /// and the screenshot matrix show a real two-column contrast with an
    /// unambiguous overall winner. Every factor is higher than `sampleScored`'s.
    static let sampleScoredHigh = Product(
        id: "sample-2",
        barcode: "3017620422003",
        name: "Lightly Salted Rice Cakes",
        brand: "Kallø",
        imageURL: "https://images.openfoodfacts.org/images/products/000/000/000/0001/front_en.400.jpg",
        score: ScoreResult(
            score: 78,
            band: .high,
            confidence: "high",
            factors: [
                ScoreFactor(
                    name: "Nutrition",
                    subScore: 72,
                    weight: 0.35,
                    detail: "Nutri-Score B maps to 72 out of 100 in our nutrient model.",
                    sources: [Source(name: "Nutri-Score nutrient model (via Open Food Facts)",
                                     url: "https://world.openfoodfacts.org/nutriscore")]
                ),
                ScoreFactor(
                    name: "Additives",
                    subScore: 100,
                    weight: 0.15,
                    detail: "No additives of concern detected.",
                    sources: [Source(name: "Curated additive review table v1.0 (EFSA / FDA / JECFA)", url: nil)]
                ),
                ScoreFactor(
                    name: "Processing",
                    subScore: 80,
                    weight: 0.50,
                    detail: "NOVA 2 (processed culinary ingredient) maps to 80 out of 100.",
                    sources: [Source(name: "NOVA classification (via Open Food Facts)",
                                     url: "https://world.openfoodfacts.org")]
                ),
            ],
            scoreVersion: "1.0.0",
            highlights: NutrientHighlights(
                watchOuts: [
                    MeterRow(label: "Salt", value: 0.5, unit: "g", tier: "low",
                             meterFraction: 0.33, kind: "watchOut",
                             sources: [Source(name: "FSA nutrient thresholds (via Open Food Facts)", url: nil)]),
                ],
                benefits: [
                    MeterRow(label: "Fiber", value: 4.2, unit: "g", tier: "good source",
                             meterFraction: 0.7, kind: "benefit",
                             sources: [Source(name: "Nutri-Score nutrient model (via Open Food Facts)", url: nil)]),
                ],
                toKnowAboutCount: 0,
                beneficialCount: 1
            )
        ),
        ingredients: [
            Ingredient(
                name: "Wholegrain rice",
                what: "A whole-grain cereal; the base of the cake.",
                whyUsed: "Forms the body and texture of the cake.",
                safety: "A common staple food, considered safe.",
                riskTier: "low",
                whoShouldAvoid: [],
                misconceptions: [],
                foundIn: ["snacks", "cereals"],
                sources: [Source(name: "USDA FoodData Central", url: "https://fdc.nal.usda.gov/")],
                confidence: "high"
            ),
        ],
        allergens: [],
        dataConfidence: "high",
        fetchedAt: "2026-07-09T09:00:00Z"
    )
}
#endif
