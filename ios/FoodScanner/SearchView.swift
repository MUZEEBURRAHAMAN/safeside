import SwiftUI

// MARK: - Query classification (Task 5 — unit-tested in SearchLogicTests)

/// Decides how typed input is handled. The 6–14 digit bound mirrors the
/// backend `BARCODE_RE` (`^\d{6,14}$`) exactly, so a typed barcode routes to
/// the identical scored `/product/:barcode` path a live scan uses, while text
/// hits name-search. A free, `@testable`-visible type — no view state.
enum SearchQuery: Equatable {
    case empty
    case barcode(String)
    case name(String)

    /// Same bounds as the backend so classification never disagrees.
    private static let barcodeRegex = /^\d{6,14}$/

    static func classify(_ raw: String) -> SearchQuery {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        if trimmed.wholeMatch(of: barcodeRegex) != nil { return .barcode(trimmed) }
        return .name(trimmed)
    }
}

// MARK: - View model

@Observable @MainActor
final class SearchViewModel {
    enum State {
        case recents
        case searching
        case results([SearchResult])
        case noResults(String)
        case error
    }

    private(set) var state: State = .recents
    /// Set to push `ProductLoaderView` for a typed barcode; bound to a
    /// `.navigationDestination(item:)`, so popping clears it.
    var pendingRoute: BarcodeRouteBox?

    /// Boxed so the destination binding lives on this observable object.
    struct BarcodeRouteBox: Identifiable, Hashable {
        let barcode: String
        var id: String { barcode }
    }

    private var searchTask: Task<Void, Never>?

    /// Debounced (~300 ms) run driven by the field's text. Classifies first:
    /// empty → recents, barcode → route straight to the scored product path,
    /// name → name-search.
    func run(query: String, api: APIClient) {
        searchTask?.cancel()
        switch SearchQuery.classify(query) {
        case .empty:
            state = .recents
        case .barcode(let code):
            // Keep the calm list behind the push; route to the scored path.
            state = .recents
            pendingRoute = BarcodeRouteBox(barcode: code)
        case .name(let q):
            searchTask = Task { [weak self] in
                await self?.performSearch(q, api: api)
            }
        }
    }

    private func performSearch(_ q: String, api: APIClient) async {
        // Debounce: let rapid typing settle before showing "Searching…".
        do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
        if Task.isCancelled { return }
        state = .searching
        do {
            let rows = try await api.search(query: q)
            if Task.isCancelled { return }
            state = rows.isEmpty ? .noResults(q) : .results(rows)
        } catch {
            if Task.isCancelled { return }
            state = .error
        }
    }
}

// MARK: - Search screen

/// Search + manual barcode entry (SCREEN_SPECS §9). Default state is a useful
/// recent-scans list — never blank (teardown STEAL #22 / AVOID #14). A typed
/// barcode takes the identical scored path as a live scan; a name hits our
/// `/search` edge function, which attaches ONLY our own cached score (never
/// Open Food Facts' Nutri-Score — transparency).
// TODO(chunk-5 follow-up): Search multi-select → CompareView (SCREEN_SPECS §10
// second entry point). Add a "Compare" mode that lets the user tick exactly two
// result rows, then push `CompareView(pair:)`. Deferred from Chunk 5 to keep
// that chunk's scope minimal — the Result-overflow entry (ProductView) ships
// the primary Compare entry. See MEMORY.md (Chunk 5).
struct SearchView: View {
    var startInBarcodeMode: Bool = false

    @Environment(SessionService.self) private var session
    @Environment(PantryService.self) private var pantryService
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var vm = SearchViewModel()
    @State private var query = ""
    @State private var barcodeMode: Bool
    @FocusState private var fieldFocused: Bool

    @ScaledMetric(relativeTo: .body) private var searchGlyph: CGFloat = 17

    init(startInBarcodeMode: Bool = false) {
        self.startInBarcodeMode = startInBarcodeMode
        _barcodeMode = State(initialValue: startInBarcodeMode)
    }

