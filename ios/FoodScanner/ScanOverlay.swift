import AVFoundation
import SwiftUI

/// Aim guidance drawn above the live `DataScannerViewController` feed
/// (docs/DESIGN_SYSTEM.md §5.9 states, §7 motion, §10.4 scan-bracket motif):
/// a centered reticle that locks solid brand-green the instant a barcode is
/// caught, a dimmed surround so users know where to point the camera, a
/// short instruction line, and a torch toggle for low light.
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

                if showsInstruction {
                    instructionLabel
                        .position(x: center.x, y: center.y + reticleSize / 2 + Theme.Space.s6)
                }

                if hasTorch {
                    VStack {
                        HStack {
                            Spacer()
                            torchButton
                        }
                        Spacer()
                    }
                    .padding(Theme.Space.s4)
                }
            }
        }
        .onAppear { startSweepIfNeeded() }
        .onDisappear { if torchOn { toggleTorch() } }   // never leave the flashlight on after leaving Scan
    }

    // MARK: - Dimmed surround

    /// Full-screen scrim with a rounded-rect "hole" over the reticle, via an
    /// even-odd fill, so only the area outside the aim frame is dimmed.
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
        .fill(Color.black.opacity(0.35), style: FillStyle(eoFill: true))
        .allowsHitTesting(false)
    }

    // MARK: - Reticle

    private var reticle: some View {
        ZStack {
            ReticleCorners()
                .stroke(reticleColor, style: StrokeStyle(lineWidth: isLocked ? 5 : 3.5, lineCap: .round, lineJoin: .round))
            if !reduceMotion && !isLocked {
                sweepLine
                    .frame(width: reticleSize - 24, height: 2)
                    .offset(y: sweepOffset)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isLocked)
        .allowsHitTesting(false)
    }

    private var reticleColor: Color {
        isLocked ? Theme.green : Theme.onGreen.opacity(0.9)
    }

    private var sweepLine: some View {
        LinearGradient(
            colors: [Theme.green.opacity(0), Theme.green.opacity(0.9), Theme.green.opacity(0)],
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
            .font(.subheadline)
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
                .background(torchOn ? Theme.lime : Color.black.opacity(0.35), in: Circle())
        }
        .accessibilityLabel(torchOn ? "Turn off flashlight" : "Turn on flashlight")
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
