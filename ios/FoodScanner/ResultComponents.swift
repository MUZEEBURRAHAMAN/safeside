import SwiftUI

/// Supporting components for the product result screen (ProductView).
/// Mirrors docs/DESIGN_SYSTEM.md §5.3 (Result Card / "why this score"), §5.5
/// (chips), §5.9 (states), §6 (iconography — no alarmist icons on scores;
/// warning iconography reserved for genuine safety/allergens).

// MARK: - Layout primitives

/// A calm, hairline row divider using a fixed-color Rectangle rather than
/// `Divider()` — SwiftUI's `Divider` does not reliably accept a tint via
/// `.overlay`/`.background` across OS versions, so a plain Rectangle is the
/// more predictable choice for a themed 1pt separator.
struct HairlineDivider: View {
    var body: some View {
        Rectangle().fill(Theme.border).frame(height: 1)
    }
}

/// Card wrapper for result-screen sections (§5.4 card anatomy: surface fill,
/// subtle border, `radius.md`, `space.4` padding).
struct SectionCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(Theme.Space.s4)
            .background(Theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }
}

/// Simple wrapping flow layout for chip rows (allergens, sources) so they
/// wrap onto multiple lines at large Dynamic Type sizes instead of clipping
/// or requiring horizontal scrolling. Stable `Layout` protocol API (iOS 16+).
struct FlowLayout: Layout {
    var spacing: CGFloat = Theme.Space.s2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            usedWidth = max(usedWidth, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        y += rowHeight
        let width = maxWidth.isFinite ? maxWidth : usedWidth
        return CGSize(width: width, height: y)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Confidence

/// "High" / "Limited data" chip (§5.3, §7 methodology). The limited state is
/// deliberately more muted/softened — it should read as a caveat, not a badge.
struct ConfidenceChip: View {
    let confidence: String // "high" | "limited"

    private var isHigh: Bool { confidence.lowercased() == "high" }

    var body: some View {
        Label {
            Text(isHigh ? "High confidence" : "Limited data")
        } icon: {
            Image(systemName: isHigh ? "checkmark.seal.fill" : "info.circle.fill")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(isHigh ? Theme.greenDeep : Theme.ResultScreen.warningTextOnLight)
        .padding(.horizontal, Theme.Space.s3)
        .padding(.vertical, Theme.Space.s1)
        .background(
            Capsule().fill(isHigh ? Theme.surfaceAlt : Theme.surface)
        )
        .overlay(
            Capsule().strokeBorder(
                (isHigh ? Theme.greenDeep : Theme.ResultScreen.warningTextOnLight).opacity(0.3),
                lineWidth: 1
            )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isHigh ? "Confidence: high" : "Confidence: limited, based on partial data")
    }
}

// MARK: - Why this score

/// A sourced, dose-aware factor row (Processing / Nutrition / Additives).
/// Headline (name, sub-score, weight) is always scannable; detail and
/// source(s) are always visible too — transparency is the product's moat, so
/// nothing here hides behind an extra tap (per docs/DESIGN_SYSTEM.md §5.3).
struct ScoreFactorRow: View {
    let factor: ScoreFactor

    private var subBand: ScoreBand { ScoreBand.from(score: factor.subScore) }

    private var barColor: Color {
        switch subBand {
        case .high: return Theme.scoreHigh
        case .mid: return Theme.scoreMid
        case .low: return Theme.scoreLow
        case .unknown: return Theme.scoreUnknown
        }
    }

    private var icon: String {
        let n = factor.name.lowercased()
        if n.contains("processing") { return "gearshape.fill" }
        if n.contains("nutrition") { return "leaf.fill" }
        if n.contains("additive") { return "flask.fill" }
        return "chart.bar.fill"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Label(factor.name, systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: Theme.Space.s2)
                Text("\(factor.subScore)/100")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }

            ProgressView(value: Double(factor.subScore), total: 100)
                .tint(barColor)
                .accessibilityHidden(true)

            Text("\(Int((factor.weight * 100).rounded()))% of the total score")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)

            Text(factor.detail)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if !factor.sources.isEmpty {
                FlowLayout(spacing: Theme.Space.s2) {
                    ForEach(factor.sources, id: \.self) { source in
                        SourceLink(source: source)
                    }
                }
            }
        }
        .padding(.vertical, Theme.Space.s2)
        .accessibilityElement(children: .combine)
    }
}

