import PhotosUI
import SwiftUI
import UIKit

/// Aim guidance drawn above the live camera feed (`ScannerView`'s
/// `CameraViewController`) — docs/DESIGN_SYSTEM_V3.md §5.9 ("the dark brand
/// moment"): a centered, brand-green corner-bracket reticle that locks solid
/// the instant a barcode is caught, a dimmed surround so users know where to
/// point the camera, a top instruction pill, a trailing-edge control cluster
/// (zoom / gallery / torch — see `controlCluster` below), and the scan-success
/// "shatter" flourish (see `ShatterOverlay`).
///
/// Zoom and torch are driven through `captureHandle` (`ScannerCaptureBridge`)
/// rather than grabbing an independent `AVCaptureDevice` — that's the fix for
/// "zoom doesn't work": the old code queried an unrelated default video
/// device that had nothing to do with whatever session was actually feeding
/// the screen. Going through the bridge guarantees we're driving the *same*
/// device/session as `ScannerView`'s live preview.
///
/// Lime is used only as the small "spark" accent on this dark surface (the
/// sweep line, the shatter flash) — the reticle itself and the lock state
/// both stay brand green, per spec.
///
/// Purely visual/feedback — the scanner underneath keeps running through
/// every phase, so a re-aim after an error or "not found" always works.
struct ScanOverlay: View {
    let phase: ScanViewModel.Phase
    /// Bridges to the live `CameraViewController` for zoom/torch — see the
    /// type header above.
    let captureHandle: ScannerCaptureBridge
    /// A fresh value each time a barcode locks; drives `ShatterOverlay`.
    let shatterEvent: ScanShatterEvent?
    /// Fired the instant the user picks a photo from `PhotosPicker` — the
    /// caller (`ScanScreen`) owns everything past that point (loading the
    /// image, running Vision, hitting the backend) via `ScanViewModel`.
    let onPhotoPicked: (PhotosPickerItem) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweepOffset: CGFloat = 0
    @State private var torchOn = false
    /// The zoom factor currently *applied* to the live device (post-clamp) —
    /// not just "did the user tap zoom," so the button label never claims a
    /// level the hardware didn't actually honor. Cycles 1x -> 2x -> 3x -> 1x.
    @State private var zoomFactor: CGFloat = 1.0
    @State private var selectedPhotoItem: PhotosPickerItem?

    private let reticleSize: CGFloat = 240

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

