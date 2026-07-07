import Foundation

/// Backend config, injected at build time via `Config.xcconfig` → Info.plist
/// `$(VAR)` substitution (see `ios/project.yml` and `ios/README.md`). Never
/// hardcode secrets here — this file only *reads* values Xcode already
/// substituted into the bundle's Info.plist.
///
/// If `Config.xcconfig` still has placeholder values (fresh checkout, before
/// the user fills in their real Supabase project), `isConfigured` is false and
/// callers (SessionService, APIClient) degrade gracefully instead of crashing.
enum AppConfig {
    private static let placeholderMarker = "REPLACE_ME"

    private static func infoString(_ key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !raw.isEmpty,
              !raw.contains(placeholderMarker) else { return nil }
        return raw
    }

    static var supabaseURL: URL? {
        guard let raw = infoString("SUPABASE_URL") else { return nil }
        return URL(string: raw)
    }

    static var supabaseAnonKey: String? {
        infoString("SUPABASE_ANON_KEY")
    }

    /// Supabase Edge Functions base URL, used by `APIClient` for all backend
    /// calls (product lookup, OCR fallback, ingredient explanations, ...).
    static var functionsBaseURL: URL? {
        supabaseURL?.appendingPathComponent("functions/v1")
    }

    static var isConfigured: Bool {
        supabaseURL != nil && supabaseAnonKey != nil
    }
}
