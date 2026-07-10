import AVFoundation
import CoreImage
import PhotosUI
import SwiftUI
import UIKit
import Vision

/// Barcode scanning via a custom, fully-owned `AVCaptureSession` pipeline.
///
/// **Why not VisionKit's `DataScannerViewController` (the original
/// implementation):** it has no public zoom API, and `videoZoomFactor` set on
/// an independently-fetched `AVCaptureDevice` does nothing to its feed —
/// VisionKit owns its own internal capture session/device and there's no
/// guarantee (in fact good evidence to the contrary, confirmed on-device)
/// that an externally grabbed `AVCaptureDevice.default(for: .video)` is even
/// the same device instance feeding the visible preview. Owning the session
/// ourselves means the exact `AVCaptureDevice` behind `videoZoomFactor` is
/// unambiguously the one producing every frame on screen.
///
/// See `CameraViewController` below for the capture pipeline itself and
/// `ScannerCaptureBridge` for how SwiftUI (`ScanOverlay`'s zoom/torch
/// buttons, `ScanScreen`'s "Snap the label" OCR flow) reaches into it.
/// `VisionOCR.swift` (unmodified) still does the actual on-device text
/// recognition — only how it gets fed a still image changes.
struct ScannerView: UIViewControllerRepresentable {
    /// Handed the live `CameraViewController` once created, so `ScanOverlay`
    /// (zoom/torch) and `ScanScreen` (OCR "Snap the label" capture) can drive
    /// the exact same capture device/session that's on screen.
    var captureHandle: ScannerCaptureBridge
    var onBarcode: (String) -> Void
    /// Fired if camera access is actually denied once we try to use it
    /// (e.g. the user taps "Don't Allow" on the system prompt while this
    /// screen is already showing) — lets `ScanScreen` flip to the calm
    /// permission-denied state without waiting for a `scenePhase` change.
    var onPermissionDenied: () -> Void

    func makeUIViewController(context: Context) -> CameraViewController {
        let controller = CameraViewController()
        controller.onBarcode = onBarcode
        controller.onPermissionDenied = onPermissionDenied
        captureHandle.attach(controller)
        return controller
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}
}

/// A `UIView` whose backing `CALayer` *is* an `AVCaptureVideoPreviewLayer`
/// (Apple's own AVCam sample pattern, via the `layerClass` override). Because
/// the preview layer is the view's own layer rather than a manually-managed
/// sublayer, UIKit keeps it sized to the view's bounds automatically on every
/// layout pass — no `layoutSubviews`/frame-syncing code needed.
final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        // Guaranteed by the `layerClass` override above.
        // swiftlint:disable:next force_cast
        layer as! AVCaptureVideoPreviewLayer
    }
}

