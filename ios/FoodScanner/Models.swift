import Foundation

/// Core models — mirror docs/DATA_MODEL.md. All nutrition numbers come from the
/// backend (computed from the DB), never from an LLM.

enum ScoreBand: String, Codable, Equatable {
    case high, mid, low, unknown

    var label: String {
        switch self {
        case .high: return "Lower-processed"
        case .mid:  return "Moderately processed"
        case .low:  return "Higher-processed"
        case .unknown: return "Not enough data"
        }
    }

    /// Mirrors the bands in docs/SCORING_METHODOLOGY.md (75–100 / 45–74 / 0–44).
    /// The backend is the source of truth for `band` on a real `ScoreResult` —
    /// this exists for previews/tests/defensive fallback, never to recompute
    /// scores on-device (the LLM/client never does the math).
    static func from(score: Int) -> ScoreBand {
        switch score {
        case 75...100: return .high
        case 45..<75:  return .mid
        case 0..<45:   return .low
        default:       return .unknown
        }
    }
}

struct ScoreFactor: Codable, Identifiable {
    var id: String { name }
    let name: String        // e.g. "Processing", "Nutrition", "Additives"
    let subScore: Int        // 0–100
    let weight: Double       // e.g. 0.50
    let detail: String       // plain-language line
    let sources: [Source]
}

struct Source: Codable, Hashable {
    let name: String
    let url: String?
}

struct ScoreResult: Codable {
    let score: Int           // 0–100
    let band: ScoreBand
    let confidence: String   // "high" | "limited"
    let factors: [ScoreFactor]
    let scoreVersion: String
}

struct Ingredient: Codable, Identifiable {
    var id: String { name }
    let name: String
    let what: String?
    let whyUsed: String?
    let safety: String?
    let riskTier: String?    // low | moderate | higher — matches scoring table
    let whoShouldAvoid: [String]
    let misconceptions: [String]
    let foundIn: [String]
    let sources: [Source]
    let confidence: String   // "high" | "limited"
}

struct Product: Codable, Identifiable {
    let id: String
    let barcode: String?
    let name: String
    let brand: String?
    let imageURL: String?
    let score: ScoreResult?
    let ingredients: [Ingredient]
    let allergens: [String]
    let dataConfidence: String   // "high" | "limited"
}
