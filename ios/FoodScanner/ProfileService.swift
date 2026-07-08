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
            loadError = "Something went wrong. Try again."
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
            loadError = "Something went wrong. Try again."
            return false
        }
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
