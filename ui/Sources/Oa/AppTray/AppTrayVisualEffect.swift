import CoreImage
import SwiftUI

/// Arc's `AppTrayVisualEffectImageProvider`: the tile's favicon blurred by 5 px and pushed to saturation 1.5,
/// brightness 0.05, contrast 0.85 at its own size, then drawn (tile width ÷ 5) × 16 pt square on the tile's centre.
struct AppTrayVisualEffect: View {
    let favicon: NSImage
    let tileWidth: CGFloat

    var body: some View {
        let side = tileWidth / 5 * 16
        Color.clear
            .overlay {
                if let image = Self.image(for: favicon) {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: side, height: side)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private static let context = CIContext()
    private static let cache = NSCache<NSImage, NSImage>()

    /// Arc filters the 32 px favicon its cache keeps; Oa's live favicons are brought to that size first.
    static func image(for favicon: NSImage) -> NSImage? {
        if let image = cache.object(forKey: favicon) { return image }
        let pixels = 32
        guard
            let bitmap = CGContext(
                data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: bitmap, flipped: false)
        favicon.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        guard let source = bitmap.makeImage() else { return nil }
        let blurred = CIImage(cgImage: source).applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 5])
        let output = blurred.applyingFilter(
            "CIColorControls",
            parameters: [
                kCIInputSaturationKey: 1.5, kCIInputBrightnessKey: 0.05, kCIInputContrastKey: 0.85,
            ])
        guard let filtered = context.createCGImage(output, from: output.extent) else { return nil }
        let image = NSImage(cgImage: filtered, size: NSSize(width: filtered.width, height: filtered.height))
        cache.setObject(image, forKey: favicon)
        return image
    }
}

/// Arc's `AppTrayItemSelectionOutlineView`: the same image through a 2 pt ring inside the tile's edge, an even-odd
/// cut of a 12 pt corner rounded rect and a 10 pt one inset by 2.
struct AppTrayRing: View {
    let favicon: NSImage
    let tileWidth: CGFloat

    var body: some View {
        AppTrayVisualEffect(favicon: favicon, tileWidth: tileWidth)
            .mask { AppTrayRingShape().fill(style: FillStyle(eoFill: true)) }
    }
}

struct AppTrayRingShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = RoundedRectangle(cornerRadius: 12, style: .continuous).path(in: rect)
        path.addPath(RoundedRectangle(cornerRadius: 10, style: .continuous).path(in: rect.insetBy(dx: 2, dy: 2)))
        return path
    }
}

/// Arc's tile image for a split Favorite: each pane's filtered favicon at 12 pt's size, centred on the pane's part of
/// the tile, parts 2 pt apart, a later one over an earlier with no clip.
struct SplitAppTrayVisualEffect: View {
    let favicons: [NSImage?]
    let tileWidth: CGFloat

    var body: some View {
        let side = tileWidth / 5 * 12
        let part = (tileWidth - 2 * CGFloat(favicons.count - 1)) / CGFloat(favicons.count)
        GeometryReader { geometry in
            ForEach(Array(favicons.enumerated()), id: \.offset) { index, favicon in
                if let favicon, let image = AppTrayVisualEffect.image(for: favicon) {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: side, height: side)
                        .position(x: CGFloat(index) * (part + 2) + part / 2, y: geometry.size.height / 2)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Arc's selection ring on a split Favorite, LIKELY with the 2 pt gaps between its parts cut out with it.
struct SplitAppTrayRing: View {
    let favicons: [NSImage?]
    let tileWidth: CGFloat

    var body: some View {
        SplitAppTrayVisualEffect(favicons: favicons, tileWidth: tileWidth)
            .mask {
                ZStack {
                    AppTrayRingShape().fill(style: FillStyle(eoFill: true))
                    let part = (tileWidth - 2 * CGFloat(favicons.count - 1)) / CGFloat(favicons.count)
                    ForEach(1..<max(favicons.count, 1), id: \.self) { index in
                        Rectangle().frame(width: 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, CGFloat(index) * (part + 2) - 2)
                    }
                }
            }
    }
}
