import Foundation
import Observation
import Supabase

/// Current deterministic score version (STATE.md — calibrated to 50 products,
/// kept current by the re-score cron, Chunk 4). Categories ranks ONLY products
/// scored at this version, so a stale-version score is never presented as
/// current. Bump in lockstep with the backend engine.
// TODO(categories-later): source this from a backend `/meta` read instead of a
// hardcoded constant, so a server-side version bump can't silently empty the
// category lists.
enum Scoring {
    static let currentVersion = "1.1.0"
}

/// SCAFFOLD (categories-later) — a data-driven verification provenance.
///
/// The founder asked for "proven by multiple testing agencies". We have NO such
/// dataset, and no free API provides multi-agency lab verification for packaged
/// food (that is Oasis's own proprietary lab work). Hardcoding agency names
/// would be a fabricated claim — a direct violation of CLAUDE.md principle #1
/// and the teardown AVOID list. So this type exists but is ALWAYS empty for now:
/// `CategoryProductRow.verifiedBy` is `[]` everywhere, and `VerifiedByBadge`
/// renders nothing while empty. When (if) a real multi-source dataset is plugged
/// in, populate `verifiedBy` from it — the view flips on with no rewrite and no
/// false claim is ever shown in the meantime.
// TODO(categories-later): populate `verifiedBy` from a real, sourced dataset.
// NEVER hardcode agency names.
struct Agency: Equatable, Hashable {
    let name: String
}

/// One ranked row in `CategoryDetailView` ("Top rated in {category}"). A trimmed
/// product shell — enough to render a row and route a tap through
/// `ProductLoaderView(barcode:)` (the identical scored `/product/:barcode` path
/// a scan uses). Every field is backend-owned; the client does ZERO score math.
struct CategoryProductRow: Identifiable, Equatable {
    let id: String
    let barcode: String?
    let name: String
    let brand: String?
    let imageURL: String?
    let score: Int
    let band: ScoreBand
    /// SCAFFOLD — always `[]` for now (see `Agency`). Never hardcode.
    var verifiedBy: [Agency] = []
}

/// Loads and ranks the products in a curated `FoodCategory`, best-first by OUR
/// score. No new backend: it reads `products` and the `product_current_scores`
/// view directly via PostgREST — the exact same globally-readable cache pattern
/// as `PantryService.loadTrending` (PantryService.swift:130). The pure ranking
/// (`rank`) is unit-tested; the network read mirrors `loadTrending` and is
/// verified on-device.
@Observable
@MainActor
final class CategoryService {
    enum State: Equatable {
        case idle
        case loading
        case loaded([CategoryProductRow])
        case error
    }

    private(set) var state: State = .idle

    private let session: SessionService

    init(session: SessionService) {
        self.session = session
    }

    /// Query `products` whose `categories_tags` OVERLAPS the category's OFF
    /// tags, attach each product's current score from `product_current_scores`,
    /// then rank (high-confidence + current-version only, best-first, deduped,
    /// capped). Honest terminal states only — never a spinner-forever.
    func loadProducts(for category: FoodCategory) async {
        // `products` + the `product_current_scores` view are globally anon-
        // readable (view is `security_invoker`, `grant select to anon`), so we
        // only need the client — not a resolved auth session. This lets the
        // list load during guest bootstrap instead of erroring before anonymous
        // sign-in finishes. A nil client means the backend isn't configured.
        guard let client = session.supabaseClient else {
            state = .error
            return
        }
        state = .loading
        do {
            // `categories_tags && {tags}` — one round-trip finds every product
            // in the category. Over-fetch generously; `rank` caps the output.
            let products: [ProductRow] = try await client
                .from("products")
                .select("id, barcode, name, brand, images, allergens_tags, data_confidence")
                .overlaps("categories_tags", value: category.offTags)
                .limit(200)
                .execute()
                .value

            guard !products.isEmpty else {
                state = .loaded([])
                return
            }

            let productIDs = products.map(\.id)
            let scores: [ScoreResultRow] = try await client
                .from("product_current_scores")
                .select("id, product_id, score, band, confidence, score_version, computed_at")
                .in("product_id", values: productIDs)
                .execute()
                .value

            state = .loaded(Self.rank(products: products, scores: scores))
        } catch {
            state = .error
        }
    }

    // MARK: - Pure ranking (unit-tested in CategoryRankingTests)

    /// Join products to their current score and produce the best-first ranked
    /// list. Pure + deterministic so it can be unit-tested without the network.
    ///
    /// Honesty gate: keeps ONLY high-confidence rows (drops `confidence ==
    /// "limited"`) at the current `SCORE_VERSION`. "Best in category" = highest
    /// on our own sourced score; the good ones float to the top. Deduped by
    /// product id (a product matching two of the category's tags appears once),
    /// sorted score-desc with a stable name tiebreak, capped at `limit`.
    nonisolated static func rank(
        products: [ProductRow],
        scores: [ScoreResultRow],
        currentVersion: String = Scoring.currentVersion,
        limit: Int = 50
    ) -> [CategoryProductRow] {
        // The view already returns one row per product; dedup defensively
        // (keep the first seen) in case a non-view fallback is ever used.
        var scoreByProduct: [String: ScoreResultRow] = [:]
        for s in scores where scoreByProduct[s.productID] == nil {
            scoreByProduct[s.productID] = s
        }
        // Non-crashing build: a product can appear once even if the query
        // returned it twice (overlapping tags) — keep the first.
        let productsByID = Dictionary(products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var rows: [CategoryProductRow] = []
        for (id, score) in scoreByProduct {
            // High-confidence + current-version only.
            guard score.confidence != "limited", score.scoreVersion == currentVersion else { continue }
            guard let product = productsByID[id] else { continue }
            rows.append(CategoryProductRow(
                id: id,
                barcode: product.barcode,
                name: product.name,
                brand: product.brand,
                imageURL: product.images?.bestURL,
                score: score.score,
                band: score.band
            ))
        }

        // Best-first. Name tiebreak keeps the order deterministic (dictionary
        // iteration above is unordered) so tests + UI are stable.
        rows.sort { $0.score != $1.score ? $0.score > $1.score : $0.name < $1.name }
        return Array(rows.prefix(limit))
    }
}
