import Testing
import Foundation
@testable import FoodScanner

/// Chunk 6 (Task 1): `APIClient` must tell *offline* apart from a *server*
/// failure so the UI can show the calm airplane-mode copy (COPY_DECK §Errors
/// Network / §Offline & limits) instead of a generic error, and must surface a
/// 429's `Retry-After` so the chat input can back off for exactly that long.
/// These exercise the pure mapping helpers so no live socket is needed.
@Suite("APIError mapping")
struct APIErrorMappingTests {

    // MARK: URLError → offline vs transport

    @Test(
        "Connectivity-loss URLErrors map to .offline",
        arguments: [
            URLError.Code.notConnectedToInternet,
            .timedOut,
            .networkConnectionLost,
            .cannotConnectToHost,
        ]
    )
    func offlineURLErrorMapsToOffline(code: URLError.Code) {
        #expect(APIClient.APIError.mapURLError(URLError(code)) == .offline)
    }

    @Test("An unrelated URLError maps to .transport, not .offline")
    func otherURLErrorMapsToTransport() {
        #expect(APIClient.APIError.mapURLError(URLError(.badURL)) == .transport)
    }

    @Test("A non-URLError maps to .transport")
    func nonURLErrorMapsToTransport() {
        struct Boom: Error {}
        #expect(APIClient.APIError.mapURLError(Boom()) == .transport)
    }

    // MARK: Calm, non-banned copy

    @Test("Offline copy is the verbatim COPY_DECK Network line and is calm")
    func offlineCopyIsCalmAndActionable() {
        let copy = APIClient.APIError.offline.errorDescription
        #expect(copy == "You're offline. We'll show saved results; reconnect to scan new items.")
        for banned in ["Something went wrong", "bad", "toxic", "error"] {
            #expect(copy?.localizedCaseInsensitiveContains(banned) == false)
        }
    }

    @Test("badResponse/decoding copy is the COPY_DECK server-hiccup line, never banned")
    func badResponseCopyIsNotBanned() {
        let bad = APIClient.APIError.badResponse.errorDescription
        let dec = APIClient.APIError.decoding.errorDescription
        #expect(bad == "That didn't load right. Give it a moment and try again.")
        #expect(dec == "That didn't load right. Give it a moment and try again.")
        #expect(bad?.contains("Something went wrong") == false)
        #expect(dec?.contains("Something went wrong") == false)
    }

    @Test("Rate-limit copy is the verbatim COPY_DECK §Offline & limits line")
    func rateLimitedCopyIsCalm() {
        #expect(
            APIClient.APIError.rateLimited(retryAfterSeconds: 30).errorDescription
                == "You've asked a lot in a short time. Give it a minute and try again."
        )
    }

    // MARK: 429 Retry-After parsing

    @Test("Body retryAfterSeconds wins when present")
    func retryAfterPrefersBody() {
        #expect(APIClient.APIError.parseRetryAfter(header: "45", bodySeconds: 30) == 30)
    }

    @Test("Retry-After header is used when the body omits it")
    func retryAfterFallsBackToHeader() {
        #expect(APIClient.APIError.parseRetryAfter(header: "45", bodySeconds: nil) == 45)
    }

    @Test("A missing/garbage Retry-After yields nil (caller applies a default)")
    func retryAfterMissingIsNil() {
        #expect(APIClient.APIError.parseRetryAfter(header: nil, bodySeconds: nil) == nil)
        #expect(APIClient.APIError.parseRetryAfter(header: "soon", bodySeconds: nil) == nil)
    }

    @Test("A non-positive Retry-After is ignored (never disables the input forever/negatively)")
    func retryAfterNonPositiveIsNil() {
        #expect(APIClient.APIError.parseRetryAfter(header: "0", bodySeconds: nil) == nil)
        #expect(APIClient.APIError.parseRetryAfter(header: "-5", bodySeconds: nil) == nil)
    }
}
