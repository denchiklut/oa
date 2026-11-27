import SwiftUI

/// Configuration for an `OaToolTip`, following Arc's `ArcTooltipConfiguration` seam.
struct OaToolTipConfiguration: Equatable {
    static let rowDelay: TimeInterval = 0.6
    static let controlDelay: TimeInterval = 0.45

    var title: String
    var subtitle: String?
    var shortcut: ARCKeyboardShortcut?
    var delay: TimeInterval = controlDelay
    /// Higher priority wins when nested hover targets overlap (e.g. a row's close button over its row).
    var priority: Int = 0
}

enum OaToolTipCorner: Equatable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
}

struct OaToolTipPalette: Equatable {
    let background: Color
    let title: Color
    let subtitle: Color
    let keyBackground: Color
    let keyBorder: Color
    let keyForeground: Color

    @MainActor
    static func forWindow(_ window: NSWindow) -> Self {
        var owner: NSWindow? = window
        var theme = WindowTheme.default
        var appearance = window.effectiveAppearance
        while let current = owner {
            if let layout = current.contentViewController as? WindowLayoutController {
                theme = layout.chromeTheme
                appearance = current.effectiveAppearance
                break
            }
            owner = current.parent ?? current.sheetParent
        }
        let scheme: ColorScheme = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
        return .space(theme.semanticColorPalette[scheme])
    }

    static func developerToolbar(_ palette: WindowTheme.SemanticColorPalette) -> Self {
        Self(
            background: palette.backgroundExtra.color, title: palette.maxContrastColor.color,
            subtitle: palette.foregroundPrimary.color, keyBackground: palette.maxContrastColor.color,
            keyBorder: palette.foregroundSecondary.color, keyForeground: palette.backgroundExtra.color)
    }

    static func space(_ palette: WindowTheme.SemanticColorPalette) -> Self {
        let background = palette.minContrastColor
        let ink = palette.maxContrastColor
        // Oa's keycap blends keep the Space hue visible behind the shortcut symbols.
        return Self(
            background: background.color, title: ink.color, subtitle: ink.opacity(0.7).over(background).color,
            keyBackground: palette.foregroundSecondary.opacity(0.2).over(background).color,
            keyBorder: palette.foregroundSecondary.opacity(0.65).over(background).color,
            keyForeground: ink.color)
    }
}