/// Owns the entire capture pipeline: one `AVCaptureSession` with a single
/// back-camera input feeding both an `AVCaptureMetadataOutput` (live barcode
/// detection) and an `AVCapturePhotoOutput` (one-shot stills for the OCR
/// fallback). Real optical zoom and torch are applied directly to this same
/// input device, so they always affect exactly what's on screen.
///
/// **Threading model:** all session/device mutation (`beginConfiguration`,
/// `addInput`/`addOutput`, `startRunning`/`stopRunning`, zoom, torch, photo
/// capture) happens serialized on `sessionQueue`, a private background serial
/// queue — mirroring Apple's own AVCam sample. `AVCaptureMetadataOutput`'s
/// delegate callbacks are also delivered on `sessionQueue` (it requires a
/// serial queue). UI-facing work (reading `videoPreviewLayer.bounds`,
/// invoking `onBarcode`, resolving the photo-capture continuation, and every
/// completion closure) is always explicitly hopped back to the main thread —
/// never assumed. Nothing here blocks the main thread.
final class CameraViewController: UIViewController {
    /// Fired (always on main) with the payload of whichever recognized
    /// barcode is currently closest to the reticle's center — mirrors the
    /// old `DataScannerViewController` Coordinator's "closest wins" logic.
    var onBarcode: ((String) -> Void)?
    /// Fired (always on main) if camera access is denied/restricted.
    var onPermissionDenied: (() -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.foodscanner.scanner.sessionQueue")
    private let metadataOutput = AVCaptureMetadataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    /// Feeds the scan-success "shatter" snapshot (see `captureSnapshotForShatter`).
    /// A *separate* output from `photoOutput` deliberately: `AVCapturePhotoOutput`
    /// round-trips through its delegate in ~100-500ms, far too slow for an
    /// effect that has to appear the instant a barcode locks. Buffering the
    /// latest live frame here instead gives us that frame essentially for free.
    private let videoDataOutput = AVCaptureVideoDataOutput()
    /// Most recent frame from `videoDataOutput`, for the shatter snapshot.
    /// Written only on `sessionQueue` (the delegate's queue); read only on
    /// `sessionQueue` (see `captureSnapshotForShatter`) — never touched from
    /// any other thread, so there's no race on it.
    private var latestPixelBuffer: CVPixelBuffer?
    /// Reused across snapshot conversions — Apple recommends against
    /// creating a fresh `CIContext` per call (it's the expensive part).
    private let ciContext = CIContext()
    /// Whether `setUpSession` actually rotated the `videoDataOutput` connection
    /// to portrait. If the connection didn't support rotation (edge hardware),
    /// this stays false and the shatter snapshot is orientation-corrected in
    /// software instead of rendering sideways. Written/read only on
    /// `sessionQueue` (setUpSession + captureSnapshotForShatter).
    private var videoConnectionRotated = false

    /// The exact `AVCaptureDevice` behind the session's video input — the
    /// single source of truth for zoom/torch, and for the OCR still capture.
    /// Written only on `sessionQueue`; read only on `sessionQueue` (zoom/
    /// torch/capture) so there's never a cross-thread race on it.
    private var videoDevice: AVCaptureDevice?
    /// Guards against configuring the session twice (e.g. if `viewWillAppear`
    /// runs again before an async permission prompt resolves). Read/written
    /// only on `sessionQueue`.
    private var isConfigured = false
    /// The in-flight "Snap the label" photo capture, if any. Read/written
    /// only on `sessionQueue` — including from the `AVCapturePhotoCaptureDelegate`
    /// callback, which is hopped onto `sessionQueue` for exactly this reason
    /// (its delivery queue is otherwise unspecified/arbitrary per Apple's docs).
    private var photoCaptureContinuation: CheckedContinuation<UIImage, Error>?

    private static let zoomSteps: [CGFloat] = [1.0, 2.0, 3.0]
    /// Index into `zoomSteps` for the *next* tap — read/written only on
    /// `sessionQueue`.
    private var zoomIndex = 0

    private var previewView: CameraPreviewView { view as! CameraPreviewView }

    override func loadView() {
        view = CameraPreviewView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Wiring the session onto the preview layer is cheap/UI-only and can
        // happen immediately on main; the actual input/output configuration
        // below is dispatched off-main since it can briefly block on
        // hardware (Apple explicitly calls this out for session setup).
        previewView.videoPreviewLayer.videoGravity = .resizeAspectFill
        previewView.videoPreviewLayer.session = session
        sessionQueue.async { [weak self] in
            self?.configureSessionIfNeeded()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionQueue.async { [weak self] in
            self?.configureSessionIfNeeded()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    // MARK: - Session configuration (sessionQueue only)

    /// Idempotent: safe to call from both `viewDidLoad` and `viewWillAppear`
    /// without double-configuring. If permission is still undetermined the
    /// first call kicks off the system prompt and configuration finishes
    /// later, on `sessionQueue`, once the user responds.
    private func configureSessionIfNeeded() {
        guard !isConfigured else {
            if !session.isRunning { session.startRunning() }
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setUpSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                self.sessionQueue.async {
                    if granted {
                        self.setUpSession()
                    } else {
                        self.notifyPermissionDenied()
                    }
                }
            }
        case .denied, .restricted:
            notifyPermissionDenied()
        @unknown default:
            notifyPermissionDenied()
        }
    }

    /// Must only run on `sessionQueue`. Picks the best available back
    /// camera, wires it into the session alongside metadata + photo outputs,
    /// and starts the session running.
    private func setUpSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo // recommended preset when the session includes an AVCapturePhotoOutput

        guard let device = Self.bestBackVideoDevice() else {
            // ScanScreen already gates entry into this screen on
            // `CameraAvailability.current` finding a video device, so this
            // is a defensive no-op path in practice, not a real user-facing case.
            session.commitConfiguration()
            return
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            session.commitConfiguration()
            return
        }
        guard session.canAddInput(input) else { session.commitConfiguration(); return }
        session.addInput(input)
        videoDevice = device

        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: sessionQueue)
            // Read *after* addInput+addOutput so it reflects this device's
            // real support, then filter our desired retail set against it —
            // AVCaptureMetadataOutput throws (NSInvalidArgumentException) if
            // you assign a type outside `availableMetadataObjectTypes`, so
            // this filter isn't optional defensiveness, it's required safety.
            let desired: [AVMetadataObject.ObjectType] = [
                .ean13, .ean8, .upce, .code128, .code39, .code93, .itf14, .qr, .pdf417, .aztec
            ]
            let available = metadataOutput.availableMetadataObjectTypes
            metadataOutput.metadataObjectTypes = desired.filter { available.contains($0) }
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            videoDataOutput.setSampleBufferDelegate(self, queue: sessionQueue)
            // Raw sample buffers come off the sensor in its native (landscape)
            // orientation — unlike AVCaptureVideoPreviewLayer, this output has
            // no built-in "just display it right-side up" behavior, so this
            // screen being portrait-only, we rotate the connection itself.
            // (`videoOrientation` is soft-deprecated in iOS 17 in favor of
            // `videoRotationAngle`, but still fully functional; used here
            // deliberately since its `.portrait` case is unambiguous, vs.
            // guessing the replacement API's exact rotation-angle convention
            // untested.)
            if let connection = videoDataOutput.connection(with: .video), connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
                videoConnectionRotated = true
            }
        }

