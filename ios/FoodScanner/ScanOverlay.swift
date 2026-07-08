import AVFoundation
import PhotosUI
import SwiftUI

/// Aim guidance drawn above the live `DataScannerViewController` feed
/// (docs/DESIGN_SYSTEM_V3.md §5.9 — "the dark brand moment"): a centered,
/// brand-green corner-bracket reticle that locks solid the instant a barcode
/// is caught, a dimmed surround so users know where to point the camera, a
/// top instruction pill, and a trailing-edge control cluster (zoom / gallery /
/// torch — see `controlCluster` below) for low light and photo-library scans.
/// Lime is used only as the small "spark" accent on this dark surface (the
/// sweep line) — the reticle itself and the lock state both stay brand green,
/// per spec.
///
/// Purely visual/feedback — the scanner underneath keeps running through
/// every phase, so a re-aim after an error or "not found" always works.
struct ScanOverlay: View {
    let phase: ScanViewModel.Phase
    /// Fired the instant the user picks a photo from `PhotosPicker` — the
    /// caller (`ScanScreen`) owns everything past that point (loading the
    /// image, running Vision, hitting the backend) via `ScanViewModel`.
    let onPhotoPicked: (PhotosPickerItem) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweepOffset: CGFloat = 0
    @State private var torchOn = false
    @State private var isZoomedIn = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    private let reticleSize: CGFloat = 240
    private let hasTorch = AVCaptureDevice.default(for: .video)?.hasTorch ?? false

