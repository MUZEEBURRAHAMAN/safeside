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

/// One Watch-outs / Benefits bar-meter row. Every value here — the number, its
/// unit, the neutral tier word, and the 0…1 meter fraction — is computed on the
/// backend from `products.nutrients` (CLAUDE.md #5). The client renders these
/// verbatim and performs ZERO arithmetic on them.
struct MeterRow: Codable, Identifiable {
    var id: String { label }
    let label: String        // "Saturated fat" | "Sugars" | "Salt" | "Fiber" | "Protein"
    let value: Double        // rounded once, backend-owned
    let unit: String         // "g"
    let tier: String         // watch-outs: low|moderate|high · benefits: low|some|good source
    let meterFraction: Double // 0…1, backend-owned
    let kind: String         // "watchOut" | "benefit"
    let sources: [Source]
}

/// Backend-computed meter rows + the pre-read counts shown on Result.
struct NutrientHighlights: Codable {
    let watchOuts: [MeterRow]
    let benefits: [MeterRow]
    let toKnowAboutCount: Int
    let beneficialCount: Int
}

struct ScoreResult: Codable {
    let score: Int           // 0–100
    let band: ScoreBand
    let confidence: String   // "high" | "limited"
    let factors: [ScoreFactor]
    let scoreVersion: String
    /// Watch-outs / Benefits meters + counts. Optional + defaulted so it decodes
    /// from pre-Chunk-1 cached responses (absent → nil) and preview/test
    /// construction sites needn't pass it.
    var highlights: NutrientHighlights? = nil
}

/// One row in the Search results list (`GET /search?q=`). A trimmed product
/// shell — enough to render a row and route a tap to the identical scored
/// `/product/:barcode` path a scan uses. `score` is present ONLY when the
/// backend has OUR cached score at the current `score_version`; a nil `score`
/// means "not scored by us yet" and the row shows a neutral affordance — we
/// never surface Open Food Facts' own Nutri-Score as ours (transparency).
struct SearchResult: Codable, Identifiable {
    var id: String { barcode }
    let barcode: String
    let name: String
    let brand: String?
    let imageURL: String?
    let score: SearchScore?          // nil ⇒ not scored by us yet (neutral dot)

    struct SearchScore: Codable {
        let score: Int
        let band: ScoreBand
    }
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
    /// Additive INS-class pill label (e.g. "Preservatives") for E-number
    /// ingredients; nil for plain food tokens. Backend-derived. Optional +
    /// defaulted so pre-Chunk-1 responses and preview literals still work.
    var category: String? = nil
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
    /// ISO timestamp the product data was fetched/cached (for dated source
    /// rows). Optional + defaulted for backward compatibility with pantry-thin
    /// reads and pre-Chunk-1 responses.
    var fetchedAt: String? = nil
}

/// One ranked better option in the Swaps sheet (`GET swaps/product/:id/swaps`).
/// Every field is backend-owned: `delta` and the `whyBetter` facts are
/// deterministic diffs of stored DB values computed server-side (CLAUDE.md #5 —
/// the LLM never does the math; principle #1 — every fact is sourced). The
/// client renders these verbatim and performs ZERO score arithmetic.
struct SwapCandidate: Codable, Identifiable {
    let id: String
    /// Routes the "View" tap through `ProductLoaderView(barcode:)` — the same
    /// scored `/product/:barcode` path a scan uses. Optional for safety; in
    /// practice a category candidate always has one.
    let barcode: String?
    let name: String
    let brand: String?
    let imageURL: String?
    let score: Int
    let band: ScoreBand
    let delta: Int                 // score − subjectScore, always > 0 here
    let inPantry: Bool
    let whyBetter: [String]        // 0–3 sourced facts, e.g. ["No colours E150d"]
}

/// `GET swaps/product/:id/swaps` response. `thin` (fewer than a strong number
/// of matches) drives the honest empty/near-miss note — never a dead-end
/// (principle #4). `filteredForAllergies` surfaces the calm restriction note.
struct SwapsResponse: Codable {
    let category: String?
    let subjectScore: Int
    let filteredForAllergies: Bool
    let swaps: [SwapCandidate]
    let thin: Bool
}

/// A side-by-side comparison of two already-scored products (Compare v1,
/// SCREEN_SPECS §10). Pure value type: it reads backend-computed integers
/// (`ScoreResult.score`, `ScoreFactor.subScore`) and decides which side reads
/// higher per metric. It NEVER computes a nutrition number or a score
/// (CLAUDE.md #5) — winner determination is display logic over integers the
/// backend already produced, not a second scoring engine. "Higher is better"
/// holds for every metric in v1 because our factor sub-scores are normalized so
/// up = better; a nil/unknown side never "wins" (honest-state rule).
struct ComparePair {
    let a: Product
    let b: Product

    enum Side: Equatable { case a, b, tie }

    /// One aligned metric row: a shared-scale label + each side's 0–100 value
    /// (nil when that side is unscored), the display band per side (for the
    /// meter tint), and the winning side.
    struct MetricRow: Identifiable, Equatable {
        let id: String          // metric name, stable
        let label: String       // "Overall" | "Nutrition" | "Additives" | "Processing"
        let valueA: Int?
        let valueB: Int?
        let bandA: ScoreBand
        let bandB: ScoreBand
        let winner: Side
    }

    /// Fixed display order so rows always align across both products,
    /// regardless of the order the backend returned factors in
    /// (mirrors `TriMetricRow.displayOrder`).
    private static let factorOrder = ["Nutrition", "Additives", "Processing"]

    /// Pure winner rule: higher wins; equal is a tie; any unknown side ⇒ tie
    /// (an unscored side never wins — never fabricate a verdict).
    static func winner(_ x: Int?, _ y: Int?) -> Side {
        guard let x, let y else { return .tie }
        if x == y { return .tie }
        return x > y ? .a : .b
    }

    private static func factorSubScore(_ p: Product, named name: String) -> Int? {
        p.score?.factors.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.subScore
    }

    /// Overall row first (from each side's `score.score` + backend `band`),
    /// then the three factors in fixed order (band derived from the sub-score
    /// for the meter tint only — display, never re-scoring). A missing factor
    /// on a side → that side's value is `nil` and the row is a tie.
    var rows: [MetricRow] {
        var out: [MetricRow] = []

        let overallA = a.score?.score
        let overallB = b.score?.score
        out.append(MetricRow(
            id: "Overall",
            label: "Overall",
            valueA: overallA,
            valueB: overallB,
            bandA: a.score?.band ?? .unknown,
            bandB: b.score?.band ?? .unknown,
            winner: Self.winner(overallA, overallB)
        ))

        for name in Self.factorOrder {
            let va = Self.factorSubScore(a, named: name)
            let vb = Self.factorSubScore(b, named: name)
            out.append(MetricRow(
                id: name,
                label: name,
                valueA: va,
                valueB: vb,
                bandA: va.map(ScoreBand.from(score:)) ?? .unknown,
                bandB: vb.map(ScoreBand.from(score:)) ?? .unknown,
                winner: Self.winner(va, vb)
            ))
        }
        return out
    }

    /// Overall winner drives which "Pick this one" CTA carries the subtle
    /// primary emphasis.
    var overallWinner: Side { Self.winner(a.score?.score, b.score?.score) }
}
