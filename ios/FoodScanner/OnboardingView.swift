import SwiftUI

/// Guest-first, fully skippable onboarding (MASTER_PLAN Phase 2,
/// docs/DATA_MODEL.md `profiles`). Eight short questions, each individually
/// skippable, plus a persistent "Skip for now" that ends the flow from any
/// step. Writes go straight into the anonymous session's profile row — no
/// account required, and scanning is never gated on completing this.
/// Calories stay opt-in throughout (ED-safe rule, CLAUDE.md).
struct OnboardingView: View {
    /// Called once — on "Done" or any Skip. The caller (FoodScannerApp)
    /// persists the "don't show again" flag and dismisses.
    var onFinish: () -> Void

    @Environment(ProfileService.self) private var profileService
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
    }

    private var currentStep: Step { Step(rawValue: stepIndex) ?? .goal }
    private var isLastStep: Bool { stepIndex == Step.allCases.count - 1 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progress

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.s5) {
                        Text(currentStep.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                            .accessibilityAddTraits(.isHeader)

                        if currentStep == .goal {
                            Text("A few quick questions so suggestions fit you. Skip anything you like.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }

                        stepBody

                        Button("Skip this question") { advance() }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .padding(Theme.Space.s4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                footer
            }
            .background(Theme.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Step \(stepIndex + 1) of \(Step.allCases.count)")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip for now") { finish() }
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    // MARK: Header

    private var progress: some View {
        ProgressView(value: Double(stepIndex + 1), total: Double(Step.allCases.count))
            .tint(Theme.greenDeep)
            .padding(.horizontal, Theme.Space.s4)
            .padding(.top, Theme.Space.s2)
            .accessibilityHidden(true)
    }

    // MARK: Step bodies

    @ViewBuilder
    private var stepBody: some View {
        switch currentStep {
        case .goal:
            singleChoice(Goal.allCases, selection: $draft.goal, label: { $0.label })

        case .diet:
            singleChoice(DietPattern.allCases, selection: $draft.dietPattern, label: { $0.label })

        case .allergies:
            multiChoice(CommonAllergen.allCases, selection: $draft.allergies, label: { $0.label }, rawValue: { $0.rawValue })

        case .household:
            VStack(alignment: .leading, spacing: Theme.Space.s5) {
                stepperRow(title: "Meals per day", value: $draft.mealsPerDay, range: 1...6, defaultValue: 3)
                stepperRow(title: "People you're cooking for", value: $draft.householdSize, range: 1...10, defaultValue: 2)
            }

        case .cookTime:
            singleChoice(CookTime.allCases, selection: $draft.cookTime, label: { $0.label })

        case .dislikes:
            VStack(alignment: .leading, spacing: Theme.Space.s3) {
                Text("Optional — foods you'd rather not see suggested.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                multiChoice(CommonDislike.allCases, selection: $draft.dislikes, label: { $0.label }, rawValue: { $0.rawValue })
            }

        case .budget:
            singleChoice(Budget.allCases, selection: $draft.budget, label: { $0.label })

        case .healthAndCalories:
            VStack(alignment: .leading, spacing: Theme.Space.s5) {
                VStack(alignment: .leading, spacing: Theme.Space.s3) {
                    Text("Optional health flags").font(.headline).foregroundStyle(Theme.textPrimary)
                    multiChoice(CommonHealthFlag.allCases, selection: $draft.healthFlags, label: { $0.label }, rawValue: { $0.rawValue })
                }

                VStack(alignment: .leading, spacing: Theme.Space.s2) {
                    Toggle(isOn: $draft.showCalories) {
                        Text("Show calorie & macro numbers")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .tint(Theme.greenDeep)
                    Text("Optional. We'll never show calorie numbers unless you turn them on.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    // MARK: Reusable step controls

    @ViewBuilder
    private func singleChoice<T: Identifiable & Equatable>(
        _ items: [T], selection: Binding<T?>, label: @escaping (T) -> String
    ) -> some View {
        VStack(spacing: Theme.Space.s2) {
            ForEach(items) { item in
                OptionRow(title: label(item), isSelected: selection.wrappedValue == item) {
                    selection.wrappedValue = (selection.wrappedValue == item) ? nil : item
                }
            }
        }
    }

    @ViewBuilder
    private func multiChoice<T: Identifiable>(
        _ items: [T], selection: Binding<[String]>, label: @escaping (T) -> String, rawValue: @escaping (T) -> String
    ) -> some View {
        VStack(spacing: Theme.Space.s2) {
            ForEach(items) { item in
                let tag = rawValue(item)
                OptionRow(title: label(item), isSelected: selection.wrappedValue.contains(tag)) {
                    if let index = selection.wrappedValue.firstIndex(of: tag) {
                        selection.wrappedValue.remove(at: index)
                    } else {
                        selection.wrappedValue.append(tag)
                    }
                }
            }
        }
    }

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
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(minHeight: 44)
        .accessibilityLabel(title)
        .accessibilityValue(value.wrappedValue.map(String.init) ?? "Skipped")
    }

    // MARK: Footer / navigation

    private var footer: some View {
        HStack(spacing: Theme.Space.s3) {
            if stepIndex > 0 {
                Button("Back") { stepIndex -= 1 }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.greenDeep)
                    .frame(minHeight: 48)
            }
            Spacer(minLength: 0)
            Button(isLastStep ? "Done" : "Next") { advance() }
                .font(.headline)
                .foregroundStyle(Theme.onGreen)
                .frame(minWidth: 120, minHeight: 48)
                .background(Theme.greenDeep)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        }
        .padding(Theme.Space.s4)
        .background(Theme.canvas)
    }

    private func advance() {
        if isLastStep {
            finish()
        } else {
            stepIndex += 1
        }
    }

    /// Ends onboarding from any step — saves whatever was answered so far
    /// (fire-and-forget; never blocks the dismiss) and calls `onFinish()`.
    private func finish() {
        Task { await profileService.save(draft) }
        onFinish()
    }
}

/// A single selectable row shared by single- and multi-select steps.
/// Min 48pt height (comfortably above the 44pt HIG minimum).
private struct OptionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: Theme.Space.s2)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.greenDeep)
                }
            }
            .padding(.horizontal, Theme.Space.s4)
            .frame(minHeight: 48)
            .background(isSelected ? Theme.surfaceAlt : Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .strokeBorder(isSelected ? Theme.greenDeep : Theme.border, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#if DEBUG
#Preview {
    OnboardingView(onFinish: {})
        .environment(ProfileService(session: SessionService()))
}
#endif
