import SwiftUI

/// What the window's chrome is drawn in. Arc takes it from the Space's theme; until Oa's Spaces carry one, it is
/// Arc's default theme as measured, light or dark with the system.
struct Theme {
    /// Along the window's width plus its height, from the top left corner.
    let surface: [Gradient.Stop]
    let foreground: Color
    let icon: Color
    let disabledIcon: Color
    let addressText: Color
    let secondaryText: Color
    /// Arc's fills are overlays on the theme: black in a light one, white in a dark one.
    let fieldFill: Color
    /// Arc's loading track is fainter under a dark foreground.
    let loadingTrackOpacity: Double

    static let light = Theme(
        surface: [
            .init(color: Color(hex: 0xDBDAF3), location: 0.09), .init(color: Color(hex: 0xE6E0EE), location: 0.37),
            .init(color: Color(hex: 0xF4E4E6), location: 0.75),
        ],
        foreground: Color(hex: 0x080C4D), icon: Color(hex: 0x5F5F69), disabledIcon: Color(hex: 0xAAAABD),
        addressText: Color(hex: 0x52535C), secondaryText: Color(hex: 0x9A99A7), fieldFill: .black.opacity(0.04),
        loadingTrackOpacity: 0.276)
    static let dark = Theme(
        surface: [
            .init(color: Color(hex: 0x252438), location: 0.09), .init(color: Color(hex: 0x2B2538), location: 0.37),
            .init(color: Color(hex: 0x352338), location: 0.75),
        ],
        foreground: Color(hex: 0xDFE0FF), icon: Color(hex: 0xA6A6AE), disabledIcon: Color(hex: 0x5C5B6A),
        addressText: Color(hex: 0xB0B0B8), secondaryText: Color(hex: 0x888892), fieldFill: .white.opacity(0.1),
        loadingTrackOpacity: 0.46)
    /// On the page's toolbar, which Arc colours from the page's top band: the system's colours stand in until Oa
    /// reads that band.
    static let toolbar = Theme(
        surface: [], foreground: .primary, icon: Color(nsColor: .secondaryLabelColor),
        disabledIcon: Color(nsColor: .tertiaryLabelColor), addressText: Color(nsColor: .secondaryLabelColor),
        secondaryText: Color(nsColor: .tertiaryLabelColor), fieldFill: .clear, loadingTrackOpacity: 0)
}

/// The theme behind the sidebar and around the page. A plain gradient through the colours measured on Arc's default
/// theme stands in for Arc's renderer.
struct WindowSurface: View {
    @Environment(\.theme) private var theme

    var body: some View {
        // Arc's runs at 45° whatever the window's shape, as its edges read at 1400 by 850.
        GeometryReader { geometry in
            let reach = (geometry.size.width + geometry.size.height) / 2
            LinearGradient(
                stops: theme.surface, startPoint: .topLeading,
                endPoint: UnitPoint(x: reach / geometry.size.width, y: reach / geometry.size.height))
        }
    }
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
