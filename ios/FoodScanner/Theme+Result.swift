import SwiftUI

/// Result-screen-only design tokens. Extends `Theme` via an extension so
/// Theme.swift itself is never touched (owned by another workstream).
///
/// Mirrors docs/DESIGN_SYSTEM.md:
/// - §2.2 dark neutrals ("this brand leans dark — make dark first-class")
/// - §2.3 `gradient.hero` (#1B7A43 → #0B2A1B, white text passes AA)
/// - §2.4/§2.5 score + feedback colors, with AA-safe *text* variants where the
///   documented hex fails 4.5:1 as small text on a light background (see
///   `warningTextOnLight` below — the raw `scoreMid` amber does not).
/// - §5.9 skeleton loading state.
///
/// Namespaced as `Theme.ResultScreen` (not `Theme.Result`) to avoid any
/// confusion with Swift's standard-library `Result<Success, Failure>`.
extension Theme {
    enum ResultScreen {
        // MARK: Dark-first hero surface (§2.2 dark column + §2.3 gradient.hero)

        /// `gradient.hero`: #1B7A43 → #0B2A1B, top → bottom.
        static let heroGradient = LinearGradient(
            colors: [Color(hex: 0x1B7A43), Color(hex: 0x0B2A1B)],
            startPoint: .top,
            endPoint: .bottom
        )

        /// Flat dark surface used for the "not enough data" hero instead of the
        /// vivid gradient — an unknown score should never read as a celebration.
        static let heroFlatUnknown = Theme.ink

        static let textOnDarkPrimary = Color(hex: 0xF2FBF4)   // §2.2 dark text.primary
        static let textOnDarkSecondary = Color(hex: 0xA9C4B4) // §2.2 dark text.secondary
        static let darkSurface = Color(hex: 0x13211A)         // §2.2 dark bg.surface
        static let darkSurfaceAlt = Color(hex: 0x16291F)      // §2.2 dark bg.surfaceAlt
        static let darkBorder = Color(hex: 0x26352B)          // §2.2 dark border.subtle

        // MARK: AA-safe text variants
        //
        // Verified against DESIGN_SYSTEM §2.4/§2.5 hexes: `scoreMid` (#C9A227)
        // is only ~2.4:1 on white/surface — fine as a badge *fill* with dark
        // text on top, but fails AA as small text/icon color on a light
        // background. `warningTextOnLight` keeps the same amber family while
        // passing ~5:1 on `bg.canvas` / `bg.surface`, for the "Limited data"
        // confidence chip and soft warning captions.
        static let warningTextOnLight = Color(hex: 0x8A6A12)

        /// `feedback.critical` (#C2381B) is already ~5.4:1 on white — safe to
        /// reuse as-is for allergen text/icons (the one place cautionary
        /// styling is allowed, per CLAUDE.md's ED-safe rule).
        static let criticalOnLight = Theme.critical

        /// Text color to place ON a solid score-band fill (badge chips).
        /// Ink passes AA on high/mid/unknown fills; low (clay) needs white.
        static func textOnBandFill(_ band: ScoreBand) -> Color {
            band == .low ? Color.white : Theme.ink
        }

        // MARK: Skeleton (loading state, §5.9)
        static let skeletonBase = Theme.surface
        static let skeletonHighlight = Theme.border
    }
}