        isConfigured = true
        // Commit BEFORE starting — startRunning() must never be called between
        // beginConfiguration/commitConfiguration (that raises NSGenericException
        // and crashes the app). The old `defer commit` ran after this line.
        session.commitConfiguration()
        if !session.isRunning { session.startRunning() }
    }

    private func notifyPermissionDenied() {
        DispatchQueue.main.async { [weak self] in self?.onPermissionDenied?() }
    }

    /// Best available back camera, preferring a multi-lens *virtual* device
    /// (triple/dual/dual-wide) over the single wide lens. This is the part
    /// that makes zoom **real optical zoom** rather than a digital crop: a
    /// virtual multi-camera device seamlessly switches physical lenses as
    /// `videoZoomFactor` crosses each lens's switchover point, whereas
    /// driving `.builtInWideAngleCamera` alone can only ever crop/upscale
    /// the wide sensor. On hardware with just one rear lens (e.g. iPhone
    /// SE), this correctly falls back to `.builtInWideAngleCamera` and zoom
    /// there is honestly digital — there's no second lens to switch to.
    private static func bestBackVideoDevice() -> AVCaptureDevice? {
        let candidateTypes: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualCamera,
            .builtInDualWideCamera,
            .builtInWideAngleCamera
        ]
        for type in candidateTypes {
            if let device = AVCaptureDevice.default(type, for: .video, position: .back) {
                return device
            }
        }
        return nil
    }

    // MARK: - Zoom / torch (sessionQueue only; completions hop back to main)

    /// Cycles 1x -> 2x -> 3x -> 1x on `videoDevice`, clamped to what the
    /// device actually supports. `completion` always fires on main with the
    /// factor that was actually applied (post-clamp), so the UI label never
    /// claims a zoom level the hardware didn't honor.
    func cycleZoom(completion: @escaping (CGFloat) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice else {
                DispatchQueue.main.async { completion(1.0) }
                return
            }
            self.zoomIndex = (self.zoomIndex + 1) % Self.zoomSteps.count
            let requested = Self.zoomSteps[self.zoomIndex]
            let clamped = min(max(requested, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
            } catch {
                // Device busy/unavailable — report whatever the hardware is
                // actually at below; the button stays tappable to retry.
            }
            let applied = device.videoZoomFactor
            DispatchQueue.main.async { completion(applied) }
        }
    }

    /// Resets zoom to 1x — used when leaving Scan so the camera never stays
    /// zoomed in for the next visit.
    func resetZoom(completion: @escaping (CGFloat) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice else {
                DispatchQueue.main.async { completion(1.0) }
                return
            }
            self.zoomIndex = 0
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = 1.0
                device.unlockForConfiguration()
            } catch {
                // Leave hardware zoom as-is; report its actual current value below.
            }
            DispatchQueue.main.async { completion(device.videoZoomFactor) }
        }
    }

    /// Sets torch on/off on the same device; `completion` reports the
    /// resulting state on main.
    func setTorch(on: Bool, completion: @escaping (Bool) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice, device.hasTorch else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            do {
                try device.lockForConfiguration()
                device.torchMode = on ? .on : .off
                device.unlockForConfiguration()
            } catch {
                // Device busy/unavailable — report actual current state below.
            }
            DispatchQueue.main.async { completion(device.torchMode == .on) }
        }
    }

    // MARK: - Still capture (OCR "Snap the label")

    /// Captures one full-resolution still frame from the live session for
    /// `VisionOCR.recognizeText(in:)`. Bridges `AVCapturePhotoOutput`'s
    /// delegate-based API to async/await; only one capture may be in flight
    /// at a time.
    func capturePhoto() async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self, self.isConfigured, self.photoCaptureContinuation == nil else {
                    continuation.resume(throwing: VisionOCRError.scannerUnavailable)
                    return
                }
                self.photoCaptureContinuation = continuation
                self.photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }

    // MARK: - Scan-success "shatter" snapshot

    /// Converts the most recently buffered live frame into a `UIImage` for
    /// the shatter transition. Asynchronous but cheap (no camera round-trip —
    /// just converting a frame we're already holding); `completion` always
    /// fires on main. Never fails loudly: a `nil` image just means
    /// `ShatterOverlay` has nothing to shatter, so it silently no-ops (this
    /// is a visual flourish, never allowed to affect the lookup it rides
    /// alongside).
    func captureSnapshotForShatter(completion: @escaping (UIImage?) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self, let pixelBuffer = self.latestPixelBuffer else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            guard let cgImage = self.ciContext.createCGImage(ciImage, from: ciImage.extent) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            // Orientation-correct: if the connection never rotated the buffer
            // to portrait (edge hardware / non-portrait capture), the raw frame
            // is 90° off — stamp `.right` so the shard grid renders upright
            // instead of sideways (Chunk 6).
            let orientation = Self.shatterImageOrientation(connectionApplied: self.videoConnectionRotated)
            let image = UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
            DispatchQueue.main.async { completion(image) }
        }
    }

    /// Pure orientation logic for the shatter snapshot (Chunk 6, TDD). When the
    /// video connection already rotated the buffer to portrait the pixels are
    /// upright (`.up`); when it didn't (landscape-native sensor), the raw frame
    /// is rotated 90° and must be corrected to portrait with `.right`.
    static func shatterImageOrientation(connectionApplied portrait: Bool) -> UIImage.Orientation {
        portrait ? .up : .right
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    /// Fires on `sessionQueue` (the delegate queue set above) for every
    /// frame; just buffers the latest one for `captureSnapshotForShatter` to
    /// pick up on demand — no per-frame work beyond a reference store.
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                        from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        latestPixelBuffer = pixelBuffer
    }
}

