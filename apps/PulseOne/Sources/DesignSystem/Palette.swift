import SwiftUI

/// PULSE ONE colors from the master directive §5.1. Views never use raw colors.
enum Palette {
    static let obsidian      = Color(hex: 0x070D19)
    static let bioCyan       = Color(hex: 0x15D9F3)
    static let neuralViolet  = Color(hex: 0x9B70FF)
    static let pulseCoral    = Color(hex: 0xFF644F)
    static let iceWhite      = Color(hex: 0xE6F4FA)

    // Derived surfaces for the cinematic dark base.
    static let surface       = obsidian
    static let surfaceRaised = Color(hex: 0x0F1A2C)
    static let hairline      = Color(hex: 0x23344F)
    static let ink           = iceWhite
    static let inkMuted      = Color(hex: 0xA3B8C8)

    /// Background mesh (3×3), row by row: deep obsidian with a cyan/violet glow behind the orb.
    static let mesh: [Color] = [
        0x070D19, 0x0A1426, 0x070D19,
        0x0B1630, 0x14204A, 0x0E1430,
        0x070D19, 0x0A1224, 0x070D19
    ].map(Color.init(hex:))
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
