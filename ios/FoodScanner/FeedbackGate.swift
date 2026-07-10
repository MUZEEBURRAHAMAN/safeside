import Foundation
import Observation
import StoreKit
import Supabase
import SwiftUI

// =============================================================================
// FeedbackGate — the post-3rd-scan sentiment gate (Chunk 7)
//
// ED-safe by design (teardown-AVOID #8/#9, CLAUDE.md principle 2):
//   • Appears at most once, and only after the 3rd *successful* scan — never
//     before the app has delivered value, never mid-onboarding (it is presented
//     from the tab shell, which structurally can't be reached during the
//     onboarding fullScreenCover; the controller also refuses to count scans
//     until onboarding is complete).
//   • No shame framing, equal-weight "Not now", one-tap dismiss, never nags —
//     once shown, `feedbackPrompted` latches and it never re-appears.
//   • Unhappy sentiment routes free text to `app_feedback` (never `events`);
//     happy sentiment offers an honest App Store review with an equal "Not now".
// =============================================================================

/// Decides *when* the sentiment gate may appear. Pure count/flag logic over an
/// injectable `UserDefaults`, so it's unit-testable without any UI.
@Observable
@MainActor
final class FeedbackGate {
    /// Transient UI trigger — not persisted. `RootTabView` binds a sheet to it.
    var shouldPrompt = false

    private let defaults: UserDefaults

    private enum Keys {
        static let scanCount = "feedback.scanCount"
        static let prompted = "feedback.prompted"
        static let onboarded = "hasOnboarded"   // shared with FoodScannerApp
    }

    /// Fire exactly on the 3rd successful scan (equality, so it never nags on
    /// the 4th+ even if the sheet were dismissed without latching `prompted`).
    private let promptThreshold = 3

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Count of successful scans that happened *after* onboarding completed.
    /// Internal for tests/diagnostics.
    var successfulScanCount: Int {
        get { defaults.integer(forKey: Keys.scanCount) }
        set { defaults.set(newValue, forKey: Keys.scanCount) }
    }

    private var feedbackPrompted: Bool {
        get { defaults.bool(forKey: Keys.prompted) }
        set { defaults.set(newValue, forKey: Keys.prompted) }
    }

    private var hasOnboarded: Bool { defaults.bool(forKey: Keys.onboarded) }

    /// Called on every successful scan (barcode or OCR). Scans before
    /// onboarding completes don't count — so the gate can only ever surface
    /// once the user has actually finished setup and seen value.
    func recordSuccessfulScan() {
        guard hasOnboarded else { return }
        let newCount = successfulScanCount + 1
        successfulScanCount = newCount
        if newCount == promptThreshold && !feedbackPrompted {
            shouldPrompt = true
        }
    }

    /// Latches "already asked" so the gate never re-appears. Called when the
    /// sheet is dismissed, however it's dismissed.
    func markPrompted() {
        feedbackPrompted = true
        shouldPrompt = false
    }
}

// MARK: - Sentiment sheet

