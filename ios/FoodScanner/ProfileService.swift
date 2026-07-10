import Foundation
import Observation
import Supabase

/// Read/write access to `profiles` (docs/DATA_MODEL.md — 1:1 with the
/// session). Backs the skippable onboarding flow: guest-first, no account
/// required — writes go straight to the anonymous session's row.
@Observable
final class ProfileService {
    private(set) var profile: Profile?
    private(set) var isSaving = false
    private(set) var loadError: String?

    private let session: SessionService

    init(session: SessionService) {
        self.session = session
    }

    @MainActor
    func load() async {
        guard session.isBackendReachable, let client = session.supabaseClient,
              !session.userID.isEmpty else { return }
        do {
            let rows: [Profile] = try await client
                .from("profiles")
                .select()
                .eq("user_id", value: session.userID)
                .limit(1)
                .execute()
                .value
            profile = rows.first
            loadError = nil
        } catch {
            loadError = "Couldn't load your profile. Check your connection and try again."
        }
    }

    /// Saves (creates or updates) whatever the onboarding draft holds. Every
    /// onboarding question is skippable, so this only sends the fields the
    /// user actually answered — see `ProfileUpsertPayload` — never clobbering
    /// other columns with `null` on conflict.
    @discardableResult
    @MainActor
    func save(_ draft: ProfileDraft) async -> Bool {
        guard session.isBackendReachable, let client = session.supabaseClient,
              !session.userID.isEmpty else { return false }
        isSaving = true
        defer { isSaving = false }

        let payload = ProfileUpsertPayload(userID: session.userID, draft: draft)
        do {
            try await client
                .from("profiles")
                .upsert(payload, onConflict: "user_id", returning: .minimal)
                .execute()
            loadError = nil
            return true
        } catch {
            loadError = "Couldn't save your answers. Check your connection and try again."
            return false
        }
    }

    // MARK: - Individual field edits (MeView)

    /// Writes exactly one `profiles` column (via `upsert`, so it also works
    /// the very first time — e.g. onboarding was skipped before the backend
    /// became reachable and no row exists yet) and mirrors the change onto
    /// the already-loaded `profile` so MeView's rows/toggles reflect the edit
    /// immediately, without a round-trip `load()`. Backs every `update*`
    /// convenience below; `save(_:)` (the onboarding draft upsert) is
    /// untouched by this.
    @MainActor
    private func patchField<Value: Encodable>(
        column: String,
        value: Value,
        apply: (inout Profile) -> Void
    ) async -> Bool {
        guard session.isBackendReachable, let client = session.supabaseClient,
              !session.userID.isEmpty else { return false }
        isSaving = true
        defer { isSaving = false }

        let payload = FieldPayload(userID: session.userID, column: column, value: value)
        do {
            try await client
                .from("profiles")
                .upsert(payload, onConflict: "user_id", returning: .minimal)
                .execute()
            var updated = profile ?? Profile.empty(userID: session.userID)
            apply(&updated)
            profile = updated
            loadError = nil
            return true
        } catch {
            loadError = "Couldn't save that change. Check your connection and try again."
            return false
        }
    }

    @discardableResult
    @MainActor
    func updateGoal(_ goal: Goal?) async -> Bool {
        await patchField(column: "goal", value: goal?.rawValue) { $0.goal = goal }
    }

    @discardableResult
    @MainActor
    func updateDietPattern(_ pattern: DietPattern?) async -> Bool {
        await patchField(column: "diet_pattern", value: pattern?.rawValue) { $0.dietPattern = pattern }
    }

    @discardableResult
    @MainActor
    func updateAllergies(_ allergies: [String]) async -> Bool {
        await patchField(column: "allergies", value: allergies) { $0.allergies = allergies }
    }

    @discardableResult
    @MainActor
    func updateDislikes(_ dislikes: [String]) async -> Bool {
        await patchField(column: "dislikes", value: dislikes) { $0.dislikes = dislikes }
    }

    @discardableResult
    @MainActor
    func updateMealsPerDay(_ value: Int?) async -> Bool {
        await patchField(column: "meals_per_day", value: value) { $0.mealsPerDay = value }
    }

    @discardableResult
    @MainActor
    func updateHouseholdSize(_ value: Int?) async -> Bool {
        await patchField(column: "household_size", value: value) { $0.householdSize = value }
    }

