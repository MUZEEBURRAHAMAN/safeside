import SwiftUI

/// Home (MASTER_PLAN Phase 2): big Scan button, recent scans (the guest-first
/// pantry), and a couple of trending healthy products. Docs:
/// docs/DESIGN_SYSTEM.md §5.4 (cards), §5.9 (states — empty/loading/error),
/// §8 (accessibility), docs/COPY_DECK.md (pantry copy).
struct HomeView: View {
    @Environment(SessionService.self) private var session
    @Environment(PantryService.self) private var pantryService
    @State private var showScanner = false
    @State private var pantryFilter: PantryFilter = .recent

    private enum PantryFilter: String, CaseIterable, Identifiable {
        case recent, favorites
        var id: String { rawValue }
        var label: String {
            switch self {
            case .recent: return "Recent"
            case .favorites: return "Favorites"
            }
        }
    }

    /// `entries` filtered for display — filtering (not re-fetching) keeps
    /// favoriting instant, since `PantryService.favoriteProductIDs` is
    /// already the live, fast-lookup source of truth.
    private var filteredEntries: [PantryEntry] {
        switch pantryFilter {
        case .recent: return pantryService.entries
        case .favorites: return pantryService.entries.filter { pantryService.isFavorite($0.product.id) }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s5) {
                    Text("What's really in your food?")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.top, Theme.Space.s4)

                    // Primary action: Scan
                    Button { showScanner = true } label: {
                        HStack {
                            Image(systemName: "barcode.viewfinder").font(.title2)
                            Text("Scan a product").font(.headline)
                        }
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .foregroundStyle(Theme.onGreen)
                        .background(Theme.greenDeep)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    }
                    .accessibilityHint("Opens the scanner to scan a barcode.")

                    pantryHeader

                    pantrySection

                    trendingSection
                }
                .padding(.horizontal, Theme.Space.s4)
                .padding(.bottom, Theme.Space.s5)
            }
            .background(Theme.canvas)
            .navigationTitle("Home")
            .task(id: session.userID) {
                // Re-runs once the anonymous session's userID resolves
                // (bootstrap is async), and whenever it changes (e.g. later
                // linking with Apple). Sequential so trending can exclude
                // products already in the just-loaded pantry.
                await pantryService.loadRecent()
                await pantryService.loadTrending()
            }
            .fullScreenCover(isPresented: $showScanner) {
                NavigationStack {
                    ScanScreen()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { showScanner = false }
                            }
                        }
                }
            }
        }
    }

    // MARK: - Pantry (recent scans / favorites)

    private var pantryHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s3) {
            Text(pantryFilter == .recent ? "Recent scans" : "Favorites")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: Theme.Space.s2)
            filterChips
        }
    }

    /// Filter chips (docs/DESIGN_SYSTEM.md §5.5): `radius.full`, selected =
    /// `brand.green` fill. Only meaningful once there's at least one scan —
    /// hidden on a totally empty pantry so there's nothing to filter.
    @ViewBuilder
    private var filterChips: some View {
        if !pantryService.entries.isEmpty {
            HStack(spacing: Theme.Space.s2) {
                ForEach(PantryFilter.allCases) { filter in
                    let isSelected = pantryFilter == filter
                    Button {
                        pantryFilter = filter
                    } label: {
                        Text(filter.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isSelected ? Theme.ink : Theme.textSecondary)
                            .padding(.horizontal, Theme.Space.s3)
                            .frame(minHeight: 32)
                            .background(isSelected ? Theme.green : Theme.surface, in: Capsule())
                            .overlay(
                                Capsule().strokeBorder(isSelected ? .clear : Theme.border, lineWidth: 1)
                            )
                    }
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    .accessibilityLabel("\(filter.label) filter")
                }
            }
        }
    }

    @ViewBuilder
    private var pantrySection: some View {
        if pantryService.isLoading && pantryService.entries.isEmpty {
            PantrySkeletonList()
        } else if let error = pantryService.loadError, pantryService.entries.isEmpty {
            StateCard(
                message: error,
                actionTitle: "Try again",
                action: { Task { await pantryService.loadRecent() } }
            )
        } else if pantryService.entries.isEmpty {
            // Empty state (guest-first: works with no account).
            StateCard(message: "Your pantry's empty — scan your first product.")
        } else if filteredEntries.isEmpty {
            // Favorites selected, but nothing favorited yet — never a
            // dead end: point back at how to favorite something.
            StateCard(message: "No favorites yet — tap the heart on a product to save it here.")
        } else {
            VStack(spacing: Theme.Space.s3) {
                ForEach(filteredEntries) { entry in
                    PantryRowContent(entry: entry)
                }
            }
        }
    }

    // MARK: - Trending healthy

    private var trendingSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s3) {
            Text("Trending healthy")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            trendingContent
        }
    }

    @ViewBuilder
    private var trendingContent: some View {
        if pantryService.isLoadingTrending && pantryService.trending.isEmpty {
            TrendingSkeletonRow()
        } else if pantryService.trendingError != nil, pantryService.trending.isEmpty {
            // Secondary/bonus section — a calm one-liner, not a full error
            // card, so it never competes with the primary pantry error.
            Text("Couldn't load trending products right now.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        } else if pantryService.trending.isEmpty {
            Text("Nothing trending yet — check back once more products have been scanned.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Theme.Space.s3) {
                    ForEach(pantryService.trending) { entry in
                        TrendingCardContent(entry: entry)
                    }
                }
                .padding(.vertical, Theme.Space.s1)
            }
        }
    }
}

