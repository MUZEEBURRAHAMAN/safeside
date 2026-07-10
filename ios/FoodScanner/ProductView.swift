import SwiftUI

/// Product result: the app's payoff screen — the trust moment. Rebuilt to
/// the Oasis-beating shape in docs/DESIGN_SYSTEM_V3.md §1/§5: a floating
/// product image on the light canvas, a name+brand row with a stroked score
/// RING (never a heavy dark hero), trust chips, a tri-metric row, the sourced
/// "why this score" breakdown (the transparency moat), "what's inside"
/// ingredient cards, allergens, sources, utility rows, and a next action.
/// Never a dead-end (principle #4); every score is sourced and dose-aware.
struct ProductView: View {
    let product: Product

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionService.self) private var session
    @Environment(PantryService.self) private var pantryService
    /// Optional (not `.self`-required) so this view never crashes if a
    /// caller's tree doesn't happen to inject `ProfileService` — a
    /// guest/no-profile viewer of this screen should just see the same
    /// screen as before this feature existed (see `flaggedAllergies` below).
    @Environment(ProfileService.self) private var profileService: ProfileService?
    /// Optional so this screen never crashes in a tree that didn't inject the
    /// logger (previews/tests); analytics is best-effort and non-essential.
    @Environment(AnalyticsLogger.self) private var analytics: AnalyticsLogger?

    @State private var identityVisible = false
    /// Guards `score_viewed` to fire once per appearance (`.task` can re-run).
    @State private var didLogScoreViewed = false

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
    @State private var showMethodologySheet = false
    @State private var showReportIssueSheet = false
    @State private var showChat = false

    /// Compare (Chunk 5): the partner-picker sheet, and the chosen partner that
    /// pushes `CompareView`. `navigationDestination(item:)` clears it on pop.
    /// `Product` isn't `Hashable`, so the pushed value is a light id-keyed box.
    @State private var showComparePicker = false
    @State private var comparePartner: ComparePartnerRoute?

    /// Chunk 2 (Search / deep-link) will flip this on to construct `ProductView`
    /// before the product resolves, showing `ResultSkeletonView`. Today the
    /// caller always passes a fully-fetched `Product`, so this stays false and
    /// behaviour is unchanged.
    @State private var isResolving = false

    /// `.failedOffline` is a calm variant of `.failed` used when the fetch
    /// failed purely because the device is offline — the ingredient sheet then
    /// reframes ("You're offline") instead of implying a server fault, while
    /// the rest of the Result screen stays fully readable (Chunk 6).
    private enum IngredientsLoadPhase: Equatable { case idle, loading, failed, failedOffline }

    init(product: Product) {
        self.product = product
        _workingProduct = State(initialValue: product)
    }

    #if DEBUG
    /// Preview-only: boot straight into the in-flight (skeleton) state so the
    /// screenshot matrix can capture `ResultSkeletonView` inside `ProductView`.
    init(product: Product, previewResolving: Bool) {
        self.product = product
        _workingProduct = State(initialValue: product)
        _isResolving = State(initialValue: previewResolving)
    }
    #endif

    private var band: ScoreBand { workingProduct.score?.band ?? .unknown }

    private var showsSkeleton: Bool { isResolving }

    /// Backend-computed Watch-outs / Benefits meters + pre-read counts. The
    /// client renders these verbatim and never derives a meter value itself.
    private var highlights: NutrientHighlights? { workingProduct.score?.highlights }

    /// A pantry-list read has a `score` with empty `factors` (see
    /// `PantryEntry.asProduct()`); an unscored product has no `score` at
    /// all. Both count as "thin" and are worth a background re-fetch.
    private var hasThinScore: Bool {
        workingProduct.score?.factors.isEmpty ?? true
    }

    private var displayIngredients: [Ingredient] {
        workingProduct.ingredients.isEmpty ? fetchedIngredients : workingProduct.ingredients
    }

    /// Every factor + ingredient source, deduplicated, for the "Sources"
    /// section (§8 — our credibility, alongside "Why this score").
    private var allSources: [Source] {
        var seen = Set<String>()
        var result: [Source] = []
        let factorSources = workingProduct.score?.factors.flatMap { $0.sources } ?? []
        let ingredientSources = displayIngredients.flatMap { $0.sources }
        for source in factorSources + ingredientSources {
            let key = source.name + (source.url ?? "")
            if seen.insert(key).inserted {
                result.append(source)
            }
        }
        return result
    }

    private var apiClient: APIClient { APIClient(session: session) }

    /// The user's flagged allergies (`profile.allergies`) — empty for a
    /// guest, a signed-in-but-still-loading profile, or a profile that
    /// skipped the question, all of which should render this screen exactly
    /// as it did before this feature existed (no banner, no chip emphasis,
    /// no ingredient notes).
    private var flaggedAllergies: [String] {
        profileService?.profile?.allergies ?? []
    }

    /// This product's allergens that match one of the user's flagged
    /// allergies — client-side only (`AllergenMatch`), never a backend call.
    /// Drives the alert banner; empty means "no banner."
    private var flaggedAllergenMatches: [String] {
        guard !flaggedAllergies.isEmpty else { return [] }
        return workingProduct.allergens.filter { AllergenMatch.tagMatches($0, flaggedAllergies: flaggedAllergies) }
    }

    var body: some View {
        ScrollView {
            // Chunk 2: set isResolving=true when opened pre-fetch from
            // Search/deep-link. Dormant today (product is always fetched).
            if showsSkeleton {
                ResultSkeletonView()
            } else {
                resultContent
            }
        }
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                favoriteButton
            }
            ToolbarItem(placement: .topBarTrailing) {
                overflowMenu
            }
        }
        .sheet(isPresented: $showComparePicker) {
            ComparePartnerPicker(excludingID: workingProduct.id) { partner in
                showComparePicker = false
                comparePartner = ComparePartnerRoute(product: partner)
            }
            .environment(pantryService)
        }
        .navigationDestination(item: $comparePartner) { route in
            CompareView(pair: ComparePair(a: workingProduct, b: route.product))
        }
        .sheet(isPresented: $showBetterOptionSheet) {
            SwapsView(product: workingProduct) {
                showBetterOptionSheet = false
                dismiss()
            }
            // swap_shown fires when the better-options sheet appears (works for
            // stub and real). TODO(chunk-3): swap_accepted on a real swap save.
            .onAppear {
                analytics?.log(.swapShown, ["from_score": .int(workingProduct.score?.score ?? -1)])
            }
        }
        .sheet(isPresented: $showMethodologySheet) {
            MethodologySheet()
        }
        .sheet(isPresented: $showReportIssueSheet) {
            ReportIssueSheet(productID: workingProduct.id, productName: workingProduct.name)
        }
        .sheet(isPresented: $showChat) {
            ChatView(product: workingProduct)
        }
        .task {
            logScoreViewedOnce()
            // Order matters: the pantry re-fetch can itself populate
            // ingredients, so the lazy ingredients load only hits the
            // network if that didn't already happen.
            await refreshThinPantryDataIfNeeded()
            await loadIngredientsIfNeeded()
        }
    }

    // MARK: Sections

    /// The full result layout (everything but the loading skeleton), in
    /// SCREEN_SPECS §4 top→bottom order.
    private var resultContent: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s5) {
            identityHeader
                .opacity(identityVisible ? 1 : 0)
                .scaleEffect(identityVisible ? 1 : 0.97)
                .onAppear { revealIdentity() }

            allergenAlertBannerOrNone

            triMetricSectionOrNone

            // Watch-outs / Benefits bar-meters — real per-100 g values from
            // score.highlights (backend-computed). Each renders only when its
            // array is non-empty; the meters visually absorb the factor rows
            // while "Why this score" keeps the full sourced breakdown below.
            if let highlights {
                MetersSection(title: "Watch-outs", rows: highlights.watchOuts)
                MetersSection(title: "Benefits", rows: highlights.benefits)
            }

            whyScoreOrNote

            ingredientPreReadOrNone

            AdditivesSummarySection(ingredients: displayIngredients)

            ingredientsSection

            allergensSection

            if !allSources.isEmpty {
                SourcesSection(sources: allSources, fetchedDate: workingProduct.fetchedAt)
            }

            UtilityRowsSection(
                onScoringInfo: { showMethodologySheet = true },
                onReportIssue: { showReportIssueSheet = true }
            )

            VStack(spacing: Theme.Space.s3) {
                // Grounded per-product AI chat (see ChatView.swift) —
                // secondary pill so it never competes with the primary
                // next-action below.
                askAboutProductButton

                // Next action — never a dead-end (principle #4). Opens the
                // Swaps sheet: a ranked, restriction-safe, sourced better option
                // in the same category, or an honest empty state (SwapsView).
                NextActionButton("See a better option", systemImage: "arrow.triangle.2.circlepath") {
                    showBetterOptionSheet = true
                }
            }

            AttributionFooter()
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Theme.Space.s4)
        .padding(.vertical, Theme.Space.s5)
    }

    /// Calm pre-read above the ingredient list. Hidden when both counts are 0
    /// and there are no ingredients (never a "0 · 0" row on a thin product).
    @ViewBuilder
    private var ingredientPreReadOrNone: some View {
        if let highlights,
           highlights.toKnowAboutCount > 0 || highlights.beneficialCount > 0 || !displayIngredients.isEmpty {
            IngredientCountPreRead(
                toKnowAboutCount: highlights.toKnowAboutCount,
                beneficialCount: highlights.beneficialCount
            )
        }
    }

    /// 1) Floating product image · 2) name/brand + score ring · 3) trust
    /// chips. Reflows to a vertical stack at accessibility Dynamic Type
    /// sizes instead of clipping the ring against the title (§7).
    private var identityHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s4) {
            HStack {
                Spacer(minLength: 0)
                FloatingProductImage(urlString: workingProduct.imageURL)
                Spacer(minLength: 0)
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Theme.Space.s3) {
                    titleBlock
                    ScoreBadge(score: workingProduct.score?.score, band: band)
                }
            } else {
                HStack(alignment: .center, spacing: Theme.Space.s4) {
                    titleBlock
                    ScoreBadge(score: workingProduct.score?.score, band: band)
                }
            }

            trustChipsRow
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(workingProduct.name)
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let brand = workingProduct.brand, !brand.isEmpty {
                Text(brand)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 3) Category/data-source + confidence trust chips. There's no product
    /// category in `Models.swift` today, so this deliberately shows only the
    /// two chips we have real data for — the data source and the confidence
    /// grade — rather than inventing a category label.
    private var trustChipsRow: some View {
        FlowLayout(spacing: Theme.Space.s2) {
            SourceChip(name: "Open Food Facts")
            ConfidenceChip(confidence: workingProduct.score?.confidence ?? workingProduct.dataConfidence)
        }
    }

    /// Brand-tinted (not alarm-colored) heart toggle, in the nav bar per the
    /// Oasis reference (bookmark top-trailing). Reads
    /// `pantryService.isFavorite(_:)` directly in `body` (rather than
    /// mirroring it into local `@State`) so it stays in sync whenever the
    /// `@Observable` PantryService's backing data changes elsewhere.
    private var favoriteButton: some View {
        let isFavorite = pantryService.isFavorite(workingProduct.id)
        return Button {
            Task { await pantryService.toggleFavorite(productID: workingProduct.id) }
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.greenDeep)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
    }

    /// Overflow menu — currently the Compare entry (SCREEN_SPECS §10). Kept as
    /// its own 44 pt target beside the heart so both stay reachable.
    private var overflowMenu: some View {
        Menu {
            Button {
                showComparePicker = true
            } label: {
                Label("Compare", systemImage: "square.split.2x1")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.greenDeep)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("More")
    }

    /// Entry point into `ChatView` — a grounded chat scoped to this one
    /// product ("Is this safe?", "Why this score?"). Secondary (outline)
    /// pill per docs/DESIGN_SYSTEM_V3.md §5.1, so it reads as an alternate
    /// path alongside the primary "See a better option" CTA rather than
    /// competing with it.
    private var askAboutProductButton: some View {
        Button {
            analytics?.log(.chatOpened, ["product_id": .string(workingProduct.id)])
            showChat = true
        } label: {
            HStack(spacing: Theme.Space.s2) {
                Image(systemName: "message.fill")
                Text("Ask about this product").font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .foregroundStyle(Theme.greenDeep)
        .background(
            Capsule().strokeBorder(Theme.greenDeep, lineWidth: 1.5)
        )
        .accessibilityHint("Opens a chat grounded in this product's data")
    }

    /// Allergen alert — the safety wedge (see CLAUDE.md non-negotiable #2:
    /// ED-safe, informational not fear-based). Renders only when a scanned
    /// product actually contains an allergen the user flagged during
    /// onboarding; a guest or an allergy-free profile sees no change to this
    /// screen at all (principle: never a false alarm, never a dead-end).
    @ViewBuilder
    private var allergenAlertBannerOrNone: some View {
        if !flaggedAllergenMatches.isEmpty {
            AllergenAlertBanner(
                matchedAllergens: flaggedAllergenMatches,
                isLimitedConfidence: workingProduct.dataConfidence.lowercased() != "high"
            )
        }
    }

    /// 4) Tri-metric row — only shown once we actually have factor data, so
    /// it never fabricates sub-scores for a thin/unscored product (the "why"
    /// section right below already covers that case in words).
    @ViewBuilder
    private var triMetricSectionOrNone: some View {
        if let score = workingProduct.score, !score.factors.isEmpty {
            TriMetricRow(factors: score.factors)
        }
    }

    /// 5) "Why this score" — sourced, dose-aware, default-open. Falls back to
    /// an honest, calm note (no fabricated breakdown) when data is too thin.
    @ViewBuilder
    private var whyScoreOrNote: some View {
        if let score = workingProduct.score, !score.factors.isEmpty {
            WhyScoreSection(score: score, onExpand: {
                analytics?.log(.whyScoreExpanded, ["product_id": .string(workingProduct.id)])
            })
        } else {
            CollapsibleSection {
                Text("Why this score")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            } content: {
                Text("We don't have enough data yet to break this product down. Once more details come in, you'll see the full processing, nutrition, and additive breakdown here.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 6) "What's inside" — collapsible, default open (core ingredient
    /// transparency); each ingredient renders as its own calm, color-coded
    /// card, so the section itself stays plain (no double-card nesting).
    private var ingredientsSection: some View {
        CollapsibleSection(cardStyle: false) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s2) {
                Text("What's inside")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                if !displayIngredients.isEmpty {
                    Text("\(displayIngredients.count)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
        } content: {
            switch ingredientsPhase {
            case .loading:
                IngredientsSkeletonView()
            case .failed, .failedOffline:
                IngredientsLoadErrorView(
                    retry: { Task { await loadIngredientsIfNeeded(forceRetry: true) } },
                    isOffline: ingredientsPhase == .failedOffline
                )
            case .idle:
                if displayIngredients.isEmpty {
                    EmptyIngredientsView()
                } else {
                    VStack(alignment: .leading, spacing: Theme.Space.s3) {
                        ForEach(displayIngredients) { ingredient in
                            IngredientCard(ingredient: ingredient, flaggedAllergies: flaggedAllergies)
                        }
                    }
                }
            }
        }
    }

    /// 7) Allergens — informational chip row, calm caution tone (never
    /// alarm-red). Only rendered when there's actually allergen data.
    @ViewBuilder
    private var allergensSection: some View {
        if !workingProduct.allergens.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s2) {
                Text("Allergens")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                AllergenChipsRow(allergens: workingProduct.allergens, flaggedAllergies: flaggedAllergies)
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
            dataConfidence: fresh.dataConfidence,
            fetchedAt: workingProduct.fetchedAt ?? fresh.fetchedAt
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
        } catch APIClient.APIError.offline {
            ingredientsPhase = .failedOffline
        } catch {
            ingredientsPhase = .failed
        }
    }

    // MARK: Analytics

    /// score_viewed — fires once per appearance (scan- *and* pantry-originated
    /// opens both count). Props are ids/enums/numbers only (no PII).
    private func logScoreViewedOnce() {
        guard !didLogScoreViewed else { return }
        didLogScoreViewed = true
        analytics?.log(.scoreViewed, [
            "product_id": .string(workingProduct.id),
            "band": .string(band.rawValue),
            "score": .int(workingProduct.score?.score ?? -1),
            "confidence": .string(workingProduct.score?.confidence ?? "unknown"),
        ])
    }

    // MARK: Motion

    /// Calm fade/scale reveal only (§6 Motion) — no bounce, and skipped
    /// entirely under Reduce Motion.
    private func revealIdentity() {
        guard !identityVisible else { return }
        if reduceMotion {
            identityVisible = true
        } else {
            withAnimation(Motion.reveal) { identityVisible = true }
        }
    }
}

// MARK: - Compare partner picker (Chunk 5)

/// Id-keyed navigation box so a chosen partner `Product` (not `Hashable`) can
/// drive `navigationDestination(item:)`. Identity is the product id.
private struct ComparePartnerRoute: Hashable, Identifiable {
    let product: Product
    var id: String { product.id }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A small sheet to pick which already-scanned product to compare against.
/// Lists the pantry's recent scans (each already scored) minus the current
/// product; never a dead-end — an empty pantry shows the calm scan prompt.
private struct ComparePartnerPicker: View {
    let excludingID: String
    let onPick: (Product) -> Void

    @Environment(PantryService.self) private var pantryService
    @Environment(\.dismiss) private var dismiss

    private var candidates: [Product] {
        pantryService.entries
            .map { $0.asProduct() }
            .filter { $0.id != excludingID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if candidates.isEmpty {
                    Text("Your pantry's empty. Scan your first product to start.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Theme.Space.s7)
                        .padding(.horizontal, Theme.Space.s4)
                } else {
                    VStack(spacing: Theme.Space.s3) {
                        ForEach(candidates) { product in
                            Button { onPick(product) } label: {
                                partnerRow(product)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(Theme.Space.s4)
                }
            }
            .background(Theme.canvas)
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.greenDeep)
                }
            }
        }
    }

    private func partnerRow(_ product: Product) -> some View {
        HStack(spacing: Theme.Space.s3) {
            FloatingProductImage(urlString: product.imageURL, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(product.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                if let brand = product.brand, !brand.isEmpty {
                    Text(brand)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Theme.Space.s2)
            ScoreBadge(score: product.score?.score,
                       band: product.score?.band ?? .unknown,
                       diameter: 44, lineWidth: 4)
        }
        .padding(Theme.Space.s3)
        .surfaceCard(padded: false)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#if DEBUG

#Preview("Sample scored — mid, limited confidence (screenshot harness data)") {
    NavigationStack {
        ProductView(product: .sampleScored)
    }
    .environment(SessionService())
    .environment(PantryService(session: SessionService()))
    .environment(ProfileService(session: SessionService()))
}

#Preview("High score — high confidence") {
    NavigationStack {
        ProductView(product: .previewHighFullConfidence)
    }
    .environment(SessionService())
    .environment(PantryService(session: SessionService()))
    .environment(ProfileService(session: SessionService()))
}

#Preview("Low score — limited confidence") {
    NavigationStack {
        ProductView(product: .previewLowLimitedConfidence)
    }
    .environment(SessionService())
    .environment(PantryService(session: SessionService()))
    .environment(ProfileService(session: SessionService()))
}

#Preview("Unknown score — no data") {
    NavigationStack {
        ProductView(product: .previewUnknownScore)
    }
    .environment(SessionService())
    .environment(PantryService(session: SessionService()))
    .environment(ProfileService(session: SessionService()))
}

#Preview("From pantry — thin read") {
    NavigationStack {
        ProductView(product: .previewFromPantryThin)
    }
    .environment(SessionService())
    .environment(PantryService(session: SessionService()))
    .environment(ProfileService(session: SessionService()))
}

#Preview("Loading skeleton via ProductView") {
    NavigationStack {
        ProductView(product: .previewHighFullConfidence, previewResolving: true)
    }
    .environment(SessionService())
    .environment(PantryService(session: SessionService()))
    .environment(ProfileService(session: SessionService()))
}

#Preview("Accessibility XXL Dynamic Type") {
    NavigationStack {
        ProductView(product: .previewHighFullConfidence)
    }
    .environment(SessionService())
    .environment(PantryService(session: SessionService()))
    .environment(ProfileService(session: SessionService()))
    .dynamicTypeSize(.accessibility3)
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
    /// ring shows a number/band immediately) but empty `factors` and empty
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
