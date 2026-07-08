import AVFoundation
import SwiftUI
import UIKit
import Vision
import VisionKit

/// Barcode scanning via VisionKit DataScannerViewController (first-party, iOS 16+).
/// See docs/NATIVE_IOS_STACK.md. Vision OCR label fallback lives in
/// VisionOCR.swift — `captureHandle` is handed the live scanner instance
/// below so ScanScreen can call `capturePhoto()` on it on demand (see
/// VisionOCR.swift for why that beats a second AVCaptureSession). Barcode
/// symbologies/detection/haptics below are unchanged.
struct ScannerView: UIViewControllerRepresentable {
    /// Handed the live `DataScannerViewController` once created, so the OCR
    /// fallback (VisionOCR.swift) can capture a still frame on demand.
    var captureHandle: ScannerCaptureHandle
    var onBarcode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            // Explicit symbology list, not the framework default set — retail
            // packaging uses EAN-13/EAN-8/UPC-E almost exclusively, with
            // Code128/39/93 and ITF-14 on shipping/bulk cases, plus QR for
            // some house brands. Relying on the default set was the likely
            // cause of "some barcodes scan, some don't".
            recognizedDataTypes: [
                .barcode(symbologies: [
                    .ean13, .ean8, .upce, .code128, .code39, .code93, .itf14, .qr
                ])
            ],
            qualityLevel: .balanced,        // accuracy over speed — small/curved retail codes need this
            // Multiple items can be in frame at once (shelf, multipack); we
            // pick the best candidate ourselves in the coordinator rather
            // than trust "the first thing recognized".
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: true,
            // We draw our own reticle/lock feedback (ScanOverlay) instead of
            // VisionKit's built-in per-item highlight boxes, so the two
            // don't visually compete now that multiple items can be tracked.
            isHighlightingEnabled: false
        )
        scanner.delegate = context.coordinator
        captureHandle.attach(scanner)
        // If the user hasn't been asked for camera permission yet, this is the
        // moment iOS presents the system prompt (DataScannerViewController
        // handles it — no manual AVCaptureDevice.requestAccess needed).
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onBarcode: onBarcode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onBarcode: (String) -> Void
        init(onBarcode: @escaping (String) -> Void) { self.onBarcode = onBarcode }

        // Fires on every add/update batch. We deliberately don't gate this
        // with a one-shot "handled" flag: debouncing "one lookup at a time",
        // and not re-spamming a barcode that just failed, are the
        // ScanViewModel's job (see blockedBarcode there) — that's what lets
        // re-aiming at a *different* code work immediately after an error.
        func dataScanner(_ scanner: DataScannerViewController, didAdd added: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            fireBestBarcode(from: allItems, scanner: scanner)
        }

        // With recognizesMultipleItems enabled, items already in frame keep
        // reporting updates (bounds move as the phone/product moves) — this
        // is what lets us continuously prefer whichever barcode is currently
        // most centered, not just whichever was recognized first.
        func dataScanner(_ scanner: DataScannerViewController, didUpdate updated: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            fireBestBarcode(from: allItems, scanner: scanner)
        }

        private func fireBestBarcode(from items: [RecognizedItem], scanner: DataScannerViewController) {
            let center = CGPoint(x: scanner.view.bounds.midX, y: scanner.view.bounds.midY)
            guard let payload = bestBarcode(among: items, centeredOn: center) else { return }
            onBarcode(payload)
        }

        /// Picks the recognized barcode closest to the given point, ignoring
        /// non-barcode items (e.g. text) and barcodes VisionKit couldn't
        /// decode a payload for.
        private func bestBarcode(among items: [RecognizedItem], centeredOn center: CGPoint) -> String? {
            var bestPayload: String?
            var bestDistanceSquared = CGFloat.greatestFiniteMagnitude

            for item in items {
                guard case let .barcode(barcode) = item, let payload = barcode.payloadStringValue else { continue }
                let bounds = item.bounds
                let itemCenter = CGPoint(
                    x: (bounds.topLeft.x + bounds.topRight.x + bounds.bottomLeft.x + bounds.bottomRight.x) / 4,
                    y: (bounds.topLeft.y + bounds.topRight.y + bounds.bottomLeft.y + bounds.bottomRight.y) / 4
                )
                let dx = itemCenter.x - center.x
                let dy = itemCenter.y - center.y
                let distanceSquared = dx * dx + dy * dy
                if distanceSquared < bestDistanceSquared {
                    bestDistanceSquared = distanceSquared
                    bestPayload = payload
                }
            }
            return bestPayload
        }
    }
}

