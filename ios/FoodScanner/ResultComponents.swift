import SwiftUI

/// Supporting components for the product result screen (ProductView).
/// Rebuilt to the Oasis-beating shape in docs/DESIGN_SYSTEM_V3.md §5 —
/// light-first, FLAT cards (no shadow, per DesignKit.swift), a stroked score
/// RING (see ScoreBadge.swift) instead of a dark hero, a tri-metric row, and
/// calm color-coded ingredient cards (never alarm red — CLAUDE.md ED-safe
/// rule). Mirrors docs/DESIGN_SYSTEM.md §5.5 (chips), §5.9 (states), §6
/// (iconography — no alarmist icons on scores; warning iconography reserved
/// for genuine safety/allergens, and even that stays a calm caution tone).

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

/// Card wrapper for result-screen sections. FLAT (no shadow, per
/// `DesignKit.surfaceCard()`) — depth comes from the hairline border against
/// the tinted canvas, not elevation.
struct SectionCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .surfaceCard()
    }
}

/// Simple wrapping flow layout for chip rows (allergens, sources, trust
/// chips) so they wrap onto multiple lines at large Dynamic Type sizes
/// instead of clipping or requiring horizontal scrolling. Stable `Layout`
/// protocol API (iOS 16+).
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

// MARK: - Collapsible section

/// A calm, hand-rolled collapsible section. Native `DisclosureGroup`'s
/// automatic label-as-button composition doesn't leave clean room for a
/// trailing badge (e.g. the confidence chip) beside the chevron, so this
/// hand-rolls the same interaction: a header row (any content + a rotating
/// chevron, 44pt tall) toggles the body below. `cardStyle` wraps the whole
/// thing in the flat `SectionCard` treatment for sections that are a single
/// cohesive panel (e.g. "Why this score"); pass `false` for sections whose
/// body is already its own row of cards/links floating on the canvas (e.g.
/// "What's inside", "Sources") so we don't nest a card inside a card.
struct CollapsibleSection<Header: View, Content: View>: View {
    @State private var isExpanded: Bool
    private let cardStyle: Bool
    private let header: Header
    private let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        initiallyExpanded: Bool = true,
        cardStyle: Bool = true,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        _isExpanded = State(initialValue: initiallyExpanded)
        self.cardStyle = cardStyle
        self.header = header()
        self.content = content()
    }

    var body: some View {
        Group {
            if cardStyle {
                SectionCard { sectionBody }
            } else {
                sectionBody
            }
        }
    }

    private var sectionBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            toggleHeader
            if isExpanded {
                content
                    .padding(.top, Theme.Space.s3)
                    .transition(.opacity)
            }
        }
    }

    private var toggleHeader: some View {
        Button {
            withAnimation(Motion.respecting(Motion.standard, reduceMotion)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(alignment: .center, spacing: Theme.Space.s2) {
                header
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}

// MARK: - Confidence & trust chips

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

/// A neutral data-source/category chip (§5.3 "chips: category + data-source").
/// Same pill shape as `ConfidenceChip` but purely informational — no
/// judgment, no color-coding.
struct SourceChip: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, Theme.Space.s3)
            .padding(.vertical, Theme.Space.s1)
            .background(Capsule().fill(Theme.surfaceAlt))
            .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
    }
}

// MARK: - Tri-metric row (§5.2 — the key steal, made more transparent)

/// Three equal columns — Nutrition / Additives / Processing — each showing
/// its sub-score, a short calm qualitative word, and a band-tinted bar.
/// Replaces Oasis's binary "Beneficial ingredients / Harmful substances"
/// counts with our sourced, ordinal sub-scores: more informative, still
/// scannable in one glance, and it's what "Why this score" right below is
/// about to explain in full.
struct TriMetricRow: View {
    let factors: [ScoreFactor]

    /// Fixed display order regardless of the order the backend returns
    /// factors in, so the row always reads Nutrition → Additives →
    /// Processing.
    private static let displayOrder = ["Nutrition", "Additives", "Processing"]

    private func factor(named name: String) -> ScoreFactor? {
        factors.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    var body: some View {
        HStack(spacing: Theme.Space.s3) {
            ForEach(Self.displayOrder, id: \.self) { name in
                if let factor = factor(named: name) {
                    TriMetricTile(factor: factor)
                }
            }
        }
    }
}

private struct TriMetricTile: View {
    let factor: ScoreFactor

    private var subBand: ScoreBand { ScoreBand.from(score: factor.subScore) }