    private var isLocked: Bool { phase == .lookingUp }
    // The lookingUp/error/needsOCR states already surface their own text via
    // ScanScreen's bottom banner — only show the instruction pill and the
    // control cluster for plain idle scanning, so we never stack the cluster
    // (or a second message) on top of a banner.
    private var showsInstruction: Bool { phase == .scanning }
    private var showsControlCluster: Bool { phase == .scanning }

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)

            ZStack {
                dimmedSurround(fullSize: proxy.size, holeCenter: center)
                    .accessibilityHidden(true)

                reticle
                    .frame(width: reticleSize, height: reticleSize)
                    .position(center)
                    .accessibilityHidden(true)

                // Instruction pill sits just BELOW the reticle (not at the top,
                // where it collided with the nav bar). Positioned relative to
                // the reticle so it tracks the frame on every device.
                if showsControlCluster {
                    instructionLabel
                        .position(x: center.x,
                                  y: center.y + reticleSize / 2 + Theme.Space.s6)
                        .accessibilityAddTraits(.isStaticText)
                }

                if showsControlCluster {
                    controlCluster
                        // Same safe-area-aware trick as topBar above, but for
                        // the trailing edge — pins ~16pt clear of the edge on
                        // every device instead of guessing a fixed inset.
                        .padding(.trailing, proxy.safeAreaInsets.trailing + Theme.Space.s4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                }
            }
        }
        .onAppear { startSweepIfNeeded() }
        .onDisappear {
            if torchOn { toggleTorch() }   // never leave the flashlight on after leaving Scan
            if isZoomedIn { toggleZoom() } // ...or the camera zoomed in
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            selectedPhotoItem = nil // re-arm so picking the same photo again still fires a change
            onPhotoPicked(newItem)
        }
    }

    // MARK: - Top bar (instruction pill)

    private var topBar: some View {
        HStack(spacing: Theme.Space.s3) {
            Spacer(minLength: 0)
            if showsInstruction {
                instructionLabel
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Dimmed surround

    /// Full-screen scrim with a rounded-rect "hole" over the reticle, via an
    /// even-odd fill, so only the area outside the aim frame is dimmed.
    /// Tinted from `Theme.ink` (the brand's near-black green) rather than raw
    /// black — tokens only, per DESIGN_SYSTEM_V3 §7.
    private func dimmedSurround(fullSize: CGSize, holeCenter: CGPoint) -> some View {
        let hole = CGRect(
            x: holeCenter.x - reticleSize / 2,
            y: holeCenter.y - reticleSize / 2,
            width: reticleSize,
            height: reticleSize
        )
        return Path { path in
            path.addRect(CGRect(origin: .zero, size: fullSize))
            path.addRoundedRect(in: hole, cornerSize: CGSize(width: Theme.Radius.lg, height: Theme.Radius.lg))
        }
        .fill(Theme.ink.opacity(0.45), style: FillStyle(eoFill: true))
        .allowsHitTesting(false)
    }

    // MARK: - Reticle

    private var reticle: some View {
        ZStack {
            ReticleCorners()
                .stroke(Theme.green, style: StrokeStyle(lineWidth: isLocked ? 6 : 3.5, lineCap: .round, lineJoin: .round))
                .shadow(color: isLocked ? Theme.green.opacity(0.55) : .clear, radius: isLocked ? 14 : 0)
            if !reduceMotion && !isLocked {
                sweepLine
                    .frame(width: reticleSize - 24, height: 2)
                    .offset(y: sweepOffset)
            }
        }
        .scaleEffect(isLocked ? 1.05 : 1.0)
        .animation(Motion.respecting(Motion.quick, reduceMotion), value: isLocked)
        .allowsHitTesting(false)
    }

    /// The calm sweep is the one "spark" moment lime is allowed on this dark
    /// surface (DESIGN_SYSTEM_V3 §5.9) — the reticle itself stays brand green
    /// at rest and locks brighter/thicker/glowing green on capture.
    private var sweepLine: some View {
        LinearGradient(
            colors: [Theme.lime.opacity(0), Theme.lime.opacity(0.9), Theme.lime.opacity(0)],
            startPoint: .leading, endPoint: .trailing
        )
    }

    private func startSweepIfNeeded() {
        guard !reduceMotion else { return }
        sweepOffset = -(reticleSize / 2 - 12)
        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
            sweepOffset = reticleSize / 2 - 12
        }
    }

    // MARK: - Instruction

    private var instructionLabel: some View {
        Text("Point your camera at a barcode.")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.onGreen)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Theme.Space.s4)
            .padding(.vertical, Theme.Space.s3)
            .background(Theme.forest.opacity(0.85), in: Capsule())
    }

    // MARK: - Control cluster (founder request: vertical pill, trailing edge,
    // vertically centered — zoom / gallery / torch, top to bottom)

    /// A dark, vertically-stacked pill of three 44×44pt controls, matching
    /// the iOS Camera app's trailing-edge control convention. Torch only
    /// appears when the device actually has one (`hasTorch`); zoom and
    /// gallery are always available.
    private var controlCluster: some View {
        VStack(spacing: 0) {
            zoomButton
            clusterDivider
            galleryButton
            if hasTorch {
                clusterDivider
                torchButton
            }
        }
        .padding(.vertical, Theme.Space.s2)
        .frame(width: 44)
        .background(Theme.ink.opacity(0.6), in: Capsule())
    }

    private var clusterDivider: some View {
        Rectangle()
            .fill(Theme.onGreen.opacity(0.2))
            .frame(width: 24, height: 1)
    }

    /// "1×" / "2×" toggle — see `toggleZoom()` for the device-level
    /// `videoZoomFactor` trick (same pattern as `toggleTorch()` below).
    private var zoomButton: some View {
        Button(action: toggleZoom) {
            Text(isZoomedIn ? "2×" : "1×")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.onGreen)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Zoom, currently \(isZoomedIn ? "2x" : "1x")")
        .accessibilityHint("Double tap to switch to \(isZoomedIn ? "1x" : "2x") zoom.")
    }

    /// Presents the system photo picker; the actual scan (barcode-first,
    /// OCR-fallback) happens in `ScanViewModel.analyzeGalleryPhoto`, wired up
    /// by `ScanScreen` via `onPhotoPicked`.
    private var galleryButton: some View {
        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            Image(systemName: "photo.on.rectangle")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.onGreen)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Choose a photo")
        .accessibilityHint("Scans a barcode or ingredients label from a photo in your library.")
    }

    private var torchButton: some View {
        Button(action: toggleTorch) {
            Image(systemName: torchOn ? "bolt.fill" : "bolt.slash.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(torchOn ? Theme.lime : Theme.onGreen)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(torchOn ? "Turn off flashlight" : "Turn on flashlight")
        .accessibilityHint("Toggles the camera flashlight for low light.")
    }

    private func toggleTorch() {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = device.torchMode == .on ? .off : .on
            torchOn = device.torchMode == .on
            device.unlockForConfiguration()
        } catch {
            // Device busy/unavailable — leave state as-is; button stays tappable to retry.
        }
    }

    /// Same device-level trick as `toggleTorch()` — `DataScannerViewController`
    /// owns the capture session, but `videoZoomFactor` is a property of the
    /// underlying `AVCaptureDevice`, which we can still reach directly.
    /// Clamps to `maxAvailableVideoZoomFactor` and degrades gracefully (label
    /// stays "1×") if the device can't zoom or the config lock fails.
    private func toggleZoom() {
        guard let device = AVCaptureDevice.default(for: .video) else { return }

        if isZoomedIn {
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = 1.0
                device.unlockForConfiguration()
                isZoomedIn = false
            } catch {
                // Leave state as-is; button stays tappable to retry.
            }
            return
        }

        let target = min(2.0, device.maxAvailableVideoZoomFactor)
        guard target > 1.0 else { return } // device can't zoom past 1x — stay at 1x
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = target
            device.unlockForConfiguration()
            isZoomedIn = true
        } catch {
            // Leave state as-is; label stays "1×".
        }
    }
}

/// Scan-bracket corners (docs/DESIGN_SYSTEM.md §10.4 motif) — four L-shaped
/// marks rather than a full rounded-rect border, echoing the brand's
/// "scan brackets" iconography instead of a generic camera frame.
private struct ReticleCorners: Shape {
    var cornerLength: CGFloat = 28

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Top-left
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + cornerLength))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.minY))
        // Top-right
        path.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cornerLength))
        // Bottom-right
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerLength))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - cornerLength, y: rect.maxY))
        // Bottom-left
        path.move(to: CGPoint(x: rect.minX + cornerLength, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cornerLength))
        return path
    }
}
