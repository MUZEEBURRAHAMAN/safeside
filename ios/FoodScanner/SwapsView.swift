import SwiftUI

/// "See a better option" — the sheet that closes the loop no competitor closes
/// (principle #4): a scanned verdict → a concrete, ranked, restriction-safe
/// better choice in the same category (SCREEN_SPECS §5). Replaces the honest
/// `NextActionSheet` stub, whose "scan another" behaviour now lives in the
/// empty/thin state below.
///
/// Everything shown is backend-owned and sourced: the `delta` and each
/// `whyBetter` fact are deterministic diffs of stored DB fields computed
/// server-side (CLAUDE.md #5 — the LLM never does the math). The client renders
/// them verbatim, performs ZERO score arithmetic, and never fabricates a swap —
/// a thin result shows the honest note, never a blank sheet (AVOID-14).
struct SwapsView: View {
    let product: Product
    /// Invoked by the empty-state "Scan another" button — the caller dismisses
    /// the sheet and routes to the scanner (mirrors the retired stub).
    let onScanAnother: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(SessionService.self) private var session
    @Environment(PantryService.self) private var pantryService

    private enum Phase {
        case loading
        case loaded(SwapsResponse)
        case failed
    }

    @State private var phase: Phase = .loading

    private var apiClient: APIClient { APIClient(session: session) }

    private var navTitle: String {
        if case .loaded(let resp) = phase, let category = resp.category {
            return "Better options in \(category)"
        }
        return "Better options"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(.horizontal, Theme.Space.s4)
                    .padding(.vertical, Theme.Space.s4)
            }
            .background(Theme.canvas)
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .navigationDestination(for: String.self) { barcode in
                ProductLoaderView(barcode: barcode)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            loadingState
        case .loaded(let resp):
            loadedState(resp)
        case .failed:
            errorState
        }
    }

    // MARK: Loading

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s4) {
            Text("Finding better options…")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            ForEach(0..<3, id: \.self) { _ in SwapSkeletonCard() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Finding better options")
    }

    // MARK: Loaded

    @ViewBuilder
    private func loadedState(_ resp: SwapsResponse) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s4) {
            if resp.filteredForAllergies {
                Label("Filtered for your allergies.", systemImage: "checkmark.shield")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.greenDeep)
                    .accessibilityLabel("Filtered for your allergies")
            }

            ForEach(resp.swaps) { candidate in
                SwapCard(candidate: candidate)
            }

            // Honest note: no better option, OR only a near-miss (thin) result.
            // The retired stub's "scan another" behaviour lives here now.
            if resp.swaps.isEmpty || resp.thin {
                honestNote(hasSome: !resp.swaps.isEmpty)
            }
        }
    }

    private func honestNote(hasSome: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s3) {
            Text("Few close matches in this category yet. Here's the nearest — or scan another to compare.")
                .font(.subheadline)
                .foregroundStyle(hasSome ? Theme.textSecondary : Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                onScanAnother()
            } label: {
                HStack(spacing: Theme.Space.s2) {
                    Image(systemName: "barcode.viewfinder")
                    Text("Scan another").font(.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 52)
            }
            .foregroundStyle(Theme.onGreen)
            .background(Theme.greenDeep, in: Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard()
    }

    // MARK: Error

    private var errorState: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s4) {
            Text("Couldn't load better options. Check your connection and try again.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Retry") {
                phase = .loading
                Task { await load() }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.greenDeep)
            .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard()
    }

    // MARK: Load

    private func load() async {
        do {
            let resp = try await apiClient.swaps(productID: product.id)
            phase = .loaded(resp)
        } catch {
            phase = .failed
        }
    }
}

// MARK: - Swap card

/// One ranked better option: thumbnail, name + brand, mini score ring, a
/// band-tinted delta chip, a 1-line sourced why-better, an optional "In your
/// pantry" chip, and View · Save-to-pantry actions. Reflows to a vertical stack
/// at accessibility Dynamic Type sizes (SCREEN_SPECS §5 responsive).
private struct SwapCard: View {
    let candidate: SwapCandidate

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(PantryService.self) private var pantryService

    @State private var saved = false

    private var bandColor: Color {
        switch candidate.band {
        case .high: return Theme.scoreHigh
        case .mid: return Theme.scoreMid
        case .low: return Theme.scoreLow
        case .unknown: return Theme.scoreUnknown
        }
    }

