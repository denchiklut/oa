import SwiftUI

/// What the window's chrome is drawn in over a Space's theme.
struct Theme {
    let foreground: Color
    let icon: Color
    let disabledIcon: Color
    let addressText: Color
    let secondaryText: Color
    let fieldFill: Color
    /// Arc's loading track is fainter under a dark foreground.
    let loadingTrackOpacity: Double
    private let isDark: Bool

    /// As measured on Arc over several themes: text takes the palette's title, and the greys and fills are black
    /// over a light theme and white over a dark one.
    init(palette: WindowTheme.SemanticColorPalette, appearance: WindowTheme.Appearance) {
        func ink(_ light: Double, _ dark: Double) -> Color {
            appearance == .dark ? .white.opacity(dark) : .black.opacity(light)
        }
        foreground = palette.title.color
        icon = ink(0.57, 0.59)
        disabledIcon = ink(0.22, 0.25)
        addressText = ink(0.62, 0.64)
        secondaryText = ink(0.3, 0.45)
        fieldFill = ink(0.04, 0.1)
        loadingTrackOpacity = appearance == .dark ? 0.46 : 0.276
        isDark = appearance == .dark
    }

    /// A Space's dot in the dock as measured on Arc: black at 25% over a light theme and white at 17% over a dark
    /// one, and at 50% for the current Space; `emphasis` is how far between.
    func dockItem(emphasis: Double) -> Color {
        let rest = isDark ? 0.175 : 0.25
        return (isDark ? Color.white : .black).opacity(rest + (0.5 - rest) * emphasis)
    }

    private init() {
        foreground = .primary
        icon = Color(nsColor: .secondaryLabelColor)
        disabledIcon = Color(nsColor: .tertiaryLabelColor)
        addressText = Color(nsColor: .secondaryLabelColor)
        secondaryText = Color(nsColor: .tertiaryLabelColor)
        fieldFill = .clear
        loadingTrackOpacity = 0
        isDark = false
    }

    /// On the page's toolbar, which Arc colours from the page's top band: the system's colours stand in until Oa
    /// reads that band.
    static let toolbar = Theme()
}

extension EnvironmentValues {
    @Entry var theme = Theme.toolbar
}
