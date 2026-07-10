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
            // Screenshot harness: boot straight into one screen so it can be
            // verified on the simulator without live tapping. DEBUG-only.
            //   SHOW_SAMPLE_RESULT=1  → populated ProductView
            //   SHOW_SCREEN=me|plan|onboarding|result
            if ProcessInfo.processInfo.environment["SHOW_SAMPLE_RESULT"] == "1"
                || ProcessInfo.processInfo.environment["SHOW_SCREEN"] == "result" {
                harness { NavigationStack { ProductView(product: .sampleScored) } }
            } else if ProcessInfo.processInfo.environment["SHOW_SCREEN"] == "me" {
                harness { MeView() }
            } else if ProcessInfo.processInfo.environment["SHOW_SCREEN"] == "plan" {
                harness { PlanView() }
            } else if ProcessInfo.processInfo.environment["SHOW_SCREEN"] == "onboarding" {
                harness { OnboardingView {} }
            } else if ProcessInfo.processInfo.environment["SHOW_SCREEN"] == "scan" {
                harness { NavigationStack { ScanScreen() } }
            } else if ProcessInfo.processInfo.environment["SHOW_SCREEN"] == "compare" {
                // Compare v1 (Chunk 5) with two full sample products so the
                // screenshot matrix shows a real two-column contrast.
                harness {
                    NavigationStack {
                        CompareView(a: .sampleScored, b: .sampleScoredHigh)
                    }
                }
            } else {
                appBody
            }
#else
            appBody
#endif
        }
    }

#if DEBUG
    /// Wraps a harness root with all services injected (matches appBody).
    private func harness<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .environment(session)
            .environment(pantryService)
            .environment(profileService)
            .tint(Theme.greenDeep)
    }
#endif

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

            PlanView()
                .tabItem { Label("Plan", systemImage: "square.grid.2x2") }

            MeView()
                .tabItem { Label("Me", systemImage: "person") }
        }
    }
}
