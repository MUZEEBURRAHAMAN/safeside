import SwiftUI
import Foundation

/// Grounded, per-product AI chat, opened from `ProductView` ("Ask about this
/// product"). Every answer is scoped to the one scanned product and comes
/// from `APIClient.chat` (docs contract: `POST chat`) — the LLM explains and
/// cites, it never invents nutrition numbers (CLAUDE.md principle #5). Light-
/// first per docs/DESIGN_SYSTEM_V3.md: user turns are solid `greenDeep`
/// bubbles, assistant turns are flat `surfaceCard`-style bubbles with their
/// sources shown inline (reusing `SourceLink` from ResultComponents.swift),
/// and the "informational, not medical advice" disclaimer stays visible
/// above the input at all times rather than only inside message text.
struct ChatView: View {
    let product: Product

    @Environment(\.dismiss) private var dismiss
    @Environment(SessionService.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var viewModel: ChatViewModel?
    @State private var draftText = ""
    @FocusState private var inputFocused: Bool

    private static let starterPrompts = [
        "Is this safe?",
        "Why this score?",
        "Can kids eat this?",
        "Better options?",
    ]

    init(product: Product) {
        self.product = product
    }

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    conversation(viewModel)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Theme.canvas)
            .navigationTitle("Ask about this product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task {
            if viewModel == nil {
                viewModel = ChatViewModel(product: product, apiClient: APIClient(session: session))
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Layout

    @ViewBuilder
    private func conversation(_ viewModel: ChatViewModel) -> some View {
        VStack(spacing: 0) {
            productHeader
            HairlineDivider()
            messagesList(viewModel)
            HairlineDivider()
            disclaimerRow(viewModel)
            inputBar(viewModel)
        }
    }

    /// Product identity + the "grounded in this product's data" trust note —
    /// this chat is explicitly scoped, never a general nutrition chatbot.
    private var productHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(product.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Label("Grounded in this product's data", systemImage: "checkmark.seal.fill")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Space.s4)
        .padding(.vertical, Theme.Space.s3)
        .accessibilityElement(children: .combine)
    }

    private func messagesList(_ viewModel: ChatViewModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Space.s3) {
                    if viewModel.messages.isEmpty {
                        starterChipsSection(viewModel)
                    }

                    ForEach(viewModel.messages) { message in
                        ChatBubble(message: message)
                            .id(message.id.uuidString)
                    }

                    if viewModel.isSending {
                        TypingIndicatorBubble()
                            .id("typing")
                    }

                    if case .failed(let errorMessage) = viewModel.phase {
                        ErrorBubble(message: errorMessage) {
                            Task { await viewModel.retry() }
                        }
                        .id("error")
                    }
                }
                .padding(Theme.Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last, last.role == .assistant {
                    AccessibilityNotification.Announcement(last.content).post()
                }
                scrollToBottom(viewModel, proxy: proxy)
            }
            .onChange(of: viewModel.phase) { _, _ in
                scrollToBottom(viewModel, proxy: proxy)
            }
            .onChange(of: inputFocused) { _, focused in
                if focused { scrollToBottom(viewModel, proxy: proxy) }
            }
        }
    }

    private func starterChipsSection(_ viewModel: ChatViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s3) {
            Text("Ask anything about \(product.name).")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: Theme.Space.s2) {
                ForEach(Self.starterPrompts, id: \.self) { prompt in
                    StarterChip(title: prompt) {
                        Task { await viewModel.send(prompt) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id("top")
    }

    private func disclaimerRow(_ viewModel: ChatViewModel) -> some View {
        Text(viewModel.disclaimer)
            .font(.caption2)
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.Space.s4)
            .padding(.top, Theme.Space.s2)
            .background(Theme.surface)
    }

    private func inputBar(_ viewModel: ChatViewModel) -> some View {
        HStack(alignment: .center, spacing: Theme.Space.s2) {
            TextField("Ask about this product…", text: $draftText)
                .textFieldStyle(.plain)
                .padding(.horizontal, Theme.Space.s3)
                .frame(minHeight: 44)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
                .focused($inputFocused)
                .disabled(viewModel.isSending)
                .submitLabel(.send)
                .onSubmit { sendDraft(viewModel) }

            Button {
                sendDraft(viewModel)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.onGreen)
                    .frame(width: 44, height: 44)
                    .background(
                        canSend(viewModel) ? Theme.greenDeep : Theme.scoreUnknown.opacity(0.35),
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSend(viewModel))
            .accessibilityLabel("Send message")
        }
        .padding(Theme.Space.s3)
        .background(Theme.surface)
    }

    // MARK: Actions

    private func canSend(_ viewModel: ChatViewModel) -> Bool {
        !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isSending
    }

    private func sendDraft(_ viewModel: ChatViewModel) {
        guard canSend(viewModel) else { return }
        let text = draftText
        draftText = ""
        Task { await viewModel.send(text) }
    }

    private func scrollToBottom(_ viewModel: ChatViewModel, proxy: ScrollViewProxy) {
        let targetID = viewModel.bottomAnchorID
        if reduceMotion {
            proxy.scrollTo(targetID, anchor: .bottom)
        } else {
            withAnimation(Motion.standard) {
                proxy.scrollTo(targetID, anchor: .bottom)
            }
        }
    }

    #if DEBUG
    /// Preview-only initializer: injects a pre-built, already-populated
    /// `ChatViewModel` so `#Preview`s render a canned conversation with no
    /// live network call (the `.task` above only ever creates a fresh
    /// `ChatViewModel` when `viewModel` is still `nil`).
    init(product: Product, previewViewModel: ChatViewModel) {
        self.product = product
        _viewModel = State(initialValue: previewViewModel)
    }
    #endif
}

// MARK: - View model

/// Holds the running conversation for one product. Guest-first: `APIClient`
/// is built from whatever `SessionService` has (anonymous session token or,
/// pre-configuration, the anon key alone — see `APIClient.request`), so this
/// works before a user ever signs in.
@MainActor
@Observable
final class ChatViewModel {
    enum Phase: Equatable {
        case idle
        case sending
        case failed(String)
    }

    let product: Product
    private let apiClient: APIClient

    private(set) var messages: [ChatMessage] = []
    private(set) var phase: Phase = .idle
    /// Default matches docs/COPY_DECK.md's footer disclaimer; overwritten by
    /// `ChatReply.disclaimer` once the backend actually replies, in case it
    /// ever wants to say something more specific.
    private(set) var disclaimer: String = "Information only — not medical advice."

    init(product: Product, apiClient: APIClient) {
        self.product = product
        self.apiClient = apiClient
    }

    var isSending: Bool {
        if case .sending = phase { return true }
        return false
    }

    /// The scroll-anchor id for "whatever's newest right now" — the typing
    /// indicator while sending, the error bubble on failure, else the last
    /// real message (or "top" before the first message, matching the
    /// starter-chips section's `.id("top")`).
    var bottomAnchorID: String {
        if isSending { return "typing" }
        if case .failed = phase { return "error" }
        return messages.last?.id.uuidString ?? "top"
    }

    /// Appends a user turn and requests the assistant's reply. Guarded
    /// against re-entrancy (double-tap send / a starter chip tapped while a
    /// reply is already in flight) and empty/whitespace-only text.
    func send(_ text: String) async {
        guard !isSending else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(ChatMessage(role: .user, content: trimmed))
        await requestReply()
    }

    /// Re-sends the same history after a failure — the failed turn's user
    /// message is already in `messages`, so this never duplicates it.
    func retry() async {
        guard case .failed = phase else { return }
        await requestReply()
    }

    private func requestReply() async {
        phase = .sending
        do {
            let reply = try await apiClient.chat(productID: product.id, messages: messages)
            let assistantMessage = ChatMessage(role: .assistant, content: reply.reply, sources: reply.sources)
            messages.append(assistantMessage)
            if !reply.disclaimer.isEmpty {
                disclaimer = reply.disclaimer
            }
            phase = .idle
        } catch {
            phase = .failed(Self.friendlyMessage(for: error))
        }
    }

    /// Calm, actionable copy (docs/COPY_DECK.md) — never the raw error.
    /// `.notConfigured` gets its own line ("AI chat unavailable") since a
    /// missing backend config is a different situation than a dropped
    /// connection; every other `APIError` already carries calm copy via
    /// `errorDescription`.
    private static func friendlyMessage(for error: Error) -> String {
        if let apiError = error as? APIClient.APIError {
            if apiError == .notConfigured {
                return "AI chat isn't available right now."
            }
            return apiError.errorDescription ?? "Something went wrong. Try again."
        }
        return "Something went wrong. Try again."
    }

    #if DEBUG
    /// Preview-only: seeds a canned conversation with no network call.
    convenience init(previewProduct product: Product, messages: [ChatMessage], disclaimer: String) {
        self.init(product: product, apiClient: APIClient(session: SessionService()))
        self.messages = messages
        self.disclaimer = disclaimer
    }

    func setPreviewPhase(_ phase: Phase) {
        self.phase = phase
    }
    #endif
}

// MARK: - Message bubbles

private struct ChatBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 40) }

            VStack(alignment: .leading, spacing: Theme.Space.s2) {
                Text(message.content)
                    .font(.subheadline)
                    .foregroundStyle(isUser ? Theme.onGreen : Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                if !message.sources.isEmpty {
                    FlowLayout(spacing: Theme.Space.s2) {
                        ForEach(message.sources, id: \.self) { source in
                            SourceLink(source: source)
                        }
                    }
                }
            }
            .padding(Theme.Space.s3)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .fill(isUser ? Theme.greenDeep : Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .strokeBorder(isUser ? Color.clear : Theme.border, lineWidth: 1)
            )

            if !isUser { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isUser ? "You" : "Assistant"): \(message.content)")
    }
}