// MARK: - AVCaptureMetadataOutputObjectsDelegate

extension CameraViewController: AVCaptureMetadataOutputObjectsDelegate {
    /// Fires on `sessionQueue` for every processed frame that contains at
    /// least one recognized metadata object.
    func metadataOutput(_ output: AVCaptureMetadataOutput,
                         didOutput metadataObjects: [AVMetadataObject],
                         from connection: AVCaptureConnection) {
        guard !metadataObjects.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            self?.fireBestBarcode(from: metadataObjects)
        }
    }

    /// Picks the recognized barcode closest to the reticle's center — same
    /// "closest wins" behavior the previous `DataScannerViewController`
    /// Coordinator had, adapted to `AVMetadataMachineReadableCodeObject` +
    /// `transformedMetadataObject(for:)` (which maps the metadata output's
    /// coordinate space into the preview layer's, i.e. view/screen points).
    /// Always called on main (see the delegate method above).
    private func fireBestBarcode(from metadataObjects: [AVMetadataObject]) {
        let previewLayer = previewView.videoPreviewLayer
        let center = CGPoint(x: previewLayer.bounds.midX, y: previewLayer.bounds.midY)
        var bestPayload: String?
        var bestDistanceSquared = CGFloat.greatestFiniteMagnitude

        for object in metadataObjects {
            guard let code = object as? AVMetadataMachineReadableCodeObject,
                  let payload = code.stringValue,
                  let transformed = previewLayer.transformedMetadataObject(for: code) else { continue }
            let bounds = transformed.bounds
            let itemCenter = CGPoint(x: bounds.midX, y: bounds.midY)
            let dx = itemCenter.x - center.x
            let dy = itemCenter.y - center.y
            let distanceSquared = dx * dx + dy * dy
            if distanceSquared < bestDistanceSquared {
                bestDistanceSquared = distanceSquared
                bestPayload = payload
            }
        }
        if let bestPayload {
            onBarcode?(bestPayload)
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                      didFinishProcessingPhoto photo: AVCapturePhoto,
                      error: Error?) {
        // Delivery queue for this callback is unspecified/arbitrary per
        // Apple's docs — hop onto sessionQueue before touching
        // `photoCaptureContinuation`, the same queue that writes it in
        // `capturePhoto()`, so there's never a cross-thread race on it.
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let continuation = self.photoCaptureContinuation
            self.photoCaptureContinuation = nil
            if let error {
                continuation?.resume(throwing: error)
            } else if let data = photo.fileDataRepresentation(), let image = UIImage(data: data) {
                continuation?.resume(returning: image)
            } else {
                continuation?.resume(throwing: VisionOCRError.invalidImage)
            }
        }
    }
}

