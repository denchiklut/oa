import AppKit
import SwiftUI

/// A Space's theme, in the shape and under the names Arc stores as `customInfo.windowTheme`.
struct WindowTheme: Hashable, Codable {
    var background: AppearanceBased<Background>
    /// Kept as Arc stores it: nil on its default and on every theme from its editor. What it drives isn't traced.
    var windowAppearance: AppearanceBased<Appearance>?
    var primaryColorPalette: PrimaryColorPalette
    var semanticColorPalette: AppearanceBased<SemanticColorPalette>

    enum Appearance: String, Hashable, Codable {
        case light, dark

        var colorScheme: ColorScheme { self == .dark ? .dark : .light }
    }

    enum AppearanceBased<Value: Hashable & Codable & Sendable>: Hashable, Codable, Sendable {
        case single(Value)
        case appearanceBased(light: Value, dark: Value)

        subscript(scheme: ColorScheme) -> Value {
            switch self {
            case .single(let value): value
            case .appearanceBased(let light, let dark): scheme == .dark ? dark : light
            }
        }
    }

    struct Background: Hashable, Codable {
        var style: Style
        var contentOverBackgroundAppearance: Appearance
        /// Kept as Arc stores it: true on themes from its editor, false on its default. What reads it isn't traced.
        var isVibrant: Bool
    }

    /// Arc stores this level over the colour styles; no other case of it has been seen.
    enum Style: Hashable, Codable {
        case color(ColorStyle)
    }

    enum ColorStyle: Hashable, Codable {
        case blendedGradient(BlendedGradient)
        case blendedSingleColor(BlendedSingleColor)
        /// Arc's built-in themes use it and its editor doesn't. How Arc draws and stores it isn't traced.
        case basicColor(BasicColor)
    }

    struct BlendedGradient: Hashable, Codable {
        var baseColors: [ThemeColor]
        var overlayColors: [ThemeColor]
        var translucencyStyle: TranslucencyStyle
        var modifiers: BlendedBackgroundModifiers
        var wheel: Wheel
    }

    struct BlendedSingleColor: Hashable, Codable {
        var color: ThemeColor
        var translucencyStyle: TranslucencyStyle
        var modifiers: BlendedBackgroundModifiers
    }

    struct BasicColor: Hashable, Codable {
        var color: ThemeColor
        var translucencyStyle: TranslucencyStyle
    }

    struct BlendedBackgroundModifiers: Hashable, Codable {
        var noiseFactor: Double
        var intensityFactor: Double
        var overlay: Overlay
    }

    enum TranslucencyStyle: String, Hashable, Codable {
        case light, dark, auto
    }

    enum Wheel: Hashable, Codable {
        case complimentary, analogous
    }

    enum Overlay: String, Hashable, Codable {
        case grain, sand, denim, tweed
    }

    struct PrimaryColorPalette: Hashable, Codable {
        var tintedLight: ThemeColor
        var midTone: ThemeColor
        var shaded: ThemeColor
        var shadedDark: ThemeColor
    }

    struct SemanticColorPalette: Hashable, Codable {
        var foregroundPrimary: ThemeColor
        var foregroundSecondary: ThemeColor
        var foregroundTertiary: ThemeColor
        var maxContrastColor: ThemeColor
        var minContrastColor: ThemeColor
        var backgroundExtra: ThemeColor
        var background: ThemeColor
        var focus: ThemeColor
        var hover: ThemeColor
        var cutoutColor: ThemeColor
        var title: ThemeColor
        var subtitle: ThemeColor
    }
}

/// Extended sRGB, as Arc stores a theme's colours: a component may leave 0…1.
struct ThemeColor: Hashable, Codable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha = 1.0
    var colorSpace = ColorSpace.extendedSRGB

    enum ColorSpace: String, Codable { case extendedSRGB }

    static let white = ThemeColor(red: 1, green: 1, blue: 1)
    static let black = ThemeColor(red: 0, green: 0, blue: 0)

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }

    func opacity(_ alpha: Double) -> ThemeColor {
        ThemeColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    var luminance: Double {
        zip([red, green, blue], [0.2126, 0.7152, 0.0722]).reduce(0) { sum, pair in
            sum + pair.1 * (pair.0 >= 0.03928 ? pow((pair.0 + 0.055) / 1.055, 2.4) : pair.0 / 12.92)
        }
    }

    func darkened(by amount: Double) -> ThemeColor {
        guard amount > 0 else { return self }
        let color = NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
        return ThemeColor(
            NSColor(
                colorSpace: .sRGB, hue: color.hueComponent, saturation: color.saturationComponent,
                brightness: max(0, color.brightnessComponent - amount), alpha: alpha))
    }

    func over(_ backdrop: ThemeColor) -> ThemeColor {
        let rest = backdrop.alpha * (1 - alpha)
        let total = alpha + rest
        guard total > 0 else { return opacity(0) }
        return ThemeColor(
            red: (red * alpha + backdrop.red * rest) / total, green: (green * alpha + backdrop.green * rest) / total,
            blue: (blue * alpha + backdrop.blue * rest) / total, alpha: total)
    }
}

extension ThemeColor {
    /// Arc reads its hex colours as Display P3.
    init(displayP3 hex: UInt32) {
        self.init(
            NSColor(
                displayP3Red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1))
    }

    init(_ color: NSColor) {
        let color = color.usingColorSpace(.extendedSRGB) ?? color
        self.init(
            red: color.redComponent, green: color.greenComponent, blue: color.blueComponent,
            alpha: color.alphaComponent)
    }
}

