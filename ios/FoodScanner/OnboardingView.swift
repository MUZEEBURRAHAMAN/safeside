import SwiftUI

/// Guest-first, fully skippable onboarding (MASTER_PLAN Phase 2,
/// docs/DATA_MODEL.md `profiles`). Eight short questions, each individually
/// skippable, plus a persistent "Skip for now" that ends the flow from any
/// step. Writes go straight into the anonymous session's profile row — no
/// account required, and scanning is never gated on completing this.
/// Calories stay opt-in throughout (ED-safe rule, CLAUDE.md).
///
/// Rebuilt to Design System v3 §5.10 (docs/DESIGN_SYSTEM_V3.md): a bold
/// Space Grotesk hero question per step, large flat option cards (radius 20,
/// selected = green ring + fill + check), pill-chip multi-select, a slim
/// green progress bar up top, a full-pill "Continue"/"Done" primary action,
/// and two deliberately QUIET skip affordances ("Skip this question" /
/// "Skip for now") — never competing with the one primary CTA (§2 "green
/// earns attention by being scarce"). Step changes use a calm opacity
/// reveal, Reduce-Motion aware (§6).
struct OnboardingView: View {
    /// Called once — on "Done" or any Skip. The caller (FoodScannerApp)
    /// persists the "don't show again" flag and dismisses.
    var onFinish: () -> Void

    @Environment(ProfileService.self) private var profileService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft = ProfileDraft()
    @State private var stepIndex = 0

    private enum Step: Int, CaseIterable {
        case goal, diet, allergies, household, cookTime, dislikes, budget, healthAndCalories

        var title: String {
            switch self {
            case .goal: return "What brings you here?"
            case .diet: return "Any diet pattern you follow?"
            case .allergies: return "Any allergies to watch for?"
            case .household: return "A couple of numbers"
            case .cookTime: return "How much time for cooking?"
            case .dislikes: return "Anything you'd rather skip?"
            case .budget: return "Does budget matter to you?"
            case .healthAndCalories: return "A couple more optional things"
            }
        }

        /// One calm, ED-safe line under every hero question (§5.10 "calm
        /// subline") — always optional, never fear-based, never overclaiming
        /// a feature that isn't built yet.
        var subline: String {
            switch self {
            case .goal: return "A few quick questions so suggestions fit you. Skip anything you like."
            case .diet: return "Optional — helps match suggestions to how you eat."
            case .allergies: return "Optional — we'll flag these clearly on scanned products. Change anytime in Me."
            case .household: return "Optional — helps size suggestions to your household."
            case .cookTime: return "Optional — matches suggestions to your schedule."
            case .dislikes: return "Optional — foods you'd rather not see suggested."
            case .budget: return "Optional — helps tailor suggestions to your budget."
            case .healthAndCalories: return "Everything here is optional and off by default."
            }
        }
    }

    private var currentStep: Step { Step(rawValue: stepIndex) ?? .goal }
    private var isLastStep: Bool { stepIndex == Step.allCases.count - 1 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.s5) {
                        Text(currentStep.title)
                            .font(DisplayType.hero)
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)

                        Text(currentStep.subline)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        stepBody

                        Button("Skip this question") { advance() }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .padding(Theme.Space.s4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Forces a fresh identity per step so the opacity reveal
                    // below actually re-triggers on every step change, and
                    // resets scroll position back to the top each time.
                    .id(stepIndex)
                    .transition(.opacity)
                }

