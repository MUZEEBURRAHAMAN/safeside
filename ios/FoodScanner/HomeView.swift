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

// MARK: - Compact score indicator

/// A compact score indicator for dense list/card contexts (pantry rows,
/// trending cards) — deliberately smaller and less repetitive than
/// `ScoreBadge` (which is sized for the result screen's brand moment, §5.2):
/// the number appears once, inside the disc, instead of being repeated as
/// "N / 100" underneath. It's paired with the same word label `ScoreBadge`
/// uses, so color is never the sole signal (§8). Band colors mirror
/// `ScoreBadge`'s mapping exactly — never red for `.low`, per CLAUDE.md's
/// ED-safe rule.
private struct ScoreDisc: View {
    /// `.stacked` — disc above a centered, wrapping label; used in the
    /// pantry row's narrow trailing column. `.inline` — disc beside a
    /// leading label; used in the wider trending card. (Named `Arrangement`,
    /// not `Layout`, to avoid any ambiguity with SwiftUI's own `Layout`
    /// protocol.)
    enum Arrangement { case stacked, inline }

    let score: Int?
    let band: ScoreBand
    var arrangement: Arrangement = .stacked

    private var color: Color {
        switch band {
        case .high: return Theme.scoreHigh
        case .mid: return Theme.scoreMid
        case .low: return Theme.scoreLow
        case .unknown: return Theme.scoreUnknown
        }
    }

    private var accessibilityText: String {
        score.map { "Score \($0) of 100, \(band.label)" } ?? band.label
    }

