import SwiftUI
import Foundation

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
    /// When set, the row reads "{name} · updated {date}" (COPY_DECK source-row
    /// pattern). Only passed for live-fetched data provenance (e.g. Open Food
    /// Facts); versioned reference tables stay undated. Never "updated (nil)".
    var updatedDate: String? = nil

    private var nameLine: String {
        if let updatedDate { return "\(source.name) · updated \(updatedDate)" }
        return source.name
    }

    var body: some View {
        Group {
            if let urlString = source.url, let url = URL(string: urlString) {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Text("Source: \(nameLine)")
                        Image(systemName: "arrow.up.right").font(.caption2)
                    }
                }
                .foregroundStyle(Theme.greenDeep)
            } else {
                Text("Source: \(nameLine)")
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .font(.caption)
    }
}

/// Format an ISO8601 fetched-at timestamp → an abbreviated date ("Jul 8, 2026")
/// for dated source rows, or nil when it's absent/unparseable (so we never
/// render "updated (nil)").
func formattedFetchedDate(_ iso: String?) -> String? {
    guard let iso, !iso.isEmpty else { return nil }
    let withFractional = ISO8601DateFormatter()
    withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let plain = ISO8601DateFormatter()
    guard let date = withFractional.date(from: iso) ?? plain.date(from: iso) else { return nil }
    return date.formatted(date: .abbreviated, time: .omitted)
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

// MARK: - Allergen matching (client-side only — no backend calls)

/// Conservative, literal matching between the user's flagged allergies
/// (`profile.allergies`, populated from onboarding's `CommonAllergen` raw
/// values — see OnboardingView.swift, e.g. `"milk"`, `"tree_nuts"`) and
/// either a product's allergen tags (`Product.allergens`, e.g. `"Milk"`,
/// `"en:milk"`) or the free-text name of an ingredient. Deliberately NOT
/// fuzzy/AI matching — every "match" here is a defensible, literal string
/// comparison, per CLAUDE.md's "never fabricate" rule. Lives here (not a
/// service) because it's pure, stateless, view-local logic with no
/// persistence or network concerns of its own.
enum AllergenMatch {
    /// A tiny, deliberately small set of synonym groups for vocabulary drift
    /// between onboarding's fixed allergy list and however a product's
    /// allergen tags happen to be spelled (Open Food Facts–style tags, or
    /// already-cleaned single words). Grouped only where onboarding itself
    /// already treats two words as one concept (e.g. "Wheat / gluten" is a
    /// single onboarding option) or where the synonym is unambiguous — never
    /// a guess about ingredient chemistry.
    private static let synonymGroups: [Set<String>] = [
        ["tree nut", "tree nuts", "nut", "nuts"],
        ["wheat", "gluten"], // onboarding presents these as one option
        ["soy", "soya", "soybean", "soybeans"],
        ["shellfish", "crustacean", "crustaceans"],
        ["sesame", "sesame seed", "sesame seeds"],
        ["egg", "eggs"],
        ["peanut", "peanuts"],
    ]

    /// Normalizes one free-form tag (`"en:milk"`, `"tree_nuts"`, `"Milk"`)
    /// down to its comparable forms: lowercased, locale-prefix stripped,
    /// separators folded to spaces, plus its known synonyms and a naive
    /// singular. Never fuzzy — this only folds together spellings that are
    /// the *same* allergen.
    static func canonicalForms(_ raw: String) -> Set<String> {
        var s = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let colon = s.firstIndex(of: ":") {
            s = String(s[s.index(after: colon)...])
        }
        s = s.replacingOccurrences(of: "_", with: " ")
        s = s.replacingOccurrences(of: "-", with: " ")
        s = s.split(separator: " ").joined(separator: " ")
        guard !s.isEmpty else { return [] }

        var forms: Set<String> = [s]
        if s.hasSuffix("s"), !s.hasSuffix("ss"), s.count > 3 {
            forms.insert(String(s.dropLast()))
        }
        for group in synonymGroups where !group.isDisjoint(with: forms) {
            forms.formUnion(group)
        }
        return forms
    }

    /// A calm display form for a raw allergen tag/profile value —
    /// `"tree_nuts"` → `"Tree Nuts"`, `"en:milk"` → `"Milk"`.
    static func displayName(_ raw: String) -> String {
        var s = raw.lowercased()
        if let colon = s.firstIndex(of: ":") { s = String(s[s.index(after: colon)...]) }
        return s.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .localizedCapitalized
    }

    /// True if a product's allergen tag is the same allergen as one the user
    /// flagged in onboarding. Used for the alert banner and for emphasizing
    /// chips.
    static func tagMatches(_ productAllergen: String, flaggedAllergies: [String]) -> Bool {
        let productForms = canonicalForms(productAllergen)
        guard !productForms.isEmpty else { return false }
        return flaggedAllergies.contains { !canonicalForms($0).isDisjoint(with: productForms) }
    }

    /// Returns the first flagged allergy whose canonical form appears as a
    /// whole word in free text (an ingredient's name) — e.g. `"soy"` inside
    /// `"Soy lecithin"`, or `"milk"` inside `"Nonfat milk"`. Whole-word only
    /// (padded-space containment), so this never fires on a coincidental
    /// substring. Used only for the ingredient-card personalization note,
    /// never to alter a score or fabricate a safety verdict.
    static func matchingFlaggedAllergy(inText text: String, flaggedAllergies: [String]) -> String? {
        guard !flaggedAllergies.isEmpty else { return nil }
        let cleaned = text.lowercased().map { (ch: Character) -> Character in
            (ch.isLetter || ch.isWhitespace) ? ch : " "
        }
        let collapsed = String(cleaned).split(separator: " ").joined(separator: " ")
        let padded = " \(collapsed) "
        for allergy in flaggedAllergies {
            for form in canonicalForms(allergy) where padded.contains(" \(form) ") {
                return allergy
            }
        }
        return nil
    }
}

// MARK: - Allergen alert banner

/// The result screen's most safety-relevant moment: a calm, dismissible
/// banner shown only when a product contains an allergen the user flagged
/// during onboarding (`profile.allergies`, read via `ProfileService`). This
/// is the one place `Theme.critical` (via `Theme.ResultScreen.criticalOnLight`)
/// is appropriate per docs/DESIGN_SYSTEM.md §2.5 — a user-flagged allergen
/// really is a safety case — but the treatment stays a soft tint + hairline
/// outline, never a solid alarm block, and the copy stays factual
/// ("contains"/"may contain"), never "toxic"/"danger" (CLAUDE.md ED-safe
/// rule). Softens to "may contain" when `isLimitedConfidence` is true, since
/// a thin/partial product read shouldn't be asserted with false certainty.
/// Collapsed by default (headline only); tapping it reveals one more line of
/// calm context, and a separate 44pt control dismisses it for this viewing.
struct AllergenAlertBanner: View {
    let matchedAllergens: [String]
    var isLimitedConfidence: Bool = false

    @State private var isDismissed = false
    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var namesList: String {
        ListFormatter.localizedString(byJoining: matchedAllergens.map(AllergenMatch.displayName))
    }

    private var headline: String {
        let verb = isLimitedConfidence ? "May contain" : "Contains"
        return "\(verb) \(namesList), which you asked to avoid."
    }

    private var detail: String {
        isLimitedConfidence
            ? "Our data on this product is limited, so treat this as a heads-up rather than a certainty. Always check the label to confirm."
            : "Always check the label to confirm — allergen data can change between products and batches."
    }

    var body: some View {
        if !isDismissed {
            VStack(alignment: .leading, spacing: 0) {
                header
                if isExpanded {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Theme.Space.s2)
                        .transition(.opacity)
                }
            }
            .padding(Theme.Space.s4)
            .background(
                Theme.ResultScreen.criticalOnLight.opacity(0.08),
                in: RoundedRectangle(cornerRadius: Theme.Radius.md)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .strokeBorder(Theme.ResultScreen.criticalOnLight.opacity(0.35), lineWidth: 1)
            )
            .onAppear {
                // VoiceOver-announced: a scanned allergen match is the kind
                // of thing a VoiceOver user shouldn't have to discover only
                // by swiping past it in reading order. `Text(verbatim:)`
                // (rather than passing `headline` directly) sidesteps any
                // ambiguity between `Announcement`'s `Text`/`LocalizedStringKey`
                // initializer overloads for a runtime `String`.
                AccessibilityNotification.Announcement(headline).post()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Space.s2) {
            Button {
                withAnimation(Motion.respecting(Motion.standard, reduceMotion)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: Theme.Space.s3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.ResultScreen.criticalOnLight)
                        .frame(width: 22)
                        .accessibilityHidden(true)

                    Text(headline)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(headline)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Double tap for more detail")

            Button {
                withAnimation(Motion.respecting(Motion.standard, reduceMotion)) {
                    isDismissed = true
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss allergen alert")
        }
    }
}

/// Allergen chip — the one place cautionary styling is allowed (CLAUDE.md
/// ED-safe rule + docs/DESIGN_SYSTEM.md §5.5), but kept CALM by default: an
/// amber caution tone, never the alarm-red treatment. Informational, not a
/// fear-based block — a small icon + name, matching Oasis's chip shape.
/// `isFlagged` (true only when this allergen matches one in `profile
/// .allergies`) steps the tone up to the restrained `criticalOnLight`
/// family — still a soft fill + outline, just a touch more emphatic than the
/// plain informational chips, per docs/DESIGN_SYSTEM.md §2.5.
struct AllergenChip: View {
    let name: String
    var isFlagged: Bool = false

    private var tone: Color {
        isFlagged ? Theme.ResultScreen.criticalOnLight : Theme.ResultScreen.warningTextOnLight
    }
    private var fillColor: Color {
        isFlagged ? Theme.ResultScreen.criticalOnLight : Theme.scoreMid
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill").font(.caption2)
            Text(AllergenMatch.displayName(name)).font(.caption.weight(isFlagged ? .bold : .medium))
        }
        .foregroundStyle(tone)
        .padding(.horizontal, Theme.Space.s3)
        .padding(.vertical, 6)
        .background(fillColor.opacity(isFlagged ? 0.16 : 0.12), in: Capsule())
        .overlay(
            Capsule().strokeBorder(fillColor.opacity(isFlagged ? 0.55 : 0.4), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isFlagged
                ? "\(AllergenMatch.displayName(name)) — matches an allergy in your profile"
                : AllergenMatch.displayName(name)
        )
    }
}

struct AllergenChipsRow: View {
    let allergens: [String]
    /// The user's flagged allergies (`profile.allergies`), for emphasizing
    /// the chips that actually matter to them. Empty by default so every
    /// existing call site keeps rendering the plain, unemphasized row.
    var flaggedAllergies: [String] = []

    private func isFlagged(_ allergen: String) -> Bool {
        AllergenMatch.tagMatches(allergen, flaggedAllergies: flaggedAllergies)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            FlowLayout(spacing: Theme.Space.s2) {
                ForEach(allergens, id: \.self) { allergen in
                    AllergenChip(name: allergen, isFlagged: isFlagged(allergen))
                }
            }
            Text("Always check the label to confirm.")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let described = allergens.map { allergen -> String in
            isFlagged(allergen)
                ? "\(AllergenMatch.displayName(allergen)), which you asked to avoid"
                : AllergenMatch.displayName(allergen)
        }
        let list = ListFormatter.localizedString(byJoining: described)
        return "Contains allergens: \(list). Always check the label to confirm."
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
    /// The user's flagged allergies (`profile.allergies`) — enables a small,
    /// neutral, client-side-only personalization note when this specific
    /// ingredient's name literally names one of them (e.g. "Soy lecithin"
    /// when the user flagged soy). Empty by default so every existing call
    /// site renders exactly as before. Never fabricated — only shown on a
    /// real, literal name match; see `AllergenMatch.matchingFlaggedAllergy`.
    var flaggedAllergies: [String] = []

    @State private var isExpanded = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var riskTier: String? { ingredient.riskTier?.lowercased() }

    /// The flagged allergy this ingredient's name literally names, if any —
    /// e.g. `"milk"` for an ingredient named "Nonfat milk". `nil` (not an
    /// empty note) when there's no real match, so nothing is ever invented.
    private var matchedFlaggedAllergy: String? {
        AllergenMatch.matchingFlaggedAllergy(inText: ingredient.name, flaggedAllergies: flaggedAllergies)
    }

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

                if let matchedFlaggedAllergy {
                    Text("You asked to avoid \(AllergenMatch.displayName(matchedFlaggedAllergy)).")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                }

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

// MARK: - Nutrient meters (Watch-outs / Benefits) — Chunk 1

/// Neutral tier → colour map for a meter row. The tier word itself is
/// backend-owned (COPY_DECK §Result upgrades ladder); this only maps it to a
/// calm score-band colour. Never alarm-red — a high watch-out uses clay
/// (`scoreLow`), per CLAUDE.md's ED-safe rule.
private func meterTierColor(kind: String, tier: String) -> Color {
    switch (kind, tier) {
    case ("watchOut", "high"): return Theme.scoreLow      // clay, never red
    case ("watchOut", "moderate"): return Theme.scoreMid
    case ("benefit", "good source"): return Theme.scoreHigh
    case ("benefit", "some"): return Theme.scoreMid
    default: return Theme.scoreUnknown                    // "low" / anything else
    }
}

/// A labeled bar meter for one Watch-out / Benefit. Every number here —
/// `value`, `unit`, `tier`, `meterFraction` — is computed on the backend from
/// `products.nutrients` (CLAUDE.md #5); this view performs ZERO arithmetic on
/// them, it only maps the tier to a colour and renders. Tapping reveals the
/// row's source(s) (teardown #5: sourced rows expand on tap).
struct MeterRowView: View {
    let row: MeterRow
    /// Full-bar reference. Defaults to 1 because the backend already sends a
    /// clamped 0…1 `meterFraction`; Compare (Chunk 5) can pass a shared scale.
    var maxScale: Double = 1

    @State private var showSources = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color { meterTierColor(kind: row.kind, tier: row.tier) }

    /// The already-clamped backend fraction, only re-projected onto a shared
    /// scale when a caller overrides `maxScale` (Compare). No value derivation.
    private var fraction: Double {
        maxScale == 1 ? row.meterFraction : min(max(row.meterFraction / maxScale, 0), 1)
    }

    private var valueText: String {
        // `.formatted()` is display formatting (drops a trailing .0), never a
        // re-round of the backend value.
        "\(row.value.formatted()) \(row.unit)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s1) {
            Button {
                guard !row.sources.isEmpty else { return }
                withAnimation(Motion.respecting(Motion.standard, reduceMotion)) {
                    showSources.toggle()
                }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s2) {
                        Text(row.label)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: Theme.Space.s2)
                        Text(valueText)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                    }
                    ProgressView(value: fraction, total: 1)
                        .tint(tint)
                        .accessibilityHidden(true)
                    Text(row.tier)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showSources {
                ForEach(row.sources, id: \.self) { SourceLink(source: $0) }
                    .transition(.opacity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.label), \(valueText), \(row.tier)")
        .accessibilityHint(row.sources.isEmpty ? "" : "Double tap to show sources")
    }
}

/// A "Watch-outs" or "Benefits" meter section. Renders nothing when `rows` is
/// empty (never a phantom empty section). Reusable + `MeterRow`-driven so
/// Compare (Chunk 5) can drop it into a shared-scale two-column layout —
/// hence `maxScale` is a parameter, not a hardcode.
struct MetersSection: View {
    let title: String              // "Watch-outs" / "Benefits" — COPY_DECK verbatim
    let rows: [MeterRow]
    var maxScale: Double = 1

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s3) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                VStack(spacing: Theme.Space.s3) {
                    ForEach(rows) { MeterRowView(row: $0, maxScale: maxScale) }
                }
                .surfaceCard()
            }
            // SCREEN_SPECS §4 Responsive — cap text width on wide screens.
            .frame(maxWidth: 560, alignment: .leading)
        }
    }
}

// MARK: - Ingredient pre-read + additive summary — Chunk 1

/// One calm pre-read row above the ingredient list. Both counts are computed
/// on the backend (`score.highlights`); the client never counts. Neutral tone,
/// small band-coloured dots, never red.
struct IngredientCountPreRead: View {
    let toKnowAboutCount: Int
    let beneficialCount: Int

    private func dot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 7, height: 7)
    }

    var body: some View {
        // Verbatim COPY_DECK: "{n} ingredients to know about · {n} beneficial".
        FlowLayout(spacing: Theme.Space.s2) {
            HStack(spacing: 6) {
                dot(Theme.scoreMid)
                Text("\(toKnowAboutCount) ingredients to know about")
            }
            Text("·").foregroundStyle(Theme.textSecondary)
            HStack(spacing: 6) {
                dot(Theme.scoreHigh)
                Text("\(beneficialCount) beneficial")
            }
        }
        .font(.subheadline)
        .foregroundStyle(Theme.textSecondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(toKnowAboutCount) ingredients to know about, \(beneficialCount) beneficial"
        )
    }
}

