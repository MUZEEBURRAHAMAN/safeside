import SwiftUI
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
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onBarcode: onBarcode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onBarcode: (String) -> Void
        private var handled = false
        init(onBarcode: @escaping (String) -> Void) { self.onBarcode = onBarcode }

        func dataScanner(_ scanner: DataScannerViewController, didAdd added: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !handled else { return }
            for item in added {
                if case let .barcode(bc) = item, let payload = bc.payloadStringValue {
                    handled = true
                    onBarcode(payload)
                    break
                }
            }
        }
    }
}

/// SwiftUI wrapper screen with graceful states (camera availability / permission).
struct ScanScreen: View {
    @Environment(SessionService.self) private var session
    @State private var lastCode: String?

    var body: some View {
        Group {
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                ScannerView { code in lastCode = code }   // TODO: → APIClient.product(barcode:)
                    .ignoresSafeArea()
                    .overlay(alignment: .bottom) {
                        if let c = lastCode {
                            Text("Scanned: \(c)")
                                .padding().background(Theme.forest).foregroundStyle(Theme.onGreen)
                                .clipShape(Capsule()).padding(.bottom, 40)
                        }
                    }
            } else {
                ContentUnavailableView("Camera unavailable",
                    systemImage: "camera",
                    description: Text("Scanning needs a device camera. Run on a real iPhone."))
            }
        }
    }
}
