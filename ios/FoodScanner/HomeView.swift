import SwiftUI

/// Home — rebuilt to Design System v3 ("Calm Intelligence", docs/DESIGN_SYSTEM_V3.md):
/// light-first mint-white canvas, white floating cards, a bold Space Grotesk
/// hero headline, a full-width green Scan CTA card as the screen's anchor, an
/// optional calm daily-insight tile, and Recent Scans / Trending Healthy as a
/// 2-column product-card grid with grade dots (§5.4). Behavior is unchanged
/// from the previous build: guest-first, `.task(id:)`-driven loads, the
/// scanner `fullScreenCover`, and favorites — only the visual language moved.
struct HomeView: View {
    @Environment(SessionService.self) private var session
    @Environment(PantryService.self) private var pantryService
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showScanner = false
    @State private var pantryFilter: PantryFilter = .recent
    @State private var pantrySort: PantrySort = .recent
    /// Product pending a remove confirmation (context menu → dialog).
    @State private var pendingRemoval: Product?

    /// Switch top-level tabs from a quick-action tile (e.g. Categories). Nil in
    /// standalone previews/harness, where a tile tap is simply inert — the real
    /// app always injects it from `RootTabView`.
    var onSelectTab: ((RootTab) -> Void)? = nil

    /// Scroll anchor so the "Favorites" quick-action can bring the pantry
    /// section (switched to its Favorites filter) into view.
    private let pantryAnchor = "home-pantry-section"

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

    private enum PantrySort: String, CaseIterable, Identifiable {
        case recent, scoreHighFirst
        var id: String { rawValue }
        var label: String {
            switch self {
            case .recent: return "Most recent"
            case .scoreHighFirst: return "Highest score"
            }
        }
    }

    /// `entries` filtered + sorted for display — filtering (not re-fetching)
    /// keeps favoriting instant, since `PantryService.favoriteProductIDs` is
    /// already the live, fast-lookup source of truth. Sort is view-local:
    /// the server order is last-seen desc (the `.recent` case); score sort
    /// is a stable client-side reorder of that same list.
    private var filteredEntries: [PantryEntry] {
        let filtered: [PantryEntry]
        switch pantryFilter {
        case .recent: filtered = pantryService.entries
        case .favorites: filtered = pantryService.entries.filter { pantryService.isFavorite($0.product.id) }
        }
        switch pantrySort {
        case .recent:
            return filtered
        case .scoreHighFirst:
            // Stable: equal/missing scores keep their last-seen order.
            return filtered.enumerated()
                .sorted { lhs, rhs in
                    let l = lhs.element.score?.score ?? -1
                    let r = rhs.element.score?.score ?? -1
                    return l != r ? l > r : lhs.offset < rhs.offset
                }
                .map(\.element)
        }
    }

    /// A calm, ED-safe one-liner for the optional daily-insight tile (v3 §5.7):
    /// "N scans this week" when there's recent activity, otherwise a neutral
    /// "N products saved" — never a streak/guilt mechanic, and omitted
    /// entirely (by returning `nil`) when the pantry has nothing to say yet.
    private var dailyInsightText: String? {
        guard !pantryService.entries.isEmpty else { return nil }
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast
        let recentCount = pantryService.entries.filter { $0.item.firstScannedAt >= sevenDaysAgo }.count
        if recentCount > 0 {
            return recentCount == 1 ? "1 scan this week" : "\(recentCount) scans this week"
        }
        let total = pantryService.entries.count
        return total == 1 ? "1 product saved" : "\(total) products saved"
    }