/// One barcode lookup at a time; drives the calm loading/error/needs-OCR
/// states around the live camera feed.
@Observable
final class ScanViewModel {
    enum Phase: Equatable {
        case scanning
        case lookingUp
        case error(String)
        case needsOCR
        /// A "Snap the label" / "Try again" tap just fired `capturePhoto()`
        /// and Vision `VNRecognizeTextRequest` is running (VisionOCR.swift).
        case capturingLabel
        /// Vision found no readable text in the captured frame (or the
        /// capture itself failed) — calm retry, not an error state.
        case labelNotFound
    }

    private(set) var phase: Phase = .scanning
    var product: Product?
    var showProduct = false

    private var isLookingUp = false
    // The last barcode that resulted in an error/needsOCR, so a stationary
    // camera doesn't spam-retry it every frame. Cleared on reset() (Retry /
    // "Try another scan" / returning from a product) so the exact same code
    // can be tried again on purpose.
    private var blockedBarcode: String?
    // Kept warm so the very first success haptic has no perceptible delay —
    // the whole point is to make detection feel instant.
    private let feedback = UINotificationFeedbackGenerator()

    init() {
        feedback.prepare()
    }

    @MainActor
    func handle(barcode: String, api: APIClient, pantryService: PantryService) async {
        guard !isLookingUp, !showProduct else { return }   // one lookup at a time; ignore while navigating away
        guard barcode != blockedBarcode else { return }    // don't spam-retry a code that just failed
        isLookingUp = true
        defer { isLookingUp = false }

        // Fire immediately — before the network call — so the user gets
        // instant confirmation that the scan was caught, independent of
        // backend latency. Phase flips to .lookingUp in the same tick, which
        // is what locks the reticle solid in ScanOverlay.
        feedback.notificationOccurred(.success)
        phase = .lookingUp

        do {
            let product = try await api.product(barcode: barcode)
            self.product = product
            phase = .scanning
            showProduct = true
            // Auto-save to the pantry (MASTER_PLAN Phase 2). Fire-and-forget —
            // must never block/delay navigation to the result screen.
            pantryService.save(product: product)
        } catch APIClient.APIError.needsOCR {
            blockedBarcode = barcode
            phase = .needsOCR
        } catch let error as APIClient.APIError {
            blockedBarcode = barcode
            phase = .error(error.errorDescription ?? "Something went wrong. Try again.")
        } catch {
            blockedBarcode = barcode
            phase = .error("Something went wrong. Try again.")
        }
    }

    /// OCR fallback (docs/BACKEND_SPEC.md §2 step 6): captures a still frame
    /// from the live scanner (VisionOCR.swift) and runs on-device Vision text
    /// recognition on it, then sends the recognized text through the same
    /// provisional-scoring endpoint a barcode lookup would use. Reuses
    /// `isLookingUp` so a capture and a barcode lookup can never race.
    @MainActor
    func captureLabel(handle: ScannerCaptureHandle, api: APIClient, pantryService: PantryService) async {
        guard !isLookingUp, !showProduct else { return }
        isLookingUp = true
        defer { isLookingUp = false }
        phase = .capturingLabel

        do {
            guard let text = try await handle.captureLabelText() else {
                phase = .labelNotFound
                return
            }
            let product = try await api.analyzeLabel(text: text)
            self.product = product
            phase = .scanning
            showProduct = true
            // Same fire-and-forget pantry save as a barcode scan. OCR results
            // are limited-confidence (backend sets source=ocr/confidence=
            // limited) — Product.dataConfidence + ProductView already surface
            // that; nothing extra to do here.
            pantryService.save(product: product)
        } catch let error as APIClient.APIError {
            // A real network/backend failure — same generic, actionable
            // error banner a barcode lookup would show.
            phase = .error(error.errorDescription ?? "Something went wrong. Try again.")
        } catch {
            // Capture/Vision-side failure (camera busy, no frame, no text
            // recognized) — calm "couldn't read that" recovery, since the
            // likely fix is lighting/positioning, not "something went wrong."
            phase = .labelNotFound
        }
    }

