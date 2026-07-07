import Foundation
import Observation

/// Guest-first session (see MASTER_PLAN principle 7 + docs/product-requirements E0).
/// The app runs on an anonymous session from first launch — NO login wall.
/// Sign in with Apple is offered later and LINKS this anonymous account
/// (so no pantry/history is lost). Wire real Supabase anonymous auth here.
@Observable
final class SessionService {
    enum State { case anonymous, linked }

    private(set) var state: State = .anonymous
    private(set) var userID: String

    init() {
        // TODO: replace with Supabase anonymous sign-in.
        // e.g. try await supabase.auth.signInAnonymously()
        // Persist the id in Keychain; reuse across launches.
        self.userID = UserDefaults.standard.string(forKey: "anonUserID") ?? {
            let id = UUID().uuidString
            UserDefaults.standard.set(id, forKey: "anonUserID")
            return id
        }()
    }

    /// Offered later as a benefit ("save/sync across devices"), never as a gate.
    /// Must LINK the anonymous account so existing data is preserved.
    func linkWithApple() async {
        // TODO: Sign in with Apple → supabase.auth.linkIdentity(...)
        state = .linked
    }
}
