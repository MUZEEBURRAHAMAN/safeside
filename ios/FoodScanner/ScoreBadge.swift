import SwiftUI

/// Signature component (docs/DESIGN_SYSTEM.md §5.2). Three redundant signals —
/// number + word label + icon — so the verdict is never carried by color alone
/// (§8 a11y). Non-alarmist by design: the low band uses a muted clay, never
/// alarm red (CLAUDE.md ED-safe rule).
///
/// Two styles:
/// - `.compact` — dense contexts (future Pantry/Meal cards, §5.4).
/// - `.hero` — the product result screen's brand moment (§1 "bold brand, calm
///   scores"); designed to sit on the dark `gradient.hero` surface.
struct ScoreBadge: View {
    enum Style { case compact, hero }

    let score: Int?
    let band: ScoreBand
    var style: Style = .compact
    /// Hero only. When set, shows a 44×44pt "i" affordance (§5.2 "small 'i' to
    /// expand why") that the caller wires to reveal/scroll to "why this score".
    var onInfoTap: (() -> Void)? = nil

    private var color: Color {
        switch band {
        case .high: return Theme.scoreHigh
        case .mid: return Theme.scoreMid
        case .low: return Theme.scoreLow
        case .unknown: return Theme.scoreUnknown
        }
    }

    private var icon: String {
        switch band {
        case .high: return "leaf.fill"
        case .mid: return "circle.lefthalf.filled"
        case .low: return "exclamationmark.circle"   // informational, not alarmist
        case .unknown: return "questionmark.circle"
        }
    }

    private var accessibilityLabelText: String {
        score.map { "Score \($0) of 100, \(band.label)" } ?? band.label
    }

    var body: some View {
        switch style {
        case .compact: compactBody
        case .hero: heroBody
        }
    }

    // MARK: Compact — dense list/card contexts

    private var compactBody: some View {
        HStack(spacing: Theme.Space.s3) {
            ZStack {
                Circle().fill(color).frame(width: 64, height: 64)
                Text(score.map(String.init) ?? "—")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.ResultScreen.textOnBandFill(band))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 2) {
                Label(band.label, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                if let s = score {
                    Text("\(s) / 100").font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
    }

    // MARK: Hero — the result screen's brand moment

    private var heroBody: some View {
        VStack(spacing: Theme.Space.s3) {
            if let onInfoTap {
                HStack {
                    Spacer(minLength: 0)
                    Button(action: onInfoTap) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Theme.ResultScreen.textOnDarkSecondary)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Why this score")
                }
            }

            VStack(spacing: Theme.Space.s2) {
                Text(score.map(String.init) ?? "—")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.ResultScreen.textOnDarkPrimary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                Label {
                    Text(band.label).font(.title3.weight(.semibold))
                } icon: {
                    Image(systemName: icon)
                }
                .foregroundStyle(Theme.ResultScreen.textOnBandFill(band))
                .padding(.horizontal, Theme.Space.s3)
                .padding(.vertical, Theme.Space.s1)
                .background(color, in: Capsule())

                if let s = score {
                    Text("\(s) / 100")
                        .font(.subheadline)
                        .foregroundStyle(Theme.ResultScreen.textOnDarkSecondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabelText)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview("Compact") {
    VStack(spacing: 16) {
        ScoreBadge(score: 82, band: .high)
        ScoreBadge(score: 53, band: .mid)
        ScoreBadge(score: 27, band: .low)
        ScoreBadge(score: nil, band: .unknown)
    }
    .padding()
}

#Preview("Hero") {
    VStack(spacing: 24) {
        ScoreBadge(score: 88, band: .high, style: .hero, onInfoTap: {})
        ScoreBadge(score: 27, band: .low, style: .hero, onInfoTap: {})
        ScoreBadge(score: nil, band: .unknown, style: .hero)
    }
    .padding()
    .background(Theme.ResultScreen.heroGradient)
}