extension WindowTheme {
    /// Arc's theme for a Space without one, with the values its binary builds it from: a light and a dark gradient,
    /// and the palettes of its brand blue.
    static let `default`: WindowTheme = {
        func background(
            _ first: UInt32, _ second: UInt32, _ intensity: Double, _ translucency: TranslucencyStyle,
            _ appearance: Appearance
        ) -> Background {
            Background(
                style: .color(
                    .blendedGradient(
                        BlendedGradient(
                            baseColors: [ThemeColor(displayP3: first), ThemeColor(displayP3: second)],
                            overlayColors: [], translucencyStyle: translucency,
                            modifiers: BlendedBackgroundModifiers(
                                noiseFactor: 0, intensityFactor: intensity, overlay: .grain),
                            wheel: .complimentary))),
                contentOverBackgroundAppearance: appearance, isVibrant: false)
        }
        // Arc converts its brand colour before deriving from it, so the palette's steps run in extended sRGB.
        let brandBlue =
            NSColor(displayP3Red: 49 / 255, green: 57 / 255, blue: 251 / 255, alpha: 1).usingColorSpace(.extendedSRGB)!
        let palette = PrimaryColorPalette(key: brandBlue)
        return WindowTheme(
            background: .appearanceBased(
                light: background(0xC8CAFE, 0xFFE6E6, 0.5, .light, .light),
                dark: background(0x01021E, 0x17011E, 0.8, .dark, .dark)),
            windowAppearance: nil, primaryColorPalette: palette,
            semanticColorPalette: .appearanceBased(
                light: SemanticColorPalette(palette, .light), dark: SemanticColorPalette(palette, .dark)))
    }()
}

extension WindowTheme {
    /// The Create a Space panel's theme until one is chosen. Oa's own, by the author's decision: open-arch's unthemed
    /// Space, an opaque indigo whatever the system's appearance, its top and bottom stops (0.15, 0.14, 0.23) and
    /// (0.17, 0.13, 0.2) met in the middle, where Arc's is its default theme.
    static let spaceCreation: WindowTheme = {
        var theme = WindowTheme.default
        let indigo = ThemeColor(red: 0.16, green: 0.135, blue: 0.215, alpha: 1)
        theme.background = .single(
            Background(
                style: .color(.basicColor(BasicColor(color: indigo, translucencyStyle: .dark))),
                contentOverBackgroundAppearance: .dark, isVibrant: false))
        theme.semanticColorPalette = .single(theme.semanticColorPalette[.dark])
        return theme
    }()
}

extension WindowTheme.PrimaryColorPalette {
    /// Arc's rule: each entry is the key colour, moved in 1 % steps of HSL lightness until its luminance is in the
    /// entry's range. Both are worked on the colour's own components, so a Display P3 key steps in P3.
    init(key: NSColor) {
        let components = [key.redComponent, key.greenComponent, key.blueComponent].map { Double($0) }
        func luminance(_ components: [Double]) -> Double {
            zip(components, [0.2126, 0.7152, 0.0722]).reduce(0) { sum, pair in
                sum + pair.1 * (pair.0 >= 0.03928 ? pow((pair.0 + 0.055) / 1.055, 2.4) : pair.0 / 12.92)
            }
        }
        func stepped(_ components: [Double], by step: Double) -> [Double] {
            let top = components.max()!
            let bottom = components.min()!
            let lightness = (top + bottom) / 2
            let target = min(max(lightness + step, 0), 1)
            let span = 1 - abs(2 * lightness - 1)
            guard top > bottom, span > 0 else { return components.map { _ in target } }
            let scale = (1 - abs(2 * target - 1)) / span
            return components.map { target + ($0 - lightness) * scale }
        }
        func entry(_ range: ClosedRange<Double>) -> ThemeColor {
            var components = components
            let step = luminance(components) < range.lowerBound ? 0.01 : -0.01
            let fits = { step > 0 ? luminance($0) >= range.lowerBound : luminance($0) <= range.upperBound }
            for _ in 0..<100 where !fits(components) { components = stepped(components, by: step) }
            return ThemeColor(
                NSColor(colorSpace: key.colorSpace, components: components.map { CGFloat($0) } + [1], count: 4))
        }
        self.init(
            tintedLight: entry(0.85...0.95), midTone: entry(0.3...0.5), shaded: entry(0...0.5),
            shadedDark: entry(0...0.1))
    }
}

extension WindowTheme.SemanticColorPalette {
    /// Arc's rule: its interface colours are entries of the primary palette, or blends of its darkest and lightest
    /// over white or black.
    init(_ palette: WindowTheme.PrimaryColorPalette, _ appearance: WindowTheme.Appearance) {
        let dark = palette.shadedDark
        switch appearance {
        case .light:
            self.init(
                foregroundPrimary: palette.shaded, foregroundSecondary: palette.midTone,
                foregroundTertiary: palette.tintedLight, maxContrastColor: dark,
                minContrastColor: palette.tintedLight, backgroundExtra: dark.opacity(0.01).over(.white),
                background: dark.opacity(0.1).over(.white), focus: dark.opacity(0.5).over(.white),
                hover: dark.opacity(0.2).over(.white), cutoutColor: palette.tintedLight,
                title: dark.opacity(0.3).over(.black), subtitle: dark.opacity(0.4).over(.white))
        case .dark:
            self.init(
                foregroundPrimary: palette.tintedLight, foregroundSecondary: palette.midTone,
                foregroundTertiary: palette.shaded, maxContrastColor: palette.tintedLight, minContrastColor: dark,
                backgroundExtra: dark.opacity(0.15).over(.black), background: dark.opacity(0.3).over(.black),
                focus: dark.opacity(0.65).over(.white.opacity(0.45)),
                hover: dark.opacity(0.35).over(.white.opacity(0.2)), cutoutColor: dark,
                title: dark.opacity(0.15).over(.white), subtitle: palette.tintedLight.opacity(0.5).over(.black))
        }
    }
}