/// Neutral severity word for an additive risk tier (COPY_DECK §Result
/// upgrades). Nil for a non-additive / untiered ingredient.
func additiveSeverityWord(_ riskTier: String?) -> String? {
    switch riskTier?.lowercased() {
    case "low": return "Lower concern"
    case "moderate": return "Moderate concern"
    case "higher": return "Higher concern"
    default: return nil
    }
}

/// Compact additive summary row: name + a neutral severity chip (tinted by
/// `riskTier`, same calm band colours as `IngredientCard`) + a factual INS-class
/// category pill. The full `IngredientCard` still renders below — this is the
/// scannable at-a-glance summary (teardown #9: severity word + category).
struct AdditiveSummaryRow: View {
    let ingredient: Ingredient

    private var severityColor: Color {
        switch ingredient.riskTier?.lowercased() {
        case "low": return Theme.scoreHigh
        case "moderate": return Theme.scoreMid
        case "higher": return Theme.scoreLow
        default: return Theme.scoreUnknown
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            Text(ingredient.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
            FlowLayout(spacing: Theme.Space.s2) {
                if let word = additiveSeverityWord(ingredient.riskTier) {
                    Text(word)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(severityColor)
                        .padding(.horizontal, Theme.Space.s3)
                        .padding(.vertical, Theme.Space.s1)
                        .background(severityColor.opacity(0.12), in: Capsule())
                        .overlay(Capsule().strokeBorder(severityColor.opacity(0.4), lineWidth: 1))
                }
                if let category = ingredient.category {
                    Text(category)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, Theme.Space.s3)
                        .padding(.vertical, Theme.Space.s1)
                        .background(Theme.surfaceAlt, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Groups the additive summary rows into one flat card, shown only when the
/// product has ≥1 additive (an ingredient carrying a non-nil `category`).
struct AdditivesSummarySection: View {
    let ingredients: [Ingredient]

    private var additives: [Ingredient] { ingredients.filter { $0.category != nil } }

    var body: some View {
        if !additives.isEmpty {
            SectionCard {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(additives.enumerated()), id: \.element.id) { index, ingredient in
                        AdditiveSummaryRow(ingredient: ingredient)
                        if index < additives.count - 1 {
                            HairlineDivider().padding(.vertical, Theme.Space.s3)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Sources

/// The collapsible "Sources" section — every factor + ingredient citation,
/// deduplicated, in one place (our credibility, alongside "Why this score").
/// Plain links floating on the canvas (no card), matching the Oasis
/// reference's plain "Sources" list.
struct SourcesSection: View {
    let sources: [Source]
    /// ISO timestamp the product data was fetched (`Product.fetchedAt`). Dates
    /// only the Open Food Facts provenance rows — that's what this timestamp
    /// describes. Versioned reference tables (additive table) stay undated.
    var fetchedDate: String? = nil

    private var formattedDate: String? { formattedFetchedDate(fetchedDate) }

    private func updatedDate(for source: Source) -> String? {
        source.name.localizedCaseInsensitiveContains("Open Food Facts") ? formattedDate : nil
    }

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
                    SourceLink(source: source, updatedDate: updatedDate(for: source))
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

/// "Report an issue" — a real round-trip to `POST product-report`. Reason
/// single-select + optional free text → submit → an honest thanks state, and
/// a Retry error state on failure (never a dead-end, principle #4). Copy is
/// verbatim from docs/COPY_DECK.md §Result upgrades.
struct ReportIssueSheet: View {
    let productID: String
    let productName: String

    @Environment(\.dismiss) private var dismiss
    @Environment(SessionService.self) private var session

    private enum Phase: Equatable { case editing, sending, done, failed }

    /// Display label ↔ backend reason. Single-select (radio), not multi-select.
    private static let reasons: [(label: String, reason: APIClient.ReportReason)] = [
        ("Score seems off", .score_off),
        ("Wrong product info", .wrong_info),
        ("Missing ingredient", .missing_ingredient),
        ("Something else", .other),
    ]

    @State private var selected: APIClient.ReportReason?
    @State private var detail: String = ""
    @State private var phase: Phase = .editing

    private var apiClient: APIClient { APIClient(session: session) }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .done: thanksState
                default: editingState
                }
            }
            .background(Theme.canvas)
            .navigationTitle("What looks wrong?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(phase == .done ? "Done" : "Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Editing / sending / failed

    private var editingState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.s4) {
                VStack(alignment: .leading, spacing: Theme.Space.s2) {
                    ForEach(Self.reasons, id: \.reason) { item in
                        reasonRow(label: item.label, reason: item.reason)
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Space.s2) {
                    Text("Tell us more (optional)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    TextEditor(text: $detail)
                        .frame(minHeight: 96)
                        .padding(Theme.Space.s2)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                .strokeBorder(Theme.border, lineWidth: 1)
                        )
                        .disabled(phase == .sending)
                }

                if phase == .failed {
                    Text("Couldn't send your report. Check your connection and try again.")
                        .font(.footnote)
                        .foregroundStyle(Theme.ResultScreen.warningTextOnLight)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: submit) {
                    HStack(spacing: Theme.Space.s2) {
                        if phase == .sending { ProgressView().tint(Theme.onGreen) }
                        Text(phase == .failed ? "Retry" : "Send report")
                            .font(.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
                .foregroundStyle(Theme.onGreen)
                .background(
                    (selected == nil ? Theme.scoreUnknown : Theme.greenDeep),
                    in: Capsule()
                )
                .disabled(selected == nil || phase == .sending)
            }
            .padding(Theme.Space.s4)
        }
    }

    private func reasonRow(label: String, reason: APIClient.ReportReason) -> some View {
        Button {
            selected = reason
        } label: {
            HStack(spacing: Theme.Space.s3) {
                Image(systemName: selected == reason ? "largecircle.fill.circle" : "circle")
                    .font(.body)
                    .foregroundStyle(selected == reason ? Theme.greenDeep : Theme.textSecondary)
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(phase == .sending)
        .accessibilityAddTraits(selected == reason ? [.isSelected] : [])
    }

    private var thanksState: some View {
        VStack(spacing: Theme.Space.s4) {
            Spacer(minLength: 0)
            Image(systemName: "checkmark.seal.fill")
                .font(.largeTitle)
                .foregroundStyle(Theme.greenDeep)
            Text("Thanks — we'll review it.")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.greenDeep)
                .frame(minHeight: 44)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Space.s4)
    }

    private func submit() {
        guard let reason = selected else { return }
        phase = .sending
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                try await apiClient.reportIssue(
                    productID: productID,
                    reason: reason,
                    detail: trimmed.isEmpty ? nil : trimmed
                )
                phase = .done
            } catch {
                phase = .failed
            }
        }
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

#Preview("Allergen chips — flagged match emphasized, still calm") {
    AllergenChipsRow(allergens: ["Milk", "Wheat", "Soy"], flaggedAllergies: ["milk"])
        .padding()
        .background(Theme.canvas)
}

#Preview("Allergen alert banner — collapsed, single match") {
    AllergenAlertBanner(matchedAllergens: ["milk"])
        .padding()
        .background(Theme.canvas)
}

#Preview("Allergen alert banner — limited confidence, multiple matches") {
    AllergenAlertBanner(matchedAllergens: ["milk", "tree_nuts"], isLimitedConfidence: true)
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
            IngredientCard(ingredient: Ingredient(
                name: "Nonfat milk", what: "A dairy ingredient made by removing fat from milk.",
                whyUsed: "Adds creaminess and protein.", safety: "Generally recognized as safe.",
                riskTier: "low", whoShouldAvoid: [], misconceptions: [], foundIn: [],
                sources: [], confidence: "high"
            ), flaggedAllergies: ["milk"])
        }
        .padding()
    }
    .background(Theme.canvas)
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
            ReportIssueSheet(productID: "sample-1", productName: "Sea Salt Popped Corn Chips")
                .environment(SessionService())
        }
}

#if DEBUG
private let sampleWatchOuts: [MeterRow] = [
    MeterRow(label: "Saturated fat", value: 26.7, unit: "g", tier: "high",
             meterFraction: 1.0, kind: "watchOut",
             sources: [Source(name: "FSA nutrient thresholds (via Open Food Facts)",
                              url: "https://world.openfoodfacts.org/nutriscore")]),
    MeterRow(label: "Sugars", value: 56.3, unit: "g", tier: "high",
             meterFraction: 1.0, kind: "watchOut",
             sources: [Source(name: "FSA nutrient thresholds (via Open Food Facts)", url: nil)]),
    MeterRow(label: "Salt", value: 0.1, unit: "g", tier: "low",
             meterFraction: 0.07, kind: "watchOut",
             sources: [Source(name: "FSA nutrient thresholds (via Open Food Facts)", url: nil)]),
]

private let sampleBenefits: [MeterRow] = [
    MeterRow(label: "Fiber", value: 4.5, unit: "g", tier: "good source",
             meterFraction: 0.75, kind: "benefit",
             sources: [Source(name: "Nutri-Score nutrient model (via Open Food Facts)", url: nil)]),
    MeterRow(label: "Protein", value: 6.3, unit: "g", tier: "some",
             meterFraction: 0.53, kind: "benefit",
             sources: [Source(name: "Nutri-Score nutrient model (via Open Food Facts)", url: nil)]),
]
#endif

#Preview("Meters — Watch-outs + Benefits") {
    ScrollView {
        VStack(alignment: .leading, spacing: Theme.Space.s5) {
            MetersSection(title: "Watch-outs", rows: sampleWatchOuts)
            MetersSection(title: "Benefits", rows: sampleBenefits)
        }
        .padding()
    }
    .background(Theme.canvas)
}

#Preview("Ingredient pre-read + additive summary") {
    ScrollView {
        VStack(alignment: .leading, spacing: Theme.Space.s4) {
            IngredientCountPreRead(toKnowAboutCount: 2, beneficialCount: 1)
            AdditivesSummarySection(ingredients: [
                Ingredient(name: "Monosodium glutamate", what: nil, whyUsed: nil, safety: nil,
                           riskTier: "moderate", whoShouldAvoid: [], misconceptions: [],
                           foundIn: [], sources: [], confidence: "high", category: "Flavour enhancers"),
                Ingredient(name: "Sulphite ammonia caramel", what: nil, whyUsed: nil, safety: nil,
                           riskTier: "higher", whoShouldAvoid: [], misconceptions: [],
                           foundIn: [], sources: [], confidence: "high", category: "Colours"),
                Ingredient(name: "Citric acid", what: nil, whyUsed: nil, safety: nil,
                           riskTier: "low", whoShouldAvoid: [], misconceptions: [],
                           foundIn: [], sources: [], confidence: "high", category: "Antioxidants"),
            ])
        }
        .padding()
    }
    .background(Theme.canvas)
}
