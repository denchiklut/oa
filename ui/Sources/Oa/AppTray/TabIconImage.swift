import AppKit
import SwiftUI

/// A tab's icon drawn as a favicon would be, for what reads a favicon's colours: a tile's tint and ring.
@MainActor
enum TabIconImage {
    private static var cache: [String: NSImage] = [:]

    static func image(for icon: String) -> NSImage {
        if let image = cache[icon] { return image }
        let renderer = ImageRenderer(
            content: SpaceIconGlyph(icon: icon)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Color(white: 0.5))
                .frame(width: 32, height: 32))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage()
        cache[icon] = image
        return image
    }
}
