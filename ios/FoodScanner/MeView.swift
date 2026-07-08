import SwiftUI

/// The "Me" tab — profile, goals, and settings (Design System v3,
/// docs/DESIGN_SYSTEM_V3.md): light-first canvas, white floating
/// `SectionCard`s, one bold Space Grotesk hero moment, native controls
/// (`Toggle`/`Stepper`), and calm, ED-safe copy throughout (CLAUDE.md:
/// calories opt-in, no shaming, guest-first). Reuses the result screen's
/// shared components (`SectionCard`, `HairlineDivider`, `UtilityRow`,
/// `MethodologySheet` — ResultComponents.swift) rather than duplicating them.
struct MeView: View {
    @Environment(SessionService.self) private var session
    @Environment(ProfileService.self) private var profileService

    @State private var activeSheet: MeSheet?

    private var profile: Profile? { profileService.profile }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s6) {
                    header
                    guestSection
                    profileSection
                    settingsSection
                    aboutSection
                    dataControlsSection
                }
                .padding(.horizontal, 20)
                .padding(.top, Theme.Space.s4)
                .padding(.bottom, Theme.Space.s7)   // clear the tab bar
            }
            .background(Theme.canvas)
            // The hero headline below is the screen's title, matching Home's
            // pattern — no redundant nav-bar title.
            .toolbar(.hidden, for: .navigationBar)
            .task(id: session.userID) {
                // Re-runs once the anonymous session's userID resolves
                // (bootstrap is async), same pattern as HomeView.
                await profileService.load()
            }
            .sheet(item: $activeSheet) { sheet in
                sheetContent(for: sheet)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            Text("You")
                .font(DisplayType.hero)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Your goals, preferences, and settings.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Guest / identity

    /// Guest-first (SessionService starts `.anonymous` and stays that way
    /// today — `linkWithApple()` is a stubbed TODO): shows the calm "your
    /// scans are saved on this device" line and a disabled, not-yet-wired
    /// Sign in with Apple row, per CLAUDE.md's honest-monetization/no-dark-
    /// patterns rule — never implying a feature that isn't real.
    private var guestSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Theme.Space.s3) {
                    ZStack {
                        Circle().fill(Theme.greenSoft).frame(width: 40, height: 40)
                        Image(systemName: "person.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.greenDeep)
                    }
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.state == .linked ? "Signed in" : "Guest")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(session.state == .linked
                             ? "Synced to your Apple ID."
                             : "Your scans are saved on this device.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, Theme.Space.s2)
                .accessibilityElement(children: .combine)

                if session.state != .linked {
                    HairlineDivider()
                    signInWithAppleRow
                }
            }
        }
    }

    /// A future benefit, not a gate (MASTER_PLAN: "Sign in with Apple is
    /// offered later as an optional benefit") — shown so users know it's
    /// coming, but not tappable/wired yet.
    private var signInWithAppleRow: some View {
        HStack(spacing: Theme.Space.s3) {
            Image(systemName: "apple.logo")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 24)
            Text("Sign in with Apple")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: Theme.Space.s2)
            Text("Coming soon")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, Theme.Space.s2)
                .padding(.vertical, 4)
                .background(Capsule().fill(Theme.surfaceAlt))
        }
        .frame(minHeight: 44)
        .opacity(0.7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sign in with Apple. Coming soon.")
    }

    // MARK: - Profile (editable — mirrors what onboarding collects)

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s4) {
            Text("Profile")
                .font(DisplayType.h2)
                .foregroundStyle(Theme.textPrimary)

            SectionCard {
                VStack(alignment: .leading, spacing: 0) {
                    ProfileFieldRow(title: "Goal", value: profile?.goal?.label ?? "Not set") {
                        activeSheet = .goal
                    }
                    HairlineDivider()
                    ProfileFieldRow(title: "Diet pattern", value: profile?.dietPattern?.label ?? "Not set") {
                        activeSheet = .dietPattern
                    }
                    HairlineDivider()
                    ProfileFieldRow(title: "Allergies", value: allergiesText) {
                        activeSheet = .allergies
                    }
                    HairlineDivider()
                    ProfileFieldRow(title: "Dislikes", value: dislikesText) {
                        activeSheet = .dislikes
                    }
                    HairlineDivider()
                    mealsPerDayRow
                    HairlineDivider()
                    householdSizeRow
                    HairlineDivider()
                    ProfileFieldRow(title: "Cook time", value: profile?.cookTime?.label ?? "Not set") {
                        activeSheet = .cookTime
                    }
                    HairlineDivider()
                    ProfileFieldRow(title: "Budget", value: profile?.budget?.label ?? "Not set") {
                        activeSheet = .budget
                    }
                    HairlineDivider()
                    ProfileFieldRow(title: "Health flags", value: healthFlagsText) {
                        activeSheet = .healthFlags
                    }
                }
            }
        }
    }

    private var allergiesText: String {
        guard let tags = profile?.allergies, !tags.isEmpty else { return "None set" }
        return tags.map { CommonAllergen(rawValue: $0)?.label ?? $0 }.joined(separator: ", ")
    }

    private var dislikesText: String {
        guard let tags = profile?.dislikes, !tags.isEmpty else { return "None set" }
        return tags.map { CommonDislike(rawValue: $0)?.label ?? $0 }.joined(separator: ", ")
    }

    private var healthFlagsText: String {
        guard let tags = profile?.healthFlags, !tags.isEmpty else { return "None set" }
        return tags.map { CommonHealthFlag(rawValue: $0)?.label ?? $0 }.joined(separator: ", ")
    }

    /// Inline `Stepper`s (not a sheet) for the two numeric fields — matches
    /// onboarding's own control for these same questions.
    private var mealsPerDayRow: some View {
        Stepper(value: mealsPerDayBinding, in: 1...6) {
            HStack {
                Text("Meals per day")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: Theme.Space.s2)
                Text(profile?.mealsPerDay.map(String.init) ?? "Not set")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, Theme.Space.s2)
        .frame(minHeight: 44)
        .accessibilityLabel("Meals per day")
        .accessibilityValue(profile?.mealsPerDay.map(String.init) ?? "Not set")
    }

    private var householdSizeRow: some View {
        Stepper(value: householdSizeBinding, in: 1...10) {
            HStack {
                Text("People you're cooking for")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: Theme.Space.s2)
                Text(profile?.householdSize.map(String.init) ?? "Not set")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, Theme.Space.s2)
        .frame(minHeight: 44)
        .accessibilityLabel("People you're cooking for")
        .accessibilityValue(profile?.householdSize.map(String.init) ?? "Not set")
    }

    private var mealsPerDayBinding: Binding<Int> {
        Binding(
            get: { profile?.mealsPerDay ?? 3 },
            set: { newValue in Task { await profileService.updateMealsPerDay(newValue) } }
        )
    }

    private var householdSizeBinding: Binding<Int> {
        Binding(
            get: { profile?.householdSize ?? 2 },
            set: { newValue in Task { await profileService.updateHouseholdSize(newValue) } }
        )
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s4) {
            Text("Settings")
                .font(DisplayType.h2)
                .foregroundStyle(Theme.textPrimary)

            SectionCard {
                VStack(alignment: .leading, spacing: Theme.Space.s4) {
                    VStack(alignment: .leading, spacing: Theme.Space.s2) {
                        Toggle(isOn: showCaloriesBinding) {
                            Text("Show calorie & macro numbers")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .tint(Theme.greenDeep)
                        Text("Optional. We'll never show calorie numbers unless you turn them on.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HairlineDivider()

                    VStack(alignment: .leading, spacing: Theme.Space.s2) {
                        Toggle(isOn: showScoresBinding) {
                            Text("Show scores")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .tint(Theme.greenDeep)
                        Text("Hide scores for a calmer view.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var showCaloriesBinding: Binding<Bool> {
        Binding(
            get: { profile?.showCalories ?? false },
            set: { newValue in Task { await profileService.updateShowCalories(newValue) } }
        )
    }

    private var showScoresBinding: Binding<Bool> {
        Binding(
            get: { (profile?.scoreDisplay ?? .shown) == .shown },
            set: { newValue in Task { await profileService.updateScoreDisplay(newValue ? .shown : .hidden) } }
        )
    }

    // MARK: - About / trust

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s4) {
            Text("About")
                .font(DisplayType.h2)
                .foregroundStyle(Theme.textPrimary)

            SectionCard {
                VStack(alignment: .leading, spacing: 0) {
                    UtilityRow(title: "How scoring works", systemImage: "chart.pie.fill") {
                        activeSheet = .methodology
                    }
                    HairlineDivider()
                    UtilityRow(title: "Privacy", systemImage: "hand.raised.fill") {
                        activeSheet = .privacy
                    }
                    HairlineDivider()
                    UtilityRow(title: "Data sources", systemImage: "leaf.fill") {
                        activeSheet = .dataSources
                    }
                }
            }
        }
    }

    // MARK: - Data controls

    /// Honest about the current state — actually wiring local-cache/backend
    /// deletion is out of scope here, so this says exactly that instead of
    /// faking a destructive action (CLAUDE.md: never fabricate a feature
    /// that isn't real; no dark patterns).
    private var dataControlsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s4) {
            Text("Data")
                .font(DisplayType.h2)
                .foregroundStyle(Theme.textPrimary)

            SectionCard {
                VStack(alignment: .leading, spacing: Theme.Space.s3) {
                    HStack(spacing: Theme.Space.s3) {
                        Image(systemName: "trash")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 24)
                        Text("Clear my data on this device")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer(minLength: Theme.Space.s2)
                        Text("Coming soon")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, Theme.Space.s2)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Theme.surfaceAlt))
                    }
                    .frame(minHeight: 44)
                    .opacity(0.7)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Clear my data on this device. Coming soon.")

                    Text("This isn't wired up yet. When it ships, it will clear your locally cached scans and reset your on-device profile — it won't touch your account or delete anything from our servers.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Sheets

    // `Hashable` must be declared explicitly for a no-associated-values enum
    // to get synthesized conformance — required here since `id: Self`.
    private enum MeSheet: Identifiable, Hashable {
        case goal, dietPattern, allergies, dislikes, cookTime, budget, healthFlags
        case methodology, privacy, dataSources
        var id: Self { self }
    }

    @ViewBuilder
    private func sheetContent(for sheet: MeSheet) -> some View {
        switch sheet {
        case .goal:
            SingleChoiceSheet(
                title: "Goal",
                items: Goal.allCases.map { ChoiceItem(id: $0.id, label: $0.label) },
                initialSelection: profile?.goal?.rawValue
            ) { selection in
                await profileService.updateGoal(selection.flatMap(Goal.init(rawValue:)))
            }
        case .dietPattern:
            SingleChoiceSheet(
                title: "Diet pattern",
                items: DietPattern.allCases.map { ChoiceItem(id: $0.id, label: $0.label) },
                initialSelection: profile?.dietPattern?.rawValue
            ) { selection in
                await profileService.updateDietPattern(selection.flatMap(DietPattern.init(rawValue:)))
            }
        case .cookTime:
            SingleChoiceSheet(
                title: "Cook time",
                items: CookTime.allCases.map { ChoiceItem(id: $0.id, label: $0.label) },
                initialSelection: profile?.cookTime?.rawValue
            ) { selection in
                await profileService.updateCookTime(selection.flatMap(CookTime.init(rawValue:)))
            }
        case .budget:
            SingleChoiceSheet(
                title: "Budget",
                items: Budget.allCases.map { ChoiceItem(id: $0.id, label: $0.label) },
                initialSelection: profile?.budget?.rawValue
            ) { selection in
                await profileService.updateBudget(selection.flatMap(Budget.init(rawValue:)))
            }
        case .allergies:
            MultiChoiceSheet(
                title: "Allergies",
                items: CommonAllergen.allCases.map { ChoiceItem(id: $0.id, label: $0.label) },
                initialSelection: profile?.allergies ?? []
            ) { selection in
                await profileService.updateAllergies(selection)
            }
        case .dislikes:
            MultiChoiceSheet(
                title: "Dislikes",
                items: CommonDislike.allCases.map { ChoiceItem(id: $0.id, label: $0.label) },
                initialSelection: profile?.dislikes ?? []
            ) { selection in
                await profileService.updateDislikes(selection)
            }
        case .healthFlags:
            MultiChoiceSheet(
                title: "Health flags",
                items: CommonHealthFlag.allCases.map { ChoiceItem(id: $0.id, label: $0.label) },
                initialSelection: profile?.healthFlags ?? []
            ) { selection in
                await profileService.updateHealthFlags(selection)
            }
        case .methodology:
            MethodologySheet()
        case .privacy:
            PrivacySheet()
        case .dataSources:
            DataSourcesSheet()
        }
    }
}

// MARK: - Editable field row

/// A calm two-line list row (title + current value) with a trailing chevron
/// — the "Profile" section's editable-field shape. Title/value stack
/// vertically (rather than trailing-aligned on one line) so long values
/// (e.g. several allergies) wrap freely at large Dynamic Type sizes instead
/// of clipping (v3 §7: "cards reflow, never clip").
private struct ProfileFieldRow: View {
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Theme.Space.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text(value)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: Theme.Space.s2)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 2)
            }
            .padding(.vertical, Theme.Space.s2)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens options.")
    }
}

