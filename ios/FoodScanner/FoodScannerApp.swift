import SwiftUI

@main
struct FoodScannerApp: App {
    // Guest-first: an anonymous session exists from launch (no login wall).
    @State private var session: SessionService
    @State private var pantryService: PantryService
    @State private var profileService: ProfileService

    // Onboarding is skippable and shown once — never gates scanning. Seeded
    // from UserDefaults so a fresh install (and only a fresh install) sees it.
    @State private var showOnboarding: Bool

    init() {
        let session = SessionService()
        _session = State(initialValue: session)
        _pantryService = State(initialValue: PantryService(session: session))
        _profileService = State(initialValue: ProfileService(session: session))
        _showOnboarding = State(initialValue: !UserDefaults.standard.bool(forKey: "hasOnboarded"))
    }

    var body: some Scene {
        WindowGroup {
#if DEBUG
            // Screenshot harness: `SHOW_SAMPLE_RESULT=1` boots straight into a
            // populated ProductView so detail screens can be verified on the
            // simulator without a live scan/tap. DEBUG-only.
            if ProcessInfo.processInfo.environment["SHOW_SAMPLE_RESULT"] == "1" {
                NavigationStack { ProductView(product: .sampleScored) }
                    .environment(session)
                    .environment(pantryService)
                    .tint(Theme.greenDeep)
            } else {
                appBody
            }
#else
            appBody
#endif
        }
    }

    private var appBody: some View {
            RootTabView()
                .environment(session)
                .environment(pantryService)
                .environment(profileService)
                .tint(Theme.greenDeep)
                .fullScreenCover(isPresented: $showOnboarding) {
                    OnboardingView {
                        UserDefaults.standard.set(true, forKey: "hasOnboarded")
                        showOnboarding = false
                    }
                    .environment(profileService)
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
