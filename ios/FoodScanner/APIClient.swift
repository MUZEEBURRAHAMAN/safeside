import Foundation

/// One turn in the grounded per-product chat (`POST chat`: `{ productId,
/// messages }`). Only `role`/`content` cross the wire — `id` and `sources`
/// are client-side-only presentation state (see `CodingKeys`), so encoding a
/// history for the request never round-trips them, matching the backend
/// contract exactly.
struct ChatMessage: Codable, Identifiable, Equatable {
    enum Role: String, Codable { case user, assistant }

    var id: UUID = UUID()
    let role: Role
    let content: String
    /// Populated locally from `ChatReply.sources` for an assistant turn;
    /// always empty for a user turn. Never sent to the backend.
    var sources: [Source] = []

    enum CodingKeys: String, CodingKey { case role, content }
}

/// `POST chat` response body: the grounded reply, the sources it drew on,
/// and the "informational, not medical advice" disclaimer to show with it.
struct ChatReply: Codable {
    let reply: String
    let sources: [Source]
    let disclaimer: String
}

/// Thin async client to OUR backend (docs/BACKEND_SPEC.md), via Supabase Edge
/// Functions. The app never calls Open Food Facts / USDA / the LLM directly —
/// the backend holds all keys and does the scoring, caching, and AI.
/// URLSession + async/await + Codable only.
struct APIClient {
    enum APIError: Error, LocalizedError, Equatable {
        case notConfigured
        case badResponse
        case notFound
        case needsOCR
        case decoding
        case transport
        case rateLimited