// MARK: - Choice sheets (single & multi select field editors)

/// One row shown in `SingleChoiceSheet`/`MultiChoiceSheet` — every onboarding
/// enum (`Goal`, `DietPattern`, `CommonAllergen`, ...) already exposes
/// `id == rawValue` and `.label`, so any of them maps straight onto this.
private struct ChoiceItem: Identifiable {
    let id: String
    let label: String
}

/// A single-select field editor — Goal, Diet pattern, Cook time, Budget.
/// Same option-row look as onboarding (v3 §5.10) but as a dedicated
/// Cancel/Save sheet, since this is an edit, not a first-run flow. Includes
/// an explicit "Not set" row so every field stays clearable after onboarding
/// too (CLAUDE.md ED-safe: no forced choices, every question skippable).
private struct SingleChoiceSheet: View {
    let title: String
    let items: [ChoiceItem]
    let initialSelection: String?
    let onSave: (String?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: String?
    @State private var isSaving = false

    init(title: String, items: [ChoiceItem], initialSelection: String?, onSave: @escaping (String?) async -> Void) {
        self.title = title
        self.items = items
        self.initialSelection = initialSelection
        self.onSave = onSave
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    selection = nil
                } label: {
                    choiceRow(label: "Not set", isSelected: selection == nil)
                }
                .buttonStyle(.plain)
                .listRowBackground(Theme.surface)

                ForEach(items) { item in
                    Button {
                        selection = item.id
                    } label: {
                        choiceRow(label: item.label, isSelected: selection == item.id)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.surface)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            isSaving = true
                            await onSave(selection)
                            isSaving = false
                            dismiss()
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func choiceRow(label: String, isSelected: Bool) -> some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: Theme.Space.s2)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.greenDeep)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A multi-select field editor — Allergies, Dislikes, Health flags. Same
/// shape as `SingleChoiceSheet` but toggles membership in a set instead of
/// picking one value.
private struct MultiChoiceSheet: View {
    let title: String
    let items: [ChoiceItem]
    let initialSelection: [String]
    let onSave: ([String]) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<String>
    @State private var isSaving = false