    /// Re-arms scanning — called on Retry/"Try another scan", and when the
    /// user navigates back from a product (see ScanScreen).
    func reset() {
        phase = .scanning
        product = nil
        blockedBarcode = nil
        feedback.prepare()
    }
}

/// Camera hardware/permission state, checked independently of the live scan
/// so we can show the right calm state (docs/DESIGN_SYSTEM.md §5.9) instead of
/// a blank camera view.
private enum CameraAvailability: Equatable {
    case ready              // supported, and not explicitly denied — DataScannerViewController
                             // will prompt for permission itself if it's still undetermined.
    case unsupportedDevice  // no camera / unsupported hardware (e.g. Simulator).
    case permissionDenied   // user previously said no — only Settings can fix this.

    @MainActor
    static var current: CameraAvailability {
        guard DataScannerViewController.isSupported else { return .unsupportedDevice }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .denied || status == .restricted { return .permissionDenied }
        // .notDetermined or .authorized — DataScannerViewController prompts
        // for permission itself the first time scanning starts.
        return .ready
    }
}

/// SwiftUI wrapper screen with graceful states (camera availability / permission,
/// loading, error, needs-OCR) around the live scanner.
struct ScanScreen: View {
    @Environment(SessionService.self) private var session
    @Environment(PantryService.self) private var pantryService
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var vm = ScanViewModel()
    // Handed to ScannerView so it can attach the live DataScannerViewController;
    // ScanScreen uses it to trigger an on-demand OCR capture (VisionOCR.swift).
    @State private var captureHandle = ScannerCaptureHandle()
    // Seeded optimistically; resolved on appear (the check is MainActor-isolated,
    // and @State default values are evaluated outside the main actor).
    @State private var availability = CameraAvailability.ready