/// Calm "assistant is thinking" state — three soft pulsing dots, one static
/// path under Reduce Motion (no animation at all, per DesignKit.Motion).
private struct TypingIndicatorBubble: View {
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Theme.textSecondary)
                        .frame(width: 6, height: 6)
                        .opacity(pulse ? 1 : 0.3)
                        .animation(
                            reduceMotion ? nil :
                                .easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(Double(index) * 0.15),
                            value: pulse
                        )
                }
            }
            .padding(Theme.Space.s3)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )

            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { pulse = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Assistant is typing")
    }
}

/// Calm, actionable error state inline in the conversation (docs/COPY_DECK.md
/// errors: "what happened + how to fix"), never a dead-end.
private struct ErrorBubble: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Space.s2) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again", action: onRetry)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.greenDeep)
                    .frame(minHeight: 44, alignment: .leading)
            }
            .padding(Theme.Space.s3)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )

            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A tappable suggested-question chip (§5.8 pill chips). Prefilling + firing
/// the send in one tap is deliberate — these are meant to be a fast on-ramp
/// into the conversation, not a draft the user still has to confirm.
private struct StarterChip: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, Theme.Space.s4)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .background(Capsule().fill(Theme.surfaceAlt))
        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
    }
}

// MARK: - Previews