/// Bridges SwiftUI (`ScanOverlay`'s zoom/torch buttons, `ScanScreen`'s "Snap
/// the label" flow) to the live `CameraViewController` so every one of those
/// actions operates on the *exact* `AVCaptureDevice`/session actually
/// producing the visible preview.
///
/// Supersedes `ScannerCaptureHandle` in `VisionOCR.swift`, which was written
/// against `DataScannerViewController.capturePhoto()` and has no caller now
/// that this feature owns a custom `AVCaptureSession` — left in place there
/// since file ownership for this change is `ScannerView.swift` +
/// `ScanOverlay.swift` only.
final class ScannerCaptureBridge {
    private weak var controller: CameraViewController?

    /// Whether the back camera reports a torch/flash unit — a read-only
    /// capability check, safe to query independently of exactly which back
    /// camera type (wide/dual/triple) ends up in use, since the torch is a
    /// single shared flash unit on the device.
    var hasTorch: Bool { AVCaptureDevice.default(for: .video)?.hasTorch ?? false }

    /// Called once by `ScannerView.makeUIViewController`.
    func attach(_ controller: CameraViewController) {
        self.controller = controller
    }

    /// Captures a still frame from the live session and runs on-device
    /// Vision text recognition on it (`VisionOCR.swift`) — same OCR fallback
    /// flow as before, just fed by our own `AVCapturePhotoOutput` instead of
    /// `DataScannerViewController.capturePhoto()`.
    @MainActor
    func captureLabelText() async throws -> String? {
        guard let controller else { throw VisionOCRError.scannerUnavailable }
        let image = try await controller.capturePhoto()
        return try await VisionOCR.recognizeText(in: image)
    }

    /// Cycles 1x -> 2x -> 3x on the live device; `completion` always fires on main.
    func cycleZoom(completion: @escaping (CGFloat) -> Void) {
        guard let controller else { completion(1.0); return }
        controller.cycleZoom(completion: completion)
    }

    /// Resets zoom to 1x; `completion` always fires on main.
    func resetZoom(completion: @escaping (CGFloat) -> Void) {
        guard let controller else { completion(1.0); return }
        controller.resetZoom(completion: completion)
    }

    /// Sets torch on/off; `completion` always fires on main.
    func setTorch(on: Bool, completion: @escaping (Bool) -> Void) {
        guard let controller else { completion(false); return }
        controller.setTorch(on: on, completion: completion)
    }

    /// Grabs the live preview's most recent frame for the scan-success
    /// "shatter" transition (`ShatterOverlay` in ScanOverlay.swift);
    /// `completion` always fires on main.
    func captureSnapshotForShatter(completion: @escaping (UIImage?) -> Void) {
        guard let controller else { completion(nil); return }
        controller.captureSnapshotForShatter(completion: completion)
    }
}

/// One "a barcode just locked" moment for `ShatterOverlay` to animate. Each
/// instance carries a fresh `id` (even if two events happen to share the
/// same/`nil` image) so SwiftUI's `.onChange(of:)` reliably fires every time
/// — `Equatable` is implemented over `id` alone since `UIImage` itself isn't
/// `Equatable`.
struct ScanShatterEvent: Equatable {
    let id = UUID()
    let image: UIImage?

    static func == (lhs: ScanShatterEvent, rhs: ScanShatterEvent) -> Bool { lhs.id == rhs.id }
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
    /// The most recent "barcode just locked" moment, for `ShatterOverlay`.
    /// See `ScanShatterEvent` — a fresh value every time, even back-to-back,
    /// so the animation reliably re-triggers.
    private(set) var shatterEvent: ScanShatterEvent?

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
    func handle(barcode: String, api: APIClient, pantryService: PantryService,
                captureHandle: ScannerCaptureBridge) async {
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
        // Fire-and-forget: grabbing + publishing the shatter snapshot is a
        // purely visual flourish (ScanOverlay's ShatterOverlay) and must
        // never gate or delay the actual lookup below.
        captureHandle.captureSnapshotForShatter { [weak self] image in
            self?.shatterEvent = ScanShatterEvent(image: image)
        }
        await lookUpProduct(barcode: barcode, api: api, pantryService: pantryService)
    }

