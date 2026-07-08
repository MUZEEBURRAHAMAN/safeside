import SwiftUI

/// The "Plan" tab, ahead of meal planning shipping (MASTER_PLAN Phase 2). A
/// calm, on-brand "coming soon" screen — light canvas, one Space Grotesk
/// hero line, neutral copy — never a raw system `Text` placeholder, and
/// never a fake progress indicator or feature that isn't real (CLAUDE.md:
/// honest, no dark patterns).
struct PlanView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Space.s5) {
                Spacer(minLength: 0)

                ZStack {
                    Circle()
                        .fill(Theme.greenSoft)
                        .frame(width: 88, height: 88)
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(Theme.greenDeep)
                }
                .accessibilityHidden(true)

                VStack(spacing: Theme.Space.s2) {
                    Text("Meal planning is coming")
                        .font(DisplayType.hero)
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)

                    Text("Soon you'll turn your scans into a week of meals built around foods you actually buy.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
                Spacer(minLength: 0)   // biases content slightly above center
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas)
            .toolbar(.hidden, for: .navigationBar)
            .accessibilityElement(children: .contain)
        }
    }
}

#if DEBUG
#Preview("Plan — coming soon") {
    PlanView()
}
#endif
