import SwiftUI

/// Signature component (docs/DESIGN_SYSTEM_V3.md §5.3, §1 "light-first").
/// The result screen's score treatment: a stroked band-tinted RING (never a
/// filled disc, never a heavy full-width dark hero panel) — à la the Oasis
/// detail page's circular score, but built from our own tokens and a
/// Space Grotesk number (DesignKit §3, "the score number's brand moment").
///
/// Three redundant signals — number + word + arc-length/color — so the
/// verdict is never carried by color alone (§7 a11y). Non-alarmist by
/// design: the low band uses a muted clay, never alarm red (CLAUDE.md
/// ED-safe rule).
struct ScoreBadge: View {
    let score: Int?
    let band: ScoreBand

    /// Scales gently with Dynamic Type (§7 "reflow, no clip") rather than
    /// clipping the inner number — the ring grows instead. `relativeTo`
    /// `.title2` keeps growth proportionate to the adjacent product title.
    @ScaledMetric(relativeTo: .title2) private var diameter: CGFloat = 108
    @ScaledMetric(relativeTo: .title2) private var lineWidth: CGFloat = 9

    private var color: Color {
        switch band {
        case .high: return Theme.scoreHigh
        case .mid: return Theme.scoreMid
        case .low: return Theme.scoreLow
        case .unknown: return Theme.scoreUnknown
        }
    }

    private var progress: CGFloat {
        guard let score else { return 0 }
        return CGFloat(min(max(score, 0), 100)) / 100
    }

    private var accessibilityLabelText: String {
        score.map { "Score \($0) of 100, \(band.label)" } ?? band.label
    }

    var body: some View {
        ZStack {
            // Track — the full circle, always visible so the arc reads as
            // "this much of the ring", not a mystery partial shape.
            Circle()
                .stroke(Theme.border, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            if score != nil {
                // The arc — starts at 12 o'clock, sweeps clockwise. A tiny
                // minimum trim keeps a sliver visible even at score 0 rather
                // than vanishing (still three redundant signals, never
                // color-only, since the number + word are also shown).
                Circle()
                    .trim(from: 0, to: max(progress, 0.014))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                // Unknown: a calm dashed ring — visibly "not filled in" yet,
                // without reading as an error or a zero score.
                Circle()
                    .stroke(
                        Theme.scoreUnknown,
                        style: StrokeStyle(lineWidth: lineWidth * 0.6, lineCap: .round, dash: [1, lineWidth * 2.2])
                    )
            }

            VStack(spacing: 1) {
                Text(score.map(String.init) ?? "—")
                    .font(Font.display(30, weight: .bold, relativeTo: .title2))
                    .foregroundStyle(Theme.textPrimary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(score != nil ? "/ 100" : "no score")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            .padding(lineWidth + 8)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
    }
}

#Preview("Score ring — all bands") {
    HStack(spacing: 20) {
        ScoreBadge(score: 88, band: .high)
        ScoreBadge(score: 51, band: .mid)
        ScoreBadge(score: 27, band: .low)
        ScoreBadge(score: nil, band: .unknown)
    }
    .padding()
    .background(Theme.canvas)
}

#Preview("Score ring — large Dynamic Type") {
    ScoreBadge(score: 51, band: .mid)
        .padding()
        .background(Theme.canvas)
        .dynamicTypeSize(.accessibility3)
}
