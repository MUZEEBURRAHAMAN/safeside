import Foundation
import Observation
import Supabase

/// Read/write access to the guest-first pantry (docs/DATA_MODEL.md
/// `pantry_items`, joined client-side to the shared `products`/`score_results`
/// cache), plus a lightweight "trending healthy products" read (top cached
/// scores, global — not personalized, not paid placement). Every successful
/// scan auto-saves here (MASTER_PLAN Phase 2); Home reads the most-recent
/// entries. Works with no account — Supabase RLS scopes every pantry row to
/// the anonymous session's `auth.uid()`; `products`/`score_results` are a
/// shared read-only cache (docs/DATA_MODEL.md §5).
///
/// `pantry_items.user_id` has NO default in the live migration (confirmed —
/// not `auth.uid()`), so every write below sets it explicitly from
/// `session.userID`. RLS still requires it to match the caller's JWT.
///
/// **Favorites contract (consumed verbatim by `ProductView`):**
/// `toggleFavorite(productID:)` and `isFavorite(_:)` below are the only two
/// entry points other views should call — do not rename.
@Observable
final class PantryService {
    private(set) var entries: [PantryEntry] = []
    private(set) var isLoading = false
    private(set) var loadError: String?

    /// Top cached high-scoring products, for Home's "Trending healthy" row.
    private(set) var trending: [TrendingEntry] = []
    private(set) var isLoadingTrending = false
    private(set) var trendingError: String?

    /// In-memory mirror of every product the user has favorited, kept in sync
    /// by `loadRecent()` (derived from `entries`) and by `toggleFavorite`
    /// (updated optimistically, then reconciled). Backs the synchronous
    /// `isFavorite(_:)` lookup so callers (row hearts, ProductView) never have
    /// to await or re-derive it from `entries`.
    private(set) var favoriteProductIDs: Set<String> = []

    private let session: SessionService

    init(session: SessionService) {
        self.session = session
    }

    // MARK: - Read