// MARK: - Pantry row

/// One pantry row: a `NavigationLink` (thumbnail, name, brand, compact score
/// badge — docs/DESIGN_SYSTEM.md §5.4 "Pantry card", reusing the existing
/// `ScoreBadge(.compact)` §5.2) plus a favorite heart. The heart is a
/// **sibling** of the `NavigationLink`, not nested inside its label — SwiftUI
/// does not reliably route taps to a `Button` embedded inside another
/// button/link's label, so nesting them would make the heart untappable (or
/// double-fire navigation). Keeping them as HStack siblings gives each its
/// own independent 44×44pt tap target.
private struct PantryRowContent: View {
    let entry: PantryEntry

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.s2) {
            NavigationLink {
                ProductView(product: entry.asProduct())
            } label: {
                PantryRow(entry: entry)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens product details.")

            FavoriteHeartInline(productID: entry.product.id)
        }
    }
}

private struct PantryRow: View {
    let entry: PantryEntry

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.s3) {
            ProductThumbnail(urlString: entry.product.images?.bestURL, size: 64)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.product.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                if let brand = entry.product.brand, !brand.isEmpty {
                    Text(brand)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 96, alignment: .leading)

            ScoreBadge(score: entry.score?.score, band: entry.band)
        }
        .padding(Theme.Space.s3)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Trending card

/// A compact, horizontally-scrolling card for a globally top-scoring cached
/// product (docs/DESIGN_SYSTEM.md §5.4 card anatomy). Honest framing per
/// CLAUDE.md: this is a top-scoring cached product, not a paid placement —
/// the neutral "Trending healthy" heading carries that, no extra badge needed.
///
/// Structured as a `NavigationLink` (passive `TrendingCardBody` label, no
/// interactive controls inside it) with the favorite heart added via
/// `.overlay`, which composes as a sibling layer rather than nesting a
/// `Button` inside the link's label (see `PantryRowContent` for why that
/// matters for tap routing).
private struct TrendingCardContent: View {
    let entry: TrendingEntry

    var body: some View {
        NavigationLink {
            ProductView(product: entry.asProduct())
        } label: {
            TrendingCardBody(entry: entry)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens product details.")
        .overlay(alignment: .topTrailing) {
            FavoriteHeartInline(productID: entry.product.id)
                .padding(.trailing, Theme.Space.s1)
        }
    }
}

private struct TrendingCardBody: View {
    let entry: TrendingEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            // Leading-aligned within a 240pt-wide card, so the top-trailing
            // heart overlay (44×44pt) never overlaps it.
            ProductThumbnail(urlString: entry.product.images?.bestURL, size: 56)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.product.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                if let brand = entry.product.brand, !brand.isEmpty {
                    Text(brand)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }

