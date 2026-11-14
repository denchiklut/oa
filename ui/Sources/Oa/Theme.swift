import SwiftUI

/// What the window's chrome is drawn in. Arc takes it from the Space's theme; until Oa's Spaces carry one, it is
/// Arc's default theme as measured, light or dark with the system.
struct Theme {
    let icon: Color
    let disabledIcon: Color

    static let light = Theme(icon: Color(hex: 0x5F5F69), disabledIcon: Color(hex: 0xAAAABD))
    static let dark = Theme(icon: Color(hex: 0xA6A6AE), disabledIcon: Color(hex: 0x5C5B6A))
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
