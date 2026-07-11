import SwiftUI

/// Branded cold-launch splash. The shield-check mark springs in, the wordmark
/// fades up, then `FoodScannerApp` cross-fades to the app. Calm + brief (~1.4s)
/// — never a gate. Respects Reduce Motion (static, no spring). The real app
/// icon art can replace the SF Symbol shield once the asset is added
/// (TODO(brand): swap `checkmark.shield.fill` for the SafeSide icon image).
struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var badge: CGFloat = 104
    @State private var appear = false

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .frame(width: badge * 2.1)
                .scaleEffect(appear ? 1 : 0.82)
                .opacity(appear ? 1 : 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("SafeSide")
        .onAppear {
            if reduceMotion {
                appear = true
            } else {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                    appear = true
                }
            }
        }
    }
}

#if DEBUG
#Preview { SplashView() }
#endif