    private var tint: Color {
        switch subBand {
        case .high: return Theme.scoreHigh
        case .mid: return Theme.scoreMid
        case .low: return Theme.scoreLow
        case .unknown: return Theme.scoreUnknown
        }
    }

    /// Short, calm, non-alarmist qualitative word — deliberately distinct
    /// from `ScoreBand.label` (which is a full-sentence overall verdict);
    /// this is a compact per-metric echo that fits a narrow tile.
    private var word: String {
        switch subBand {
        case .high: return "Strong"
        case .mid: return "Moderate"
        case .low: return "Limited"
        case .unknown: return "Unknown"
        }
    }

    private var icon: String {
        let n = factor.name.lowercased()
        if n.contains("nutrition") { return "leaf.fill" }
        if n.contains("additive") { return "flask.fill" }
        if n.contains("processing") { return "gearshape.fill" }
        return "chart.bar.fill"
    }

    var body: some View {
        VStack(spacing: Theme.Space.s1) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
            Text(factor.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(word)
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint)
            ProgressView(value: Double(factor.subScore), total: 100)
                .tint(tint)
                .accessibilityHidden(true)
            Text("\(factor.subScore)/100")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, Theme.Space.s3)
        .padding(.horizontal, Theme.Space.s2)
        .frame(maxWidth: .infinity)
        .surfaceCard(padded: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(factor.name): \(factor.subScore) of 100, \(word)")
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

/// The full "why this score" breakdown, collapsible (default OPEN — this is
/// the transparency moat, per docs/DESIGN_SYSTEM_V3.md it stays above the
/// fold): header + confidence chip in the toggle row, an optional soft
/// caveat when data is limited, and every factor row.
struct WhyScoreSection: View {
    let score: ScoreResult

    private var isLimited: Bool { score.confidence.lowercased() != "high" }

    var body: some View {
        CollapsibleSection {
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
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                if isLimited {
                    Text("Based on partial data — treat this as a starting point.")
                        .font(.caption)
                        .foregroundStyle(Theme.ResultScreen.warningTextOnLight)
                        .padding(.bottom, Theme.Space.s2)
                }

                HairlineDivider()

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

// MARK: - Product identity

/// Small square product thumbnail with graceful loading/failure/empty states
/// (§5.9). Used in dense contexts (Home's recent-scans grid). Purely
/// decorative alongside adjacent name/brand text, so it's hidden from
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

/// The result screen's product image — floats directly on the light canvas
/// (NOT inside a heavy card), per docs/DESIGN_SYSTEM_V3.md §1 and the Oasis
/// detail-page shape the founder asked us to match. A soft tinted backdrop
/// keeps broken/missing images from reading as an error.
struct FloatingProductImage: View {
    let urlString: String?
    var size: CGFloat = 152

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholder(showsProgress: true)
                    case .success(let image):
                        image.resizable().scaledToFit().padding(Theme.Space.s4)
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
        .background(Theme.surfaceAlt, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func placeholder(showsProgress: Bool) -> some View {
        if showsProgress {
            ProgressView()
        } else {
            Image(systemName: "shippingbox")
                .font(.system(size: 36))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

/// Allergen chip — the one place cautionary styling is allowed (CLAUDE.md
/// ED-safe rule + docs/DESIGN_SYSTEM.md §5.5), but kept CALM: an amber
/// caution tone, never the alarm-red treatment. Informational, not a
/// fear-based block — a small icon + name, matching Oasis's chip shape.
struct AllergenChip: View {
    let name: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill").font(.caption2)
            Text(name.localizedCapitalized).font(.caption.weight(.medium))
        }
        .foregroundStyle(Theme.ResultScreen.warningTextOnLight)
        .padding(.horizontal, Theme.Space.s3)
        .padding(.vertical, 6)
        .background(Theme.scoreMid.opacity(0.12), in: Capsule())
        .overlay(
            Capsule().strokeBorder(Theme.scoreMid.opacity(0.4), lineWidth: 1)
        )
    }
}

struct AllergenChipsRow: View {
    let allergens: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            FlowLayout(spacing: Theme.Space.s2) {
                ForEach(allergens, id: \.self) { allergen in
                    AllergenChip(name: allergen)
                }
            }
            Text("Always check the label to confirm.")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Contains allergens: \(allergens.joined(separator: ", ")). Always check the label to confirm.")
    }
}

// MARK: - Ingredients ("What's inside")

/// A single ingredient card with a CALM color-coded left accent — green for
/// low concern, amber for moderate, clay for higher (NEVER red, per
/// CLAUDE.md's ED-safe rule). Collapsed to name + plain "what it is" line;
/// "Read more" expands why it's used, safety notes, who should avoid it,
/// common misconceptions, and sources. An ingredient with no vetted data at
/// all renders as a neutral calm card instead of a scary empty state.
struct IngredientCard: View {
    let ingredient: Ingredient
    @State private var isExpanded = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var riskTier: String? { ingredient.riskTier?.lowercased() }

    /// True once we have *any* vetted content to show — matches the backend
    /// contract where a not-yet-explained ingredient (e.g. "Natural
    /// flavouring" in PreviewSupport's sample) arrives with every field nil.
    private var hasVettedInfo: Bool {
        (ingredient.what?.isEmpty == false)
            || (ingredient.whyUsed?.isEmpty == false)
            || (ingredient.safety?.isEmpty == false)
            || riskTier != nil
    }

    private var accentColor: Color {
        guard hasVettedInfo else { return Theme.scoreUnknown }
        switch riskTier {
        case "low": return Theme.scoreHigh
        case "moderate": return Theme.scoreMid
        case "higher": return Theme.scoreLow
        default: return Theme.scoreUnknown
        }
    }

    private var hasExpandableDetail: Bool {
        (ingredient.whyUsed?.isEmpty == false)
            || (ingredient.safety?.isEmpty == false)
            || !ingredient.whoShouldAvoid.isEmpty
            || !ingredient.misconceptions.isEmpty
            || !ingredient.foundIn.isEmpty
            || !ingredient.sources.isEmpty
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.s3) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accentColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: Theme.Space.s2) {
                Text(ingredient.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)

                if hasVettedInfo {
                    if let what = ingredient.what, !what.isEmpty {
                        Text(what)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if isExpanded {
                        expandedDetail
                    }

                    if hasExpandableDetail {
                        Button(isExpanded ? "Show less" : "Read more") {
                            withAnimation(Motion.respecting(Motion.standard, reduceMotion)) {
                                isExpanded.toggle()
                            }
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.greenDeep)
                        .padding(.vertical, Theme.Space.s1)
                        .contentShape(Rectangle())
                    }
                } else {
                    Text("We don't have vetted info on this ingredient yet.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Theme.Space.s3)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var expandedDetail: some View {
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
        .surfaceCard()
        .accessibilityElement(children: .combine)
    }
}

/// Loading state for the lazily-fetched ingredient explanations (§5.9
/// "Loading: skeletons for lists"). Pulses like `ResultSkeletonView`, and is
/// likewise skipped under Reduce Motion.
struct IngredientsSkeletonView: View {
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s3) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: Theme.Space.s2) {
                    block(width: 140, height: 14)
                    block(width: 220, height: 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .surfaceCard()
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading ingredient details")
    }

    @ViewBuilder
    private func block(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(pulse ? Theme.ResultScreen.skeletonHighlight : Theme.ResultScreen.skeletonBase)
            .frame(width: width, height: height)
    }
}

/// Calm, actionable error state for a failed ingredients fetch
/// (docs/COPY_DECK.md Errors: "what happened + how to fix"). A 44pt retry
/// target, not a dead-end.
struct IngredientsLoadErrorView: View {
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            Text("Something went wrong.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("We couldn't load ingredient details. Try again.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            Button(action: retry) {
                Text("Try again")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .foregroundStyle(Theme.greenDeep)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Sources

/// The collapsible "Sources" section — every factor + ingredient citation,
/// deduplicated, in one place (our credibility, alongside "Why this score").
/// Plain links floating on the canvas (no card), matching the Oasis
/// reference's plain "Sources" list.
struct SourcesSection: View {
    let sources: [Source]

    var body: some View {
        CollapsibleSection(initiallyExpanded: false, cardStyle: false) {
            HStack {
                Text("Sources")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: Theme.Space.s2)
                Text("\(sources.count)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        } content: {
            VStack(alignment: .leading, spacing: Theme.Space.s3) {
                ForEach(sources, id: \.self) { source in
                    SourceLink(source: source)
                }
            }
        }
    }
}

// MARK: - Utility rows (§ "How scoring works" / "Report an issue")

/// A calm list row with a leading icon and trailing chevron — the Oasis
/// footer-utility shape ("How scoring works" / "Report an issue"), 44pt tall.
struct UtilityRow: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.s3) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.greenDeep)
                    .frame(width: 24)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: Theme.Space.s2)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Groups the two utility rows into one flat card, like Oasis's grouped
/// footer block.
struct UtilityRowsSection: View {
    let onScoringInfo: () -> Void
    let onReportIssue: () -> Void

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 0) {
                UtilityRow(title: "How scoring works", systemImage: "chart.pie.fill", action: onScoringInfo)
                HairlineDivider()
                UtilityRow(title: "Report an issue", systemImage: "flag.fill", action: onReportIssue)
            }
        }
    }
}

/// The plain-language methodology explainer (docs/SCORING_METHODOLOGY.md
/// §2/§4) — "the transparency is the marketing, not just compliance" (§8).
struct MethodologySheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s5) {
                    Text("Your score blends three sourced factors — never estimated by AI, always computed the same way.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: Theme.Space.s4) {
                        methodRow(
                            title: "Processing — 50% of the score",
                            detail: "How processed the product is, from the NOVA classification. This is our core promise, so it carries the most weight."
                        )
                        methodRow(
                            title: "Nutrition — 35% of the score",
                            detail: "Sugar, saturated fat, salt, fiber and protein, from the Nutri-Score nutrient model."
                        )
                        methodRow(
                            title: "Additives — 15% of the score",
                            detail: "A dose-aware review against regulatory sources (EFSA/FDA/JECFA). One additive never tanks the score — the floor is 30, not 0."
                        )
                    }

                    Text("Every factor links to its source on the result screen. Higher always means lower-processed and a better nutritional profile — never a moral judgment.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.Space.s4)
            }
            .background(Theme.canvas)
            .navigationTitle("How scoring works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func methodRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
            Text(detail).font(.footnote).foregroundStyle(Theme.textSecondary)
        }
    }
}

/// "Report an issue" — honest about the current state (in-app reporting
/// isn't wired to a backend yet) rather than faking a submit-and-confirm
/// flow, same principle as `NextActionSheet` below: never fabricate a
/// feature that isn't real (docs/COPY_DECK.md voice: clear, calm, honest).
struct ReportIssueSheet: View {
    let productName: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s4) {
                    VStack(alignment: .leading, spacing: Theme.Space.s2) {
                        Text("In-app reporting isn't live yet")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("We'd rather tell you that than collect a report and quietly drop it. If something about \u{201c}\(productName)\u{201d} looks off — the score, an ingredient, an allergen — it's a known gap, and reporting will be one of the first things we wire up.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SectionCard {
                        Text("In the meantime, \u{201c}How scoring works\u{201d} often answers why a product landed where it did.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Theme.Space.s4)
            }
            .background(Theme.canvas)
            .navigationTitle("Report an issue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Next action

/// The result's primary next-action CTA (§5.3: "Footer action ... never a
/// dead-end"). Full-pill per docs/DESIGN_SYSTEM_V3.md §5.1.
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
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .foregroundStyle(Theme.onGreen)
        .background(Theme.greenDeep, in: Capsule())
    }
}

/// The sheet behind "See a better option" (§5.8 bottom sheets, `radius.lg`
/// top). The real swaps engine is Phase 3 — this deliberately does NOT
/// fabricate a specific alternative product. Instead it's honest about that,
/// gives one concrete band-relevant habit, and offers the one truthful next
/// action available today: scan something else to compare.
struct NextActionSheet: View {
    let band: ScoreBand
    let onScanAnother: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var tip: String {
        switch band {
        case .low:
            return "Products with a shorter ingredient list and less added sugar often score higher on processing and nutrition. Comparing two similar items side by side next time you shop is a simple way to find one that scores better."
        case .mid:
            return "This one's in the middle of the range. Comparing it against a similar product with fewer additives or less added sugar can sometimes turn up one that scores a bit higher."
        case .high:
            return "This one already scores well. If you're deciding between a few options, scanning each is the fastest way to compare them directly."
        case .unknown:
            return "We don't have enough data yet to say anything specific about this product. Scanning a different product — or one with a clearer ingredients label — is the best next step."
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s4) {
                    VStack(alignment: .leading, spacing: Theme.Space.s2) {
                        Text("Not a personalized swap — yet")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Suggesting a specific better product is a feature we haven't built yet, so we won't make one up. Here's something real you can do instead:")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    SectionCard {
                        Text(tip)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button(action: onScanAnother) {
                        HStack(spacing: Theme.Space.s2) {
                            Image(systemName: "barcode.viewfinder")
                            Text("Scan another product").font(.body.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .foregroundStyle(Theme.onGreen)
                    .background(Theme.greenDeep, in: Capsule())
                }
                .padding(Theme.Space.s4)
            }
            .background(Theme.canvas)
            .navigationTitle("See a better option")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
        .frame(maxWidth: .infinity, alignment: .center)
        .multilineTextAlignment(.center)
    }
}

// MARK: - Loading skeleton (§5.9)

/// Designed loading state for the result screen. Not currently wired into
/// `ProductView` (the caller only constructs `ProductView` once a `Product`
/// has already been fetched — see ScannerView.swift's `.lookingUp` phase,
/// which owns the loading banner today). This is the documented design for
/// the day ProductView accepts an in-flight/optional product. Shapes mirror
/// the light-first, ring-based result layout (floating image block, ring
/// block) rather than the old dark hero.
struct ResultSkeletonView: View {
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s5) {
            HStack {
                Spacer(minLength: 0)
                block(width: 132, height: 132, radius: Theme.Radius.md)
                Spacer(minLength: 0)
            }
            HStack(spacing: Theme.Space.s3) {
                VStack(alignment: .leading, spacing: Theme.Space.s2) {
                    block(width: 160, height: 20, radius: 4)
                    block(width: 100, height: 14, radius: 4)
                }
                Spacer(minLength: 0)
                block(width: 96, height: 96, radius: 48)
            }
            block(width: nil, height: 220, radius: Theme.Radius.md)
            block(width: nil, height: 52, radius: Theme.Radius.full)
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
    ScrollView { ResultSkeletonView() }
        .background(Theme.canvas)
}

#Preview("Confidence & trust chips") {
    FlowLayout {
        ConfidenceChip(confidence: "high")
        ConfidenceChip(confidence: "limited")
        SourceChip(name: "Open Food Facts")
    }
    .padding()
    .background(Theme.canvas)
}

#Preview("Allergen chips (calm caution, no red)") {
    AllergenChipsRow(allergens: ["Milk", "Wheat", "Soy", "Tree nuts"])
        .padding()
        .background(Theme.canvas)
}

#Preview("Tri-metric row") {
    TriMetricRow(factors: [
        ScoreFactor(name: "Nutrition", subScore: 30, weight: 0.35, detail: "", sources: []),
        ScoreFactor(name: "Additives", subScore: 94, weight: 0.15, detail: "", sources: []),
        ScoreFactor(name: "Processing", subScore: 55, weight: 0.50, detail: "", sources: []),
    ])
    .padding()
    .background(Theme.canvas)
}

#Preview("Ingredient cards") {
    ScrollView {
        VStack(spacing: Theme.Space.s3) {
            IngredientCard(ingredient: Ingredient(
                name: "Corn", what: "A whole-grain cereal; the base of the chip.",
                whyUsed: "Forms the body and texture of the snack.", safety: "A common staple food, considered safe.",
                riskTier: "low", whoShouldAvoid: [], misconceptions: [], foundIn: ["snacks"],
                sources: [Source(name: "USDA FoodData Central", url: "https://fdc.nal.usda.gov/")], confidence: "high"
            ))
            IngredientCard(ingredient: Ingredient(
                name: "Monosodium glutamate", what: "A flavour enhancer.",
                whyUsed: "Adds a savoury, umami taste.", safety: "Considered safe at typical intakes.",
                riskTier: "moderate", whoShouldAvoid: ["people advised to limit sodium"], misconceptions: [],
                foundIn: [], sources: [], confidence: "high"
            ))
            IngredientCard(ingredient: Ingredient(
                name: "Sodium benzoate", what: "A preservative.", whyUsed: "Prevents mold and bacterial growth.",
                safety: "Restricted in some regions above certain thresholds; under active review.",
                riskTier: "higher", whoShouldAvoid: [], misconceptions: [], foundIn: [], sources: [], confidence: "limited"
            ))
            IngredientCard(ingredient: Ingredient(
                name: "Natural flavouring", what: nil, whyUsed: nil, safety: nil, riskTier: nil,
                whoShouldAvoid: [], misconceptions: [], foundIn: [], sources: [], confidence: "limited"
            ))
        }
        .padding()
    }
    .background(Theme.canvas)
}

#Preview("Next action sheet — low band") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            NextActionSheet(band: .low, onScanAnother: {})
        }
}

#Preview("Methodology sheet") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            MethodologySheet()
        }
}

#Preview("Report issue sheet") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            ReportIssueSheet(productName: "Sea Salt Popped Corn Chips")
        }
}