    private var disc: some View {
        ZStack {
            Circle().fill(color).frame(width: 44, height: 44)
            Text(score.map(String.init) ?? "—")
                .font(.system(.callout, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.ResultScreen.textOnBandFill(band))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(width: 44, height: 44)
    }

    private var label: some View {
        Text(band.label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(Theme.textSecondary)
    }

    var body: some View {
        Group {
            switch arrangement {
            case .stacked:
                VStack(spacing: 2) {
                    disc
                    label
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .frame(width: 76)
            case .inline:
                HStack(spacing: Theme.Space.s2) {
                    disc
                    label
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}

/// Shared "surface card" look for the redesigned pantry row and trending
/// card (docs/DESIGN_SYSTEM.md §5.4: `bg.surface`, subtle border, `radius.md`,
/// `elevation.1`). Callers apply their own `space.4` padding first — the
/// pantry row's padding wraps the favorite heart too, while the trending
/// card's doesn't.
private extension View {
    func homeCardSurface() -> some View {
        background(Theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            // §4 elevation.1 (y2, blur8, ~6% navy) — no dedicated "navy" token
            // exists, so this reuses `Theme.ink` at low opacity. Kept faint by
            // design (§1: calm, not flashy).
            .shadow(color: Theme.ink.opacity(0.06), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Pantry row

/// One pantry row, redesigned as a **single** surface card containing
/// everything — thumbnail, name/brand, score, and the favorite heart
/// (docs/DESIGN_SYSTEM.md §5.4 "Pantry card": "thumbnail, name, score badge,
/// favorite toggle"). The heart is still a **sibling** of the `NavigationLink`,
/// not nested inside its label — SwiftUI does not reliably route taps to a
/// `Button` embedded inside another button/link's label, so nesting them
/// would make the heart untappable (or double-fire navigation). Keeping them
/// as HStack siblings (both wrapped in one shared card background) gives each
/// its own independent 44×44pt tap target while looking like one row, not a
/// floating heart bolted onto the outside of a card.
private struct PantryRowContent: View {
    let entry: PantryEntry

    var body: some View {
        HStack(spacing: Theme.Space.s3) {
            NavigationLink {
                ProductView(product: entry.asProduct())
            } label: {
                PantryRow(entry: entry)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens product details.")

            FavoriteHeartInline(productID: entry.product.id)
        }
        .padding(Theme.Space.s4)
        .homeCardSurface()
    }
}

private struct PantryRow: View {
    let entry: PantryEntry

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.s3) {
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
            // Flexible, not a fixed 96pt frame — takes whatever width is left
            // after the thumbnail/score/heart, so names truncate correctly
            // instead of wrapping a narrow fixed column.
            .frame(maxWidth: .infinity, alignment: .leading)

            ScoreDisc(score: entry.score?.score, band: entry.band)
        }
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
                .padding(.top, Theme.Space.s1)
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
            // Reserves the same vertical space whether a card's name is one
            // line or two, and whether a brand is present — so the score row
            // below starts at the same height across every card in the row
            // (the "align tops" requirement), without clamping the card to a
            // hard total height that could clip at large Dynamic Type sizes.
            .frame(minHeight: 54, alignment: .top)

            ScoreDisc(score: entry.score.score, band: entry.band, arrangement: .inline)
        }
        .padding(Theme.Space.s4)
        .frame(width: 240, alignment: .leading)
        .homeCardSurface()
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

/// Matches `PantryRowContent`'s compact geometry exactly (56pt thumbnail,
/// `space.4` card padding, 44pt score placeholder, 44pt heart placeholder) so
/// loading never jumps once real rows arrive.
private struct SkeletonPantryRow: View {
    var body: some View {
        HStack(spacing: Theme.Space.s3) {
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(Theme.border.opacity(0.6))
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: Theme.Space.s2) {
                RoundedRectangle(cornerRadius: 4).fill(Theme.border.opacity(0.6)).frame(height: 12)
                RoundedRectangle(cornerRadius: 4).fill(Theme.border.opacity(0.4)).frame(width: 60, height: 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Circle().fill(Theme.border.opacity(0.6)).frame(width: 44, height: 44)
            Circle().fill(Theme.border.opacity(0.35)).frame(width: 44, height: 44)
        }
        .padding(Theme.Space.s4)
        .homeCardSurface()
    }
}

/// Skeleton loader for the horizontal trending row — mirrors
/// `TrendingCardBody`'s geometry (240pt width, `space.4` padding, reserved
/// name-block height, inline score placeholder).
private struct TrendingSkeletonRow: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Theme.Space.s3) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: Theme.Space.s2) {
                        RoundedRectangle(cornerRadius: Theme.Radius.sm)
                            .fill(Theme.border.opacity(0.6))
                            .frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            RoundedRectangle(cornerRadius: 4).fill(Theme.border.opacity(0.6)).frame(height: 12)
                            RoundedRectangle(cornerRadius: 4).fill(Theme.border.opacity(0.6)).frame(width: 120, height: 12)
                            RoundedRectangle(cornerRadius: 4).fill(Theme.border.opacity(0.4)).frame(width: 80, height: 10)
                        }
                        .frame(minHeight: 54, alignment: .top)
                        HStack(spacing: Theme.Space.s2) {
                            Circle().fill(Theme.border.opacity(0.6)).frame(width: 44, height: 44)
                            RoundedRectangle(cornerRadius: 4).fill(Theme.border.opacity(0.4)).frame(width: 90, height: 10)
                        }
                    }
                    .padding(Theme.Space.s4)
                    .frame(width: 240, alignment: .leading)
                    .homeCardSurface()
                }
            }
            .padding(.vertical, Theme.Space.s1)
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

#Preview("Pantry — recent list") {
    NavigationStack {
        ScrollView {
            VStack(spacing: Theme.Space.s3) {
                PantryRowContent(entry: .previewShort)
                PantryRowContent(entry: .previewLongName)
                PantryRowContent(entry: .previewFavorited)
            }
            .padding()
        }
    }
    .environment(PantryService(session: SessionService()))
}

#Preview("Pantry row — favorited") {
    NavigationStack {
        PantryRowContent(entry: .previewFavorited)
            .padding()
    }
    .environment(PantryService(session: SessionService()))
}

#Preview("Trending cards") {
    NavigationStack {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: Theme.Space.s3) {
                TrendingCardContent(entry: .preview)
                TrendingCardContent(entry: .previewLongName)
            }
            .padding()
        }
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
    static let previewShort = PantryEntry(
        item: PantryItemRow(
            id: "item-0",
            userID: "user-1",
            productID: "product-0",
            status: .scanned,
            firstScannedAt: Date(),
            lastSeenAt: Date()
        ),
        product: ProductRow(
            id: "product-0",
            barcode: "0000000000000",
            name: "Plain Greek Yogurt",
            brand: "Meadow Co.",
            images: nil,
            allergensTags: ["Milk"],
            dataConfidence: "high"
        ),
        score: ScoreResultRow(
            id: "score-0",
            productID: "product-0",
            score: 74,
            band: .mid,
            confidence: "high",
            scoreVersion: "1.0",
            computedAt: Date()
        )
    )

    /// Exercises the flexible name column + wrapping score label at their
    /// worst case: a long name, a long brand, and a low-band score.
    static let previewLongName = PantryEntry(
        item: PantryItemRow(
            id: "item-2",
            userID: "user-1",
            productID: "product-3",
            status: .scanned,
            firstScannedAt: Date(),
            lastSeenAt: Date()
        ),
        product: ProductRow(
            id: "product-3",
            barcode: "1111111111111",
            name: "Biscuits Sablés aux Amandes Décortiquées et Chocolat Noir",
            brand: "Maison Boulangère Artisanale",
            images: nil,
            allergensTags: ["Milk", "Wheat"],
            dataConfidence: "limited"
        ),
        score: ScoreResultRow(
            id: "score-3",
            productID: "product-3",
            score: 41,
            band: .low,
            confidence: "limited",
            scoreVersion: "1.0",
            computedAt: Date()
        )
    )

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

    /// Exercises the trending card's reserved name-block height + inline
    /// score label wrapping with a long name/brand pair.
    static let previewLongName = TrendingEntry(
        product: ProductRow(
            id: "product-4",
            barcode: "2222222222222",
            name: "Amandes Décortiquées Non Salées Bio",
            brand: "Ferme du Val Vert Artisanale",
            images: nil,
            allergensTags: ["Tree nuts"],
            dataConfidence: "high"
        ),
        score: ScoreResultRow(
            id: "score-4",
            productID: "product-4",
            score: 96,
            band: .high,
            confidence: "high",
            scoreVersion: "1.0",
            computedAt: Date()
        )
    )
}

#endif
