import SwiftUI

@main
struct FoodScannerApp: App {
    // Guest-first: an anonymous session exists from launch (no login wall).
    @State private var session: SessionService
    @State private var pantryService: PantryService
    @State private var profileService: ProfileService
    // Live connectivity signal for the calm offline banners (Chunk 6).
    @State private var networkMonitor = NetworkMonitor()

    // Batched, best-effort analytics + the post-3rd-scan sentiment gate (Chunk 7).
    @State private var analytics: AnalyticsLogger
    @State private var feedbackGate: FeedbackGate

    // Onboarding is skippable and shown once — never gates scanning. Seeded
    // from UserDefaults so a fresh install (and only a fresh install) sees it.
    @State private var showOnboarding: Bool

    init() {
        let session = SessionService()
        _session = State(initialValue: session)
        _pantryService = State(initialValue: PantryService(session: session))
        _profileService = State(initialValue: ProfileService(session: session))
        // Events insert directly via PostgREST (owner-only RLS) — no edge fn.
        // Stamp user_id from the live session at log time; the sink re-stamps
        // at send time in case an event was buffered before sign-in resolved.
        _analytics = State(initialValue: AnalyticsLogger(
            sink: SupabaseEventSink(session: session),
            userID: { session.userID }
        ))
        _feedbackGate = State(initialValue: FeedbackGate())
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
                // Kept for the screenshot matrix — PlanView stays in the code
                // even though its tab item is retired. TODO(categories-later):
                // restore the Plan tab.
                harness { PlanView() }
            } else if ProcessInfo.processInfo.environment["SHOW_SCREEN"] == "categories" {
                harness { CategoriesView() }
            } else if ProcessInfo.processInfo.environment["SHOW_SCREEN"] == "categorydetail" {
                // Seeded to Sodas & colas — the densest real cohort (Coke / Zero
                // / water), so the ranked-list screenshot shows real data.
                harness {
                    NavigationStack {
                        CategoryDetailView(category: FoodCategory.all[0])
                    }
                }
            } else if ProcessInfo.processInfo.environment["SHOW_SCREEN"] == "home" {
                harness { NavigationStack { HomeView() } }
            } else if ProcessInfo.processInfo.environment["SHOW_SCREEN"] == "search" {
                harness { NavigationStack { SearchView() } }
            } else if ProcessInfo.processInfo.environment["SHOW_SCREEN"] == "swaps" {
                harness {
                    Color(.systemBackground)
                        .sheet(isPresented: .constant(true)) {
                            SwapsView(product: .sampleScored, onScanAnother: {})
                        }
                }
            } else if ProcessInfo.processInfo.environment["SHOW_SCREEN"] == "chat" {
                harness { NavigationStack { ChatView(product: .sampleScored) } }
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
            } else if ProcessInfo.processInfo.environment["SHOW_SCREEN"] == "feedback" {
                // Chunk 7: the sentiment gate, presented over the Me tab so the
                // screenshot matrix can capture it (it can't be reached mid-flow).
                // The .sheet lives INSIDE the harness content so its FeedbackGate/
                // AnalyticsLogger/SessionService environment is in scope.
                harness {
                    MeView()
                        .sheet(isPresented: .constant(true)) { FeedbackGateSheet() }
                }
            } else if ProcessInfo.processInfo.environment["SHOW_SCREEN"] == "privacy" {
                harness { NavigationStack { PrivacyPolicyView() } }
            } else if ProcessInfo.processInfo.environment["SHOW_SCREEN"] == "terms" {
                harness { NavigationStack { TermsView() } }
            } else if ProcessInfo.processInfo.environment["SHOW_SCREEN"] == "attribution" {
                harness { NavigationStack { AttributionView() } }
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
            .environment(networkMonitor)
            .environment(analytics)
            .environment(feedbackGate)
            .tint(Theme.greenDeep)
    }
#endif

    private var appBody: some View {
            RootTabView()
                .environment(session)
                .environment(pantryService)
                .environment(profileService)
                .environment(networkMonitor)
                .environment(analytics)
                .environment(feedbackGate)
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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AnalyticsLogger.self) private var analytics
    @Environment(FeedbackGate.self) private var feedbackGate

    var body: some View {
        // @Bindable so the sentiment gate's `shouldPrompt` can drive a sheet.
        @Bindable var gate = feedbackGate
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }

            // Center/primary in the IA; simple tab here for Phase 0.
            NavigationStack { ScanScreen() }
                .tabItem { Label("Scan", systemImage: "barcode.viewfinder") }

            // Categories replaces Plan in the bar for now (Home · Categories ·
            // Scan · Me). PlanView stays in the codebase and in the DEBUG
            // harness (SHOW_SCREEN=plan).
            // TODO(categories-later): restore the Plan tab (5th slot, or swap
            // back) — its view is unchanged, only its `.tabItem` is retired:
            //   PlanView().tabItem { Label("Plan", systemImage: "calendar") }
            CategoriesView()
                .tabItem { Label("Categories", systemImage: "square.grid.2x2") }

            MeView()
                .tabItem { Label("Me", systemImage: "person") }
        }
        // Presented from the tab shell (never the onboarding fullScreenCover),
        // so the gate structurally cannot appear mid-onboarding.
        .sheet(isPresented: $gate.shouldPrompt) {
            FeedbackGateSheet()
        }
        // Best-effort delivery before the app suspends.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                Task { await analytics.flush() }
            }
        }
    }
}
