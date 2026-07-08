import SwiftUI

/// Product result: the app's payoff screen — the trust moment. Score hero
/// (brand moment, §5.2) → sourced "why this score" breakdown (§5.3, the
/// transparency moat) → next action → ingredients → attribution.
/// Never a dead-end (principle #4); every score is sourced and dose-aware.
struct ProductView: View {
    let product: Product

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionService.self) private var session
    @Environment(PantryService.self) private var pantryService

    @State private var heroVisible = false

    /// Working copy of `product`. `product` itself never changes (it's the
    /// caller's contract), but a pantry-list entry arrives "thin" — score
    /// with no `factors`, no `ingredients` — so this view fills in the rest
    /// in the background without ever blocking the initial render.
    @State private var workingProduct: Product

    /// Ingredients fetched lazily via `APIClient.ingredients(productID:)`,
    /// kept separate from `workingProduct.ingredients` per the lazy-load
    /// contract; `displayIngredients` below reconciles the two sources.
    @State private var fetchedIngredients: [Ingredient] = []
    @State private var ingredientsPhase: IngredientsLoadPhase = .idle

    @State private var showBetterOptionSheet = false

    private enum IngredientsLoadPhase: Equatable { case idle, loading, failed }

    init(product: Product) {
        self.product = product
        _workingProduct = State(initialValue: product)
    }

    private var band: ScoreBand { workingProduct.score?.band ?? .unknown }

    /// A pantry-list read has a `score` with empty `factors` (see
    /// `PantryEntry.asProduct()`); an unscored product has no `score` at
    /// all. Both count as "thin" and are worth a background re-fetch.
    private var hasThinScore: Bool {
        workingProduct.score?.factors.isEmpty ?? true
    }

    private var displayIngredients: [Ingredient] {
        workingProduct.ingredients.isEmpty ? fetchedIngredients : workingProduct.ingredients
    }

    private var apiClient: APIClient { APIClient(session: session) }

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

                    // Next action — never a dead-end. The swaps engine isn't
                    // built yet (Phase 3), so this opens a calm sheet with a
                    // real, generic next step instead of a fabricated swap.
                    NextActionButton("See a better option", systemImage: "arrow.triangle.2.circlepath") {
                        showBetterOptionSheet = true
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
        .sheet(isPresented: $showBetterOptionSheet) {
            NextActionSheet(band: band) {
                showBetterOptionSheet = false
                dismiss()
            }
        }
        .task {
            // Order matters: the pantry re-fetch can itself populate
            // ingredients, so the lazy ingredients load only hits the
            // network if that didn't already happen.
            await refreshThinPantryDataIfNeeded()
            await loadIngredientsIfNeeded()
        }
    }

    // MARK: Sections

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s3) {
            HStack(alignment: .top, spacing: Theme.Space.s3) {
                ProductThumbnail(urlString: workingProduct.imageURL)
                VStack(alignment: .leading, spacing: 2) {
                    Text(workingProduct.name)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let brand = workingProduct.brand, !brand.isEmpty {
                        Text(brand)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: Theme.Space.s2)
                favoriteButton
            }

            if !workingProduct.allergens.isEmpty {
                AllergenChipsRow(allergens: workingProduct.allergens)
            }
        }
    }

    /// Brand-tinted (not alarm-colored) heart toggle. Reads
    /// `pantryService.isFavorite(_:)` directly in `body` (rather than
    /// mirroring it into local `@State`) so it stays in sync whenever the
    /// `@Observable` PantryService's backing data changes elsewhere.
    private var favoriteButton: some View {
        let isFavorite = pantryService.isFavorite(workingProduct.id)
        return Button {
            Task { await pantryService.toggleFavorite(productID: workingProduct.id) }
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.greenDeep)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
    }

    private func heroSection(proxy: ScrollViewProxy) -> some View {
        ScoreHeroSection(
            score: workingProduct.score?.score,
            band: band,
            confidence: workingProduct.score?.confidence,
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
        if let score = workingProduct.score, !score.factors.isEmpty {
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

            switch ingredientsPhase {
            case .loading:
                IngredientsSkeletonView()
            case .failed:
                IngredientsLoadErrorView {
                    Task { await loadIngredientsIfNeeded(forceRetry: true) }
                }
            case .idle:
                if displayIngredients.isEmpty {
                    EmptyIngredientsView()
                } else {
                    SectionCard {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(displayIngredients.enumerated()), id: \.element.id) { index, ingredient in
                                IngredientRow(ingredient: ingredient)
                                if index < displayIngredients.count - 1 {
                                    HairlineDivider()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Data loading

    /// Pantry-detail fix: a product opened from the pantry list arrives with
    /// an empty `factors`/`ingredients` (a "thin" read — see
    /// `PantryEntry.asProduct()`). Re-fetch the full product by barcode and
    /// merge in whatever's missing, without ever overwriting data that's
    /// already full.
    private func refreshThinPantryDataIfNeeded() async {
        guard hasThinScore, let barcode = workingProduct.barcode, !barcode.isEmpty else { return }
        do {
            let fresh = try await apiClient.product(barcode: barcode)
            mergeFullProduct(fresh)
        } catch {
            // Silent by design: this is background enrichment on top of a
            // screen that's already showing whatever the pantry list had.
            // A calm, already-visible result beats an error banner here.
        }
    }

    private func mergeFullProduct(_ fresh: Product) {
        let mergedScore: ScoreResult?
        if let current = workingProduct.score, !current.factors.isEmpty {
            mergedScore = current // already full — never regress
        } else {
            mergedScore = fresh.score ?? workingProduct.score
        }

        workingProduct = Product(
            id: workingProduct.id,
            barcode: workingProduct.barcode,
            name: workingProduct.name,
            brand: workingProduct.brand ?? fresh.brand,
            imageURL: workingProduct.imageURL ?? fresh.imageURL,
            score: mergedScore,
            ingredients: workingProduct.ingredients.isEmpty ? fresh.ingredients : workingProduct.ingredients,
            allergens: workingProduct.allergens.isEmpty ? fresh.allergens : workingProduct.allergens,
            dataConfidence: fresh.dataConfidence
        )
    }

    /// Lazy-loads AI ingredient explanations (backend now returns additive +
    /// text explanations). Never runs if ingredients are already present —
    /// either from the initial `product`, or filled in by the pantry
    /// re-fetch above.
    private func loadIngredientsIfNeeded(forceRetry: Bool = false) async {
        guard workingProduct.ingredients.isEmpty else { return }
        guard forceRetry || fetchedIngredients.isEmpty else { return }
        ingredientsPhase = .loading
        do {
            let result = try await apiClient.ingredients(productID: workingProduct.id)
            fetchedIngredients = result
            ingredientsPhase = .idle
        } catch {
            ingredientsPhase = .failed
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
    .environment(SessionService())
    .environment(PantryService(session: SessionService()))
}

#Preview("Low score — limited confidence") {
    NavigationStack {
        ProductView(product: .previewLowLimitedConfidence)
    }
    .environment(SessionService())
    .environment(PantryService(session: SessionService()))
}

#Preview("Unknown score") {
    NavigationStack {
        ProductView(product: .previewUnknownScore)
    }
    .environment(SessionService())
    .environment(PantryService(session: SessionService()))
}

#Preview("From pantry — thin read") {
    NavigationStack {
        ProductView(product: .previewFromPantryThin)
    }
    .environment(SessionService())
    .environment(PantryService(session: SessionService()))
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

    /// Mirrors `PantryEntry.asProduct()`'s thin read: a real `score` (so the
    /// hero shows a number/band immediately) but empty `factors` and empty
    /// `ingredients` — this is exactly the shape that should trigger
    /// `refreshThinPantryDataIfNeeded()` on appear.
    static let previewFromPantryThin = Product(
        id: "4",
        barcode: "1112223334445",
        name: "Sourdough Bread",
        brand: "Corner Bakery",
        imageURL: nil,
        score: ScoreResult(score: 71, band: .mid, confidence: "high", factors: [], scoreVersion: "1.0"),
        ingredients: [],
        allergens: ["Wheat"],
        dataConfidence: "high"
    )
}

#endif
