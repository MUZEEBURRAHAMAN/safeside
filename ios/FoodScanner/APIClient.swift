import Foundation

/// Thin async client to OUR backend (docs/BACKEND_SPEC.md). The app never calls
/// Open Food Facts / USDA / the LLM directly — the backend holds all keys and
/// does the scoring, caching, and AI. URLSession + async/await + Codable only.
struct APIClient {
    // TODO: set your backend base URL (Supabase Edge Functions).
    static let baseURL = URL(string: "https://YOUR-PROJECT.supabase.co/functions/v1")!

    var authToken: String   // Supabase JWT (anonymous or linked)

    enum APIError: Error { case badResponse, notFound, needsOCR }

    private func request<T: Decodable>(_ path: String, method: String = "GET",
                                       body: Data? = nil) async throws -> T {
        var req = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.badResponse }
        if http.statusCode == 404 { throw APIError.notFound }
        guard (200..<300).contains(http.statusCode) else { throw APIError.badResponse }
        return try JSONDecoder().decode(T.self, from: data)
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