#if DEBUG

private struct ChatPreviewHost: View {
    let product: Product
    let messages: [ChatMessage]
    var phase: ChatViewModel.Phase = .idle

    var body: some View {
        let viewModel = ChatViewModel(
            previewProduct: product,
            messages: messages,
            disclaimer: "Information only — not medical advice."
        )
        viewModel.setPreviewPhase(phase)
        return ChatView(product: product, previewViewModel: viewModel)
            .environment(SessionService())
    }
}

#Preview("Conversation — grounded answer with sources") {
    ChatPreviewHost(product: .sampleScored, messages: [
        ChatMessage(role: .user, content: "Is this safe?"),
        ChatMessage(
            role: .assistant,
            content: "Based on this product's data, it's a moderately processed snack (NOVA 3) with one moderate-concern additive, monosodium glutamate, which is considered safe at typical intakes. Nothing here is flagged as an allergen you've asked to avoid. As always, checking the label yourself is worth doing if you have a specific concern.",
            sources: [
                Source(name: "NOVA classification (via Open Food Facts)", url: "https://world.openfoodfacts.org"),
                Source(name: "EFSA re-evaluation, 2017", url: "https://www.efsa.europa.eu/"),
            ]
        ),
    ])
}

#Preview("Empty — starter chips") {
    ChatPreviewHost(product: .sampleScored, messages: [])
}

#Preview("Sending — typing indicator") {
    ChatPreviewHost(
        product: .sampleScored,
        messages: [ChatMessage(role: .user, content: "Why this score?")],
        phase: .sending
    )
}

#Preview("Error — calm retry") {
    ChatPreviewHost(
        product: .sampleScored,
        messages: [ChatMessage(role: .user, content: "Can kids eat this?")],
        phase: .failed("Couldn't reach the server. Check your connection and try again.")
    )
}

#Preview("Accessibility XXL Dynamic Type") {
    ChatPreviewHost(product: .sampleScored, messages: [
        ChatMessage(role: .user, content: "Is this safe?"),
        ChatMessage(
            role: .assistant,
            content: "This is a moderately processed snack with one moderate-concern additive.",
            sources: [Source(name: "Open Food Facts", url: nil)]
        ),
    ])
    .dynamicTypeSize(.accessibility3)
}

#endif
