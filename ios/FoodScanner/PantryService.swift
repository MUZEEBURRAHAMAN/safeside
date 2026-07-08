import Foundation
import Observation
import Supabase

/// Read/write access to the guest-first pantry (docs/DATA_MODEL.md
/// `pantry_items`, joined client-side to the shared `products`/`score_results`
/// cache). Every successful scan auto-saves here (MASTER_PLAN Phase 2); Home
/// reads the most-recent entries. Works with no account — Supabase RLS scopes
/// every row to the anonymous session's `auth.uid()`.
///
/// `pantry_items.user_id` has NO default in the live migration (confirmed —
/// not `auth.uid()`), so every write below sets it explicitly from
/// `session.userID`. RLS still requires it to match the caller's JWT.
@Observable
final class PantryService {
    private(set) var entries: [PantryEntry] = []
    private(set) var isLoading = false
    private(set) var loadError: String?

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
            loadError = nil
        } catch {
            // Calm, actionable copy (docs/COPY_DECK.md) — never surface the raw error.
            loadError = "Something went wrong. Try again."
        }
    }

    // MARK: - Write

    /// Auto-save on every successful scan. Fire-and-forget by design — the
    /// caller (ScanViewModel) must never block navigation to the result
    /// screen on this write; failures are swallowed here.
    func save(product: Product) {
        Task { [weak self] in
            await self?.recordScan(productID: product.id, status: .scanned)
            await self?.loadRecent()
        }
    }

    /// Toggles the favorited status. Never touches `first_scanned_at`.
    func toggleFavorite(_ entry: PantryEntry) {
        let newStatus: PantryStatus = entry.status == .favorited ? .scanned : .favorited
        Task { [weak self] in
            await self?.recordScan(productID: entry.product.id, status: newStatus)
            await self?.loadRecent()
        }
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
    @MainActor
    private func recordScan(productID: String, status: PantryStatus) async {
        guard session.isBackendReachable, let client = session.supabaseClient,
              !session.userID.isEmpty else { return }
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
        } catch {
            // Swallow: the pantry is a bridge feature, never a scan blocker.
            #if DEBUG
            print("PantryService.recordScan failed: \(error)")
            #endif
        }
    }
}
