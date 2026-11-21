import SwiftUI

/// What the window's chrome is drawn in over a Space's theme.
struct Theme {
    let foreground: Color
    let maxContrast: Color
    let cutout: Color
    let icon: Color
    let disabledIcon: Color
    let addressText: Color
    let secondaryText: Color
    let fieldFill: Color
    let itemFill: Color
    let itemHoveredFill: Color
    let separator: Color
    let tertiaryText: Color
    let secondaryGlyph: Color
    let sectionHeaderText: Color
    let selectedCard: Color
    let selectedShadow: Color
    let selectedTile: Color
    /// Arc's modal buttons (`ModalButtonStyle`): the palette's `backgroundExtra` under its `foregroundPrimary`, which
    /// is darkened in a light scheme by however far its luminance passes 0.4.
    let modalButtonFill: Color
    let modalButtonGlyph: Color
    /// Arc's loading track is fainter under a dark foreground.
    let loadingTrackOpacity: Double
    let isDark: Bool

    /// As measured on Arc over several themes: text takes the palette's title, and the greys and fills are black
    /// over a light theme and white over a dark one.
    init(palette: WindowTheme.SemanticColorPalette, appearance: WindowTheme.Appearance) {
        func ink(_ light: Double, _ dark: Double) -> Color {
            appearance == .dark ? .white.opacity(dark) : .black.opacity(light)
        }
        foreground = palette.title.color
        maxContrast = palette.maxContrastColor.color
        cutout = palette.cutoutColor.color
        icon = ink(0.57, 0.59)
        disabledIcon = ink(0.22, 0.25)
        addressText = ink(0.62, 0.64)
        secondaryText = ink(0.3, 0.45)
        fieldFill = ink(0.04, 0.1)
        itemFill = ink(0.05, 0.1)
        itemHoveredFill = ink(0.1, 0.15)
        separator = ink(0.15, 0.15)
        tertiaryText = ink(0.3, 0.3)
        secondaryGlyph = ink(0.5, 0.5)
        sectionHeaderText = ink(0.45, 0.45)
        selectedCard = .white.opacity(appearance == .dark ? 0.2 : 0.85)
        selectedShadow = .black.opacity(appearance == .dark ? 0 : 0.2)
        selectedTile = .white.opacity(appearance == .dark ? 0.45 : 0.8)
        modalButtonFill = palette.backgroundExtra.color
        modalButtonGlyph =
            appearance == .dark
            ? palette.foregroundPrimary.color
            : palette.foregroundPrimary.darkened(by: palette.foregroundPrimary.luminance - 0.4).color
        loadingTrackOpacity = appearance == .dark ? 0.46 : 0.276
        isDark = appearance == .dark
    }

    /// Arc's `ForegroundSecondary`, which the dock's dots and resting icons are drawn in at `dockRestAlpha`.
    var dockInk: Color { (isDark ? Color.white : .black).opacity(0.5) }
    var dockRestAlpha: Double { isDark ? 0.35 : 0.5 }
    /// As measured on Arc: the URL field's magnifier.
    var promptGlyph: Color { (isDark ? Color.white : .black).opacity(0.4) }
    /// ARCUI `GrayA4`.
    var dockHoverFill: Color { (isDark ? Color.white : .black).opacity(isDark ? 0.077 : 0.071) }

    private init() {
        foreground = .primary
        maxContrast = .primary
        cutout = Color(nsColor: .textBackgroundColor)
        icon = Color(nsColor: .secondaryLabelColor)
        disabledIcon = Color(nsColor: .tertiaryLabelColor)
        addressText = Color(nsColor: .secondaryLabelColor)
        secondaryText = Color(nsColor: .tertiaryLabelColor)
        fieldFill = .clear
        itemFill = .primary.opacity(0.05)
        itemHoveredFill = .primary.opacity(0.1)
        separator = Color(nsColor: .separatorColor)
        tertiaryText = Color(nsColor: .tertiaryLabelColor)
        secondaryGlyph = Color(nsColor: .secondaryLabelColor)
        sectionHeaderText = Color(nsColor: .secondaryLabelColor)
        selectedCard = Color(nsColor: .controlBackgroundColor)
        selectedShadow = .black.opacity(0.2)
        selectedTile = Color(nsColor: .controlBackgroundColor)
        modalButtonFill = Color(nsColor: .controlBackgroundColor)
        modalButtonGlyph = .primary
        loadingTrackOpacity = 0
        isDark = false
    }

    /// The system's colours, where no theme reaches: the Peek's toolbar.
    static let toolbar = Theme()

    /// Over the page's colour on its toolbar, as Arc's `brightnessProfile`: text and icons are white at 0.75 or
    /// black at 0.6, whichever has the higher WCAG contrast over it, white on a tie, whatever the app's appearance.
    /// The dimmer inks and the fills are Oa's own.
    init(toolbarOver background: NSColor) {
        let backdrop = ThemeColor(background)
        func contrast(_ text: ThemeColor) -> Double {
            let luminances = [text.over(backdrop).luminance, backdrop.luminance]
            return (luminances.max()! + 0.05) / (luminances.min()! + 0.05)
        }
        let dark = contrast(.white.opacity(0.75)) >= contrast(.black.opacity(0.6))
        let ink = dark ? Color.white.opacity(0.75) : .black.opacity(0.6)
        let fill = dark ? Color.white : .black
        foreground = ink
        maxContrast = ink
        cutout = backdrop.color
        icon = ink
        disabledIcon = ink.opacity(0.4)
        addressText = ink
        secondaryText = ink.opacity(0.6)
        fieldFill = .clear
        itemFill = fill.opacity(0.05)
        itemHoveredFill = fill.opacity(0.09)
        separator = fill.opacity(0.15)
        tertiaryText = ink.opacity(0.4)
        secondaryGlyph = ink.opacity(0.6)
        sectionHeaderText = ink.opacity(0.6)
        selectedCard = fill.opacity(0.09)
        selectedShadow = .clear
        selectedTile = fill.opacity(0.09)
        modalButtonFill = fill.opacity(0.09)
        modalButtonGlyph = ink
        loadingTrackOpacity = dark ? 0.46 : 0.276
        isDark = dark
    }
}

extension EnvironmentValues {
    @Entry var theme = Theme.toolbar
    /// The window's own light or dark, where the chrome has taken its theme's.
    @Entry var windowColorScheme = ColorScheme.light
}
