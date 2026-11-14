import SwiftUI
import simd

/// A theme's background behind the sidebar and around the page, stacked as Arc's is: the window's material, an
/// underlay, the colours at the alpha their intensity gives, then the texture. The material shows the desktop only
/// while the window is active, so an inactive window is opaque, as Arc's.
struct WindowSurface: View {
    let background: WindowTheme.Background
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack {
            WindowMaterial(material: material)
            ZStack {
                // Arc's underlay goes by the window's appearance, not the theme's: black under a dark one.
                let underlay = min(alpha, 0.5)
                ThemeColors(
                    style: background.style, alpha: alpha,
                    underlay: colorScheme == .dark ? .black.opacity(0.35 * underlay) : .white.opacity(underlay))
                texture
            }
            .compositingGroup()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var translucencyStyle: WindowTheme.TranslucencyStyle {
        switch background.style {
        case .blendedGradient(_, _, let style, _, _), .blendedSingleColor(_, let style, _), .basicColor(_, let style):
            style
        }
    }

    private var modifiers: WindowTheme.BlendedBackgroundModifiers? {
        switch background.style {
        case .blendedGradient(_, _, _, let modifiers, _), .blendedSingleColor(_, _, let modifiers): modifiers
        case .basicColor: nil
        }
    }

    /// Arc passes the raw values of the deprecated light and dark materials.
    private var material: NSVisualEffectView.Material {
        switch translucencyStyle {
        case .light: NSVisualEffectView.Material(rawValue: 1)!
        case .dark: NSVisualEffectView.Material(rawValue: 2)!
        case .auto: .windowBackground
        }
    }

    /// Oa's own for a basic colour, which has no intensity: opaque.
    private var alpha: Double {
        modifiers.map { 0.2 + 0.55 * $0.intensityFactor } ?? 1
    }

    /// Arc's texture gains, a quarter as strong in an inactive window.
    @ViewBuilder private var texture: some View {
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

private struct WindowMaterial: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
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
            layer.contents = colors.image(size: bounds.size)
            drawn = (colors, bounds.size)
        }
    }

    private func image(size: CGSize) -> CGImage? {
        let base: [ThemeColor]
        let overlay: [ThemeColor]
        switch style {
        case .blendedGradient(let baseColors, let overlayColors, _, _, _):
            (base, overlay) = (baseColors, overlayColors)
        case .blendedSingleColor(let color, _, _), .basicColor(let color, _):
            (base, overlay) = ([color], [])
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

/// Oa's own textures, generated to the measured tone, contrast and grain size of Arc's four, a texel to a pixel.
@MainActor
private enum WindowTexture {
    private static let side = 200
    private static var images: [WindowTheme.Overlay: CGImage] = [:]

    static func image(_ overlay: WindowTheme.Overlay) -> CGImage {
        if let image = images[overlay] { return image }
        var random = SystemRandomNumberGenerator()
        // Noise softened towards its neighbours by `spread`, wrapping at the tile's edges, at the given tone.
        func noise(
            mean: Double, deviation: Double, spread: (x: Double, y: Double),
            wave: (Int, Int) -> Double = { _, _ in 0 }
        ) -> [Double] {
            var field = (0..<side * side).map { _ in
                (0..<4).reduce(0.0) { sum, _ in sum + Double.random(in: -1...1, using: &random) }
            }
            for (step, spread) in [(1, spread.x), (side, spread.y)] {
                let row = step == 1 ? side : side * side
                field = field.indices.map { index in
                    let line = index / row * row
                    let before = line + (index - line - step + row) % row
                    let after = line + (index - line + step) % row
                    return field[index] + spread * (field[before] + field[after])
                }
            }
            let average = field.reduce(0, +) / Double(field.count)
            let scale = (field.reduce(0) { $0 + ($1 - average) * ($1 - average) } / Double(field.count)).squareRoot()
            return field.indices.map { index in
                mean + wave(index % side, index / side) + deviation * (field[index] - average) / scale
            }
        }
        let alpha: Double
        let channels: [[Double]]
        switch overlay {
        case .grain:
            // Arc's grain is a faint film: each channel its own noise.
            alpha = 0.26
            channels = (0..<3).map { _ in noise(mean: 0.735, deviation: 0.24, spread: (0.27, 0.27)) }
        case .sand:
            alpha = 1
            channels = [noise(mean: 0.656, deviation: 0.207, spread: (0.34, 0.34))]
        case .denim:
            // A twill: diagonal ribs five texels apart.
            alpha = 1
            channels = [
                noise(mean: 0.841, deviation: 0.022, spread: (0.2, 0.2)) { x, y in
                    0.062 * cos(2 * .pi * (Double(x) / 5 - Double(y) * 44 / Double(side)))
                }
            ]
        case .tweed:
            alpha = 1
            channels = [noise(mean: 0.706, deviation: 0.046, spread: (0.23, 0.3))]
        }
        let pixels = (0..<side * side).flatMap { index in
            (0..<3).map { UInt8(min(max(channels[$0 % channels.count][index], 0), 1) * alpha * 255) }
                + [UInt8(alpha * 255)]
        }
        let image = CGImage(
            width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil, shouldInterpolate: true,
            intent: .defaultIntent)!
        images[overlay] = image
        return image
    }
}
