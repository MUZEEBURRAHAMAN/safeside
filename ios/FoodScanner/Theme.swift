import SwiftUI

/// Design tokens — single source of truth. Views reference these, never raw hex.
/// Mirrors docs/DESIGN_SYSTEM.md (bold-green brand; non-alarmist score scale).
enum Theme {
    // Brand
    static let green        = Color(hex: 0x1FC24D) // primary brand green
    static let greenDeep    = Color(hex: 0x15803D) // primary button fill (white text passes AA)
    static let lime         = Color(hex: 0xC8F24A) // accent / CTA — dark surfaces only
    static let forest       = Color(hex: 0x0E3A24) // deep green surface
    static let ink          = Color(hex: 0x0A140E) // near-black green-black

    // Neutrals (light)
    static let textPrimary  = Color(hex: 0x0A140E)
    static let textSecondary = Color(hex: 0x516057)
    static let onGreen      = Color.white
    static let canvas       = Color.white
    static let surface      = Color(hex: 0xF3F8F4)
    static let surfaceAlt   = Color(hex: 0xE8F6EC)
    static let border       = Color(hex: 0xDCE7E0)

    // Score bands (ordinal, NON-alarmist — never pure red)
    static let scoreHigh    = Color(hex: 0x1FC24D)
    static let scoreMid     = Color(hex: 0xC9A227)
    static let scoreLow     = Color(hex: 0xB5502E) // clay, not red
    static let scoreUnknown = Color(hex: 0x7C8A82)

    // Safety-only (allergen block / destructive) — NOT for food scores
    static let critical     = Color(hex: 0xC2381B)

    // Spacing (4-pt grid)
    enum Space { static let s1: CGFloat = 4, s2: CGFloat = 8, s3: CGFloat = 12,
                 s4: CGFloat = 16, s5: CGFloat = 24, s6: CGFloat = 32 }
    enum Radius { static let sm: CGFloat = 8, md: CGFloat = 14, lg: CGFloat = 24 }
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
