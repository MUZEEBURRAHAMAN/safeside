import SwiftUI

/// Branded cold-launch splash. The shield-check mark springs in, the wordmark
/// fades up, then `FoodScannerApp` cross-fades to the app. Calm + brief (~1.4s)
/// — never a gate. Respects Reduce Motion (static, no spring). The real app
/// icon art can replace the SF Symbol shield once the asset is added
/// (TODO(brand): swap `checkmark.shield.fill` for the SafeSide icon image).
struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var badge: CGFloat = 104
    @ScaledMetric(relativeTo: .largeTitle) private var glyph: CGFloat = 52
    @State private var appear = false

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            VStack(spacing: Theme.Space.s4) {
                ZStack {
                    RoundedRectangle(cornerRadius: badge * 0.24, style: .continuous)
                        .fill(Theme.greenSoft)
                        .frame(width: badge, height: badge)
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: glyph, weight: .bold))
                        .foregroundStyle(Theme.greenDeep)
                        .scaleEffect(appear ? 1 : 0.5)
                        .opacity(appear ? 1 : 0)
                }

                Text("SafeSide")
                    .font(.display(34, weight: .bold, relativeTo: .largeTitle))
                    .foregroundStyle(Theme.greenDeep)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 10)
            }
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