    /// Two columns normally; a single column once Dynamic Type crosses into
    /// the accessibility range, so long names/scores always have room to
    /// grow instead of being crushed into a too-narrow column (§7/§8: "grid
    /// reflows, cards grow").
    private var gridColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: Theme.Space.s4), GridItem(.flexible())]
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.s6) {
                        wordmarkGreeting

                        // Showcase carousel (v3 §5 showcase): a swipeable, paged
                        // set of green "how it works" cards that teach the flow
                        // — scan → sourced score → better swap. Auto-advance is
                        // slow and disabled under Reduce Motion (handled inside).
                        HowItWorksCarousel()

                        // Four calm greenSoft shortcuts (matches the Categories
                        // cards + Scan chrome): Scan · Search · Categories ·
                        // Favorites. See `quickActionGrid` for each route.
                        quickActionGrid(proxy: proxy)

                        // Live offline banner (Chunk 6): cached pantry/trending
                        // below stay browsable; Retry re-attempts the loads. Never
                        // alarm-red, never a blank screen (teardown AVOID #5/#14).
                        if !networkMonitor.isOnline {
                            OfflineBanner {
                                Task {
                                    await pantryService.loadRecent()
                                    await pantryService.loadTrending()
                                }
                            }
                        }

                        if let dailyInsightText {
                            DailyInsightTile(text: dailyInsightText)
                        }

                        VStack(alignment: .leading, spacing: Theme.Space.s4) {
                            pantryHeader
                            pantrySection
                        }
                        .id(pantryAnchor)

                        VStack(alignment: .leading, spacing: Theme.Space.s4) {
                            Text("Trending healthy")
                                .font(DisplayType.h2)
                                .foregroundStyle(Theme.textPrimary)
                            trendingContent
                        }
                    }
                    .padding(.horizontal, Theme.Space.s45)
                    .padding(.top, Theme.Space.s4)
                    .padding(.bottom, Theme.Space.s7)   // clear the tab bar
                }
            }
            .background(Theme.canvas)
            // The wordmark is the screen's title — no redundant nav-bar title
            // (also removes card "ghosting" under a translucent bar).
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                // Pull-to-refresh re-runs both loads (sequential so trending can
                // exclude just-loaded pantry items), mirroring the `.task` below.
                await pantryService.loadRecent()
                await pantryService.loadTrending()
            }
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

    // MARK: - Wordmark + greeting

    /// The SafeSide wordmark (Space Grotesk, brand green) + one calm greeting
    /// line — the screen's brand moment (v3 §3: "max one display per region").
    /// Uses `greenDeep` (not the lighter `green`) so the large bold wordmark
    /// clears WCAG AA large-text 3:1 contrast on the mint canvas (§7).
    private var wordmarkGreeting: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s1) {
            Text("SafeSide")
                .font(DisplayType.h1)
                .foregroundStyle(Theme.greenDeep)
                .accessibilityAddTraits(.isHeader)
            Text("Know what's really in your food.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Quick-action grid

    /// Two columns normally, four across; drops to a 2×2 grid at accessibility
    /// Dynamic Type sizes so labels never crush (§7: "reflow, never clip").
    private var quickActionColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible(), spacing: Theme.Space.s3), GridItem(.flexible())]
            : Array(repeating: GridItem(.flexible(), spacing: Theme.Space.s3), count: 4)
    }

    /// Four calm greenSoft shortcuts. Routes chosen to stay honest + never a
    /// dead-end:
    ///   • Scan       → the scanner `fullScreenCover` (unchanged).
    ///   • Search     → pushes `SearchView` in Home's own stack (push-safe).
    ///   • Categories → hops to the Categories tab via `onSelectTab` (its view
    ///                  owns its own `NavigationStack`, so we switch tabs rather
    ///                  than nest a second stack).
    ///   • Favorites  → there is NO two-product Compare picker in the app yet
    ///                  (CompareView only opens from a product vs. a swap), so
    ///                  per the brief we route the 4th tile to Favorites: it
    ///                  flips the pantry filter and scrolls to it — the honest,
    ///                  non-dead-end pool a user would compare *from*.
    private func quickActionGrid(proxy: ScrollViewProxy) -> some View {
        LazyVGrid(columns: quickActionColumns, spacing: Theme.Space.s3) {
            Button { showScanner = true } label: {
                QuickActionTileLabel(icon: "barcode.viewfinder", label: "Scan")
            }
            .buttonStyle(CardPressButtonStyle())
            .accessibilityLabel("Scan a product")
            .accessibilityHint("Opens the scanner.")

            NavigationLink { SearchView() } label: {
                QuickActionTileLabel(icon: "magnifyingglass", label: "Search")
            }
            .buttonStyle(CardPressButtonStyle())
            .accessibilityLabel("Search any product")

            Button { onSelectTab?(.categories) } label: {
                QuickActionTileLabel(icon: "square.grid.2x2", label: "Categories")
            }
            .buttonStyle(CardPressButtonStyle())
            .accessibilityLabel("Browse categories")

            Button {
                pantryFilter = .favorites
                withAnimation(Motion.respecting(Motion.standard, reduceMotion)) {
                    proxy.scrollTo(pantryAnchor, anchor: .top)
                }
            } label: {
                QuickActionTileLabel(icon: "heart", label: "Favorites")
            }
            .buttonStyle(CardPressButtonStyle())
            .accessibilityLabel("Your favorites")
            .accessibilityHint("Shows the products you've saved.")
        }
    }

    // MARK: - Pantry (recent scans / favorites)

    private var pantryHeader: some View {
        // Title on its own line; chips on a second row so the big display title
        // never squeezes the chips into wrapping ("Re-cent"/"Fa-vorites").
        VStack(alignment: .leading, spacing: Theme.Space.s3) {
            Text(pantryFilter == .recent ? "Recent scans" : "Favorites")
                .font(DisplayType.h2)
                .foregroundStyle(Theme.textPrimary)
            filterChips
        }
    }

    /// Pill filter chips (v3 §5.8: `radius.full`, selected = `brand.green`
    /// fill, ink label). Only meaningful once there's at least one scan —
    /// hidden on a totally empty pantry so there's nothing to filter.
    @ViewBuilder
    private var filterChips: some View {
        if !pantryService.entries.isEmpty {
            HStack(spacing: Theme.Space.s2) {
                ForEach(PantryFilter.allCases) { filter in
                    FilterChipButton(label: filter.label, isSelected: pantryFilter == filter) {
                        pantryFilter = filter
                    }
                }

                Spacer(minLength: 0)

                sortMenu
            }
        }
    }

    /// Small, quiet sort control on the chips row — a system `Menu` (native
    /// affordance per DESIGN.md "defer to the platform"), never competing
    /// with the primary chips.
    private var sortMenu: some View {
        Menu {
            Picker("Sort pantry", selection: $pantrySort) {
                ForEach(PantrySort.allCases) { sort in
                    Text(sort.label).tag(sort)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Sort pantry")
        .accessibilityValue(pantrySort.label)
    }

    @ViewBuilder
    private var pantrySection: some View {
        if pantryService.isLoading && pantryService.entries.isEmpty {
            ProductGridSkeleton()
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
            LazyVGrid(columns: gridColumns, spacing: Theme.Space.s4) {
                ForEach(filteredEntries) { entry in
                    // Context menu (grid = no swipe rows) + confirm before the
                    // destructive delete — pantry cards only, never trending.
                    ProductCard(product: entry.asProduct())
                        .contextMenu {
                            Button(role: .destructive) {
                                pendingRemoval = entry.asProduct()
                            } label: {
                                Label("Remove from pantry", systemImage: "trash")
                            }
                        }
                }
            }
            .confirmationDialog(
                "Remove \(pendingRemoval?.name ?? "this product") from your pantry?",
                isPresented: Binding(
                    get: { pendingRemoval != nil },
                    set: { if !$0 { pendingRemoval = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    if let product = pendingRemoval {
                        Task { await pantryService.remove(productID: product.id) }
                    }
                    pendingRemoval = nil
                }
                Button("Keep", role: .cancel) { pendingRemoval = nil }
            }
        }
    }

    // MARK: - Trending healthy

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
                HStack(alignment: .top, spacing: Theme.Space.s4) {
                    ForEach(pantryService.trending) { entry in
                        ProductCard(product: entry.asProduct(), fixedWidth: 172)
                    }
                }
                .padding(.vertical, Theme.Space.s1)
                // A little breathing room so the card shadow/elevation isn't
                // visually clipped at the scroll view's leading/trailing edge.
                .padding(.horizontal, 2)
            }
        }
    }
}

// MARK: - Motion — card press

/// A calm press-scale for card taps (v3 §6): 0.97 scale, quick ease-out, no
/// bounce, routed through `DesignKit.Motion` so Reduce Motion is honored in
/// one place — a static tap is the Reduce-Motion-safe path.
private struct CardPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(Motion.respecting(Motion.quick, reduceMotion), value: configuration.isPressed)
    }
}

