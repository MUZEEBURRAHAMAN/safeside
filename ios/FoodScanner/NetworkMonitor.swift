import Foundation
import Network
import Observation

/// Live connectivity signal for the calm offline banners (Chunk 6). Wraps
/// `NWPathMonitor` so any tab can react to airplane mode being toggled
/// *mid-session* — unlike `SessionService.isBackendReachable`, which is set
/// once at bootstrap and never updates.
///
/// This is used only to *inform the UI* (show/hide a banner, pick offline
/// copy). It never *gates* requests: the app stays offline-first — it still
/// attempts the call and falls back to cached content, so a false "offline"
/// reading can never block a request that would actually have worked
/// (`ios-networking` reachability guidance).
@MainActor
@Observable
final class NetworkMonitor {
    /// Optimistically `true` so there's no false "offline" flash before the
    /// first path callback arrives.
    private(set) var isOnline: Bool = true

    /// `nil` in test mode — state is then driven purely by `apply(status:)`.
    private let monitor: NWPathMonitor?

    init() {
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            // Hop to the main actor: `pathUpdateHandler` fires on the monitor's
            // own queue, but the observable state must mutate on the main actor
            // (no UI-thread violation).
            let status = path.status
            Task { @MainActor [weak self] in self?.apply(status: status) }
        }
        monitor.start(queue: DispatchQueue(label: "io.omnisai.foodscanner.networkmonitor"))
    }

    /// Test seam: no live `NWPathMonitor`; feed `apply(status:)` directly.
    init(testMode: Bool) {
        self.monitor = nil
    }

    /// Maps an `NWPath.Status` to `isOnline`. Only a `.satisfied` path is
    /// usable now — `.requiresConnection` (needs a VPN/tunnel first) reads as
    /// offline until it becomes satisfied.
    func apply(status: NWPath.Status) {
        isOnline = (status == .satisfied)
    }

    deinit {
        monitor?.cancel()
    }
}
