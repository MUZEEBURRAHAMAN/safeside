import Foundation
import Testing
@testable import FoodScanner

/// The sentiment-gate timing controller (Chunk 7). Locks in the ED-safe rules:
/// the gate fires exactly once, only after the 3rd successful scan, never
/// during onboarding, and never nags afterward. Each test uses an isolated
/// `UserDefaults` suite so runs don't leak into each other or the real app.
@Suite("FeedbackGate")
@MainActor
struct FeedbackGateTests {

    /// A fresh, isolated defaults suite. `hasOnboarded` seeded to `true` by
    /// default (the common case); tests override it when they need to.
    private func makeDefaults(onboarded: Bool = true) -> UserDefaults {
        let suite = "feedbackgate.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(onboarded, forKey: "hasOnboarded")
        return defaults
    }

    @Test("Prompts exactly on the 3rd scan, and only once")
    func promptsExactlyOnThirdScan() {
        let gate = FeedbackGate(defaults: makeDefaults())

        gate.recordSuccessfulScan()
        #expect(gate.shouldPrompt == false)   // 1
        gate.recordSuccessfulScan()
        #expect(gate.shouldPrompt == false)   // 2
        gate.recordSuccessfulScan()
        #expect(gate.shouldPrompt == true)    // 3 → fire

        gate.shouldPrompt = false             // simulate the sheet consuming it
        gate.recordSuccessfulScan()
        #expect(gate.shouldPrompt == false)   // 4 → never again on equality
    }

    @Test("Never prompts during onboarding; flips true only after it completes")
    func neverPromptsDuringOnboarding() {
        let defaults = makeDefaults(onboarded: false)
        let gate = FeedbackGate(defaults: defaults)

        // Scans before onboarding don't count toward the threshold at all.
        gate.recordSuccessfulScan()
        gate.recordSuccessfulScan()
        gate.recordSuccessfulScan()
        #expect(gate.shouldPrompt == false)
        #expect(gate.successfulScanCount == 0)

        // Onboarding completes; now scans count and the 3rd tips the gate.
        defaults.set(true, forKey: "hasOnboarded")
        gate.recordSuccessfulScan()
        #expect(gate.shouldPrompt == false)
        gate.recordSuccessfulScan()
        #expect(gate.shouldPrompt == false)
        gate.recordSuccessfulScan()
        #expect(gate.shouldPrompt == true)
    }

    @Test("Never re-prompts after it has been shown")
    func neverRepromptsAfterShown() {
        let gate = FeedbackGate(defaults: makeDefaults())

        gate.recordSuccessfulScan()
        gate.recordSuccessfulScan()
        gate.recordSuccessfulScan()
        #expect(gate.shouldPrompt == true)

        gate.markPrompted()                   // sheet dismissed → latch
        #expect(gate.shouldPrompt == false)

        for _ in 0..<5 { gate.recordSuccessfulScan() }
        #expect(gate.shouldPrompt == false)   // never nags
    }

    @Test("Scan count persists across controller instances")
    func countPersists() {
        let defaults = makeDefaults()
        let first = FeedbackGate(defaults: defaults)
        first.recordSuccessfulScan()
        first.recordSuccessfulScan()
        #expect(first.successfulScanCount == 2)

        // A new controller reading the same defaults sees the same count, and
        // its 3rd scan tips the gate.
        let second = FeedbackGate(defaults: defaults)
        #expect(second.successfulScanCount == 2)
        second.recordSuccessfulScan()
        #expect(second.shouldPrompt == true)
    }
}