    /// Most-recently-seen pantry entries first. Safe to call repeatedly (e.g.
    /// from `.task(id: session.userID)` on Home) — this is a full reload, not
    /// a diff, which is fine at this list size (~20).
    @MainActor
    func loadRecent(limit: Int = 20) async {
        guard session.isBackendReachable, let client = session.supabaseClient,
              !session.userID.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let items: [PantryItemRow] = try await client
                .from("pantry_items")
                .select()
                .eq("user_id", value: session.userID)
                .order("last_seen_at", ascending: false)
                .limit(limit)
                .execute()
                .value

            guard !items.isEmpty else {
                entries = []
                favoriteProductIDs = []
                loadError = nil
                return
            }

            let productIDs = items.map(\.productID)

            let products: [ProductRow] = try await client
                .from("products")
                .select("id, barcode, name, brand, images, allergens_tags, data_confidence")
                .in("id", values: productIDs)
                .execute()
                .value

            let scores: [ScoreResultRow] = try await client
                .from("score_results")
                .select("id, product_id, score, band, confidence, score_version, computed_at")
                .in("product_id", values: productIDs)
                .order("computed_at", ascending: false)
                .execute()
                .value

            let productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })

            // score_results keeps history (docs/DATA_MODEL.md §2) — the query
            // above orders desc, so the first row seen per product is the
            // most recently computed one.
            var latestScoreByProduct: [String: ScoreResultRow] = [:]
            for row in scores where latestScoreByProduct[row.productID] == nil {
                latestScoreByProduct[row.productID] = row
            }

            entries = items.compactMap { item in
                guard let product = productsByID[item.productID] else { return nil }
                return PantryEntry(item: item, product: product, score: latestScoreByProduct[item.productID])
            }
            // Reconcile the fast-lookup favorites set with the server's truth
            // on every full reload (covers favorites toggled elsewhere).
            favoriteProductIDs = Set(entries.filter { $0.status == .favorited }.map { $0.product.id })
            loadError = nil
        } catch {
            // Calm, actionable copy (docs/COPY_DECK.md) — never surface the raw error.
            loadError = "Something went wrong. Try again."
        }
    }

    /// A handful of the highest-scoring cached products (`band == .high`),
    /// for Home's "Trending healthy" row (MASTER_PLAN Phase 2: "a couple of
    /// trending healthy products"). Global and honest — these are top-scoring
    /// cached products, never a paid placement. Excludes products already in
    /// the caller's pantry when `entries` has already loaded (best-effort:
    /// safe to call before or after `loadRecent()`, but call it after for the
    /// exclusion to actually apply).
    ///
    /// ASSUMPTION: `score_results` keeps history (docs/DATA_MODEL.md §2) with
    /// no server-side "current score per product" view, and PostgREST can't
    /// express a per-group top-1 in one call. This fetches the highest-scoring
    /// `band == high` rows across all history and keeps the first (highest)
    /// row per product — in the common case (a product is scored once, or
    /// re-scored and stays high) that's also its current score. A product
    /// whose score *dropped* out of the high band since an earlier high score
    /// could theoretically still surface here until this list is refreshed
    /// again after the product is re-scored. Flagged as an open question —
    /// the correct long-term fix is a backend view exposing one current row
    /// per product.
    @MainActor
    func loadTrending(limit: Int = 5) async {
        guard session.isBackendReachable, let client = session.supabaseClient else { return }
        isLoadingTrending = true
        defer { isLoadingTrending = false }

        do {
            // Over-fetch so that, after de-duplicating per product and
            // excluding ones already in the pantry, we can still usually
            // return `limit` results.
            let fetchCount = limit + entries.count + 15

            let scores: [ScoreResultRow] = try await client
                .from("score_results")
                .select("id, product_id, score, band, confidence, score_version, computed_at")
                .eq("band", value: ScoreBand.high.rawValue)
                .order("score", ascending: false)
                .limit(fetchCount)
                .execute()
                .value

            var latestScoreByProduct: [String: ScoreResultRow] = [:]
            var scoreOrderedProductIDs: [String] = []
            for row in scores where latestScoreByProduct[row.productID] == nil {
                latestScoreByProduct[row.productID] = row
                scoreOrderedProductIDs.append(row.productID)
            }

            let ownedProductIDs = Set(entries.map { $0.product.id })
            let candidateIDs = Array(
                scoreOrderedProductIDs.filter { !ownedProductIDs.contains($0) }.prefix(limit)
            )

            guard !candidateIDs.isEmpty else {
                trending = []
                trendingError = nil
                return
            }

            let products: [ProductRow] = try await client
                .from("products")
                .select("id, barcode, name, brand, images, allergens_tags, data_confidence")
                .in("id", values: candidateIDs)
                .execute()
                .value
            let productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })

            // Preserve score-desc order — `candidateIDs` already carries it.
            trending = candidateIDs.compactMap { id in
                guard let product = productsByID[id], let score = latestScoreByProduct[id] else { return nil }
                return TrendingEntry(product: product, score: score)
            }
            trendingError = nil
        } catch {
            trendingError = "Something went wrong. Try again."
        }
    }

    // MARK: - Write

    /// Auto-save on every successful scan. Fire-and-forget by design — the
    /// caller (ScanViewModel) must never block navigation to the result
    /// screen on this write; failures are swallowed here.
    ///
    /// Preserves an existing `favorited` status across re-scans (checked
    /// against the fast in-memory favorites set) — a re-scan should never
    /// silently un-favorite something the user already saved.
    func save(product: Product) {
        Task { [weak self] in
            guard let self else { return }
            let status: PantryStatus = self.isFavorite(product.id) ? .favorited : .scanned
            _ = await self.upsertStatus(productID: product.id, status: status)
            await self.loadRecent()
        }
    }

    /// Flips a product between `favorited` and not — the contract other
    /// views (ProductView) call verbatim. Works for products already in the
    /// pantry (flips back to `scanned`) and for products the user has never
    /// scanned (e.g. a trending card) — those get a fresh `pantry_items` row
    /// with `status: favorited`. Updates the observable `favoriteProductIDs`
    /// set optimistically so `isFavorite(_:)` reflects the change
    /// immediately, then reconciles with a full reload; reverts the
    /// optimistic flip if the write fails.
    @MainActor
    func toggleFavorite(productID: String) async {
        let wasFavorite = favoriteProductIDs.contains(productID)
        let newStatus: PantryStatus = wasFavorite ? .scanned : .favorited

        if wasFavorite {
            favoriteProductIDs.remove(productID)
        } else {
            favoriteProductIDs.insert(productID)
        }

        let succeeded = await upsertStatus(productID: productID, status: newStatus)
        if succeeded {
            await loadRecent()
        } else {
            // Revert the optimistic update so isFavorite(_:) stays truthful.
            if wasFavorite {
                favoriteProductIDs.insert(productID)
            } else {
                favoriteProductIDs.remove(productID)
            }
        }
    }

    /// Fast, synchronous favorite lookup — safe to call from view bodies
    /// (e.g. to pick a filled vs. outline heart) without awaiting anything.
    func isFavorite(_ productID: String) -> Bool {
        favoriteProductIDs.contains(productID)
    }

    /// Insert-or-touch a `pantry_items` row on the unique `(user_id,
    /// product_id)` pair, WITHOUT using a literal `.upsert()` call.
    ///
    /// Why: PostgREST's upsert does `INSERT ... ON CONFLICT DO UPDATE SET
    /// <every submitted column>`, which would overwrite `first_scanned_at`
    /// with `now()` on every re-scan — breaking "first scanned" semantics.
    /// Doing an UPDATE first (touching only `status`/`last_seen_at`), and
    /// falling back to an INSERT only when no row was updated, is the only
    /// way to get "set once, bumped every time" from the client alone.
    ///
    /// Returns whether the write succeeded, so callers can decide whether to
    /// keep or revert any optimistic in-memory state.
    @MainActor
    @discardableResult
    private func upsertStatus(productID: String, status: PantryStatus) async -> Bool {
        guard session.isBackendReachable, let client = session.supabaseClient,
              !session.userID.isEmpty else { return false }
        let now = Date()

        struct TouchRow: Encodable {
            let status: String
            let last_seen_at: Date
        }
        struct InsertRow: Encodable {
            let user_id: String
            let product_id: String
            let status: String
            let first_scanned_at: Date
            let last_seen_at: Date
        }

        do {
            let touched: [PantryItemRow] = try await client
                .from("pantry_items")
                .update(TouchRow(status: status.rawValue, last_seen_at: now))
                .eq("user_id", value: session.userID)
                .eq("product_id", value: productID)
                .select()
                .execute()
                .value

            if touched.isEmpty {
                try await client
                    .from("pantry_items")
                    .insert(InsertRow(
                        user_id: session.userID,
                        product_id: productID,
                        status: status.rawValue,
                        first_scanned_at: now,
                        last_seen_at: now
                    ))
                    .execute()
            }
            return true
        } catch {
            // Swallow: the pantry is a bridge feature, never a scan blocker.
            #if DEBUG
            print("PantryService.upsertStatus failed: \(error)")
            #endif
            return false
        }
    }
}
