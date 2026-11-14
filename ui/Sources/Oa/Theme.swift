import SwiftUI

/// What the window's chrome is drawn in. Arc takes it from the Space's theme; until Oa's Spaces carry one, it is
/// Arc's default theme as measured, light or dark with the system.
struct Theme {
    let icon: Color
    let disabledIcon: Color
    let addressText: Color
    let secondaryText: Color
    /// Arc's fills are overlays on the theme: black in a light one, white in a dark one.
    let fieldFill: Color

    static let light = Theme(
        icon: Color(hex: 0x5F5F69), disabledIcon: Color(hex: 0xAAAABD), addressText: Color(hex: 0x52535C),
        secondaryText: Color(hex: 0x9A99A7), fieldFill: .black.opacity(0.04))
    static let dark = Theme(
        icon: Color(hex: 0xA6A6AE), disabledIcon: Color(hex: 0x5C5B6A), addressText: Color(hex: 0xB0B0B8),
        secondaryText: Color(hex: 0x888892), fieldFill: .white.opacity(0.1))
}

extension EnvironmentValues {
    @Entry var theme = Theme.light
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}
