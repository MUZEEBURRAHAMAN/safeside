import SwiftUI

/// Design foundation (Phase A "quality bar") layered on the existing tokens in
/// Theme.swift / Theme+Result.swift — never raw hex. Three things live here:
///   1. Typography — the bundled Space Grotesk display face (DESIGN_SYSTEM §3)
///      for headlines + the score number; SF Pro stays the body/UI face so
///      Dynamic Type keeps working everywhere.
///   2. Motion — one calm, quick motion language (§7), Reduce-Motion aware.
///   3. Elevation — the two card/sheet shadow levels (§4), dark-first friendly.
///
/// Brand direction is unchanged (bold green, dark-first) — this raises the
/// execution polish, per the founder's "UI/UX first, never compromise" rule.

// MARK: - Display typeface

extension Font {
    /// Bundled display face (Space Grotesk, OFL). Scales with Dynamic Type via
    /// `relativeTo`. Falls back to the system rounded face if the font failed
    /// to register (so text never disappears). Use for hero headlines and the
    /// score number only — NOT body text (§3: "max one display per screen").
    static func display(
        _ size: CGFloat,
        weight: Font.Weight = .bold,
        relativeTo textStyle: Font.TextStyle = .largeTitle
    ) -> Font {
        .custom("Space Grotesk", size: size, relativeTo: textStyle).weight(weight)
    }
}

/// Named display ramp mapped to DESIGN_SYSTEM §3. Body/label styles deliberately
/// use the system font (`.body`, `.headline`, …) elsewhere for Dynamic Type +
/// legibility; these are the brand display moments.
enum DisplayType {
    /// The score number's brand moment (hero). Large, scales down gracefully.
    static let score = Font.display(56, weight: .bold, relativeTo: .largeTitle)
    /// Screen hero headline ("What's really in your food?").
    static let hero = Font.display(30, weight: .bold, relativeTo: .largeTitle)
    /// Screen title.
    static let h1 = Font.display(26, weight: .bold, relativeTo: .title)
    /// Prominent section header where we want brand character.
    static let h2 = Font.display(20, weight: .semibold, relativeTo: .title2)
    /// Standard result-screen section header ("What's inside", "Sources", …).
    /// DESIGN_SYSTEM_V3 §3/§8.2: Space Grotesk on every section headline (the
    /// brand's typographic signature — fixes the audit "generic SF Pro heading
    /// layer" finding). Sits between h2 and body in the ramp.
    static let h3 = Font.display(18, weight: .semibold, relativeTo: .title3)
}

// MARK: - Motion

/// One motion language (§7): purposeful, quick (150–250ms), ease-out, no
/// bounce, no urgency. Always route brand animations through these so Reduce
/// Motion is honored in one place.
enum Motion {
    static let quick: Animation = .easeOut(duration: 0.18)
    static let standard: Animation = .easeOut(duration: 0.24)
    /// The calm score reveal — gentle fade/scale, never a bounce.
    static let reveal: Animation = .easeOut(duration: 0.28)

    /// Returns `nil` (no animation) when Reduce Motion is on, else `animation`.
    /// Usage: `.animation(Motion.respecting(.standard, reduceMotion), value: x)`
    static func respecting(_ animation: Animation, _ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

// MARK: - Elevation

/// The two elevation levels from §4 ("flat by default"). Subtle — this brand
/// leans on color/space, not heavy shadows.
enum Elevation {
    case card
    case floating

    var color: Color { Color.black.opacity(self == .card ? 0.06 : 0.10) }
    var radius: CGFloat { self == .card ? 8 : 16 }
    var y: CGFloat { self == .card ? 2 : 6 }
}

extension View {
    /// Apply a design-system elevation shadow.
    func elevation(_ level: Elevation) -> some View {
        shadow(color: level.color, radius: level.radius, x: 0, y: level.y)
    }

    /// Standard surface card: white fill, `radius.md`, hairline border, `space.4`
    /// padding, plus the v3 "floating card" soft shadow. DESIGN_SYSTEM_V3 §4/§8.1
    /// (and the 2026-07-11 UI audit "Home top win") supersede the old "flat by
    /// default" rule: white cards now lift off the tinted canvas with a soft,
    /// low shadow (`y:6, blur:20, ~6% black`) *and* the hairline border together
    /// — the Ingrex/Oasis look. Subtle, never heavy. The one true card container
    /// so every panel matches (§5.4). `padded: false` to supply your own padding.
    func surfaceCard(padded: Bool = true) -> some View {
        self
            .padding(padded ? Theme.Space.s4 : 0)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 20, x: 0, y: 6)
    }
}
