import AVFoundation
import SwiftUI
import UIKit
import VisionKit

/// Barcode scanning via VisionKit DataScannerViewController (first-party, iOS 16+).
/// See docs/NATIVE_IOS_STACK.md. Vision OCR is the label fallback (add later).
struct ScannerView: UIViewControllerRepresentable {
    var onBarcode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
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

        // Fires once per newly-recognized item. We deliberately don't gate
        // this with a one-shot "handled" flag: debouncing "one lookup at a
        // time" is the ScanViewModel's job (so scanning naturally re-arms —
        // move the barcode out of frame and back in, or point at a new
        // product, to look up again after an error).
        func dataScanner(_ scanner: DataScannerViewController, didAdd added: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for item in added {
                if case let .barcode(bc) = item, let payload = bc.payloadStringValue {
                    onBarcode(payload)
                    break
                }
            }
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
    }

    private(set) var phase: Phase = .scanning
    var product: Product?
    var showProduct = false

    private var isLookingUp = false

    @MainActor
    func handle(barcode: String, api: APIClient) async {
        guard !isLookingUp else { return }   // debounce: one lookup at a time
        isLookingUp = true
        phase = .lookingUp
        defer { isLookingUp = false }

        do {
            let product = try await api.product(barcode: barcode)
            self.product = product
            phase = .scanning
            showProduct = true
        } catch APIClient.APIError.needsOCR {
            phase = .needsOCR
        } catch let error as APIClient.APIError {
            phase = .error(error.errorDescription ?? "Something went wrong. Try again.")
        } catch {
            phase = .error("Something went wrong. Try again.")
        }
    }

    /// Re-arms scanning — called on Retry/"Try another scan", and when the
    /// user navigates back from a product (see ScanScreen).
    func reset() {
        phase = .scanning
        product = nil
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
    @Environment(\.scenePhase) private var scenePhase
    @State private var vm = ScanViewModel()
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
            ScannerView { code in
                Task { await vm.handle(barcode: code, api: APIClient(session: session)) }
            }
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
            HStack(spacing: Theme.Space.s2) {
                ProgressView().tint(Theme.onGreen)
                Text("Reading the barcode…")
                    .font(.subheadline)
                    .foregroundStyle(Theme.onGreen)
            }
            .padding(Theme.Space.s4)
            .background(Theme.forest.opacity(0.92))
            .clipShape(Capsule())
            .padding(.bottom, Theme.Space.s6)
            .accessibilityElement(children: .combine)
        case .needsOCR:
            calmBanner(
                title: "We don't have this one yet.",
                message: "Snap the ingredients label and we'll score it.",
                actionTitle: "Try another scan"
            ) { vm.reset() }
        case .error(let message):
            calmBanner(
                title: "Something went wrong.",
                message: message,
                actionTitle: "Retry"
            ) { vm.reset() }
        }
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