                footer
            }
            .background(Theme.canvas)
            // The hero question is the screen's title (matches Home's v3
            // pattern) — no redundant nav-bar title; the nav bar exists only
            // to host the quiet, always-available "Skip for now".
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip for now") { finish() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    // MARK: Header — slim progress bar + step count (§5.10)

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            SlimProgressBar(progress: Double(stepIndex + 1) / Double(Step.allCases.count))
            Text("Step \(stepIndex + 1) of \(Step.allCases.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, Theme.Space.s4)
        .padding(.top, Theme.Space.s3)
    }

    // MARK: Step bodies

    @ViewBuilder
    private var stepBody: some View {
        switch currentStep {
        case .goal:
            singleChoice(Goal.allCases, selection: $draft.goal, icon: Self.goalIcon, label: { $0.label })

        case .diet:
            singleChoice(DietPattern.allCases, selection: $draft.dietPattern, icon: Self.dietIcon, label: { $0.label })

        case .allergies:
            multiChoice(CommonAllergen.allCases, selection: $draft.allergies, label: { $0.label }, rawValue: { $0.rawValue })

        case .household:
            VStack(alignment: .leading, spacing: Theme.Space.s3) {
                stepperRow(title: "Meals per day", value: $draft.mealsPerDay, range: 1...6, defaultValue: 3)
                stepperRow(title: "People you're cooking for", value: $draft.householdSize, range: 1...10, defaultValue: 2)
            }

        case .cookTime:
            singleChoice(CookTime.allCases, selection: $draft.cookTime, icon: Self.cookTimeIcon, label: { $0.label })

        case .dislikes:
            multiChoice(CommonDislike.allCases, selection: $draft.dislikes, label: { $0.label }, rawValue: { $0.rawValue })

        case .budget:
            singleChoice(Budget.allCases, selection: $draft.budget, icon: Self.budgetIcon, label: { $0.label })

        case .healthAndCalories:
            VStack(alignment: .leading, spacing: Theme.Space.s5) {
                VStack(alignment: .leading, spacing: Theme.Space.s3) {
                    Text("Optional health flags")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    multiChoice(CommonHealthFlag.allCases, selection: $draft.healthFlags, label: { $0.label }, rawValue: { $0.rawValue })
                }

                caloriesToggleCard

                // Final-step closer (SCREEN_SPECS §1): everything remains
                // editable — closes the flow without a dead-end feeling.
                Text("You can change all of this anytime in the Me tab.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The calories opt-in — explicit, off by default, neutral copy, no
    /// numbers pushed at the user (ED-safe rule, CLAUDE.md). Wrapped in the
    /// same flat `surfaceCard()` language as every other panel in the app.
    private var caloriesToggleCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            Toggle(isOn: $draft.showCalories) {
                Text("Show calorie & macro numbers")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.greenDeep)
            Text("Optional. We'll never show calorie numbers unless you turn them on.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .surfaceCard()
        .accessibilityElement(children: .combine)
    }

    // MARK: Reusable step controls

    @ViewBuilder
    private func singleChoice<T: Identifiable & Equatable>(
        _ items: [T], selection: Binding<T?>, icon: ((T) -> String)? = nil, label: @escaping (T) -> String
    ) -> some View {
        VStack(spacing: Theme.Space.s3) {
            ForEach(items) { item in
                OptionCard(title: label(item), icon: icon?(item), isSelected: selection.wrappedValue == item) {
                    withAnimation(Motion.respecting(Motion.quick, reduceMotion)) {
                        selection.wrappedValue = (selection.wrappedValue == item) ? nil : item
                    }
                }
            }
        }
    }

    /// Multi-select renders as wrapping pill chips (§5.10 "pill chips ... for
    /// multi-select") rather than a tall card stack — the right call once a
    /// step has 8-9 short options (allergies, dislikes, health flags): chips
    /// stay scannable without forcing a long scroll.
    @ViewBuilder
    private func multiChoice<T: Identifiable>(
        _ items: [T], selection: Binding<[String]>, label: @escaping (T) -> String, rawValue: @escaping (T) -> String
    ) -> some View {
        FlowLayout(spacing: Theme.Space.s2) {
            ForEach(items) { item in
                let tag = rawValue(item)
                MultiSelectChip(title: label(item), isSelected: selection.wrappedValue.contains(tag)) {
                    withAnimation(Motion.respecting(Motion.quick, reduceMotion)) {
                        if let index = selection.wrappedValue.firstIndex(of: tag) {
                            selection.wrappedValue.remove(at: index)
                        } else {
                            selection.wrappedValue.append(tag)
                        }
                    }
                }
            }
        }
    }

    /// A stepper row in the same flat card language as the rest of the app
    /// (§4/§5.4), rather than a bare `Stepper` floating on the canvas.
    private func stepperRow(title: String, value: Binding<Int?>, range: ClosedRange<Int>, defaultValue: Int) -> some View {
        let bound = Binding<Int>(
            get: { value.wrappedValue ?? defaultValue },
            set: { value.wrappedValue = $0 }
        )
        return Stepper(value: bound, in: range) {
            HStack {
                Text(title).font(.body).foregroundStyle(Theme.textPrimary)
                Spacer(minLength: Theme.Space.s2)
                Text(value.wrappedValue.map(String.init) ?? "Skipped")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(minHeight: 56)
        .surfaceCard()
        .accessibilityLabel(title)
        .accessibilityValue(value.wrappedValue.map(String.init) ?? "Skipped")
    }

    // MARK: Footer / navigation

    /// Full-pill primary "Continue"/"Done" (§5.1: filled `greenDeep`, white
    /// label, height 56, radius full, subtle press-scale) plus a quiet
    /// text "Back" — the pill is the only bold, colored element in the
    /// footer so it reads as the one clear next step.
    private var footer: some View {
        HStack(spacing: Theme.Space.s3) {
            if stepIndex > 0 {
                Button("Back") {
                    withAnimation(Motion.respecting(Motion.standard, reduceMotion)) { stepIndex -= 1 }
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(minHeight: 56)
            }

            Button(action: advance) {
                Text(isLastStep ? "Done" : "Continue")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .foregroundStyle(Theme.onGreen)
            .background(Theme.greenDeep, in: Capsule())
            .buttonStyle(OnboardingPressButtonStyle())
        }
        .padding(Theme.Space.s4)
        .background(Theme.canvas)
    }

    private func advance() {
        if isLastStep {
            finish()
        } else {
            withAnimation(Motion.respecting(Motion.standard, reduceMotion)) { stepIndex += 1 }
        }
    }

    /// Ends onboarding from any step — saves whatever was answered so far
    /// (fire-and-forget; never blocks the dismiss) and calls `onFinish()`.
    private func finish() {
        Task { await profileService.save(draft) }
        onFinish()
    }

    // MARK: Decorative icons (purely visual — labels carry the meaning for
    // VoiceOver, so these are hidden from the accessibility tree by `OptionCard`)

    private static func goalIcon(_ goal: Goal) -> String {
        switch goal {
        case .healthier: return "leaf.fill"
        case .less_processed: return "shippingbox.fill"
        case .lose: return "arrow.down.right.circle.fill"
        case .gain: return "arrow.up.right.circle.fill"
        case .condition: return "heart.text.square.fill"
        case .budget: return "dollarsign.circle.fill"
        }
    }

    private static func dietIcon(_ diet: DietPattern) -> String {
        switch diet {
        case .omnivore: return "fork.knife"
        case .flexitarian: return "leaf"
        case .vegetarian: return "carrot.fill"
        case .vegan: return "leaf.fill"
        case .pescatarian: return "fish.fill"
        case .keto: return "flame.fill"
        case .mediterranean: return "sun.max.fill"
        case .none: return "circle.dashed"
        }
    }

    private static func cookTimeIcon(_ cookTime: CookTime) -> String {
        switch cookTime {
        case .quick: return "bolt.fill"
        case .medium: return "clock.fill"
        case .enjoy: return "flame.fill"
        }
    }

    private static func budgetIcon(_ budget: Budget) -> String {
        switch budget {
        case .low: return "dollarsign.circle.fill"
        case .medium: return "dollarsign.circle"
        case .none: return "checkmark.circle"
        }
    }
}

// MARK: - Slim progress bar (§5.10 "progress bar on top")

/// A slim, flat green progress bar — deliberately not a system `ProgressView`
/// so it matches the app's other pill/capsule shapes exactly. Purely
/// decorative; the adjacent "Step N of M" text carries the accessible value.
private struct SlimProgressBar: View {
    let progress: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.border)
                Capsule()
                    .fill(Theme.greenDeep)
                    .frame(width: max(8, geo.size.width * min(max(progress, 0), 1)))
            }
        }
        .frame(height: 6)
        .animation(Motion.respecting(Motion.standard, reduceMotion), value: progress)
        .accessibilityHidden(true)
    }
}

// MARK: - Motion — shared press-scale for onboarding's tappable controls

/// A calm press-scale (v3 §6): 0.97 scale, quick ease-out, no bounce, always
/// routed through `DesignKit.Motion` so Reduce Motion is honored in one
/// place — a static tap is the Reduce-Motion-safe path.
private struct OnboardingPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(Motion.respecting(Motion.quick, reduceMotion), value: configuration.isPressed)
    }
}

// MARK: - Option card (single-select, §5.10)

/// A large, flat, tappable option card — radius 20, hairline border, FLAT (no
/// shadow, per `DesignKit.surfaceCard()`'s "flat by default" rule). Selected
/// state is never color-only: a green ring + soft green fill + a filled
/// checkmark disc together carry the state (§7 accessibility rule).
private struct OptionCard: View {
    let title: String
    let icon: String?
    let isSelected: Bool
    let action: () -> Void
    @ScaledMetric(relativeTo: .body) private var iconCircle: CGFloat = 40
    @ScaledMetric(relativeTo: .body) private var iconGlyph: CGFloat = 17
    @ScaledMetric(relativeTo: .caption) private var checkDisc: CGFloat = 24
    @ScaledMetric(relativeTo: .caption) private var checkGlyph: CGFloat = 12

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.s3) {
                if let icon {
                    ZStack {
                        Circle()
                            .fill(isSelected ? Theme.greenDeep : Theme.surfaceAlt)
                            .frame(width: iconCircle, height: iconCircle)
                        Image(systemName: icon)
                            .font(.system(size: iconGlyph, weight: .semibold))
                            .foregroundStyle(isSelected ? Theme.onGreen : Theme.textSecondary)
                    }
                    .accessibilityHidden(true)
                }

                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: Theme.Space.s2)

                ZStack {
                    Circle()
                        .fill(isSelected ? Theme.greenDeep : Color.clear)
                    Circle()
                        .strokeBorder(isSelected ? Color.clear : Theme.border, lineWidth: 1.5)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: checkGlyph, weight: .bold))
                            .foregroundStyle(Theme.onGreen)
                    }
                }
                .frame(width: checkDisc, height: checkDisc)
                .accessibilityHidden(true)
            }
            .padding(Theme.Space.s4)
            .frame(minHeight: 64)
            .background(isSelected ? Theme.greenSoft : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .strokeBorder(isSelected ? Theme.greenDeep : Theme.border, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(OnboardingPressButtonStyle())
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Multi-select chip (§5.8 pill chips, reused for §5.10 multi-select)

/// A pill chip for multi-select steps — same shape language as Home's
/// `FilterChipButton` (radius full, selected = green fill, ink label), plus
/// a leading checkmark on selection so the state is never color-only.
private struct MultiSelectChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(isSelected ? Theme.onGreen : Theme.textPrimary)
            .padding(.horizontal, Theme.Space.s4)
            .frame(minHeight: 44)
            .background(isSelected ? Theme.greenDeep : Theme.surface, in: Capsule())
            .overlay(
                Capsule().strokeBorder(isSelected ? .clear : Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(OnboardingPressButtonStyle())
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#if DEBUG
#Preview("Onboarding") {
    OnboardingView(onFinish: {})
        .environment(ProfileService(session: SessionService()))
}

#Preview("Option cards") {
    VStack(spacing: 12) {
        OptionCard(title: "Eat healthier overall", icon: "leaf.fill", isSelected: true, action: {})
        OptionCard(title: "Manage weight — lose", icon: "arrow.down.right.circle.fill", isSelected: false, action: {})
    }
    .padding()
    .background(Theme.canvas)
}

#Preview("Multi-select chips") {
    FlowLayout(spacing: 8) {
        MultiSelectChip(title: "Milk", isSelected: true, action: {})
        MultiSelectChip(title: "Peanuts", isSelected: false, action: {})
        MultiSelectChip(title: "Tree nuts", isSelected: false, action: {})
        MultiSelectChip(title: "Shellfish", isSelected: true, action: {})
    }
    .padding()
    .background(Theme.canvas)
}

#Preview("Slim progress bar") {
    VStack(alignment: .leading, spacing: 16) {
        SlimProgressBar(progress: 0.25)
        SlimProgressBar(progress: 0.75)
    }
    .padding()
    .background(Theme.canvas)
}
#endif