    /// Core barcode → product network lookup, shared by `handle(barcode:)`
    /// (live scanning) and `analyzeGalleryPhoto` (a barcode found in a picked
    /// photo) so both go through the exact same backend call and
    /// error/needsOCR handling. Callers own the `isLookingUp` guard and the
    /// `.lookingUp` phase/haptic — this only does the request + result.
    @MainActor
    private func lookUpProduct(barcode: String, api: APIClient, pantryService: PantryService) async {
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
            phase = .error(Self.scanErrorMessage(for: error))
        } catch {
            blockedBarcode = barcode
            phase = .error(APIClient.APIError.badResponse.errorDescription!)
        }
    }

    /// OCR fallback (docs/BACKEND_SPEC.md §2 step 6): captures a still frame
    /// from the live scanner (VisionOCR.swift) and runs on-device Vision text
    /// recognition on it, then sends the recognized text through the same
    /// provisional-scoring endpoint a barcode lookup would use. Reuses
    /// `isLookingUp` so a capture and a barcode lookup can never race.
    @MainActor
    func captureLabel(handle: ScannerCaptureBridge, api: APIClient, pantryService: PantryService) async {
        guard !isLookingUp, !showProduct else { return }
        isLookingUp = true
        defer { isLookingUp = false }
        phase = .capturingLabel

        do {
            guard let text = try await handle.captureLabelText() else {
                phase = .labelNotFound
                return
            }
            await analyzeLabelText(text, api: api, pantryService: pantryService)
        } catch {
            // Capture/Vision-side failure (camera busy, no frame, no text
            // recognized) — calm "couldn't read that" recovery, since the
            // likely fix is lighting/positioning, not "something went wrong."
            phase = .labelNotFound
        }
    }

    /// Core OCR text → product network lookup, shared by `captureLabel(handle:)`
    /// (live "Snap the label") and `analyzeGalleryPhoto` (no barcode found in
    /// a picked photo, falls back to recognized text) — same backend call and
    /// error handling either way.
    @MainActor
    private func analyzeLabelText(_ text: String, api: APIClient, pantryService: PantryService) async {
        do {
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
            // A real network/backend failure — same calm, actionable
            // error banner a barcode lookup would show (offline-aware).
            phase = .error(Self.scanErrorMessage(for: error))
        } catch {
            phase = .error(APIClient.APIError.badResponse.errorDescription!)
        }
    }

    /// Gallery fallback (founder request — control cluster's "Choose a photo"):
    /// loads the picked image, tries Vision's barcode detector first (same
    /// symbologies as the live scanner in `ScannerView` above) and routes a
    /// hit through the exact same lookup as a live scan; if no barcode is
    /// found, falls back to `VNRecognizeTextRequest` and routes the result
    /// through the same OCR path as `captureLabel`. Never throws outward —
    /// every failure (bad data, no barcode, no text) degrades to the calm
    /// `.labelNotFound` banner ("Couldn't read that.").
    ///
    /// Reuses `isLookingUp` for the *entire* flow (load + Vision + network),
    /// not just the network part, so a live scan can't race a gallery pick —
    /// this deliberately calls the private `lookUpProduct`/`analyzeLabelText`
    /// helpers directly rather than the public `handle(barcode:)` /
    /// `captureLabel(handle:)`, which would immediately bail on their own
    /// `isLookingUp` guard.
    @MainActor
    func analyzeGalleryPhoto(_ item: PhotosPickerItem, api: APIClient, pantryService: PantryService) async {
        guard !isLookingUp, !showProduct else { return }
        isLookingUp = true
        defer { isLookingUp = false }
        // We don't yet know if this is a barcode photo or a label photo, so
        // "Reading the label…" is the closer-fitting of the two existing
        // loading captions for this in-between "loading + running Vision" moment.
        phase = .capturingLabel

        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data) else {
            phase = .labelNotFound
            return
        }

        let detectedBarcode = (try? await GalleryBarcodeDetector.detectPayload(in: uiImage)) ?? nil
        if let barcode = detectedBarcode {
            feedback.notificationOccurred(.success)
            phase = .lookingUp
            await lookUpProduct(barcode: barcode, api: api, pantryService: pantryService)
            return
        }

        let recognizedText = (try? await VisionOCR.recognizeText(in: uiImage)) ?? nil
        guard let text = recognizedText else {
            // Neither a barcode nor readable text in the photo — calm retry,
            // reusing the existing labelNotFound copy/state.
            phase = .labelNotFound
            return
        }
        await analyzeLabelText(text, api: api, pantryService: pantryService)
    }

    /// Re-arms scanning — called on Retry/"Try another scan", and when the
    /// user navigates back from a product (see ScanScreen).
    func reset() {
        phase = .scanning
        product = nil
        blockedBarcode = nil
        shatterEvent = nil
        feedback.prepare()
    }

    /// Calm, honest copy for a failed scan lookup (Chunk 6). Offline gets the
    /// scan-specific COPY_DECK §Offline & limits line (pantry still works),
    /// never the generic Network copy; every other backend/parse failure gets
    /// the drafted "Server hiccup" line — never the banned "Something went
    /// wrong."
    static func scanErrorMessage(for error: APIClient.APIError) -> String {
        if error == .offline {
            return "You're offline. Scanning needs a connection — your pantry still works."
        }
        return error.errorDescription ?? APIClient.APIError.badResponse.errorDescription!
    }
}

