import ImageIO
import SwiftUI
import simd

/// A theme's background behind the sidebar and around the page, stacked as Arc's is: the window's material, an
/// underlay, the colours at the alpha their intensity gives, then the texture. The material shows the desktop only
/// while the window is active, so an inactive window is opaque, as Arc's.
struct WindowSurface: View {
    typealias Next = (background: WindowTheme.Background, progress: Double)

    let background: WindowTheme.Background
    /// Arc's `.transitioning` pair during a swipe between Spaces: the next Space's background and how far toward it.
    /// Its colours cross-fade with these, as measured on Arc, uniformly and in encoded values, and its material goes
    /// over this one's at the progress where the two differ, as Arc's foreground frame does.
    var next: Next?
    /// The window in this surface's space, for a part of the window's background drawn elsewhere: the floating
    /// sidebar's.
    var window: CGRect?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack {
            WindowMaterial(material: background.material, blendingMode: .behindWindow)
            if let next, next.background.material != background.material {
                WindowMaterial(material: next.background.material, blendingMode: .behindWindow)
                    .opacity(next.progress)
            }
            if let window {
                Color.clear
                    .overlay(alignment: .topLeading) {
                        colors
                            .frame(width: window.width, height: window.height)
                            .offset(x: window.minX, y: window.minY)
                    }
                    .clipped()
            } else {
                colors
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var colors: some View {
        ZStack {
            layer(background).opacity(1 - (next?.progress ?? 0))
            if let next {
                layer(next.background).opacity(next.progress).blendMode(.plusLighter)
            }
        }
        .compositingGroup()
    }

    private func layer(_ background: WindowTheme.Background) -> some View {
        ZStack {
            // Arc's underlay goes by the window's appearance, not the theme's: black under a dark one.
            let alpha = background.alpha
            let underlay = min(alpha, 0.5)
            ThemeColors(
                style: background.style, alpha: alpha,
                underlay: colorScheme == .dark ? .black.opacity(0.35 * underlay) : .white.opacity(underlay))
            texture(background.modifiers)
        }
        .compositingGroup()
    }

    /// Arc's texture gains, a quarter as strong in an inactive window.
    @ViewBuilder private func texture(_ modifiers: WindowTheme.BlendedBackgroundModifiers?) -> some View {
        if let modifiers, modifiers.noiseFactor > 0 {
            let gain =
                switch modifiers.overlay {
                case .grain: 0.8
                case .sand: 0.15
                case .denim: 0.6
                case .tweed: 0.4
                }
            Image(decorative: WindowTexture.image(modifiers.overlay), scale: displayScale)
                .resizable(resizingMode: .tile)
                .blendMode(.multiply)
                .opacity(modifiers.noiseFactor * gain * (activeState == .inactive ? 0.25 : 1))
        }
    }
}

extension WindowTheme.Background {
    fileprivate var translucencyStyle: WindowTheme.TranslucencyStyle {
        switch style {
        case .color(.blendedGradient(let gradient)): gradient.translucencyStyle
        case .color(.blendedSingleColor(let single)): single.translucencyStyle
        case .color(.basicColor(let basic)): basic.translucencyStyle
        }
    }

    fileprivate var modifiers: WindowTheme.BlendedBackgroundModifiers? {
        switch style {
        case .color(.blendedGradient(let gradient)): gradient.modifiers
        case .color(.blendedSingleColor(let single)): single.modifiers
        case .color(.basicColor): nil
        }
    }

    /// Arc passes the raw values of the deprecated light and dark materials.
    fileprivate var material: NSVisualEffectView.Material {
        switch translucencyStyle {
        case .light: NSVisualEffectView.Material(rawValue: 1)!
        case .dark: NSVisualEffectView.Material(rawValue: 2)!
        case .auto: .windowBackground
        }
    }

    /// Oa's own for a basic colour, which has no intensity: opaque.
    fileprivate var alpha: Double {
        modifiers.map { 0.2 + 0.55 * $0.intensityFactor } ?? 1
    }
}

struct WindowMaterial: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    var state = NSVisualEffectView.State.followsWindowActiveState

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// A theme's colours, computed as Arc's shader lays them: the base colours mixed in Oklab from the top left corner
/// to the bottom right at 45° whatever the window's shape, and done three quarters of the way; the overlay colours
/// top to bottom over them in linear light; and the whole over the underlay in sRGB's encoding. In a bitmap of Oa's
/// own, because a theme's colours may leave sRGB, where SwiftUI's layers would clamp them.
private struct ThemeColors: NSViewRepresentable, Equatable {
    let style: WindowTheme.Style
    let alpha: Double
    let underlay: ThemeColor

    func makeNSView(context: Context) -> Bitmap {
        let view = Bitmap()
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: Bitmap, context: Context) {
        view.colors = self
        view.needsLayout = true
    }

    final class Bitmap: NSView {
        var colors: ThemeColors?
        private var drawn: (colors: ThemeColors, size: CGSize)?

        override func layout() {
            super.layout()
            guard let colors, let layer, bounds.width > 0, bounds.height > 0 else { return }
            if let drawn, drawn.colors == colors, drawn.size == bounds.size { return }
            layer.contentsGravity = .resize
            layer.contents = Self.image(of: colors, size: bounds.size)
            drawn = (colors, bounds.size)
        }

        /// The last few bitmaps, so the Library's cards, all one size and often one theme, compute theirs once.
        private static var recent: [(colors: ThemeColors, size: CGSize, image: CGImage?)] = []

        private static func image(of colors: ThemeColors, size: CGSize) -> CGImage? {
            if let cached = recent.first(where: { $0.colors == colors && $0.size == size }) { return cached.image }
            let image = colors.image(size: size)
            recent = Array((recent + [(colors, size, image)]).suffix(8))
            return image
        }
    }

    private func image(size: CGSize) -> CGImage? {
        let base: [ThemeColor]
        let overlay: [ThemeColor]
        switch style {
        case .color(.blendedGradient(let gradient)): (base, overlay) = (gradient.baseColors, gradient.overlayColors)
        case .color(.blendedSingleColor(let single)): (base, overlay) = ([single.color], [])
        case .color(.basicColor(let basic)): (base, overlay) = ([basic.color], [])
        }
        guard let first = base.first, let last = base.last else { return nil }
        let side = base.count + overlay.count > 1 ? 256 : 1
        let ends = (first.oklab, last.oklab)
        // As Arc: a clear overlay colour takes the other's hue, so the ramp fades in rather than through grey.
        let over = overlay.first.flatMap { top in overlay.last.map { (top.alpha == 0 ? $0 : top, top.alpha, $0) } }
        var pixels = [Float](repeating: 0, count: side * side * 4)
        for row in 0..<side {
            let v = (Double(row) + 0.5) / Double(side)
            let above = over.map { ThemeColor.linear(oklab: $0.0.oklab + ($0.2.oklab - $0.0.oklab) * v) } ?? .zero
            let cover = over.map { ($0.1 + ($0.2.alpha - $0.1) * v) * alpha } ?? 0
            let rest = alpha * (1 - cover)
            for column in 0..<side {
                let u = (Double(column) + 0.5) / Double(side)
                let along = (u * size.width + v * size.height) / (size.width + size.height)
                let below = ThemeColor.linear(oklab: ends.0 + (ends.1 - ends.0) * min(along * 4 / 3, 1))
                let layer = ThemeColor(linear: (above * cover + below * rest) / (cover + rest))
                    .opacity(cover + rest).over(underlay)
                // A layer's contents lose what lies outside their colour space, so the bitmap is in Display P3,
                // which Arc's theme colours are picked in.
                let color = ThemeColor.displayP3 * layer.linear
                for channel in 0..<3 {
                    pixels[(row * side + column) * 4 + channel] = Float(
                        ThemeColor.encoded(color[channel]) * layer.alpha)
                }
                pixels[(row * side + column) * 4 + 3] = Float(layer.alpha)
            }
        }
        return pixels.withUnsafeBytes { bytes in
            CGImage(
                width: side, height: side, bitsPerComponent: 32, bitsPerPixel: 128, bytesPerRow: side * 16,
                space: CGColorSpace(name: CGColorSpace.displayP3)!,
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue
                        | CGBitmapInfo.byteOrder32Little.rawValue),
                provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: true,
                intent: .defaultIntent)
        }
    }
}

extension ThemeColor {
    fileprivate static func decoded(_ value: Double) -> Double {
        let size = abs(value)
        return (value < 0 ? -1 : 1) * (size > 0.04045 ? pow((size + 0.055) / 1.055, 2.4) : size / 12.92)
    }