    @discardableResult
    @MainActor
    func updateCookTime(_ value: CookTime?) async -> Bool {
        await patchField(column: "cook_time", value: value?.rawValue) { $0.cookTime = value }
    }

    @discardableResult
    @MainActor
    func updateBudget(_ value: Budget?) async -> Bool {
        await patchField(column: "budget", value: value?.rawValue) { $0.budget = value }
    }

    @discardableResult
    @MainActor
    func updateHealthFlags(_ flags: [String]) async -> Bool {
        await patchField(column: "health_flags", value: flags) { $0.healthFlags = flags }
    }

    /// ED-safe: calorie numbers are opt-in (docs/DATA_MODEL.md
    /// `show_calories` defaults false) — this is a real on/off setting, not
    /// a skippable draft field, so MeView's toggle writes immediately.
    @discardableResult
    @MainActor
    func updateShowCalories(_ value: Bool) async -> Bool {
        await patchField(column: "show_calories", value: value) { $0.showCalories = value }
    }

    @discardableResult
    @MainActor
    func updateScoreDisplay(_ value: ScoreDisplay) async -> Bool {
        await patchField(column: "score_display", value: value.rawValue) { $0.scoreDisplay = value }
    }
}

/// A brand-new, all-unset row — the local starting point `patchField` mirrors
/// a single-column edit onto when no `profile` has been loaded yet (e.g. the
/// backend was unreachable during onboarding, so no row exists locally, but
/// the user is now editing a field in MeView).
private extension Profile {
    static func empty(userID: String) -> Profile {
        Profile(
            userID: userID, goal: nil, dietPattern: nil, allergies: [], dislikes: [],
            mealsPerDay: nil, householdSize: nil, cookTime: nil, budget: nil,
            healthFlags: [], showCalories: false, scoreDisplay: .shown
        )
    }
}

/// A single dynamic `CodingKey` so one generic `FieldPayload` can encode any
/// `profiles` column by name, instead of a bespoke Encodable struct per field.
private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    init?(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int? { nil }
    init?(intValue: Int) { nil }
}

/// Encodes `{ "user_id": ..., "<column>": <value> }` — a one-column upsert
/// payload, reusable by every `update*` convenience above.
private struct FieldPayload<Value: Encodable>: Encodable {
    let userID: String
    let column: String
    let value: Value

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        try container.encode(userID, forKey: DynamicCodingKey(stringValue: "user_id")!)
        try container.encode(value, forKey: DynamicCodingKey(stringValue: column)!)
    }
}

/// Encodes only the fields the user actually answered. `profiles.user_id` is
/// the primary key, so `.upsert(onConflict: "user_id")` is a true 1:1 upsert
/// here (unlike `pantry_items`, there's no "first set" timestamp to protect).
/// `showCalories` is always sent — it's a real on/off choice (ED-safe:
/// opt-in, defaults to false), not a skippable question.
private struct ProfileUpsertPayload: Encodable {
    let userID: String
    let draft: ProfileDraft

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case goal
        case dietPattern = "diet_pattern"
        case allergies, dislikes
        case mealsPerDay = "meals_per_day"
        case householdSize = "household_size"
        case cookTime = "cook_time"
        case budget
        case healthFlags = "health_flags"
        case showCalories = "show_calories"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(userID, forKey: .userID)
        try c.encodeIfPresent(draft.goal, forKey: .goal)
        try c.encodeIfPresent(draft.dietPattern, forKey: .dietPattern)
        if !draft.allergies.isEmpty { try c.encode(draft.allergies, forKey: .allergies) }
        if !draft.dislikes.isEmpty { try c.encode(draft.dislikes, forKey: .dislikes) }
        try c.encodeIfPresent(draft.mealsPerDay, forKey: .mealsPerDay)
        try c.encodeIfPresent(draft.householdSize, forKey: .householdSize)
        try c.encodeIfPresent(draft.cookTime, forKey: .cookTime)
        try c.encodeIfPresent(draft.budget, forKey: .budget)
        if !draft.healthFlags.isEmpty { try c.encode(draft.healthFlags, forKey: .healthFlags) }
        try c.encode(draft.showCalories, forKey: .showCalories)
    }
}
