import UIKit
import Vision
import VisionKit

/// On-device OCR fallback for products Open Food Facts doesn't have
/// (docs/BACKEND_SPEC.md §2 step 6 — the barcode lookup returns `needsOCR`).
///
/// **Capture approach (chosen deliberately):** `DataScannerViewController`
/// (iOS 16+) exposes `capturePhoto() async throws -> UIImage`, which grabs a
/// full-resolution still frame straight from the scanner's own, already-running
/// capture session. We use that instead of standing up a second
/// `AVCaptureSession`/`AVCapturePhotoOutput`: `ScannerView`'s
/// `DataScannerViewController` privately owns the camera's `AVCaptureSession`
/// (it isn't exposed to us), so a second, independent session would contend
/// with it for the same physical camera device. `capturePhoto()` is Apple's
/// own answer to exactly this "I need one full-quality frame while the
/// scanner keeps running" scenario, so it's both the simplest and the most
/// reliable option here — no camera hand-off, no flicker, no risk of the two
/// sessions fighting each other.
///
/// Vision then runs its own `VNRecognizeTextRequest` at `.accurate` recognition
/// level on that frame (DataScannerViewController's own live `.text(...)`
/// recognized-item type is tuned for fast on-the-fly tracking, not maximum
/// accuracy, and doesn't let us choose a recognition level — so we do a
/// dedicated, one-shot, high-accuracy pass ourselves instead of reusing it).
/// Fully on-device/offline, matching CLAUDE.md's "LLM never does the math"
/// stance and this app's privacy posture.

enum VisionOCRError: Error {
    /// The `DataScannerViewController` instance is gone (e.g. the user
    /// navigated away mid-capture). Treated as a calm retry, not a crash.
    case scannerUnavailable
    /// The captured frame couldn't be read as a `CGImage`.
    case invalidImage
}

/// Bridges the SwiftUI layer to the live `DataScannerViewController` so
/// `ScanScreen` can trigger an on-demand label capture without `ScannerView`
/// (barcode scanning) needing to know anything about OCR. Owned as `@State`
/// by `ScanScreen`, handed into `ScannerView`, which attaches the actual
/// scanner instance once VisionKit creates it.
///
/// Method-level `@MainActor` (not a class-level annotation) to match the
/// isolation pattern already used throughout this codebase for UI-adjacent
/// helpers (see `ScanViewModel.handle/captureLabel`, `SessionService`,
/// `PantryService`, `ProfileService`) — keeps the type itself lightweight to
/// construct (e.g. as a plain `@State` default value) while the one method
/// that actually touches the (globally `@MainActor`-isolated)
/// `DataScannerViewController` stays properly isolated.
final class ScannerCaptureHandle {
    private weak var scanner: DataScannerViewController?

    /// Called once by `ScannerView.makeUIViewController`. Just stores the
    /// reference — doesn't touch any of the scanner's isolated members, so
    /// it's safe to call from any context (including synchronously from
    /// `makeUIViewController`).
    func attach(_ scanner: DataScannerViewController) {
        self.scanner = scanner
    }

    /// Captures a still frame from the live camera feed and runs on-device
    /// text recognition on it. Returns `nil` (not a thrown error) when no
    /// text was found in the frame — that's the calm "couldn't read that"
    /// retry path (docs/COPY_DECK.md), never a crash or a scary error.
    @MainActor
    func captureLabelText() async throws -> String? {
        guard let scanner else { throw VisionOCRError.scannerUnavailable }
        let image = try await scanner.capturePhoto()
        return try await VisionOCR.recognizeText(in: image)
    }
}

/// Pure Vision OCR — no VisionKit/UI dependencies beyond the input image, so
/// it's trivially unit-testable in isolation from the live camera.
enum VisionOCR {
    /// Runs `VNRecognizeTextRequest` (`.accurate`, on-device) against a
    /// captured frame and concatenates the recognized lines into one payload
    /// string for `APIClient.analyzeLabel(text:)`. Dispatched onto a
    /// background queue since `VNImageRequestHandler.perform` is synchronous
    /// and `.accurate` recognition is not instant — this must never block
    /// the main actor / UI.
    static func recognizeText(in image: UIImage) async throws -> String? {
        guard let cgImage = image.cgImage else { throw VisionOCRError.invalidImage }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true

                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
                do {
                    try handler.perform([request])
                    let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                    let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: text.isEmpty ? nil : text)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

/// Standard `UIImage.Orientation` → `CGImagePropertyOrientation` mapping
/// (Apple's own sample-code pattern) so Vision reads the captured frame the
/// right way up regardless of device orientation at capture time.
private extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
