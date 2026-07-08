import SwiftUI

/// Design tokens — single source of truth. Views reference these, never raw hex.
/// Mirrors docs/DESIGN_SYSTEM.md (bold-green brand; non-alarmist score scale).
enum Theme {
    // Brand (Design System v3 — light-first, green-accent)
    static let green        = Color(hex: 0x1FC24D) // primary brand green
    static let greenDeep    = Color(hex: 0x12994A) // primary button fill (white text passes AA)
    static let greenSoft    = Color(hex: 0xDDF3E1) // green chip/tile background (ink text)
    static let lime         = Color(hex: 0xC8F24A) // spark accent — dark surfaces only
    static let forest       = Color(hex: 0x0E3A24) // deep green surface
    static let ink          = Color(hex: 0x0A140E) // near-black green-black (dark hero/scan)

    // Neutrals — light-first (soft tinted canvas, pure-white floating cards, v3 §2)
    static let textPrimary  = Color(hex: 0x0E1A12)
    static let textSecondary = Color(hex: 0x5A6B60)
    static let onGreen      = Color.white
    static let canvas       = Color(hex: 0xF4F8F1) // soft mint-white — NOT pure white
    static let surface      = Color(hex: 0xFFFFFF) // cards/sheets float on the canvas
    static let surfaceAlt   = Color(hex: 0xEEF6EA)
    static let border       = Color(hex: 0xE4EDE5)

    // Score bands (ordinal, NON-alarmist — never pure red)
    static let scoreHigh    = Color(hex: 0x1FC24D)
    static let scoreMid     = Color(hex: 0xC9A227)
    static let scoreLow     = Color(hex: 0xB5502E) // clay, not red
    static let scoreUnknown = Color(hex: 0x7C8A82)

    // Safety-only (allergen block / destructive) — NOT for food scores
    static let critical     = Color(hex: 0xC2381B)

    // Spacing (4-pt grid)
    enum Space { static let s1: CGFloat = 4, s2: CGFloat = 8, s3: CGFloat = 12,
                 s4: CGFloat = 16, s5: CGFloat = 24, s6: CGFloat = 32, s7: CGFloat = 48 }
    // v3 §4 — larger radii; primary buttons use `full` (pill).
    enum Radius { static let sm: CGFloat = 12, md: CGFloat = 20, lg: CGFloat = 28,
                  full: CGFloat = 999 }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}