            ScoreBadge(score: entry.score.score, band: entry.band)
        }
        .padding(Theme.Space.s3)
        .frame(width: 240, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Favorite toggle

/// A 44×44pt heart button bound directly to `PantryService`'s favorites
/// contract (`isFavorite(_:)` / `toggleFavorite(productID:)`). Reads
/// `pantryService` from the environment itself so both `PantryRowContent`
/// and `TrendingCardContent` can drop it in without threading state through.
private struct FavoriteHeartInline: View {
    @Environment(PantryService.self) private var pantryService
    let productID: String

    private var isFavorite: Bool { pantryService.isFavorite(productID) }

    var body: some View {
        Button {
            Task { await pantryService.toggleFavorite(productID: productID) }
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isFavorite ? Theme.greenDeep : Theme.textSecondary)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
        .accessibilityAddTraits(isFavorite ? [.isSelected] : [])
    }
}

// MARK: - States (§5.9 — empty, loading, error)

/// A calm single-message card used for empty and error states alike — the
/// error variant adds a "Try again" affordance (§5.9: "what happened + how
/// to fix").
private struct StateCard: View {
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Theme.Space.s3) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.greenDeep)
                    .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Space.s4)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }
}

/// Skeleton loader for the pantry list (§5.9: "skeletons for lists"). Static
/// blocks, not a shimmer animation — calm by default and automatically
/// Reduce-Motion-safe since nothing here animates.
private struct PantrySkeletonList: View {
    var body: some View {
        VStack(spacing: Theme.Space.s3) {
            ForEach(0..<3, id: \.self) { _ in SkeletonPantryRow() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading your pantry")
    }
}

private struct SkeletonPantryRow: View {
    var body: some View {
        HStack(spacing: Theme.Space.s3) {
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(Theme.border.opacity(0.6))
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: Theme.Space.s2) {
                RoundedRectangle(cornerRadius: 4).fill(Theme.border.opacity(0.6)).frame(height: 12)
                RoundedRectangle(cornerRadius: 4).fill(Theme.border.opacity(0.4)).frame(width: 60, height: 10)
            }
            .frame(width: 96)
            Circle().fill(Theme.border.opacity(0.6)).frame(width: 64, height: 64)
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.s3)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }
}

/// Skeleton loader for the horizontal trending row.
private struct TrendingSkeletonRow: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.s3) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: Theme.Space.s2) {
                        RoundedRectangle(cornerRadius: Theme.Radius.sm)
                            .fill(Theme.border.opacity(0.6))
                            .frame(width: 56, height: 56)
                        RoundedRectangle(cornerRadius: 4).fill(Theme.border.opacity(0.6)).frame(height: 12)
                        RoundedRectangle(cornerRadius: 4).fill(Theme.border.opacity(0.4)).frame(width: 80, height: 10)
                    }
                    .padding(Theme.Space.s3)
                    .frame(width: 240, alignment: .leading)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading trending products")
    }
}

// MARK: - Previews

#if DEBUG

#Preview("Home — populated") {
    let session = SessionService()
    let pantry = PantryService(session: session)
    HomeView()
        .environment(session)
        .environment(pantry)
}

#Preview("Pantry row — favorited") {
    NavigationStack {
        PantryRowContent(entry: .previewFavorited)
            .padding()
    }
    .environment(PantryService(session: SessionService()))
}

#Preview("Trending card") {
    NavigationStack {
        TrendingCardContent(entry: .preview)
            .padding()
    }
    .environment(PantryService(session: SessionService()))
}

#Preview("Skeletons") {
    VStack(alignment: .leading, spacing: Theme.Space.s5) {
        PantrySkeletonList()
        TrendingSkeletonRow()
    }
    .padding()
}

fileprivate extension PantryEntry {
    static let previewFavorited = PantryEntry(
        item: PantryItemRow(
            id: "item-1",
            userID: "user-1",
            productID: "product-1",
            status: .favorited,
            firstScannedAt: Date(),
            lastSeenAt: Date()
        ),
        product: ProductRow(
            id: "product-1",
            barcode: "0123456789012",
            name: "Organic Rolled Oats",
            brand: "Fieldbrook Farms",
            images: nil,
            allergensTags: [],
            dataConfidence: "high"
        ),
        score: ScoreResultRow(
            id: "score-1",
            productID: "product-1",
            score: 88,
            band: .high,
            confidence: "high",
            scoreVersion: "1.0",
            computedAt: Date()
        )
    )
}

fileprivate extension TrendingEntry {
    static let preview = TrendingEntry(
        product: ProductRow(
            id: "product-2",
            barcode: "9876543210123",
            name: "Plain Greek Yogurt",
            brand: "Meadow Co.",
            images: nil,
            allergensTags: ["Milk"],
            dataConfidence: "high"
        ),
        score: ScoreResultRow(
            id: "score-2",
            productID: "product-2",
            score: 91,
            band: .high,
            confidence: "high",
            scoreVersion: "1.0",
            computedAt: Date()
        )
    )
}

#endif
