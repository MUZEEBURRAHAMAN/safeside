import SwiftUI

@main
struct FoodScannerApp: App {
    // Guest-first: an anonymous session exists from launch (no login wall).
    @State private var session = SessionService()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(session)
                .tint(Theme.greenDeep)
        }
    }
}

/// 4-tab shell (docs/DESIGN_SYSTEM §5.7). Scan is the primary action.
struct RootTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }

            // Center/primary in the IA; simple tab here for Phase 0.
            NavigationStack { ScanScreen() }
                .tabItem { Label("Scan", systemImage: "barcode.viewfinder") }

            Text("Plan — coming in Phase 2")
                .tabItem { Label("Plan", systemImage: "square.grid.2x2") }

            Text("Me — profile, goals, settings")
                .tabItem { Label("Me", systemImage: "person") }
        }
    }
}