    var body: some View {
        content
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { availability = .current }
            .navigationDestination(isPresented: $vm.showProduct) {
                if let product = vm.product {
                    ProductView(product: product)
                }
            }
            .onChange(of: vm.showProduct) { _, isShowing in
                // Re-arm scanning when the user comes back from a result.
                if !isShowing { vm.reset() }
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Re-check after returning from Settings (permission may have
                // just been granted).
                if newPhase == .active { availability = .current }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch availability {
        case .ready:
            scannerBody
        case .unsupportedDevice:
            ContentUnavailableView(
                "Camera unavailable",
                systemImage: "camera",
                description: Text("Scanning needs a device camera. Run on a real iPhone.")
            )
        case .permissionDenied:
            permissionDeniedView
        }
    }

    private var scannerBody: some View {
        ZStack {
            ScannerView(captureHandle: captureHandle) { code in
                Task { await vm.handle(barcode: code, api: APIClient(session: session), pantryService: pantryService) }
            }
            .ignoresSafeArea()

            ScanOverlay(phase: vm.phase)
                .ignoresSafeArea()
        }
        .overlay(alignment: .bottom) { phaseBanner }
    }

    @ViewBuilder
    private var phaseBanner: some View {
        switch vm.phase {
        case .scanning:
            EmptyView()
        case .lookingUp:
            labeledSpinner("Reading the barcode…")
        case .capturingLabel:
            labeledSpinner("Reading the label…")
        case .needsOCR:
            ocrBanner(
                title: "We don't have this one yet.",
                message: "Snap the ingredients label and we'll score it.",
                hint: "Line up the ingredients + nutrition panel.",
                primaryTitle: "Snap the label",
                primaryAction: { Task { await captureLabel() } },
                secondaryTitle: "Try another scan",
                secondaryAction: { vm.reset() }
            )
        case .labelNotFound:
            ocrBanner(
                title: "Couldn't read that.",
                message: "Try again in better light.",
                hint: nil,
                primaryTitle: "Try again",
                primaryAction: { Task { await captureLabel() } },
                secondaryTitle: "Try another scan",
                secondaryAction: { vm.reset() }
            )
        case .error(let message):
            calmBanner(
                title: "Something went wrong.",
                message: message,
                actionTitle: "Retry"
            ) { vm.reset() }
        }
    }

    private func captureLabel() async {
        await vm.captureLabel(handle: captureHandle, api: APIClient(session: session), pantryService: pantryService)
    }

    private func labeledSpinner(_ text: String) -> some View {
        HStack(spacing: Theme.Space.s2) {
            ProgressView().tint(Theme.onGreen)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.onGreen)
        }
        .padding(Theme.Space.s4)
        .background(Theme.forest.opacity(0.92))
        .clipShape(Capsule())
        .padding(.bottom, Theme.Space.s6)
        .accessibilityElement(children: .combine)
    }

    private func calmBanner(title: String, message: String, actionTitle: String,
                             action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            Text(title).font(.headline).foregroundStyle(Theme.onGreen)
            Text(message).font(.subheadline).foregroundStyle(Theme.onGreen.opacity(0.85))
            Button(actionTitle, action: action)
                .font(.subheadline.bold())
                .foregroundStyle(Theme.lime)
                .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.s4)
        .background(Theme.forest.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .padding(Theme.Space.s4)
    }

    /// Two-action calm banner for the OCR fallback states (`needsOCR` /
    /// `labelNotFound`) — always offers a way forward (Snap the label / Try
    /// again) *and* a way out (Try another scan), so OCR is never a dead end
    /// (CLAUDE.md principle 4). Buttons stack vertically at accessibility
    /// Dynamic Type sizes so labels never truncate/clip side by side.
    private func ocrBanner(title: String, message: String, hint: String?,
                            primaryTitle: String, primaryAction: @escaping () -> Void,
                            secondaryTitle: String, secondaryAction: @escaping () -> Void) -> some View {
        let primaryButton = Button(primaryTitle, action: primaryAction)
            .font(.subheadline.bold())
            .foregroundStyle(Theme.ink)
            .frame(minHeight: 44)
            .padding(.horizontal, Theme.Space.s4)
            .background(Theme.lime, in: Capsule())
        let secondaryButton = Button(secondaryTitle, action: secondaryAction)
            .font(.subheadline.bold())
            .foregroundStyle(Theme.lime)
            .frame(minHeight: 44)

        return VStack(alignment: .leading, spacing: Theme.Space.s2) {
            Text(title).font(.headline).foregroundStyle(Theme.onGreen)
            Text(message).font(.subheadline).foregroundStyle(Theme.onGreen.opacity(0.85))
            if let hint {
                Text(hint).font(.footnote).foregroundStyle(Theme.onGreen.opacity(0.7))
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Theme.Space.s3) {
                    primaryButton
                    secondaryButton
                }
            } else {
                HStack(spacing: Theme.Space.s3) {
                    primaryButton
                    secondaryButton
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.s4)
        .background(Theme.forest.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .padding(Theme.Space.s4)
    }

    private var permissionDeniedView: some View {
        ContentUnavailableView {
            Label("Camera's off", systemImage: "camera.fill")
        } description: {
            Text("Turn it on in Settings to scan.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .frame(minHeight: 44)
            .accessibilityHint("Opens the Settings app so you can allow camera access.")
        }
    }
}
