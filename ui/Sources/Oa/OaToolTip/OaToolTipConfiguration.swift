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

/// Arc's indigo tooltip palette, measured from Arc's light and dark captures. Dark-mode keycap colours are Oa's own
/// where Arc's dark keycaps weren't captured.
struct OaToolTipPalette {
    let background: Color
    let title: Color
    let subtitle: Color
    let keyBackground: Color
    let keyBorder: Color
    let keyForeground: Color

    static func resolved(for colorScheme: ColorScheme) -> Self {
        if colorScheme == .dark {
            Self(
                background: Color(.sRGB, red: 10 / 255, green: 22 / 255, blue: 94 / 255),
                title: Color(.sRGB, red: 245 / 255, green: 245 / 255, blue: 1),
                subtitle: Color(.sRGB, red: 245 / 255, green: 245 / 255, blue: 1, opacity: 0.68),
                keyBackground: Color(.sRGB, red: 26 / 255, green: 39 / 255, blue: 117 / 255),
                keyBorder: Color(.sRGB, red: 72 / 255, green: 87 / 255, blue: 179 / 255),
                keyForeground: Color(.sRGB, red: 186 / 255, green: 196 / 255, blue: 1)
            )
        } else {
            Self(
                background: Color(.sRGB, red: 237 / 255, green: 239 / 255, blue: 254 / 255),
                title: Color(.sRGB, red: 10 / 255, green: 22 / 255, blue: 94 / 255),
                subtitle: Color(.sRGB, red: 10 / 255, green: 22 / 255, blue: 94 / 255, opacity: 0.62),
                keyBackground: Color(.sRGB, red: 219 / 255, green: 221 / 255, blue: 254 / 255),
                keyBorder: Color(.sRGB, red: 148 / 255, green: 156 / 255, blue: 233 / 255),
                keyForeground: Color(.sRGB, red: 45 / 255, green: 74 / 255, blue: 252 / 255)
            )
        }
    }
}