/// A single sourced citation — a tappable Link when a URL is available,
/// otherwise plain attributed text. Every point of the score is sourced
/// (docs/SCORING_METHODOLOGY.md — "the product's moat").
struct SourceLink: View {
    let source: Source

    var body: some View {
        Group {
            if let urlString = source.url, let url = URL(string: urlString) {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Text("Source: \(source.name)")
                        Image(systemName: "arrow.up.right").font(.caption2)
                    }
                }
                .foregroundStyle(Theme.greenDeep)
            } else {
                Text("Source: \(source.name)")
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .font(.caption)
    }
}

/// Card wrapping the full "why this score" breakdown: header + confidence
/// chip, an optional soft caveat when data is limited, and every factor row.
struct WhyScoreCard: View {
    let score: ScoreResult

    private var isLimited: Bool { score.confidence.lowercased() != "high" }

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Theme.Space.s3) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Why this score")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Every factor, sourced.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: Theme.Space.s2)
                    ConfidenceChip(confidence: score.confidence)
                }

                if isLimited {
                    Text("Based on partial data — treat this as a starting point.")
                        .font(.caption)
                        .foregroundStyle(Theme.ResultScreen.warningTextOnLight)
                }

                HairlineDivider()

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(score.factors.enumerated()), id: \.element.id) { index, factor in
                        ScoreFactorRow(factor: factor)
                        if index < score.factors.count - 1 {
                            HairlineDivider()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Product identity

/// Product image with graceful loading/failure/empty states (§5.9). Purely
/// decorative alongside the adjacent name/brand text, so it's hidden from
/// VoiceOver rather than announced as an untitled image.
struct ProductThumbnail: View {
    let urlString: String?
    var size: CGFloat = 72

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholder(showsProgress: true)
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder(showsProgress: false)
                    @unknown default:
                        placeholder(showsProgress: false)
                    }
                }
            } else {
                placeholder(showsProgress: false)
            }
        }
        .frame(width: size, height: size)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm).strokeBorder(Theme.border, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func placeholder(showsProgress: Bool) -> some View {
        ZStack {
            Color.clear
            if showsProgress {
                ProgressView()
            } else {
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

/// Allergen chip — the one place cautionary styling is allowed (CLAUDE.md
/// ED-safe rule + docs/DESIGN_SYSTEM.md §5.5), kept informational rather than
/// a fear-based block: a small triangle + name, not a solid alarm banner.
struct AllergenChip: View {
    let name: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill").font(.caption2)
            Text(name).font(.caption.weight(.medium))
        }
        .foregroundStyle(Theme.ResultScreen.criticalOnLight)
        .padding(.horizontal, Theme.Space.s3)
        .padding(.vertical, 6)
        .background(Theme.ResultScreen.criticalOnLight.opacity(0.08), in: Capsule())
        .overlay(
            Capsule().strokeBorder(Theme.ResultScreen.criticalOnLight.opacity(0.35), lineWidth: 1)
        )
    }
}

struct AllergenChipsRow: View {
    let allergens: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            Text("Contains")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            FlowLayout(spacing: Theme.Space.s2) {
                ForEach(allergens, id: \.self) { allergen in
                    AllergenChip(name: allergen)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Contains allergens: \(allergens.joined(separator: ", "))")
    }
}

// MARK: - Ingredients

/// A single ingredient row — name + plain "what it is" line collapsed;
/// expands to why it's used, safety notes, who should avoid it, common
/// misconceptions, where else it's found, and its sources.
struct IngredientRow: View {
    let ingredient: Ingredient
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: Theme.Space.s2) {
                if let whyUsed = ingredient.whyUsed, !whyUsed.isEmpty {
                    labeled("Why it's used", whyUsed)
                }
                if let safety = ingredient.safety, !safety.isEmpty {
                    labeled("Safety", safety)
                }
                if !ingredient.whoShouldAvoid.isEmpty {
                    labeled("Who should avoid it", ingredient.whoShouldAvoid.joined(separator: ", "))
                }
                if !ingredient.misconceptions.isEmpty {
                    labeled("Common misconceptions", ingredient.misconceptions.joined(separator: " "))
                }
                if !ingredient.foundIn.isEmpty {
                    labeled("Also found in", ingredient.foundIn.joined(separator: ", "))
                }
                if !ingredient.sources.isEmpty {
                    FlowLayout(spacing: Theme.Space.s2) {
                        ForEach(ingredient.sources, id: \.self) { SourceLink(source: $0) }
                    }
                }
                if ingredient.confidence.lowercased() != "high" {
                    Text("Based on partial data")
                        .font(.caption2)
                        .foregroundStyle(Theme.ResultScreen.warningTextOnLight)
                }
            }
            .padding(.top, Theme.Space.s2)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(ingredient.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                if let what = ingredient.what, !what.isEmpty {
                    Text(what).font(.footnote).foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.vertical, 4)
        }
        .tint(Theme.greenDeep)
    }

    private func labeled(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            Text(value).font(.footnote).foregroundStyle(Theme.textPrimary)
        }
    }
}

