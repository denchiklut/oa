import AppKit
import SwiftUI

/// Colours of Arc's ARCUI asset catalog, light and dark as it has them.
enum ARCUIColor {
    static let gray1 = dynamic(srgb(0.99, 1), srgb(0.085, 1))
    static let grayA4 = dynamic(srgb(0, 0.071), srgb(1, 0.077))

    private static func srgb(_ white: CGFloat, _ alpha: CGFloat) -> NSColor {
        NSColor(srgbRed: white, green: white, blue: white, alpha: alpha)
    }

    private static func dynamic(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            })
    }
}
