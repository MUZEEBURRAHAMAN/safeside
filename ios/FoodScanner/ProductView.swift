import SwiftUI

/// Product result: the app's payoff screen — the trust moment. Score hero
/// (brand moment, §5.2) → sourced "why this score" breakdown (§5.3, the
/// transparency moat) → next action → ingredients → attribution.
/// Never a dead-end (principle #4); every score is sourced and dose-aware.
struct ProductView: View {
    let product: Product

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var heroVisible = false

    private var band: ScoreBand { product.score?.band ?? .unknown }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s5) {
                    identitySection

                    heroSection(proxy: proxy)
                        .opacity(heroVisible ? 1 : 0)
                        .scaleEffect(heroVisible ? 1 : 0.96)
                        .onAppear { revealHero() }

                    whyScoreOrNote
                        .id("whyScore")

                    // Next action — never a dead-end, even when the swaps
                    // engine isn't built yet (stubbed for now).
                    NextActionButton("See a better option", systemImage: "arrow.triangle.2.circlepath") {
                        // TODO: wire to the swaps engine once it exists.
                    }

                    ingredientsSection

                    AttributionFooter()
                }
                .padding(.horizontal, Theme.Space.s4)
                .padding(.vertical, Theme.Space.s5)
            }
            .background(Theme.canvas)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: Sections

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s3) {
            HStack(alignment: .top, spacing: Theme.Space.s3) {
                ProductThumbnail(urlString: product.imageURL)
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let brand = product.brand, !brand.isEmpty {
                        Text(brand)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }

            if !product.allergens.isEmpty {
                AllergenChipsRow(allergens: product.allergens)
            }
        }
    }

    private func heroSection(proxy: ScrollViewProxy) -> some View {
        ScoreHeroSection(
            score: product.score?.score,
            band: band,
            confidence: product.score?.confidence,
            onInfoTap: {
                let animation: Animation? = reduceMotion ? nil : .easeInOut(duration: 0.3)
                withAnimation(animation) {
                    proxy.scrollTo("whyScore", anchor: .top)
                }
            }
        )
    }

    @ViewBuilder
    private var whyScoreOrNote: some View {
        if let score = product.score {
            WhyScoreCard(score: score)
        } else {
            SectionCard {
                VStack(alignment: .leading, spacing: Theme.Space.s2) {
                    Text("Why this score")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("We don't have enough data yet to break this product down. Once more details come in, you'll see the full processing, nutrition, and additive breakdown here.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s3) {
            Text("Ingredients")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            if product.ingredients.isEmpty {
                EmptyIngredientsView()
            } else {
                SectionCard {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(product.ingredients.enumerated()), id: \.element.id) { index, ingredient in
                            IngredientRow(ingredient: ingredient)
                            if index < product.ingredients.count - 1 {
                                HairlineDivider()
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Motion

    /// Calm fade/scale reveal only (§7) — no bounce, and skipped entirely
    /// under Reduce Motion.
    private func revealHero() {
        guard !heroVisible else { return }
        if reduceMotion {
            heroVisible = true
        } else {
            withAnimation(.easeOut(duration: 0.28)) { heroVisible = true }
        }
    }
}

// MARK: - Previews

#if DEBUG

#Preview("High score — full confidence") {
    NavigationStack {
        ProductView(product: .previewHighFullConfidence)
    }
}

#Preview("Low score — limited confidence") {
    NavigationStack {
        ProductView(product: .previewLowLimitedConfidence)
    }
}

#Preview("Unknown score") {
    NavigationStack {
        ProductView(product: .previewUnknownScore)
    }
}

fileprivate extension Product {
    static let previewHighFullConfidence = Product(
        id: "1",
        barcode: "0123456789012",
        name: "Organic Rolled Oats",
        brand: "Fieldbrook Farms",
        imageURL: "https://images.openfoodfacts.org/images/products/012/345/678/9012/front_en.400.jpg",
        score: ScoreResult(
            score: 88,
            band: .high,
            confidence: "high",
            factors: [
                ScoreFactor(
                    name: "Processing",
                    subScore: 100,
                    weight: 0.50,
                    detail: "NOVA group 1 — unprocessed or minimally processed.",
                    sources: [Source(name: "Open Food Facts (NOVA)", url: "https://world.openfoodfacts.org")]
                ),
                ScoreFactor(
                    name: "Nutrition",
                    subScore: 82,
                    weight: 0.35,
                    detail: "Nutri-Score B — high fiber, low sugar and saturated fat.",
                    sources: [Source(name: "Open Food Facts (Nutri-Score)", url: "https://world.openfoodfacts.org")]
                ),
                ScoreFactor(
                    name: "Additives",
                    subScore: 100,
                    weight: 0.15,
                    detail: "No additives detected.",
                    sources: [Source(name: "Open Food Facts", url: nil)]
                )
            ],
            scoreVersion: "1.0"
        ),
        ingredients: [
            Ingredient(
                name: "Whole grain oats",
                what: "A minimally processed whole grain.",
                whyUsed: "Base grain — provides fiber and structure.",
                safety: "Generally recognized as safe.",
                riskTier: "low",
                whoShouldAvoid: ["People with celiac disease should confirm gluten-free certification."],
                misconceptions: [],
                foundIn: ["Granola", "Oat milk", "Baked goods"],
                sources: [Source(name: "USDA FoodData Central", url: "https://fdc.nal.usda.gov")],
                confidence: "high"
            )
        ],
        allergens: [],
        dataConfidence: "high"
    )

    static let previewLowLimitedConfidence = Product(
        id: "2",
        barcode: "9876543210123",
        name: "Frosted Fruit Rings Cereal",
        brand: "Sunny Pantry",
        imageURL: nil,
        score: ScoreResult(
            score: 27,
            band: .low,
            confidence: "limited",
            factors: [
                ScoreFactor(
                    name: "Processing",
                    subScore: 20,
                    weight: 0.50,
                    detail: "NOVA group 4 — ultra-processed.",
                    sources: [Source(name: "Open Food Facts (NOVA)", url: "https://world.openfoodfacts.org")]
                ),
                ScoreFactor(
                    name: "Nutrition",
                    subScore: 30,
                    weight: 0.35,
                    detail: "Nutri-Score D — high in added sugar.",
                    sources: [Source(name: "Open Food Facts (Nutri-Score)", url: "https://world.openfoodfacts.org")]
                ),
                ScoreFactor(
                    name: "Additives",
                    subScore: 46,
                    weight: 0.15,
                    detail: "2 additives found: 1 moderate-concern, 1 low-concern.",
                    sources: [Source(name: "Additives risk table v1", url: nil)]
                )
            ],
            scoreVersion: "1.0"
        ),
        ingredients: [],
        allergens: ["Milk", "Wheat"],
        dataConfidence: "limited"
    )

    static let previewUnknownScore = Product(
        id: "3",
        barcode: "5555555555555",
        name: "Imported Rice Crackers",
        brand: nil,
        imageURL: nil,
        score: nil,
        ingredients: [],
        allergens: [],
        dataConfidence: "limited"
    )
}

#endif