    private var api: APIClient { APIClient(session: session) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.s5) {
                stateBody
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Space.s45)
            .padding(.top, Theme.Space.s5)
            .padding(.bottom, Theme.Space.s4)
        }
        .background(Theme.canvas)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        // Oasis signature: the input is pinned to the bottom, riding just above
        // the keyboard while the list scrolls above it. `safeAreaInset` insets
        // the ScrollView so no row is ever hidden behind the bar.
        .safeAreaInset(edge: .bottom) { bottomBar }
        .navigationDestination(item: $vm.pendingRoute) { route in
            ProductLoaderView(barcode: route.barcode)
        }
        .onAppear { fieldFocused = true }
        .onChange(of: query) { _, newValue in
            vm.run(query: newValue, api: api)
        }
    }

    // MARK: Bottom search bar (pinned above the keyboard)

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            barcodeToggle
            HStack(spacing: Theme.Space.s2) {
                searchPill
                closeButton
            }
        }
        .padding(.horizontal, Theme.Space.s45)
        .padding(.top, Theme.Space.s3)
        .padding(.bottom, Theme.Space.s2)
        .background(Theme.canvas)
    }

    /// Soft-fill search pill (radius = input, not card) with the leading glyph.
    private var searchPill: some View {
        HStack(spacing: Theme.Space.s3) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: searchGlyph, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)

            TextField(
                barcodeMode ? "Barcode number" : "Search any product…",
                text: $query
            )
            .focused($fieldFocused)
            .keyboardType(barcodeMode ? .numberPad : .default)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(barcodeMode)
            .submitLabel(.search)
            .font(.body)
            .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, Theme.Space.s4)
        .frame(minHeight: 52)
        .frame(maxWidth: .infinity)
        .background(Theme.surfaceAlt, in: Capsule())
    }

    /// White circular button beside the pill (the Oasis X): clears the field
    /// when there's text, otherwise dismisses Search back toward the scanner.
    private var closeButton: some View {
        Button {
            if query.isEmpty {
                dismiss()
            } else {
                query = ""
                fieldFocused = true
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: searchGlyph, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 52, height: 52)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.border, lineWidth: 1))
        }
        .accessibilityLabel(query.isEmpty ? "Close search" : "Clear search")
    }

    /// Explicit mode switch (icon + label) so it reads as a control, not just
    /// another green link — and is visually distinct from "Scan instead".
    private var barcodeToggle: some View {
        Button {
            barcodeMode.toggle()
            query = ""
            fieldFocused = true
        } label: {
            HStack(spacing: Theme.Space.s2) {
                Image(systemName: barcodeMode ? "textformat" : "barcode.viewfinder")
                    .font(.system(size: 15, weight: .semibold))
                Text(barcodeMode ? "Search by name" : "Enter a barcode")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Theme.greenDeep)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(
            barcodeMode
                ? "Switch to searching by product name"
                : "Switch to entering a barcode number"
        )
    }

    // MARK: State body

    @ViewBuilder
    private var stateBody: some View {
        switch vm.state {
        case .recents:
            recentsSection
        case .searching:
            searchingRow
        case .results(let rows):
            resultsList(rows)
        case .noResults(let q):
            noResults(q)
        case .error:
            errorState
        }
    }

    /// Section shell: a large Space Grotesk header over a clean, divider-free
    /// list of rows — the Oasis "Popular searches" pattern (ours = recents).
    private func listSection<Rows: View>(
        header: String,
        @ViewBuilder rows: () -> Rows
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s3) {
            Text(header)
                .font(DisplayType.h1)
                .foregroundStyle(Theme.textPrimary)
            VStack(spacing: Theme.Space.s2) {
                rows()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Default state — a useful recent-scans list, never a blank screen.
    @ViewBuilder
    private var recentsSection: some View {
        if pantryService.entries.isEmpty {
            emptyState
        } else {
            listSection(header: "Recent") {
                ForEach(pantryService.entries) { entry in
                    let product = entry.asProduct()
                    NavigationLink {
                        ProductView(product: product)
                    } label: {
                        SearchResultRow(
                            name: product.name,
                            brand: product.brand,
                            imageURL: product.imageURL,
                            scoreValue: product.score?.score,
                            band: product.score?.band
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var searchingRow: some View {
        HStack(spacing: Theme.Space.s3) {
            ProgressView().tint(Theme.greenDeep)
            Text("Searching Open Food Facts…")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Theme.Space.s4)
        .accessibilityElement(children: .combine)
    }

    private func resultsList(_ rows: [SearchResult]) -> some View {
        listSection(header: "Results") {
            ForEach(rows) { row in
                Button {
                    vm.pendingRoute = SearchViewModel.BarcodeRouteBox(barcode: row.barcode)
                } label: {
                    SearchResultRow(
                        name: row.name,
                        brand: row.brand,
                        imageURL: row.imageURL,
                        scoreValue: row.score?.score,
                        band: row.score?.band
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Calm, centered no-results state (no boxy card) with the single next step.
    private func noResults(_ q: String) -> some View {
        centeredState(
            glyph: "magnifyingglass",
            headline: "No matches for '\(q)'",
            body: "Try the barcode, or snap the label.",
            action: scanInsteadButton
        )
    }

    private var errorState: some View {
        centeredState(
            glyph: "wifi.exclamationmark",
            headline: "Search isn't available",
            body: "Check your connection and try again.",
            action: AnyView(
                Button("Retry") { vm.run(query: query, api: api) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.greenDeep)
                    .frame(minHeight: 44)
            )
        )
    }

    /// Calm, centered empty recents state — muted glyph + Space Grotesk
    /// headline + one line + a single quiet action (no bordered card).
    private var emptyState: some View {
        centeredState(
            glyph: "clock.arrow.circlepath",
            headline: "No recent scans yet",
            body: "Search a product name, or enter a barcode below.",
            action: scanInsteadButton
        )
    }

    private func centeredState(
        glyph: String,
        headline: String,
        body: String,
        action: some View
    ) -> some View {
        VStack(spacing: Theme.Space.s3) {
            Image(systemName: glyph)
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            Text(headline)
                .font(DisplayType.h2)
                .foregroundStyle(Theme.textPrimary)
            Text(body)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            action
                .padding(.top, Theme.Space.s1)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.top, Theme.Space.s7)
    }

    /// Way-out that dismisses Search back toward the scanner — never a dead
    /// end. Search is always presented from a surface that owns the scanner
    /// (Home tab / scan sheet), so dismissing returns the user there.
    @Environment(\.dismiss) private var dismiss
    private var scanInsteadButton: AnyView {
        AnyView(
            Button("Scan instead") { dismiss() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.greenDeep)
                .frame(minHeight: 44)
        )
    }
}

// MARK: - Result row

/// One search / recents row in the Oasis mold: a rounded thumbnail, the product
/// name (Space Grotesk), a muted brand meta line, and — ONLY when we hold our
/// own current-version score — a green "Scored" chip with a check. Unscored rows
/// carry a neutral "Not scored yet" caption instead of any chip or colored dot,
/// so we never imply reassurance we haven't earned (teardown AVOID #5). Clean
/// and divider-free like Oasis. Purely presentational; the parent owns the tap.
private struct SearchResultRow: View {
    let name: String
    let brand: String?
    let imageURL: String?
    let scoreValue: Int?
    /// nil ⇒ not scored by us yet → neutral caption (never a chip or dot).
    let band: ScoreBand?

    private var isScored: Bool { band != nil }

    private var accessibilityText: String {
        var parts = [name]
        if let brand, !brand.isEmpty { parts.append(brand) }
        if let band {
            parts.append(scoreValue.map { "Score \($0) of 100, \(band.label)" } ?? "Scored, \(band.label)")
        } else {
            parts.append("Not scored yet")
        }
        parts.append("Opens product details.")
        return parts.joined(separator: ". ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.s3) {
            ProductThumbnail(urlString: imageURL, size: 56)

            VStack(alignment: .leading, spacing: Theme.Space.s2) {
                Text(name)
                    .font(.display(17, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let brand, !brand.isEmpty {
                    Text(brand)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }

                statusChip
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Theme.Space.s2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    /// The transparency gate: a green "tested"-style chip appears ONLY when we
    /// have our own current-version score; otherwise a neutral caption — never a
    /// chip or colored dot implying a score we don't hold.
    @ViewBuilder
    private var statusChip: some View {
        if isScored {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("Scored")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(Theme.greenDeep)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.greenSoft, in: Capsule())
        } else {
            Text("Not scored yet")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - Barcode / row → scored Result loader (Task 8)

/// Fetches `/product/:barcode` (the exact scored/cached path a live scan uses)
/// and lands on the full scored `ProductView`. While the fetch is in flight it
/// shows the real `ResultSkeletonView` — the same calm skeleton the Result
/// screen reserves for a pre-fetch open — so search-found products resolve
/// with the same chrome as a scan. Never a dead end (principle #4): a
/// not-found barcode offers "Snap the label", and any other failure offers
/// Retry.
struct ProductLoaderView: View {
    let barcode: String

    @Environment(SessionService.self) private var session
    @Environment(PantryService.self) private var pantryService
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case loading
        case loaded(Product)
        case notFound
        case failed
    }

    @State private var phase: Phase = .loading

    private var api: APIClient { APIClient(session: session) }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ScrollView { ResultSkeletonView() }
                    .background(Theme.canvas)
                    .navigationBarTitleDisplayMode(.inline)
            case .loaded(let product):
                ProductView(product: product)
            case .notFound:
                recovery(
                    message: "We don't have this one yet. Snap the ingredients label and we'll score it.",
                    actionTitle: "Scan instead",
                    action: { dismiss() }
                )
            case .failed:
                recovery(
                    message: "Couldn't reach the product database. Check your connection and try again.",
                    actionTitle: "Retry",
                    action: { phase = .loading; Task { await load() } }
                )
            }
        }
        .task(id: barcode) {
            if case .loading = phase { await load() }
        }
    }

    private func load() async {
        do {
            let product = try await api.product(barcode: barcode)
            phase = .loaded(product)
            // Auto-save to pantry so a search-found product behaves exactly
            // like a scanned one (mirrors ScanViewModel.lookUpProduct).
            pantryService.save(product: product)
        } catch APIClient.APIError.needsOCR, APIClient.APIError.notFound {
            phase = .notFound
        } catch {
            phase = .failed
        }
    }

    /// Calm, never-a-dead-end recovery card on the light canvas.
    private func recovery(message: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s4) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(actionTitle, action: action)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.greenDeep)
                .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard()
        .padding(.horizontal, Theme.Space.s45)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, Theme.Space.s5)
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Search — recents") {
    NavigationStack {
        SearchView()
    }
    .environment(SessionService())
    .environment(PantryService(session: SessionService()))
}

#Preview("Result row — scored + unscored") {
    VStack(spacing: 12) {
        SearchResultRow(name: "Nutella", brand: "Ferrero", imageURL: nil, scoreValue: 29, band: .low)
        SearchResultRow(name: "Store Oats", brand: nil, imageURL: nil, scoreValue: nil, band: nil)
    }
    .padding(20)
    .background(Theme.canvas)
}
#endif