                // On top of everything else in this overlay — the "whole
                // screen freezes and breaks apart" moment reads correctly
                // only above the reticle/dimming/instruction chrome.
                ShatterOverlay(event: shatterEvent)
            }
        }
        .onAppear { startSweepIfNeeded() }
        .onDisappear {
            // Never leave the flashlight on, or the camera zoomed in, after
            // leaving Scan.
            if torchOn { captureHandle.setTorch(on: false) { torchOn = $0 } }
            if zoomFactor != 1.0 { captureHandle.resetZoom { zoomFactor = $0 } }
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
    /// appears when the device actually has one (`captureHandle.hasTorch`);
    /// zoom and gallery are always available.
    private var controlCluster: some View {
        VStack(spacing: 0) {
            zoomButton
            clusterDivider
            galleryButton
            if captureHandle.hasTorch {
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

    /// "1×" / "2×" / "3×" cycle — see `CameraViewController.cycleZoom` for
    /// the real-optical-zoom device-level implementation (same completion-
    /// handler pattern as `toggleTorch()` below, since the actual device
    /// mutation now happens on the capture session's background queue).
    private var zoomButton: some View {
        Button(action: cycleZoom) {
            Text(zoomLabel(zoomFactor))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.onGreen)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Zoom, currently \(zoomLabel(zoomFactor))")
        .accessibilityHint("Double tap to cycle to the next zoom level.")
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
        captureHandle.setTorch(on: !torchOn) { isOn in
            torchOn = isOn
        }
    }

    private func cycleZoom() {
        captureHandle.cycleZoom { factor in
            zoomFactor = factor
        }
    }

    /// Compact "1×"/"2×"/"3×" label for a whole-number factor, or "2.5×"-style
    /// one decimal place for whatever a device's `maxAvailableVideoZoomFactor`
    /// clamp lands on (e.g. a device whose optical range tops out below 3x).
    private func zoomLabel(_ factor: CGFloat) -> String {
        if factor.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(factor))×"
        }
        return String(format: "%.1f×", factor)
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

/// One grid piece of a `ShatterOverlay` snapshot — see `ShatterOverlay.makeShards`.
private struct Shard: Identifiable {
    let id: Int
    let image: UIImage
    /// This shard's center within the full snapshot, normalized 0...1 —
    /// multiplied by the overlay's actual on-screen size to place it.
    let unitCenter: CGPoint
    /// This shard's size within the full snapshot, normalized 0...1.
    let unitSize: CGSize
    /// A small per-shard rotation (degrees), applied in full at `progress ==
    /// 1`, purely for visual variety so pieces don't fly dead-straight and
    /// identically outward.
    let rotation: Double
}

/// Scan-success "shatter" transition: the instant a barcode locks,
/// `ScanViewModel` hands us a frozen snapshot of the live preview (see
/// `CameraViewController.captureSnapshotForShatter`); this view slices it
/// into a grid and animates the pieces flying outward + fading, revealing the
/// live feed underneath again as the lookup proceeds — a brief (~0.45s)
/// ease-out flourish riding alongside the existing success haptic + green
/// reticle lock, never gating them or the lookup itself (`ScanViewModel`
/// fires the snapshot capture fire-and-forget).
///
/// **Reduce Motion:** no flying shards at all — a single quick, calm
/// lime flash stands in, matching this brand's one "spark" accent.
private struct ShatterOverlay: View {
    /// A new (non-`nil`, non-equal) value fires the animation.
    let event: ScanShatterEvent?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shards: [Shard] = []
    @State private var progress: CGFloat = 0
    @State private var flashOpacity: Double = 0
    @State private var isPlaying = false

    private static let columns = 5
    private static let rows = 8
    private static let duration = 0.45
    /// How far a shard at the very edge of the frame travels outward, in
    /// points, at `progress == 1`. Shards nearer the center travel
    /// proportionally less (see `offset(for:)`), which is what reads as an
    /// "explosion from the middle" rather than a uniform slide.
    private static let maxOutwardDistance: CGFloat = 140

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if reduceMotion {
                    Rectangle()
                        .fill(Theme.lime)
                        .opacity(flashOpacity)
                        .allowsHitTesting(false)
                } else {
                    ForEach(shards) { shard in
                        let offset = offset(for: shard)
                        Image(uiImage: shard.image)
                            .resizable()
                            .frame(
                                width: shard.unitSize.width * proxy.size.width,
                                height: shard.unitSize.height * proxy.size.height
                            )
                            .position(
                                x: shard.unitCenter.x * proxy.size.width + offset.dx,
                                y: shard.unitCenter.y * proxy.size.height + offset.dy
                            )
                            .rotationEffect(.degrees(shard.rotation * progress))
                            .opacity(1 - progress)
                    }
                }
            }
            .allowsHitTesting(false)
            .onChange(of: event) { _, newEvent in
                guard let newEvent else { return }
                play(with: newEvent)
            }
        }
    }

    /// Outward displacement for one shard at the current `progress`, scaled
    /// by how far this shard's center already sits from the frame's own
    /// center (0 at dead-center, up to `maxOutwardDistance` at the edges).
    private func offset(for shard: Shard) -> (dx: CGFloat, dy: CGFloat) {
        let dx = shard.unitCenter.x - 0.5
        let dy = shard.unitCenter.y - 0.5
        return (dx * 2 * Self.maxOutwardDistance * progress, dy * 2 * Self.maxOutwardDistance * progress)
    }

    private func play(with event: ScanShatterEvent) {
        if reduceMotion {
            flashOpacity = 0.35
            withAnimation(.easeOut(duration: 0.2)) { flashOpacity = 0 }
            return
        }
        guard let image = event.image, !isPlaying else { return }
        isPlaying = true
        shards = Self.makeShards(from: image, columns: Self.columns, rows: Self.rows)
        progress = 0
        // A dedicated ease-out, no-bounce duration for this specific
        // flourish (Motion.swift's presets top out at 0.28s) — kept local
        // since only ScanOverlay.swift is in scope for this feature; the
        // easing/no-bounce character still matches DesignKit's Motion
        // language in spirit.
        withAnimation(.easeOut(duration: Self.duration)) {
            progress = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration) {
            shards = []
            progress = 0
            isPlaying = false
        }
    }

    /// Slices `image` into a `columns` x `rows` grid of independent `UIImage`
    /// pieces (each with its own normalized center/size so they can be laid
    /// out and animated independently regardless of the overlay's actual
    /// on-screen size).
    private static func makeShards(from image: UIImage, columns: Int, rows: Int) -> [Shard] {
        guard let cgImage = image.cgImage else { return [] }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        guard width > 0, height > 0 else { return [] }
        let tileWidth = width / CGFloat(columns)
        let tileHeight = height / CGFloat(rows)

        var shards: [Shard] = []
        var id = 0
        for row in 0..<rows {
            for col in 0..<columns {
                let rect = CGRect(x: CGFloat(col) * tileWidth, y: CGFloat(row) * tileHeight,
                                   width: tileWidth, height: tileHeight)
                guard let cropped = cgImage.cropping(to: rect) else { continue }
                let unitCenter = CGPoint(x: rect.midX / width, y: rect.midY / height)
                let unitSize = CGSize(width: tileWidth / width, height: tileHeight / height)
                // Deterministic per-shard rotation from grid position rather
                // than true randomness, so behavior is stable/reproducible:
                // spans roughly -24...+24 degrees.
                let rotation = (Double((row * columns + col) % 7) - 3.0) * 8.0
                shards.append(Shard(id: id, image: UIImage(cgImage: cropped), unitCenter: unitCenter,
                                     unitSize: unitSize, rotation: rotation))
                id += 1
            }
        }
        return shards
    }
}
