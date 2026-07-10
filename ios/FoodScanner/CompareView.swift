import SwiftUI

// TODO(chunk-2 done → follow-up): Search multi-select → CompareView is left as
// the secondary entry point (SCREEN_SPECS §10). The Result-overflow entry
// (ProductView) is the primary one and ships now; see MEMORY.md for why the
// Search tick-two-rows affordance is deferred rather than half-wired here.

/// Compare v1 (SCREEN_SPECS §10): two already-scored products side by side.
///
/// Pure client screen — it never fetches, never scores, never computes a
/// nutrition number (CLAUDE.md #5). Every value comes from each `Product`'s
/// backend `ScoreResult`; `ComparePair` only decides which side reads higher.
///
/// - Aligned metric rows (Overall + the three factor sub-scores) render both
///   sides on ONE fixed 0–100 scale, so bar lengths are directly comparable.
/// - The per-row winner gets a *subtle* band-colour wash on its own side only —
///   never a penalty colour on the other side, never alarm-red (teardown
///   AVOID #1/#5; ED-safe: "Pick this one", never "this is worse").
/// - Never a dead-end: each column's "Pick this one" saves to the pantry and
///   returns the user to where they came from (principle #4).
struct CompareView: View {
    let pair: ComparePair

    @Environment(PantryService.self) private var pantryService
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss

    /// Which single column the compact (accessibility-size) layout shows.
    @State private var selectedSide: ComparePair.Side = .a
    /// Which side the user just picked — flips the CTA to the saved confirmation.
    @State private var savedSide: ComparePair.Side?

    /// iPhone has no split-view width class, so accessibility Dynamic Type is
    /// the "compact" proxy (matches ProductView's reflow guard).
    private var compact: Bool { dynamicTypeSize.isAccessibilitySize }

    init(pair: ComparePair) { self.pair = pair }
    init(a: Product, b: Product) { self.pair = ComparePair(a: a, b: b) }

    var body: some View {
        VStack(spacing: 0) {
            // Sticky A/B toggle for the compact layout — always visible above
            // the scrolling content so switching sides is one tap away.
            if compact {
                Picker("Product", selection: $selectedSide) {
                    Text(compactLabel(pair.a.name)).tag(ComparePair.Side.a)
                    Text(compactLabel(pair.b.name)).tag(ComparePair.Side.b)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.Space.s4)
                .padding(.vertical, Theme.Space.s3)
                .background(Theme.canvas)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s5) {
                    if compact {
                        compactColumn(for: selectedSide)
                    } else {
                        sideBySideHeader
                        metricRows
                    }
                }
                .padding(.horizontal, Theme.Space.s4)
                .padding(.vertical, Theme.Space.s5)
            }
        }
        .background(Theme.canvas)
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Side-by-side (standard) layout

    private var sideBySideHeader: some View {
        HStack(alignment: .top, spacing: Theme.Space.s3) {
            headerColumn(for: .a)
            headerColumn(for: .b)
        }
    }

