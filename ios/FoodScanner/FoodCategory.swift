import Foundation

/// A curated browsable food category (Categories tab, Oasis `categories-01`).
///
/// The Open Food Facts taxonomy is messy and overlapping (`en:snacks` vs
/// `en:sweet-snacks` vs `en:biscuits`; `en:sodas`/`en:colas`/`en:carbonated-drinks`),
/// so we map a small hand-picked set of clean, human titles to one-or-more real
/// OFF tags rather than surfacing raw taxonomy slugs. Static in the app — no
/// backend, no taxonomy fetch (see the curated-vs-dynamic note in the plan).
///
/// A category's product list is ranked by OUR OWN sourced score, best-first
/// (see `CategoryService.rank`). "Best in category" therefore means "scores
/// highest on our transparent, sourced scale" — never a lab/agency verdict we
/// don't hold (CLAUDE.md principle #1; teardown AVOID list).
struct FoodCategory: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    /// SF Symbol shown in the soft-green leading tile.
    // TODO(categories-later): swap the SF Symbol for a per-category product
    // photo thumbnail (Oasis shows a real product image per card). Needs a
    // curated image per category; SF Symbols keep it honest + instant for now.
    let systemImage: String
    /// One or more real OFF `categories_tags` this card maps to. A product is
    /// in the category when its `categories_tags` OVERLAPS this list.
    let offTags: [String]

    // TODO(categories-later): a per-category product `count` badge ("12
    // products") on the card. Needs a count query per category (or a materialized
    // count) — omitted now to keep the list a single, instant, no-load render.
    // let count: Int?

    /// The curated set. Titles/order are product decisions; every `offTags`
    /// entry is a real tag present in our `products.categories_tags` data
    /// (verified against the seed/DB). Kept intentionally small while the
    /// product corpus is thin — categories fill in as more products are scored.
    static let all: [FoodCategory] = [
        FoodCategory(
            id: "sodas-colas",
            title: "Sodas & colas",
            systemImage: "waterbottle",
            // The densest real cohort in our data (Coke / Zero / water) — the
            // best category to demo a ranked, best-first list.
            offTags: ["en:sodas", "en:colas", "en:carbonated-drinks"]
        ),
        FoodCategory(
            id: "beverages",
            title: "Beverages",
            systemImage: "cup.and.saucer",
            offTags: ["en:beverages", "en:beverages-and-beverages-preparations"]
        ),
        FoodCategory(
            id: "snacks",
            title: "Snacks",
            systemImage: "bag",
            offTags: ["en:snacks"]
        ),
        FoodCategory(
            id: "sweet-snacks",
            title: "Sweet snacks",
            systemImage: "birthday.cake",
            offTags: ["en:sweet-snacks", "en:confectioneries"]
        ),
        FoodCategory(
            id: "chocolate-spreads",
            title: "Chocolate & spreads",
            systemImage: "drop",
            offTags: [
                "en:chocolate-spreads",
                "en:sweet-spreads",
                "en:confectionary-based-spreads",
            ]
        ),
        FoodCategory(
            id: "biscuits-cookies",
            title: "Biscuits & cookies",
            systemImage: "square.grid.2x2",
            offTags: ["en:biscuits", "en:biscuits-and-cakes", "en:biscuits-and-crackers"]
        ),
        FoodCategory(
            id: "breakfast",
            title: "Breakfast",
            systemImage: "sunrise",
            offTags: ["en:breakfasts"]
        ),
        // TODO(categories-later): add Dairy / Cereal once the corpus is less
        // thin (2–8 products/category today — see the data-reality note).
    ]
}