    /// One sensible VoiceOver sentence for the informational block (SCREEN_SPECS
    /// §5 A11y). The action buttons stay separately focusable below.
    private var infoAccessibilityLabel: String {
        var parts = ["Better option: \(candidate.name)"]
        parts.append("score \(candidate.score), \(candidate.band.label)")
        parts.append("plus \(candidate.delta) versus this product")
        if !candidate.whyBetter.isEmpty {
            parts.append(candidate.whyBetter.joined(separator: ", "))
        }
        if candidate.inPantry { parts.append("In your pantry") }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s3) {
            infoBlock
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(infoAccessibilityLabel)
            actionsRow
        }
        .surfaceCard()
    }

    @ViewBuilder
    private var infoBlock: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Theme.Space.s3) {
                HStack(spacing: Theme.Space.s3) {
                    ProductThumbnail(urlString: candidate.imageURL, size: 52)
                    ScoreBadge(score: candidate.score, band: candidate.band,
                               diameter: 52, lineWidth: 5)
                }
                nameAndBrand
                chipsAndWhy
            }
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.s3) {
                HStack(spacing: Theme.Space.s3) {
                    ProductThumbnail(urlString: candidate.imageURL, size: 52)
                    nameAndBrand
                    Spacer(minLength: 0)
                    ScoreBadge(score: candidate.score, band: candidate.band,
                               diameter: 52, lineWidth: 5)
                }
                chipsAndWhy
            }
        }
    }

    private var nameAndBrand: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(candidate.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let brand = candidate.brand, !brand.isEmpty {
                Text(brand)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chipsAndWhy: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            HStack(spacing: Theme.Space.s2) {
                deltaChip
                if candidate.inPantry { pantryChip }
            }
            if !candidate.whyBetter.isEmpty {
                Text(candidate.whyBetter.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // Band-tinted, never alarm red (band colors only — AVOID-1/5). Tabular
    // digits so the "+N" reads as a stable number (make-interfaces-feel-better).
    private var deltaChip: some View {
        Text("+\(candidate.delta) score")
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(bandColor)
            .padding(.horizontal, Theme.Space.s2)
            .padding(.vertical, 4)
            .background(bandColor.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(bandColor.opacity(0.4), lineWidth: 1))
    }

    private var pantryChip: some View {
        Label("In your pantry", systemImage: "cabinet")
            .font(.caption2.weight(.medium))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, Theme.Space.s2)
            .padding(.vertical, 4)
            .background(Theme.greenSoft, in: Capsule())
    }

    private var actionsRow: some View {
        HStack(spacing: Theme.Space.s3) {
            if let barcode = candidate.barcode {
                NavigationLink(value: barcode) {
                    Text("View")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .foregroundStyle(Theme.onGreen)
                .background(Theme.greenDeep, in: Capsule())
            }

            Button {
                pantryService.saveToPantry(productID: candidate.id)
                withAnimation(.snappy) { saved = true }
            } label: {
                Label(saved ? "Saved" : "Save to pantry",
                      systemImage: saved ? "checkmark" : "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .foregroundStyle(saved ? Theme.textSecondary : Theme.greenDeep)
            .background(
                Capsule().strokeBorder(
                    (saved ? Theme.textSecondary : Theme.greenDeep).opacity(0.4),
                    lineWidth: 1
                )
            )
            .disabled(saved)
            .accessibilityLabel(saved ? "Saved to pantry" : "Save to pantry")
        }
    }
}

// MARK: - Loading skeleton card

private struct SwapSkeletonCard: View {
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s3) {
            HStack(spacing: Theme.Space.s3) {
                block(width: 52, height: 52, radius: Theme.Radius.sm)
                VStack(alignment: .leading, spacing: Theme.Space.s2) {
                    block(width: 150, height: 16, radius: 4)
                    block(width: 90, height: 12, radius: 4)
                }
                Spacer(minLength: 0)
                block(width: 52, height: 52, radius: 26)
            }
            block(width: nil, height: 44, radius: Theme.Radius.full)
        }
        .surfaceCard()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func block(width: CGFloat?, height: CGFloat, radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(pulse ? Theme.ResultScreen.skeletonHighlight : Theme.ResultScreen.skeletonBase)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
    }
}

// MARK: - Previews

#if DEBUG
private let swapsPreviewProduct = Product(
    id: "subject-1", barcode: "9990000000001", name: "Choco Hazelnut Spread",
    brand: "DemoBrand", imageURL: nil, score: nil, ingredients: [], allergens: [],
    dataConfidence: "high"
)

#Preview("Swaps — loaded (2 cards)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        SwapsView(product: swapsPreviewProduct, onScanAnother: {})
            .environment(SessionService())
            .environment(PantryService(session: SessionService()))
    }
}
#endif