    fileprivate static func encoded(_ value: Double) -> Double {
        let size = abs(value)
        return (value < 0 ? -1 : 1) * (size > 0.0031308 ? 1.055 * pow(size, 1 / 2.4) - 0.055 : size * 12.92)
    }

    fileprivate var linear: SIMD3<Double> {
        SIMD3(Self.decoded(red), Self.decoded(green), Self.decoded(blue))
    }

    fileprivate init(linear: SIMD3<Double>) {
        self.init(red: Self.encoded(linear.x), green: Self.encoded(linear.y), blue: Self.encoded(linear.z))
    }

    fileprivate var oklab: SIMD3<Double> {
        let cone = Self.cones * linear
        return Self.opponents * SIMD3(cbrt(cone.x), cbrt(cone.y), cbrt(cone.z))
    }

    fileprivate static func linear(oklab: SIMD3<Double>) -> SIMD3<Double> {
        let cone = opponents.inverse * oklab
        return cones.inverse * (cone * cone * cone)
    }

    /// Linear sRGB to linear Display P3.
    fileprivate static let displayP3 = simd_double3x3(rows: [
        SIMD3(0.8224621, 0.1775380, 0), SIMD3(0.0331941, 0.9668058, 0), SIMD3(0.0170827, 0.0723974, 0.9105199),
    ])
    /// Oklab's published matrices: linear sRGB to cone responses, and their cube roots to lightness and two opponents.
    private static let cones = simd_double3x3(rows: [
        SIMD3(0.4122214708, 0.5363325363, 0.0514459929), SIMD3(0.2119034982, 0.6806995451, 0.1073969566),
        SIMD3(0.0883024619, 0.2817188376, 0.6299787005),
    ])
    private static let opponents = simd_double3x3(rows: [
        SIMD3(0.2104542553, 0.7936177850, -0.0040720468), SIMD3(1.9779984951, -2.4285922050, 0.4505937099),
        SIMD3(0.0259040371, 0.7827717662, -0.8086757660),
    ])
}

@MainActor
enum WindowTexture {
    private static var images: [WindowTheme.Overlay: CGImage] = [:]

    static func image(_ overlay: WindowTheme.Overlay) -> CGImage {
        if let image = images[overlay] { return image }
        let name =
            switch overlay {
            case .grain: "grain"
            case .sand: "sand"
            case .denim: "denim"
            case .tweed: "tweed"
            }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "ThemeTextures"),
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { preconditionFailure("Could not load window texture: \(name)") }
        images[overlay] = image
        return image
    }
}