// MARK: - How-it-works carousel (Home showcase)

/// One "how it works" slide's content.
private struct HowItWorksSlide: Identifiable {
    let id: Int
    let symbol: String
    let headline: String
    let line: String
}

/// A swipeable, paged carousel of green cards that teaches the SafeSide flow
/// (scan → sourced score → better swap). Built on a paged `TabView` with the
/// default dots hidden, plus a custom dot row so the dots use our green /
/// greenSoft tokens (brief). Auto-advance is deliberately slow (7s) and fully
/// disabled under Reduce Motion — manual swipe always works. The card frame is
/// `@ScaledMetric` so it grows with Dynamic Type instead of clipping (§7).
private struct HowItWorksCarousel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    @ScaledMetric(relativeTo: .body) private var cardHeight: CGFloat = 184

    // A slow, calm auto-advance — gated on Reduce Motion inside `onReceive`.
    private let autoAdvance = Timer.publish(every: 7, on: .main, in: .common).autoconnect()

    private let slides: [HowItWorksSlide] = [
        HowItWorksSlide(
            id: 0, symbol: "barcode.viewfinder",
            headline: "Scan any barcode",
            line: "Point your camera, get a result in seconds."
        ),
        HowItWorksSlide(
            id: 1, symbol: "checkmark.seal",
            headline: "See a sourced score",
            line: "Every number cited, dose-aware — no black box."
        ),
        HowItWorksSlide(
            id: 2, symbol: "arrow.triangle.2.circlepath",
            headline: "Swap for a better option",
            line: "A better choice in the same category."
        )
        // TODO(home-later): featured product slide — a real curated pick
        // (image + name + our sourced score + "See why"). Intentionally omitted
        // until we actually have a featured product; we never fake one.
        // HowItWorksSlide(id: 3, symbol: "star", headline: "This week's pick",
        //     line: "A high-scoring product we like right now."),
    ]

    var body: some View {
        VStack(spacing: Theme.Space.s3) {
            TabView(selection: $page) {
                ForEach(slides) { slide in
                    // Inset each page vertically so the green card's rounded top/
                    // bottom edges don't clip against the paged TabView's bounds.
                    HowItWorksCardView(slide: slide)
                        .padding(.vertical, 6)
                        .tag(slide.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: cardHeight)
            .onReceive(autoAdvance) { _ in
                // Reduce Motion → no auto-advance at all (manual swipe stands).
                guard !reduceMotion else { return }
                withAnimation(Motion.standard) {
                    page = (page + 1) % slides.count
                }
            }

            dotRow
        }
    }

    /// Custom dots in the brand tokens: active = `green`, inactive = `greenSoft`.
    /// Purely decorative — the slides themselves are the VoiceOver elements.
    private var dotRow: some View {
        HStack(spacing: Theme.Space.s2) {
            ForEach(slides) { slide in
                Circle()
                    .fill(slide.id == page ? Theme.green : Theme.greenSoft)
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A single green showcase card: an icon in a translucent disc, a Space Grotesk
/// headline, and one calm supporting line. `greenDeep` fill keeps the white
/// text AA-legible (§7). Combined into one VoiceOver element per card.
private struct HowItWorksCardView: View {
    let slide: HowItWorksSlide
    @ScaledMetric(relativeTo: .title3) private var iconCircle: CGFloat = 48
    @ScaledMetric(relativeTo: .title3) private var iconGlyph: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s3) {
            ZStack {
                Circle().fill(Theme.onGreen.opacity(0.18))
                    .frame(width: iconCircle, height: iconCircle)
                Image(systemName: slide.symbol)
                    .font(.system(size: iconGlyph, weight: .semibold))
                    .foregroundStyle(Theme.onGreen)
            }
            .accessibilityHidden(true)

            Spacer(minLength: 0)

            Text(slide.headline)
                .font(.display(20, weight: .bold, relativeTo: .title3))
                .foregroundStyle(Theme.onGreen)
                .fixedSize(horizontal: false, vertical: true)
            Text(slide.line)
                .font(.subheadline)
                .foregroundStyle(Theme.onGreen.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.greenDeep, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        // A little inset so the paged card's rounded edges + shadow don't clip
        // against the TabView's page bounds.
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(slide.headline). \(slide.line)")
    }
}

// MARK: - Quick-action tile

/// One calm greenSoft shortcut tile: a green SF Symbol over a short label,
/// matching the Categories row tiles + Scan chrome. Presentational — the parent
/// `Button`/`NavigationLink` owns the tap + accessibility label.
private struct QuickActionTileLabel: View {
    let icon: String
    let label: String
    @ScaledMetric(relativeTo: .title3) private var glyph: CGFloat = 22

    var body: some View {
        VStack(spacing: Theme.Space.s2) {
            Image(systemName: icon)
                .font(.system(size: glyph, weight: .semibold))
                .foregroundStyle(Theme.greenDeep)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 72)
        .padding(.vertical, Theme.Space.s2)
        .background(Theme.greenSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .accessibilityHidden(true)
    }
}

// MARK: - Daily-insight tile (v3 §5.7 — optional, ED-safe)

/// A calm, one-line stat card ("3 scans this week" / "12 products saved").
/// Never a streak or guilt mechanic — purely a friendly anchor, and `HomeView`
/// omits it entirely (no empty card) when there's no pantry data yet.
private struct DailyInsightTile: View {
    let text: String
    @ScaledMetric(relativeTo: .subheadline) private var iconCircle: CGFloat = 40
    @ScaledMetric(relativeTo: .subheadline) private var iconGlyph: CGFloat = 15

    var body: some View {
        HStack(spacing: Theme.Space.s3) {
            ZStack {
                Circle().fill(Theme.greenSoft).frame(width: iconCircle, height: iconCircle)
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: iconGlyph, weight: .semibold))
                    .foregroundStyle(Theme.greenDeep)
            }
            .accessibilityHidden(true)

            Text(text)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()   // count doesn't jitter as it changes (audit)
                .foregroundStyle(Theme.textPrimary)

            Spacer(minLength: 0)
        }
        .surfaceCard()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Filter chip (v3 §5.8)

private struct FilterChipButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)  // never wrap ("Re-cent")
                .foregroundStyle(isSelected ? Theme.ink : Theme.textSecondary)
                .padding(.horizontal, Theme.Space.s4)
                .frame(minHeight: 36)
                .background(isSelected ? Theme.green : Theme.surface, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(isSelected ? .clear : Theme.border, lineWidth: 1)
                )
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel("\(label) filter")
    }
}

// MARK: - Grade dot (v3 §5.3 — mini score disc for cards)

/// Shared band → color mapping (mirrors `ScoreBadge`'s, kept local since this
/// file owns nothing in that one) — never alarm red for `.low`, per CLAUDE.md's
/// ED-safe rule.
private func bandColor(_ band: ScoreBand) -> Color {
    switch band {
    case .high: return Theme.scoreHigh
    case .mid: return Theme.scoreMid
    case .low: return Theme.scoreLow
    case .unknown: return Theme.scoreUnknown
    }
}

/// The Ingrex-style "grade dot": a small band-tinted disc with the number
/// inside, always paired with the band word beside it by callers so color is
/// never the only signal (v3 §7). Purely decorative on its own — the parent
/// card supplies one combined accessibility label instead.
private struct GradeDot: View {
    let score: Int?
    let band: ScoreBand
    var diameter: CGFloat = 28
    // One shared factor scales disc + number together with Dynamic Type.
    @ScaledMetric(relativeTo: .caption) private var scale: CGFloat = 1

    var body: some View {
        ZStack {
            Circle().fill(bandColor(band)).frame(width: diameter * scale, height: diameter * scale)
            Text(score.map(String.init) ?? "—")
                .font(.system(size: 13 * scale, weight: .bold, design: .rounded))
                .monospacedDigit()   // scores align disc-to-disc in the grid (audit)
                .foregroundStyle(Theme.ResultScreen.textOnBandFill(band))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(width: diameter * scale, height: diameter * scale)
        .accessibilityHidden(true)
    }
}

// MARK: - Product card (v3 §5.4 — the 2-col grid + trending row's shared card)

/// The one product-card language for Home: white surface, radius 20, product
/// image filling the top on `surfaceAlt`, name + brand, a grade dot + band
/// word, and a favorite heart. Used both in the Recent/Favorites 2-column
/// grid (`fixedWidth == nil`, fills its `LazyVGrid` column) and, at a fixed
/// width, in the horizontally-scrolling Trending row — one visual language
/// everywhere on Home, per the brief.
///
/// The favorite heart is added via `.overlay`, never nested inside the
/// `NavigationLink`'s label: SwiftUI does not reliably route taps to a
/// `Button` embedded inside another button/link's label, so nesting them
/// would make the heart untappable (or double-fire navigation). As a sibling
/// overlay it gets its own independent 44×44pt tap target and stays a
/// separate VoiceOver element from the card underneath.
private struct ProductCard: View {
    let product: Product
    /// `nil` lets the card fill its `LazyVGrid` column; a fixed value is used
    /// for the horizontally-scrolling Trending row.
    var fixedWidth: CGFloat? = nil

    private var band: ScoreBand { product.score?.band ?? .unknown }
    private var scoreValue: Int? { product.score?.score }

    private var accessibilityText: String {
        var parts = [product.name]
        if let brand = product.brand, !brand.isEmpty { parts.append(brand) }
        parts.append(scoreValue.map { "Score \($0) of 100, \(band.label)" } ?? band.label)
        return parts.joined(separator: ". ")
    }

    var body: some View {
        NavigationLink {
            ProductView(product: product)
        } label: {
            cardLabelContent
        }
        .buttonStyle(CardPressButtonStyle())
        .frame(width: fixedWidth, alignment: .leading)
        .accessibilityHint("Opens product details.")
        .overlay(alignment: .topTrailing) {
            FavoriteHeartInline(productID: product.id)
                .padding(6)
        }
    }

    /// Image filling the card's top edge-to-edge on `surfaceAlt`, so the
    /// whole card's outer `radius.md` clip naturally rounds its top corners
    /// too — no separate corner-only shape needed.
    private var imageHeader: some View {
        ZStack {
            Theme.surfaceAlt
            ProductThumbnail(urlString: product.imageURL, size: 92)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 132)
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s1) {
            Text(product.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let brand = product.brand, !brand.isEmpty {
                Text(brand)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            HStack(spacing: Theme.Space.s2) {
                GradeDot(score: scoreValue, band: band)
                Text(band.label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
            .padding(.top, 2)
        }
        .padding(Theme.Space.s4)
        // Reserves a consistent floor height for the text block regardless of
        // whether the name wraps to one or two lines and whether a brand is
        // present, so every card in a grid row/trending scroll starts its
        // score row at roughly the same height. A floor, not a cap — it never
        // clips content that needs more room at large Dynamic Type sizes.
        .frame(minHeight: 118, alignment: .top)
    }

    private var cardLabelContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            imageHeader
            textBlock
        }
        .surfaceCard(padded: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}

// MARK: - Favorite toggle

/// A heart button bound directly to `PantryService`'s favorites contract
/// (`isFavorite(_:)` / `toggleFavorite(productID:)`). Reads `pantryService`
/// from the environment itself so `ProductCard` can drop it in without
/// threading state through. A small white/hairline disc behind the glyph
/// keeps it legible over any product photo, while the tappable area stays a
/// full 44×44pt regardless of the smaller visible disc.
private struct FavoriteHeartInline: View {
    @Environment(PantryService.self) private var pantryService
    let productID: String
    @ScaledMetric(relativeTo: .subheadline) private var visualCircle: CGFloat = 32
    @ScaledMetric(relativeTo: .subheadline) private var glyph: CGFloat = 15

    private var isFavorite: Bool { pantryService.isFavorite(productID) }

    var body: some View {
        Button {
            Task { await pantryService.toggleFavorite(productID: productID) }
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: glyph, weight: .semibold))
                .foregroundStyle(isFavorite ? Theme.greenDeep : Theme.textSecondary)
                .frame(width: visualCircle, height: visualCircle)
                .background(Theme.surface.opacity(0.92), in: Circle())
                .overlay(Circle().strokeBorder(Theme.border, lineWidth: 1))
        }
        .frame(width: max(44, visualCircle), height: max(44, visualCircle))
        .contentShape(Circle())
        .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
        .accessibilityAddTraits(isFavorite ? [.isSelected] : [])
    }
}

// MARK: - States (empty, loading, error)

/// A calm single-message white floating card used for empty and error states
/// alike — the error variant adds a "Try again" affordance.
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
        .surfaceCard()
    }
}

/// Skeleton loader matching `ProductCard`'s geometry (image block + reserved
/// text-block height), so loading never jumps once real cards arrive. Static
/// blocks, not a shimmer animation — calm by default and automatically
/// Reduce-Motion-safe since nothing here animates.
private struct SkeletonProductCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Theme.border.opacity(0.5))
                .frame(height: 132)
            VStack(alignment: .leading, spacing: Theme.Space.s2) {
                RoundedRectangle(cornerRadius: 4).fill(Theme.border.opacity(0.6)).frame(height: 14)
                RoundedRectangle(cornerRadius: 4).fill(Theme.border.opacity(0.4)).frame(width: 80, height: 10)
                Circle().fill(Theme.border.opacity(0.5)).frame(width: 28, height: 28)
            }
            .padding(Theme.Space.s4)
            .frame(minHeight: 118, alignment: .top)
        }
        .surfaceCard(padded: false)
    }
}

