import AVFoundation
import SwiftUI

/// Aim guidance drawn above the live `DataScannerViewController` feed
/// (docs/DESIGN_SYSTEM_V3.md §5.9 — "the dark brand moment"): a centered,
/// brand-green corner-bracket reticle that locks solid the instant a barcode
/// is caught, a dimmed surround so users know where to point the camera, a
/// top instruction pill, and a torch toggle for low light. Lime is used only
/// as the small "spark" accent on this dark surface (the sweep line) — the
/// reticle itself and the lock state both stay brand green, per spec.
///
/// Purely visual/feedback — the scanner underneath keeps running through
/// every phase, so a re-aim after an error or "not found" always works.
struct ScanOverlay: View {
    let phase: ScanViewModel.Phase

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweepOffset: CGFloat = 0
    @State private var torchOn = false

    private let reticleSize: CGFloat = 240
    private let hasTorch = AVCaptureDevice.default(for: .video)?.hasTorch ?? false

    private var isLocked: Bool { phase == .lookingUp }
    // The lookingUp/error/needsOCR states already surface their own text via
    // ScanScreen's bottom banner — only show this line for plain idle
    // scanning so we never stack two messages.
    private var showsInstruction: Bool { phase == .scanning }

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

                VStack(spacing: 0) {
                    topBar
                        // GeometryProxy.safeAreaInsets still reports the
                        // nav-bar/status-bar inset here even though this view
                        // (and its ScannerView sibling) ignore safe area to
                        // bleed the dark camera full-screen — that's what lets
                        // the pill sit cleanly below the nav bar instead of
                        // guessing a fixed offset.
                        .padding(.top, proxy.safeAreaInsets.top + Theme.Space.s3)
                        .padding(.horizontal, Theme.Space.s4)
                    Spacer(minLength: 0)
                }
            }
        }
        .onAppear { startSweepIfNeeded() }
        .onDisappear { if torchOn { toggleTorch() } }   // never leave the flashlight on after leaving Scan
    }

    // MARK: - Top bar (instruction pill + torch)

    /// Balances the instruction pill so it reads visually centered whether or
    /// not the torch button is present, matching the reference's
    /// pill-top-center / control-top-corner layout (reference/moodboards
    /// "Ingrex" dark scan screen).
    private var topBar: some View {
        HStack(spacing: Theme.Space.s3) {
            Color.clear.frame(width: hasTorch ? 44 : 0)
            Spacer(minLength: 0)
            if showsInstruction {
                instructionLabel
            }
            Spacer(minLength: 0)
            if hasTorch {
                torchButton
            }
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

    // MARK: - Torch

    private var torchButton: some View {
        Button(action: toggleTorch) {
            Image(systemName: torchOn ? "bolt.fill" : "bolt.slash.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(torchOn ? Theme.ink : Theme.onGreen)
                .frame(minWidth: 44, minHeight: 44)
                .background(torchOn ? Theme.lime : Theme.ink.opacity(0.55), in: Circle())
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