/// Calm empty state — never invents ingredient content that isn't there yet.
struct EmptyIngredientsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            Image(systemName: "doc.text")
                .font(.title3)
                .foregroundStyle(Theme.textSecondary)
            Text("Ingredient details are coming")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("We don't have a full ingredient breakdown for this product yet.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.s4)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Score hero

/// Wraps the hero-style `ScoreBadge` in the dark, brand-forward container
/// (§2.2/§2.3/§11 "dark first-class"). Uses the flat ink surface instead of
/// the vivid gradient when the band is `.unknown`, so a missing score never
/// reads as a celebratory brand moment.
struct ScoreHeroSection: View {
    let score: Int?
    let band: ScoreBand
    let confidence: String?
    var onInfoTap: (() -> Void)? = nil

    private var isUnknown: Bool { band == .unknown }

    var body: some View {
        VStack(spacing: Theme.Space.s3) {
            ScoreBadge(score: score, band: band, style: .hero, onInfoTap: onInfoTap)
            if let confidence {
                ConfidenceChip(confidence: confidence)
            }
        }
        .padding(.vertical, Theme.Space.s6)
        .padding(.horizontal, Theme.Space.s4)
        .frame(maxWidth: .infinity)
        .background(
            Group {
                if isUnknown {
                    Theme.ResultScreen.heroFlatUnknown
                } else {
                    Theme.ResultScreen.heroGradient
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
    }
}

// MARK: - Next action

/// The result's footer CTA (§5.3: "Footer action ... never a dead-end").
struct NextActionButton: View {
    private let title: String
    private let systemImage: String?
    private let action: () -> Void

    init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.s2) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title).font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .foregroundStyle(Theme.onGreen)
        .background(Theme.greenDeep, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
    }
}

// MARK: - Attribution

struct AttributionFooter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Data from Open Food Facts")
            Text("Information only — not medical advice.")
        }
        .font(.caption2)
        .foregroundStyle(Theme.textSecondary)
    }
}

// MARK: - Loading skeleton (§5.9)

/// Designed loading state for the result screen. Not currently wired into
/// `ProductView` (the caller only constructs `ProductView` once a `Product`
/// has already been fetched — see ScannerView.swift's `.lookingUp` phase,
/// which owns the loading banner today). This is the documented design for
/// the day ProductView accepts an in-flight/optional product.
struct ResultSkeletonView: View {
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s5) {
            HStack(spacing: Theme.Space.s3) {
                block(width: 72, height: 72, radius: Theme.Radius.sm)
                VStack(alignment: .leading, spacing: Theme.Space.s2) {
                    block(width: 160, height: 20, radius: 4)
                    block(width: 100, height: 14, radius: 4)
                }
                Spacer(minLength: 0)
            }
            block(width: nil, height: 180, radius: Theme.Radius.lg)
            block(width: nil, height: 220, radius: Theme.Radius.md)
            block(width: nil, height: 48, radius: Theme.Radius.md)
        }
        .padding(Theme.Space.s4)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading product result")
    }

    @ViewBuilder
    private func block(width: CGFloat?, height: CGFloat, radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(pulse ? Theme.ResultScreen.skeletonHighlight : Theme.ResultScreen.skeletonBase)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
    }
}

#Preview("Loading skeleton") {
    ResultSkeletonView()
}

#Preview("Confidence chips") {
    HStack {
        ConfidenceChip(confidence: "high")
        ConfidenceChip(confidence: "limited")
    }
    .padding()
}

#Preview("Allergen chips") {
    AllergenChipsRow(allergens: ["Milk", "Wheat", "Soy", "Tree nuts"])
        .padding()
}