/// Vision's barcode detector run once against a still image from the photo
/// library (gallery fallback), using the same symbology list as the live
/// scanner above so a picked photo can be routed through the exact same
/// barcode lookup path as a live scan. Deliberately separate from
/// VisionOCR.swift's text-recognition helper (different Vision request
/// type; kept here since this feature's file ownership is ScanOverlay.swift +
/// ScannerView.swift only).
private enum GalleryBarcodeDetector {
    static func detectPayload(in image: UIImage) async throws -> String? {
        guard let cgImage = image.cgImage else { return nil }
        let orientation = CGImagePropertyOrientation(galleryImageOrientation: image.imageOrientation)

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNDetectBarcodesRequest()
                request.symbologies = [
                    .ean13, .ean8, .upce, .code128, .code39, .code93, .itf14, .qr
                ]
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
                do {
                    try handler.perform([request])
                    // A picked photo should contain one product barcode
                    // (unlike the multi-item live-scan case) — first hit wins.
                    let payload = (request.results ?? []).compactMap { $0.payloadStringValue }.first
                    continuation.resume(returning: payload)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

/// Local copy of the standard `UIImage.Orientation` → `CGImagePropertyOrientation`
/// mapping (VisionOCR.swift has its own file-private version of this same
/// mapping) — duplicated here rather than shared since this feature's file
/// ownership is ScanOverlay.swift + ScannerView.swift only.
private extension CGImagePropertyOrientation {
    init(galleryImageOrientation orientation: UIImage.Orientation) {
        switch orientation {
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

/// Camera hardware/permission state, checked independently of the live scan
/// so we can show the right calm state (docs/DESIGN_SYSTEM.md §5.9) instead of
/// a blank camera view.
private enum CameraAvailability: Equatable {
    case ready              // supported, and not explicitly denied — CameraViewController
                             // requests permission itself if it's still undetermined.
    case unsupportedDevice  // no camera / unsupported hardware (e.g. Simulator).
    case permissionDenied   // user previously said no — only Settings can fix this.

    @MainActor
    static var current: CameraAvailability {
        guard AVCaptureDevice.default(for: .video) != nil else { return .unsupportedDevice }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .denied || status == .restricted { return .permissionDenied }
        // .notDetermined or .authorized — CameraViewController prompts for
        // permission itself the first time it configures the session.
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
    // Handed to ScannerView so it can attach the live CameraViewController;
    // ScanScreen/ScanOverlay use it to drive zoom/torch and to trigger an
    // on-demand OCR capture (VisionOCR.swift).
    @State private var captureHandle = ScannerCaptureBridge()
    // Seeded optimistically; resolved on appear (the check is MainActor-isolated,
    // and @State default values are evaluated outside the main actor).
    @State private var availability = CameraAvailability.ready
    /// Presents the Search screen (barcode mode) as a sheet — the last
    /// dead-end escape when a label is broken/absent (SCREEN_SPECS §Home item
    /// 2). A sheet, not a push, keeps the immersive dark scan chrome intact
    /// underneath.
    @State private var showManualEntry = false

    var body: some View {
        content
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { availability = .current }
            .sheet(isPresented: $showManualEntry) {
                NavigationStack {
                    SearchView(startInBarcodeMode: true)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { showManualEntry = false }
                            }
                        }
                }
            }
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
            unavailableView(
                systemImage: "camera",
                title: "Camera unavailable",
                description: "Scanning needs a device camera. Run on a real iPhone."
            )
        case .permissionDenied:
            permissionDeniedView
        }
    }

    /// Calm, light-canvas styling for the two "can't show the camera" states
    /// (DESIGN_SYSTEM_V3 §1: dark is a moment, not the mode — these aren't the
    /// immersive scan moment, so they read as a normal light-first screen,
    /// not the dark camera treatment).
    private func unavailableView(systemImage: String, title: String, description: String) -> some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(description))
            .tint(Theme.greenDeep)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas)
    }

    private var scannerBody: some View {
        ZStack {
            ScannerView(captureHandle: captureHandle, onBarcode: { code in
                Task {
                    await vm.handle(barcode: code, api: APIClient(session: session), pantryService: pantryService,
                                     captureHandle: captureHandle)
                }
            }, onPermissionDenied: {
                availability = .permissionDenied
            })
            .ignoresSafeArea()

            ScanOverlay(phase: vm.phase, captureHandle: captureHandle, shatterEvent: vm.shatterEvent) { item in
                Task {
                    await vm.analyzeGalleryPhoto(item, api: APIClient(session: session), pantryService: pantryService)
                }
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
                secondaryAction: { vm.reset() },
                manualEntryAction: { showManualEntry = true }
            )
        case .labelNotFound:
            ocrBanner(
                title: "Couldn't read that.",
                message: "Try again in better light.",
                hint: nil,
                primaryTitle: "Try again",
                primaryAction: { Task { await captureLabel() } },
                secondaryTitle: "Try another scan",
                secondaryAction: { vm.reset() },
                manualEntryAction: { showManualEntry = true }
            )
        case .error(let message):
            calmBanner(
                title: "That didn't load right.",
                message: message,
                actionTitle: "Retry",
                action: { vm.reset() },
                manualEntryAction: { showManualEntry = true }
            )
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

    // MARK: - Banner button styles (v3 card language on the dark surface)

    /// Filled lime pill, ink label — the primary action in a banner. Full
    /// pill (`Radius.full` via `Capsule`), 44pt tall per DESIGN_SYSTEM_V3 §5.1/§7.
    private func primaryPillButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(Theme.ink)
                .frame(minHeight: 44)
                .padding(.horizontal, Theme.Space.s4)
        }
        .background(Theme.lime, in: Capsule())
    }

    /// Quiet lime-label text action — the secondary/way-out option beside a
    /// primary pill (e.g. "Try another scan").
    private func secondaryPillButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(Theme.lime)
                .frame(minHeight: 44)
                .padding(.horizontal, Theme.Space.s2)
        }
    }

    /// Quiet lime text button for the "Enter barcode manually" way-out —
    /// tertiary, below the primary/secondary group, so a broken/absent label
    /// still always has a way to type the barcode (never a dead end).
    private func manualEntryButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Enter barcode manually")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.lime)
                .frame(minHeight: 44)
                .padding(.horizontal, Theme.Space.s2)
        }
    }

    private func calmBanner(title: String, message: String, actionTitle: String,
                             action: @escaping () -> Void,
                             manualEntryAction: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s3) {
            VStack(alignment: .leading, spacing: Theme.Space.s2) {
                Text(title).font(.headline).foregroundStyle(Theme.onGreen)
                Text(message).font(.subheadline).foregroundStyle(Theme.onGreen.opacity(0.85))
            }
            primaryPillButton(actionTitle, action: action)
            if let manualEntryAction {
                manualEntryButton(manualEntryAction)
            }
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
                            secondaryTitle: String, secondaryAction: @escaping () -> Void,
                            manualEntryAction: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s3) {
            VStack(alignment: .leading, spacing: Theme.Space.s2) {
                Text(title).font(.headline).foregroundStyle(Theme.onGreen)
                Text(message).font(.subheadline).foregroundStyle(Theme.onGreen.opacity(0.85))
                if let hint {
                    Text(hint).font(.footnote).foregroundStyle(Theme.onGreen.opacity(0.7))
                }
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Theme.Space.s3) {
                    primaryPillButton(primaryTitle, action: primaryAction)
                    secondaryPillButton(secondaryTitle, action: secondaryAction)
                }
            } else {
                HStack(spacing: Theme.Space.s3) {
                    primaryPillButton(primaryTitle, action: primaryAction)
                    secondaryPillButton(secondaryTitle, action: secondaryAction)
                }
            }
            if let manualEntryAction {
                manualEntryButton(manualEntryAction)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.s4)
        .background(Theme.forest.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .padding(Theme.Space.s4)
    }

    /// Calm light-canvas permission explainer (DESIGN_SYSTEM_V3 §1 — not the
    /// dark camera moment) with a full-pill "Open Settings" CTA.
    private var permissionDeniedView: some View {
        ContentUnavailableView {
            Label("Camera's off", systemImage: "camera.fill")
        } description: {
            Text("Turn it on in Settings to scan.")
        } actions: {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Settings")
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.onGreen)
                    .frame(minHeight: 44)
                    .padding(.horizontal, Theme.Space.s5)
            }
            .background(Theme.greenDeep, in: Capsule())
            .accessibilityHint("Opens the Settings app so you can allow camera access.")
        }
        .tint(Theme.greenDeep)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
    }
}