        /// Calm, actionable copy — never alarmist (docs/COPY_DECK.md).
        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "The app isn't connected to a backend yet."
            case .badResponse, .decoding:
                return "Something went wrong. Try again."
            case .notFound:
                return "We don't have this one yet."
            case .needsOCR:
                return "We don't have this one yet. Snap the ingredients label and we'll score it."
            case .transport:
                return "Couldn't reach the server. Check your connection and try again."
            case .rateLimited:
                // COPY_DECK.md §"Offline & limits" — chat rate-limit (429), verbatim.
                return "You've asked a lot in a short time. Give it a minute and try again."
            }
        }
    }

    /// Matches the 404 body the backend returns when a barcode isn't cached
    /// and wasn't found in Open Food Facts (docs/BACKEND_SPEC.md §2 step 6).
    private struct ErrorBody: Decodable {
        let error: String?
        let needsOcr: Bool?
    }

    /// Used to fetch a fresh token per-request; never cached on this struct.
    let session: SessionService

    private func request<T: Decodable>(_ path: String, method: String = "GET",
                                        body: Data? = nil) async throws -> T {
        guard let baseURL = AppConfig.functionsBaseURL,
              let anonKey = AppConfig.supabaseAnonKey else {
            throw APIError.notConfigured
        }

        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Supabase Edge Functions expect both headers: `apikey` (the project's
        // anon key) and `Authorization` (the caller's JWT — anonymous or
        // linked). Fall back to the anon key itself as the bearer token if we
        // don't have a session yet, same as the Supabase JS client does.
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        let token = await session.accessToken ?? anonKey
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = body

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError.transport
        }

        guard let http = resp as? HTTPURLResponse else { throw APIError.badResponse }

        if http.statusCode == 404 {
            if let errorBody = try? JSONDecoder().decode(ErrorBody.self, from: data),
               errorBody.needsOcr == true {
                throw APIError.needsOCR
            }
            throw APIError.notFound
        }
        // 429: the backend rate-limited this caller (e.g. a burst of /chat).
        // Surface the calm COPY_DECK line rather than a generic error so the
        // chat UI tells the user exactly what to do (never a dead-end).
        if http.statusCode == 429 { throw APIError.rateLimited }
        guard (200..<300).contains(http.statusCode) else { throw APIError.badResponse }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    /// Scan: lookup → cache → deterministic score (backend). Returns a scored Product.
    func product(barcode: String) async throws -> Product {
        try await request("product/\(barcode)")
    }

    private struct SearchEnvelope: Decodable { let results: [SearchResult] }

    /// Name-search over Open Food Facts (`GET /search?q=`), returning our
    /// normalized rows with OUR cached score attached where we have one.
    /// Built with `URLComponents`/`queryItems` rather than the path-appending
    /// `request(_:)` helper, which percent-encodes `?`/`=` in the path (they'd
    /// otherwise be escaped and break the query). Same auth headers as
    /// `request(_:)`. A typed barcode never comes here — the client routes
    /// barcodes to `product(barcode:)` directly (identical scored path).
    func search(query: String) async throws -> [SearchResult] {
        guard let baseURL = AppConfig.functionsBaseURL,
              let anonKey = AppConfig.supabaseAnonKey else {
            throw APIError.notConfigured
        }

        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("search"),
            resolvingAgainstBaseURL: false
        ) else { throw APIError.badResponse }
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else { throw APIError.badResponse }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        let token = await session.accessToken ?? anonKey
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError.transport
        }

        guard let http = resp as? HTTPURLResponse else { throw APIError.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIError.badResponse }

        do {
            return try JSONDecoder().decode(SearchEnvelope.self, from: data).results
        } catch {
            throw APIError.decoding
        }
    }

    /// AI ingredient explanations for a product (cached backend; see AI_INGREDIENT_EXPLANATION.md).
    func ingredients(productID: String) async throws -> [Ingredient] {
        try await request("product/\(productID)/ingredients")
    }

    /// Ranked, restriction-safe better options in the same category
    /// (GET swaps/product/:id/swaps). The ranking and every "why better" fact
    /// are deterministic, sourced diffs of DB fields computed server-side — the
    /// LLM never runs here (CLAUDE.md #5). Allergen filtering runs against the
    /// caller's own profile under RLS.
    func swaps(productID: String) async throws -> SwapsResponse {
        try await request("swaps/product/\(productID)/swaps")
    }

    /// Label OCR fallback when a barcode isn't in the DB.
    func analyzeLabel(text: String) async throws -> Product {
        let body = try JSONEncoder().encode(["text": text])
        return try await request("product/ocr", method: "POST", body: body)
    }

    private struct ChatRequestBody: Encodable {
        let productId: String
        let messages: [ChatMessage]
    }

    /// Grounded, per-product AI chat (docs contract: `POST chat`). Sends the
    /// full running `messages` history on every call — the backend is
    /// stateless per turn — and returns one assistant reply, its sources,
    /// and the disclaimer to show alongside it. Never medical advice; the
    /// backend is the only thing that ever fabricates prose here — all
    /// nutrition/score numbers it references were already computed
    /// server-side (CLAUDE.md: "the LLM never does the math").
    func chat(productID: String, messages: [ChatMessage]) async throws -> ChatReply {
        let body = try JSONEncoder().encode(ChatRequestBody(productId: productID, messages: messages))
        return try await request("chat", method: "POST", body: body)
    }

    /// A "Report an issue" reason — raw values match the backend
    /// `report_reason_type` enum + the product-report edge function contract.
    enum ReportReason: String, CaseIterable {
        case score_off, wrong_info, missing_ingredient, other
    }

    /// File a product report (`POST product-report`). Fire-and-confirm: the
    /// backend inserts into `product_reports` and returns `{ ok: true }`.
    /// Offline surfaces as `APIError.transport` so the sheet can offer Retry.
    func reportIssue(productID: String, reason: ReportReason, detail: String?) async throws {
        struct Body: Encodable { let productId: String; let reason: String; let detail: String? }
        let data = try JSONEncoder().encode(
            Body(productId: productID, reason: reason.rawValue, detail: detail)
        )
        let _: EmptyResponse = try await request("product-report", method: "POST", body: data)
    }
}

/// Decodes an empty/`{ ok: true }`-style success body for endpoints whose
/// result we don't need to read (e.g. product-report).
struct EmptyResponse: Decodable {}