    init(title: String, items: [ChoiceItem], initialSelection: [String], onSave: @escaping ([String]) async -> Void) {
        self.title = title
        self.items = items
        self.initialSelection = initialSelection
        self.onSave = onSave
        _selection = State(initialValue: Set(initialSelection))
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(items) { item in
                    Button {
                        if selection.contains(item.id) {
                            selection.remove(item.id)
                        } else {
                            selection.insert(item.id)
                        }
                    } label: {
                        choiceRow(label: item.label, isSelected: selection.contains(item.id))
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.surface)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            isSaving = true
                            await onSave(Array(selection))
                            isSaving = false
                            dismiss()
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func choiceRow(label: String, isSelected: Bool) -> some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: Theme.Space.s2)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.greenDeep)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - About sheets

/// Placeholder privacy explainer — honest about what's real today (no
/// dedicated privacy-policy page shipped yet) rather than a canned legal
/// wall of text, same "never fabricate a feature that isn't real" principle
/// as `ReportIssueSheet` (ResultComponents.swift).
private struct PrivacySheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s4) {
                    Text("Your data, in plain terms")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("You can use this app as a guest — nothing is required to scan and see scores. What we store is used to run the app (your profile, scans, and any plans you build), and it's never sold. A full privacy policy is on its way; this screen will link to it once it ships.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    SectionCard {
                        Text("Information only — not medical advice. Allergen data may be incomplete; check labels.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Theme.Space.s4)
            }
            .background(Theme.canvas)
            .navigationTitle("Privacy")
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

/// Data-source attribution — Open Food Facts is ODbL-licensed, which
/// requires attribution and share-alike on the data (CLAUDE.md's tech
/// direction note); this is that attribution, one tap away.
private struct DataSourcesSheet: View {
    @Environment(\.dismiss) private var dismiss

    private var openFoodFactsURL: URL? { URL(string: "https://world.openfoodfacts.org") }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s4) {
                    Text("Where the data comes from")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)

                    SectionCard {
                        VStack(alignment: .leading, spacing: Theme.Space.s2) {
                            Text("Open Food Facts")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Product names, ingredients, and nutrition come from Open Food Facts, a free, open, community-built database, used under the Open Database License (ODbL) — we attribute the data and share alike, as the license requires.")
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let openFoodFactsURL {
                                Link("world.openfoodfacts.org", destination: openFoodFactsURL)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Theme.greenDeep)
                            }
                        }
                    }

                    Text("Information only — not medical advice.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(Theme.Space.s4)
            }
            .background(Theme.canvas)
            .navigationTitle("Data sources")
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

// MARK: - Previews

#if DEBUG
#Preview("Me — guest, empty profile") {
    MeView()
        .environment(SessionService())
        .environment(ProfileService(session: SessionService()))
}
#endif
