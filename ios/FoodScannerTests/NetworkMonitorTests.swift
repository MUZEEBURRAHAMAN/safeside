import Testing
import Network
@testable import FoodScanner

/// Chunk 6 (Task 2): the live connectivity signal that drives the calm offline
/// banners. `NWPathMonitor` needs a real interface, so we test the observable
/// state transitions through the `apply(status:)` seam rather than a live path.
@MainActor
@Suite("NetworkMonitor")
struct NetworkMonitorTests {

    @Test("Starts optimistically online (no false offline flash before first callback)")
    func startsOptimisticallyOnline() {
        let monitor = NetworkMonitor(testMode: true)
        #expect(monitor.isOnline == true)
    }

    @Test("A satisfied path is online")
    func satisfiedPathIsOnline() {
        let monitor = NetworkMonitor(testMode: true)
        monitor.apply(status: .unsatisfied)
        monitor.apply(status: .satisfied)
        #expect(monitor.isOnline == true)
    }

    @Test("An unsatisfied path is offline")
    func unsatisfiedPathIsOffline() {
        let monitor = NetworkMonitor(testMode: true)
        monitor.apply(status: .unsatisfied)
        #expect(monitor.isOnline == false)
    }

    @Test("requiresConnection is treated as offline (not yet usable)")
    func requiresConnectionIsOffline() {
        let monitor = NetworkMonitor(testMode: true)
        monitor.apply(status: .requiresConnection)
        #expect(monitor.isOnline == false)
    }
}
