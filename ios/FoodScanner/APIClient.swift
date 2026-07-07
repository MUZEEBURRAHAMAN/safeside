import Foundation

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

    /// AI ingredient explanations for a product (cached backend; see AI_INGREDIENT_EXPLANATION.md).
    func ingredients(productID: String) async throws -> [Ingredient] {
        try await request("product/\(productID)/ingredients")
    }

    /// Label OCR fallback when a barcode isn't in the DB.
    func analyzeLabel(text: String) async throws -> Product {
        let body = try JSONEncoder().encode(["text": text])
        return try await request("product/ocr", method: "POST", body: body)
    }
}