/// Skeleton for the Recent/Favorites grid — mirrors `HomeView.gridColumns`
/// (single column at accessibility Dynamic Type sizes) so the loading state's
/// layout matches whatever the real grid will do once entries arrive.
private struct ProductGridSkeleton: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: Theme.Space.s4), GridItem(.flexible())]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: Theme.Space.s4) {
            ForEach(0..<4, id: \.self) { _ in SkeletonProductCard() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading your pantry")
    }
}

/// Skeleton for the horizontally-scrolling Trending row — same fixed card
/// width as the real `ProductCard(fixedWidth:)` usage.
private struct TrendingSkeletonRow: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Theme.Space.s4) {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonProductCard().frame(width: 172)
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
        .environment(NetworkMonitor())
}

#Preview("Product grid — incl. long name") {
    NavigationStack {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], spacing: 16) {
                ProductCardPreviewHost(product: PantryEntry.previewShort.asProduct())
                ProductCardPreviewHost(product: PantryEntry.previewFavorited.asProduct())
                ProductCardPreviewHost(product: PantryEntry.previewLongName.asProduct())
            }
            .padding(20)
        }
        .background(Theme.canvas)
    }
    .environment(PantryService(session: SessionService()))
}

#Preview("Filter chips") {
    HStack(spacing: 8) {
        FilterChipButton(label: "Recent", isSelected: true, action: {})
        FilterChipButton(label: "Favorites", isSelected: false, action: {})
    }
    .padding()
    .background(Theme.canvas)
}