/// The emoji-free sentiment gate UI. Copy VERBATIM from COPY_DECK §Feedback
/// gate. Four equal-weight options; unhappy → free text (to `app_feedback`),
/// happy → App Store review (with an equal "Not now").
struct FeedbackGateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @Environment(SessionService.self) private var session
    @Environment(AnalyticsLogger.self) private var analytics
    @Environment(FeedbackGate.self) private var gate

    /// The four sentiments, in order. `rawValue` matches the `app_feedback`
    /// `feedback_sentiment_type` enum and the `feedback_sentiment` event prop.
    /// `fileprivate` so the extracted `SentimentOptionsRow` can reference it.
    fileprivate enum Sentiment: String, CaseIterable {
        case notGreat = "not_great"
        case okay
        case good
        case great

        var label: String {
            switch self {
            case .notGreat: return "Not great"
            case .okay: return "Okay"
            case .good: return "Good"
            case .great: return "Great"
            }
        }

        /// Unhappy sentiments route to free-text feedback; happy ones to review.
        var isPositive: Bool { self == .good || self == .great }
    }

    private enum Stage: Equatable { case picking, fixText, rate, sent }

    @State private var stage: Stage = .picking
    @State private var sentiment: Sentiment?
    @State private var message: String = ""
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .picking: pickingStage
                case .fixText: fixTextStage
                case .rate: rateStage
                case .sent: sentStage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.canvas)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.greenDeep)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        // Latch "already asked" on any dismissal (tap Close, swipe, Not now,
        // Rate, or Done) so the gate never re-appears (never nags).
        .onDisappear { gate.markPrompted() }
    }

    // MARK: Stages

    private var pickingStage: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s5) {
            Text("How's SafeSide so far?")
                .font(DisplayType.h2)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            // Equal-weight options — a plain row of chips at compact sizes,
            // stacked at accessibility sizes so labels never clip.
            SentimentOptionsRow { choose($0) }
        }
        .padding(Theme.Space.s5)
    }

    private var fixTextStage: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s4) {
            Text("What should we fix?")
                .font(DisplayType.h2)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $message)
                .frame(minHeight: 120)
                .padding(Theme.Space.s2)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
                .disabled(isSubmitting)

            Button(action: submitFeedback) {
                HStack(spacing: Theme.Space.s2) {
                    if isSubmitting { ProgressView().tint(Theme.onGreen) }
                    Text("Thanks — this goes straight to the team.")
                        .font(.body.weight(.semibold))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 52)
            }
            .foregroundStyle(Theme.onGreen)
            .background(Theme.greenDeep, in: Capsule())
            .disabled(isSubmitting)
        }
        .padding(Theme.Space.s5)
    }

    private var rateStage: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s5) {
            Text("Glad it helps. Mind rating us on the App Store?")
                .font(DisplayType.h2)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: Theme.Space.s3) {
                Button {
                    analytics.log(.appReviewRequested)
                    requestReview()
                    dismiss()
                } label: {
                    Text("Rate SafeSide")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .foregroundStyle(Theme.onGreen)
                .background(Theme.greenDeep, in: Capsule())

                // Equal-weight, no dark pattern — a real, quiet way out.
                Button {
                    dismiss()
                } label: {
                    Text("Not now")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .foregroundStyle(Theme.greenDeep)
            }
        }
        .padding(Theme.Space.s5)
    }

    private var sentStage: some View {
        VStack(spacing: Theme.Space.s4) {
            Spacer(minLength: 0)
            Image(systemName: "checkmark.seal.fill")
                .font(.largeTitle)
                .foregroundStyle(Theme.greenDeep)
            Text("Thanks — this goes straight to the team.")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.greenDeep)
                .frame(minHeight: 44)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Space.s5)
    }

    // MARK: Actions

    private func choose(_ choice: Sentiment) {
        sentiment = choice
        // Sentiment is an enum value — allowed in events.props (no PII).
        analytics.log(.feedbackSentiment, ["sentiment": .string(choice.rawValue)])
        stage = choice.isPositive ? .rate : .fixText
    }

    /// Writes the free text to `app_feedback` — NEVER `events.props`. Best-effort
    /// (mirrors ProfileService): on failure it still advances to the calm thanks
    /// state rather than blocking the user behind an error.
    private func submitFeedback() {
        guard let sentiment else { return }
        isSubmitting = true
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await AppFeedbackWriter(session: session)
                .submit(sentiment: sentiment.rawValue, message: trimmed.isEmpty ? nil : trimmed)
            isSubmitting = false
            stage = .sent
        }
    }
}

/// The four equal-weight sentiment chips. Extracted so `pickingStage` stays
/// readable; reflows to a vertical stack at accessibility Dynamic Type sizes.
private struct SentimentOptionsRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let onPick: (FeedbackGateSheet.Sentiment) -> Void

    var body: some View {
        let options = FeedbackGateSheet.Sentiment.allCases
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: Theme.Space.s3) {
                    ForEach(options, id: \.self) { chip($0) }
                }
            } else {
                HStack(spacing: Theme.Space.s2) {
                    ForEach(options, id: \.self) { chip($0) }
                }
            }
        }
    }

    private func chip(_ option: FeedbackGateSheet.Sentiment) -> some View {
        Button { onPick(option) } label: {
            Text(option.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, Theme.Space.s2)
                .background(Theme.surfaceAlt, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Owner-only insert into `app_feedback` (Chunk 7 migration). The sentiment
/// gate's free text lives here, structurally separate from analytics `events`,
/// so PII never touches `events.props`.
private struct AppFeedbackWriter {
    let session: SessionService

    struct Payload: Encodable {
        let user_id: String
        let sentiment: String
        let message: String?
    }

    @MainActor
    func submit(sentiment: String, message: String?) async {
        guard session.isBackendReachable, let client = session.supabaseClient,
              !session.userID.isEmpty else { return }
        let payload = Payload(user_id: session.userID, sentiment: sentiment, message: message)
        do {
            try await client.from("app_feedback").insert(payload).execute()
        } catch {
            // Best-effort: never surface a feedback-write failure to the user.
        }
    }
}
