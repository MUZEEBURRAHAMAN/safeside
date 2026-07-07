import Foundation
import Observation
import Supabase

/// Guest-first session (see MASTER_PLAN principle 7 + docs/product-requirements E0).
/// The app runs on an anonymous Supabase session from first launch — NO login
/// wall. Sign in with Apple is offered later and LINKS this anonymous account
/// (so no pantry/history is lost).
///
/// supabase-swift persists the session (Keychain-backed) and restores it
/// automatically on next launch, so we only call `signInAnonymously()` when
/// there's genuinely no session yet.
@Observable
final class SessionService {
    enum State { case anonymous, linked }

    private(set) var state: State = .anonymous
    private(set) var userID: String = ""

    /// False when `Config.xcconfig` hasn't been filled in yet, or the very
    /// first anonymous sign-in couldn't reach the backend. The scanner UI
    /// still works in this state; `APIClient` surfaces a calm, clear error
    /// instead of crashing.
    private(set) var isBackendReachable = false

    /// nil when SUPABASE_URL / SUPABASE_ANON_KEY are missing (see AppConfig).
    private let client: SupabaseClient?

    init() {
        guard let url = AppConfig.supabaseURL, let key = AppConfig.supabaseAnonKey else {
            client = nil
            return
        }
        let client = SupabaseClient(supabaseURL: url, supabaseKey: key)
        self.client = client
        Task { [weak self] in await self?.bootstrap(client) }
    }

    @MainActor
    private func bootstrap(_ client: SupabaseClient) async {
        do {
            // Restores a persisted session (Keychain), if one exists.
            let session = try await client.auth.session
            userID = session.user.id.uuidString
            isBackendReachable = true
        } catch {
            // No persisted session — start a fresh anonymous one.
            do {
                let session = try await client.auth.signInAnonymously()
                userID = session.user.id.uuidString
                isBackendReachable = true
            } catch {
                // Misconfigured project or offline at first launch. Leave
                // isBackendReachable = false; APIClient will surface this.
                isBackendReachable = false
            }
        }
    }

    /// Fresh access token for `APIClient`, fetched right before each request.
    /// supabase-swift refreshes the token under the hood if it's expired.
    /// Returns nil when the backend isn't configured or no session exists yet.
    var accessToken: String? {
        get async {
            guard let client else { return nil }
            return try? await client.auth.session.accessToken
        }
    }

    /// Offered later as a benefit ("save/sync across devices"), never as a
    /// gate. Must LINK the anonymous account so existing data is preserved.
    func linkWithApple() async {
        // TODO(Phase 3+): wire real Sign in with Apple → link the identity to
        // this anonymous user (supabase-swift's identity-linking flow needs a
        // real ASAuthorization credential + server-side handling). Stubbed
        // until Sign in with Apple ships; guest-first semantics unaffected.
        state = .linked
    }
}