    private var metricRows: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s4) {
            ForEach(pair.rows) { row in
                metricBlock(row)
            }

            // CTA per column — primary green for the overall winner, quiet
            // outline for the other (never a "loser" penalty).
            HStack(spacing: Theme.Space.s3) {
                pickButton(for: .a, primary: pair.overallWinner == .a)
                pickButton(for: .b, primary: pair.overallWinner == .b)
            }
            .padding(.top, Theme.Space.s2)
        }
    }

    /// One aligned metric: the label, then each side's meter stacked on the
    /// same 0–100 scale (A above B), winner side subtly emphasised.
    private func metricBlock(_ row: ComparePair.MetricRow) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s3) {
            Text(row.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            SharedScaleMeter(value: row.valueA, band: row.bandA,
                             trailingText: valueText(row.valueA),
                             emphasized: row.winner == .a)
            SharedScaleMeter(value: row.valueB, band: row.bandB,
                             trailingText: valueText(row.valueB),
                             emphasized: row.winner == .b)
        }
        .padding(Theme.Space.s4)
        .surfaceCard(padded: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel(row))
    }

    // MARK: Compact (stacked / accessibility) layout

    /// A single product's card — header + its own meters on the shared 0–100
    /// scale — plus its "Pick this one" CTA. Toggling the sticky A/B picker
    /// swaps sides; the fixed scale keeps the two directly comparable.
    private func compactColumn(for side: ComparePair.Side) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s5) {
            headerColumn(for: side)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: Theme.Space.s4) {
                ForEach(pair.rows) { row in
                    let value = side == .a ? row.valueA : row.valueB
                    let band = side == .a ? row.bandA : row.bandB
                    VStack(alignment: .leading, spacing: Theme.Space.s2) {
                        HStack {
                            Text(row.label)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer(minLength: Theme.Space.s2)
                            if row.winner == side {
                                Text("Higher")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(band.tint)
                            }
                        }
                        SharedScaleMeter(value: value, band: band,
                                         trailingText: valueText(value),
                                         emphasized: row.winner == side)
                    }
                    .padding(Theme.Space.s4)
                    .surfaceCard(padded: false)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(compactRowAccessibilityLabel(row, side: side))
                }
            }

            pickButton(for: side, primary: pair.overallWinner == side)
        }
    }

    // MARK: Shared pieces

    private func headerColumn(for side: ComparePair.Side) -> some View {
        let product = product(for: side)
        return VStack(spacing: Theme.Space.s3) {
            FloatingProductImage(urlString: product.imageURL, size: compact ? 132 : 104)
            VStack(spacing: 2) {
                Text(product.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let brand = product.brand, !brand.isEmpty {
                    Text(brand)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            ScoreBadge(score: product.score?.score,
                       band: product.score?.band ?? .unknown,
                       diameter: compact ? 108 : 76,
                       lineWidth: compact ? 8 : 6)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func pickButton(for side: ComparePair.Side, primary: Bool) -> some View {
        let isSaved = savedSide == side
        return Button {
            pantryService.save(product: product(for: side))
            withAnimation(.snappy) { savedSide = side }
            Task {
                try? await Task.sleep(nanoseconds: 900_000_000)
                dismiss()
            }
        } label: {
            Text(isSaved ? "Saved to pantry." : "Pick this one")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .foregroundStyle(primary && !isSaved ? Theme.onGreen : Theme.greenDeep)
        .background {
            if primary && !isSaved {
                Capsule().fill(Theme.greenDeep)
            } else {
                Capsule().strokeBorder(Theme.greenDeep.opacity(isSaved ? 0.4 : 1), lineWidth: 1.5)
            }
        }
        .disabled(savedSide != nil)
        .accessibilityLabel(isSaved
            ? "Saved to pantry."
            : "Pick \(product(for: side).name)")
    }

    // MARK: Helpers

    private func product(for side: ComparePair.Side) -> Product {
        side == .b ? pair.b : pair.a
    }

    private func valueText(_ value: Int?) -> String {
        value.map { "\($0)/100" } ?? "—"
    }

    /// Compact toggle label — product name truncated at 18 chars + ellipsis
    /// (COPY_DECK §Compare).
    private func compactLabel(_ name: String) -> String {
        name.count > 18 ? String(name.prefix(18)) + "…" : name
    }

    /// VoiceOver reads the aligned row as one element: label, each side's
    /// value, then the winner sentence (COPY_DECK: "{Product} scores higher on
    /// {metric}"). "no score" for an unscored side — never a fabricated number.
    private func rowAccessibilityLabel(_ row: ComparePair.MetricRow) -> String {
        var parts = ["\(row.label).",
                     "\(pair.a.name) \(spoken(row.valueA)).",
                     "\(pair.b.name) \(spoken(row.valueB))."]
        if let winnerName = winnerName(row.winner) {
            parts.append("\(winnerName) scores higher on \(row.label).")
        }
        return parts.joined(separator: " ")
    }

    private func compactRowAccessibilityLabel(_ row: ComparePair.MetricRow,
                                              side: ComparePair.Side) -> String {
        let value = side == .a ? row.valueA : row.valueB
        var label = "\(row.label). \(product(for: side).name) \(spoken(value))."
        if row.winner == side {
            label += " \(product(for: side).name) scores higher on \(row.label)."
        }
        return label
    }

    private func spoken(_ value: Int?) -> String {
        value.map { "\($0) of 100" } ?? "no score"
    }

    private func winnerName(_ side: ComparePair.Side) -> String? {
        switch side {
        case .a: return pair.a.name
        case .b: return pair.b.name
        case .tie: return nil
        }
    }
}

#if DEBUG
#Preview("Compare — side by side") {
    NavigationStack {
        CompareView(a: .sampleScored, b: .sampleScoredHigh)
    }
    .environment(PantryService(session: SessionService()))
}

#Preview("Compare — compact (AX3 stacked)") {
    NavigationStack {
        CompareView(a: .sampleScored, b: .sampleScoredHigh)
    }
    .environment(PantryService(session: SessionService()))
    .dynamicTypeSize(.accessibility3)
}
#endif