#Preview("Trending row") {
    NavigationStack {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 16) {
                ProductCardPreviewHost(product: TrendingEntry.preview.asProduct(), fixedWidth: 172)
                ProductCardPreviewHost(product: TrendingEntry.previewLongName.asProduct(), fixedWidth: 172)
            }
            .padding(20)
        }
        .background(Theme.canvas)
    }
    .environment(PantryService(session: SessionService()))
}

#Preview("Skeletons") {
    ScrollView {
        VStack(alignment: .leading, spacing: 32) {
            ProductGridSkeleton()
            TrendingSkeletonRow()
        }
        .padding(20)
    }
    .background(Theme.canvas)
}

#Preview("Empty state") {
    VStack(spacing: 24) {
        StateCard(message: "Your pantry's empty — scan your first product.")
        StateCard(message: "That didn't load right. Give it a moment and try again.", actionTitle: "Try again", action: {})
        OfflineBanner {}
    }
    .padding(20)
    .background(Theme.canvas)
}

/// Thin pass-through to `ProductCard` so each preview above can be built with
/// plain, readable call sites; the surrounding preview supplies the single
/// `NavigationStack` each `NavigationLink`-based card needs.
private struct ProductCardPreviewHost: View {
    let product: Product
    var fixedWidth: CGFloat? = nil

    var body: some View {
        ProductCard(product: product, fixedWidth: fixedWidth)
    }
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

    /// Exercises the flexible name column + wrapping band label at their
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

    /// Exercises the trending card's reserved text-block height + name
    /// wrapping with a long name/brand pair.
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
