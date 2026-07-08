import Foundation

/// Pantry + Profile models — mirror docs/DATA_MODEL.md `profiles` and
/// `pantry_items` tables (already migrated in the live DB). Raw DB rows use
/// explicit snake_case `CodingKeys` because supabase-swift's default
/// JSONDecoder does NOT convert key casing (see `JSONDecoder.supabase()`).
///
/// `Product`/`ScoreBand`/`ScoreResult` already live in Models.swift — reused
/// here, not duplicated.

// MARK: - Profile (docs/DATA_MODEL.md `profiles`)

/// Every onboarding question is optional/skippable — including these enums —
/// per MASTER_PLAN Phase 2 + CLAUDE.md's ED-safe rule. Raw values match the
/// Postgres enum tokens in `profiles` exactly.
enum Goal: String, Codable, CaseIterable, Identifiable, Equatable {
    case healthier, less_processed, lose, gain, condition, budget
    var id: String { rawValue }

    var label: String {
        switch self {
        case .healthier: return "Eat healthier overall"
        case .less_processed: return "Eat less processed food"
        case .lose: return "Manage weight — lose"
        case .gain: return "Manage weight — gain"
        case .condition: return "Manage a health condition"
        case .budget: return "Eat well on a budget"
        }
    }
}

enum DietPattern: String, Codable, CaseIterable, Identifiable, Equatable {
    case omnivore, flexitarian, vegetarian, vegan, pescatarian, keto, mediterranean, none
    var id: String { rawValue }

    var label: String {
        switch self {
        case .omnivore: return "Omnivore"
        case .flexitarian: return "Flexitarian"
        case .vegetarian: return "Vegetarian"
        case .vegan: return "Vegan"
        case .pescatarian: return "Pescatarian"
        case .keto: return "Keto"
        case .mediterranean: return "Mediterranean"
        case .none: return "No particular pattern"
        }
    }
}

enum CookTime: String, Codable, CaseIterable, Identifiable, Equatable {
    case quick, medium, enjoy
    var id: String { rawValue }

    var label: String {
        switch self {
        case .quick: return "Quick — as little time as possible"
        case .medium: return "Some time — happy to cook a bit"
        case .enjoy: return "I enjoy cooking"
        }
    }
}

enum Budget: String, Codable, CaseIterable, Identifiable, Equatable {
    case low, medium, none
    var id: String { rawValue }

    var label: String {
        switch self {
        case .low: return "Budget-conscious"
        case .medium: return "Moderate"
        case .none: return "Not a factor"
        }
    }
}

enum ScoreDisplay: String, Codable {
    case shown, hidden
}

/// Common allergen tags for the onboarding multi-select (free-form `text[]`
/// column — this list is a starting point, not an exhaustive enum).
enum CommonAllergen: String, CaseIterable, Identifiable {
    case milk, eggs, peanuts, treeNuts = "tree_nuts", soy, wheat, fish, shellfish, sesame
    var id: String { rawValue }

    var label: String {
        switch self {
        case .milk: return "Milk"
        case .eggs: return "Eggs"
        case .peanuts: return "Peanuts"
        case .treeNuts: return "Tree nuts"
        case .soy: return "Soy"
        case .wheat: return "Wheat / gluten"
        case .fish: return "Fish"
        case .shellfish: return "Shellfish"
        case .sesame: return "Sesame"
        }
    }
}

/// Common optional health flags for the onboarding multi-select — informational
/// only, never used to make medical claims (see docs/COPY_DECK.md disclaimer).
enum CommonHealthFlag: String, CaseIterable, Identifiable {
    case diabetes, hypertension, pregnancy, glp1
    var id: String { rawValue }

    var label: String {
        switch self {
        case .diabetes: return "Diabetes"
        case .hypertension: return "Hypertension"
        case .pregnancy: return "Pregnancy"
        case .glp1: return "Taking a GLP-1 medication"
        }
    }
}

/// Common dislikes for the onboarding multi-select (free-form `text[]`
/// column — a starting point, not an exhaustive enum).
enum CommonDislike: String, CaseIterable, Identifiable {
    case mushrooms, cilantro, seafood, spicyFood = "spicy_food", olives, blueCheese = "blue_cheese", organMeats = "organ_meats", verySweet = "very_sweet"
    var id: String { rawValue }

    var label: String {
        switch self {
        case .mushrooms: return "Mushrooms"
        case .cilantro: return "Cilantro"
        case .seafood: return "Seafood"
        case .spicyFood: return "Spicy food"
        case .olives: return "Olives"
        case .blueCheese: return "Blue cheese"
        case .organMeats: return "Organ meats"
        case .verySweet: return "Very sweet foods"
        }
    }
}

/// Row shape for reading `profiles` (1:1 with the anonymous/linked session).
struct Profile: Codable {
    var userID: String
    var goal: Goal?
    var dietPattern: DietPattern?
    var allergies: [String]
    var dislikes: [String]
    var mealsPerDay: Int?
    var householdSize: Int?
    var cookTime: CookTime?
    var budget: Budget?
    var healthFlags: [String]
    var showCalories: Bool
    var scoreDisplay: ScoreDisplay

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
        case scoreDisplay = "score_display"
        // `computed_targets` (jsonb) intentionally omitted: onboarding never
        // writes it, and it's not needed by the views built here. Codable
        // simply ignores JSON keys with no matching CodingKey.
    }
}

/// What the onboarding flow collects in-memory before saving. Every field is
/// optional/empty by default because every question is skippable — `nil`
/// means "skipped," not "no"/"none." `showCalories` is the one real on/off
/// choice (ED-safe: opt-in, defaults to false — never shown unless the user
/// turns it on).
struct ProfileDraft {
    var goal: Goal?
    var dietPattern: DietPattern?
    var allergies: [String] = []
    var mealsPerDay: Int?
    var householdSize: Int?
    var cookTime: CookTime?
    var dislikes: [String] = []
    var budget: Budget?
    var healthFlags: [String] = []
    var showCalories = false
}

// MARK: - Pantry (docs/DATA_MODEL.md `pantry_items`, `products`, `score_results`)

enum PantryStatus: String, Codable, Equatable {
    case scanned, favorited, owned
}

/// Raw `pantry_items` row.
struct PantryItemRow: Codable, Identifiable {
    let id: String
    let userID: String
    let productID: String
    let status: PantryStatus
    let firstScannedAt: Date
    let lastSeenAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case productID = "product_id"
        case status
        case firstScannedAt = "first_scanned_at"
        case lastSeenAt = "last_seen_at"
    }
}

/// Defensive decode of `products.images` (jsonb). The exact shape isn't
/// pinned down beyond "urls" in docs/DATA_MODEL.md, so this accepts a flat
/// `{variant: url}` map (Open Food Facts–style, e.g. `{"front": "...url..."}`)
/// and never throws — an unexpected shape just means "no thumbnail," not a
/// crash or a dropped pantry row. ASSUMPTION: verify against the real payload
/// shape once a scan has actually populated `products.images`.
struct ProductImages: Decodable {
    let bestURL: String?

    init(from decoder: Decoder) throws {
        if let dict = try? decoder.singleValueContainer().decode([String: String].self) {
            bestURL = dict["front"] ?? dict.values.first
        } else {
            bestURL = nil
        }
    }
}

/// Subset of `products` columns the pantry list needs (fetched with an
/// explicit `.select(...)` list — no need to model `nutrients`/`raw_off`).
struct ProductRow: Decodable {
    let id: String
    let barcode: String?
    let name: String
    let brand: String?
    let images: ProductImages?
    let allergensTags: [String]?
    let dataConfidence: String?

    enum CodingKeys: String, CodingKey {
        case id, barcode, name, brand, images
        case allergensTags = "allergens_tags"
        case dataConfidence = "data_confidence"
    }
}

/// Subset of `score_results` columns the pantry list needs. `score_results`
/// keeps history (docs/DATA_MODEL.md), so callers fetch ordered by
/// `computed_at` desc and keep only the most recent row per `productID`.
struct ScoreResultRow: Codable {
    let id: String
    let productID: String
    let score: Int
    let band: ScoreBand
    let confidence: String
    let scoreVersion: String
    let computedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case productID = "product_id"
        case score, band, confidence
        case scoreVersion = "score_version"
        case computedAt = "computed_at"
    }
}

/// A pantry row ready for display — joins `pantry_items` + `products` +
/// the latest `score_results` row, all fetched client-side by PantryService.
struct PantryEntry: Identifiable {
    let item: PantryItemRow
    let product: ProductRow
    let score: ScoreResultRow?

    var id: String { item.id }
    var status: PantryStatus { item.status }

    var band: ScoreBand { score?.band ?? .unknown }

    /// Builds a `Product` for `ProductView(product:)` from cached pantry data
    /// only (no network re-fetch). `ingredients` and the score's `factors`
    /// breakdown aren't cached by this lightweight pantry read, so ProductView
    /// degrades gracefully: the "why this score" card shows no factor rows,
    /// and the ingredients section shows its existing empty state. A full
    /// re-scan (or a future re-fetch-by-id) fills those back in.
    func asProduct() -> Product {
        Product(
            id: product.id,
            barcode: product.barcode,
            name: product.name,
            brand: product.brand,
            imageURL: product.images?.bestURL,
            score: score.map {
                ScoreResult(
                    score: $0.score,
                    band: $0.band,
                    confidence: $0.confidence,
                    factors: [],
                    scoreVersion: $0.scoreVersion
                )
            },
            ingredients: [],
            allergens: product.allergensTags ?? [],
            dataConfidence: product.dataConfidence ?? "limited"
        )
    }
}

/// A "trending healthy" entry for Home — a globally top-scoring cached
/// product (docs/DATA_MODEL.md `products` + `score_results`), NOT a
/// pantry item. No `PantryItemRow` backs this: the user may never have
/// scanned it. See `PantryService.loadTrending`.
struct TrendingEntry: Identifiable {
    let product: ProductRow
    let score: ScoreResultRow

    var id: String { product.id }
    var band: ScoreBand { score.band }

    /// Builds a `Product` for `ProductView(product:)` from cached data only
    /// (no network re-fetch) — same graceful-degradation notes as
    /// `PantryEntry.asProduct()` apply (no ingredients/factors cached here).
    func asProduct() -> Product {
        Product(
            id: product.id,
            barcode: product.barcode,
            name: product.name,
            brand: product.brand,
            imageURL: product.images?.bestURL,
            score: ScoreResult(
                score: score.score,
                band: score.band,
                confidence: score.confidence,
                factors: [],
                scoreVersion: score.scoreVersion
            ),
            ingredients: [],
            allergens: product.allergensTags ?? [],
            dataConfidence: product.dataConfidence ?? "limited"
        )
    }
}
