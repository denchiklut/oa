import AppKit

/// Arc's `SpaceStyleEditor`: the theme editor's state, what each of its controls does to it, and the theme it makes.
/// Each change that Arc files for undo returns the state it changed from.
struct SpaceStyleEditor: Equatable {
    static let maxColors = 3
    static let padReach = 0.99
    static let emptyStateText = "Tap to pick a color for this space"

    let originalTheme: WindowTheme?
    private let initialState: State
    private(set) var state: State
    /// Arc's `undoStack`: the state a gesture started from, until it ends.
    private var gestureStart: State?

    struct State: Equatable {
        var primaryColor: EditorColor?
        var numberOfColors = 0
        var noiseFactor = 0.0
        var overlay = WindowTheme.Overlay.grain
        var intensityFactor = 0.8
        var wheel = WindowTheme.Wheel.complimentary
        var saturation = 1.0
        var lightnessRange: ClosedRange<Double> = 0.01...0.97
        /// The app's appearance, which the Automatic, Light and Dark buttons show. As Arc's, unread until the editor
        /// has appeared, and again after an undo rebuilds the state.
        var appearance: NSAppearance.Name?
        var hasAppeared = false
    }

    /// Arc's `SpaceStyleEditorColorSet`.
    struct ColorSet: Hashable {
        let keyColor: EditorColor
        var companions = 0
        var wheel = WindowTheme.Wheel.complimentary

        var colors: [EditorColor] { SpaceStyleEditor.companions(of: keyColor, count: companions + 1, wheel: wheel) }
    }

    /// Arc's `didUpdateNoiseFactor` gestures, which round, file undo and tap the trackpad differently.
    enum NoiseGesture { case drag, dialClick }

    init(theme: WindowTheme? = nil) {
        originalTheme = theme
        initialState = Self.controls(for: theme)
        state = initialState
    }

    private static func controls(for theme: WindowTheme?) -> State {
        var state = State()
        guard case .single(let background)? = theme?.background, case .color(let style) = background.style else {
            return state
        }
        let key: ThemeColor
        switch style {
        case .basicColor(let basic):
            key = basic.color
            state.intensityFactor = 0
        case .blendedSingleColor(let single):
            key = single.color
            state.numberOfColors = 1
            state.apply(single.modifiers)
        case .blendedGradient(let gradient):
            guard let first = gradient.baseColors.first else { return state }
            key = first
            state.numberOfColors = gradient.overlayColors.isEmpty ? 2 : 3
            state.wheel = gradient.wheel
            state.apply(gradient.modifiers)
        }
        let color = EditorColor(key.nsColor)
        state.primaryColor = color
        state.saturation = max(color.saturation, 0.01)
        state.lightnessRange = Self.automaticRange(around: color.lightness)
        return state
    }

    private static func automaticRange(around lightness: Double) -> ClosedRange<Double> {
        max(lightness - 0.25, 0.01)...min(lightness + 0.25, 0.97)
    }

    static func companions(of key: EditorColor, count: Int, wheel: WindowTheme.Wheel) -> [EditorColor] {
        let turns: [Double] =
            switch (count, wheel) {
            case (...1, _): []
            case (2, .analogous): [40]
            case (2, .complimentary): [180]
            case (_, .analogous): [40, -40]
            case (_, .complimentary): [150, 210]
            }
        return [key] + turns.map(key.turned(by:))
    }

    var colors: [EditorColor] {
        if state.hasSameColors(as: initialState),
            case .single(let background)? = originalTheme?.background,
            case .color(.blendedGradient(let gradient)) = background.style
        {
            let saved = gradient.baseColors + gradient.overlayColors.suffix(1)
            return saved.map { EditorColor($0.nsColor) }
        }
        return state.primaryColor.map { Self.companions(of: $0, count: state.numberOfColors, wheel: state.wheel) } ?? []
    }

    var canAddColor: Bool { state.primaryColor != nil && state.numberOfColors < Self.maxColors }
    var canRemoveColor: Bool { state.numberOfColors != 0 }

    /// Where each colour's knob sits on the pad, the key's first: the angle is the hue, clockwise from the right, and
    /// the distance from the centre, in half the pad's width, is the lightness's place in the pad's range.
    var knobs: [(color: EditorColor, point: CGPoint)] {
        let range = state.lightnessRange
        let span = range.upperBound - range.lowerBound
        return colors.map { color in
            let reach = span == 0 ? 0 : Self.padReach * min(max((color.lightness - range.lowerBound) / span, 0), 1)
            let angle = color.hue * 2 * .pi
            return (color, CGPoint(x: reach * cos(angle), y: reach * sin(angle)))
        }
    }

    // MARK: Controls

    /// A tap or drag on the pad, in half the pad's width from its centre, y down.
    mutating func didDragColorKnob(to point: CGPoint) {
        beginGesture()
        let hue = (atan2(point.y, point.x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360) / 360
        let reach = min(max(hypot(point.x, point.y) / Self.padReach, 0), 1)
        let range = state.lightnessRange
        state.primaryColor = EditorColor(
            hue: hue, saturation: state.saturation,
            lightness: range.lowerBound + reach * (range.upperBound - range.lowerBound))
        state.numberOfColors = max(state.numberOfColors, 1)
    }

    /// The end of a pad, intensity or dial drag: one undo step for it, if it changed anything.
    mutating func didEndGesture() -> State? {
        defer { gestureStart = nil }
        return gestureStart.flatMap { $0 == state ? nil : $0 }
    }

    mutating func didAddColor() -> State? {
        guard canAddColor else { return nil }
        let old = state
        state.numberOfColors += 1
        return old
    }

    /// As Arc: under two colours the wheel is complementary again, and the last colour goes with the noise and
    /// texture too.
    mutating func didRemoveColor() -> State? {
        guard canRemoveColor else { return nil }
        let old = state
        state.numberOfColors -= 1
        if state.numberOfColors < 2 { state.wheel = .complimentary }
        if state.numberOfColors == 0 { reset() }
        return old
    }

    mutating func didSelectColorSet(_ set: ColorSet) -> State? {
        let old = state
        state.primaryColor = set.keyColor
        state.numberOfColors = min(set.companions + 1, Self.maxColors)
        state.wheel = set.wheel
        state.saturation = max(set.keyColor.saturation, 0.01)
        state.lightnessRange = Self.automaticRange(around: set.keyColor.lightness)
        let changed =
            old.primaryColor != state.primaryColor || old.numberOfColors != state.numberOfColors
            || old.wheel != state.wheel
        return changed ? old : nil
    }

    mutating func didUpdateIntensityFactor(_ value: Double) {
        beginGesture()
        let new = min(max(value, 0), 1)
        Self.tap(from: state.intensityFactor, to: new, every: 0.2)
        state.intensityFactor = new
    }

    /// A drag around the dial is a gesture, one undo step when it ends; a click on the ring is one at once. Both
    /// round to 0.05, and only the drag taps the trackpad.
    mutating func didUpdateNoiseFactor(_ value: Double, _ gesture: NoiseGesture) -> State? {
        let new = (min(max(value, 0), 1) * 20).rounded() / 20
        switch gesture {
        case .drag:
            beginGesture()
            Self.tap(from: state.noiseFactor, to: new, every: 0.1)
            state.noiseFactor = new
            return nil
        case .dialClick:
            guard new != state.noiseFactor else { return nil }
            let old = state
            state.noiseFactor = new
            return old
        }
    }

    /// As Arc: with no noise the dial's centre turns it on at 0.8; with noise it moves to the next texture, and after
    /// the last turns the noise off.
    mutating func didTapNoiseKnob() -> State? {
        let old = state
        if state.noiseFactor == 0 {
            state.noiseFactor = 0.8
        } else if let next = WindowTheme.Overlay.allCases.drop(while: { $0 != state.overlay }).dropFirst().first {
            state.overlay = next
        } else {
            state.noiseFactor = 0
            state.overlay = .grain
        }
        return old
    }

    mutating func onAppearanceUpdated(_ appearance: NSAppearance.Name?) {
        state.appearance = appearance
        state.hasAppeared = true
    }

    private mutating func beginGesture() {
        if gestureStart == nil { gestureStart = state }
    }

    private mutating func reset() {
        let appearance = (state.appearance, state.hasAppeared)
        state = State()
        (state.appearance, state.hasAppeared) = appearance
    }

    /// As Arc: one tap each time a move crosses a multiple of the step, ends included.
    private static func tap(from old: Double, to new: Double, every step: Double) {
        guard new != old else { return }
        let span = min(old, new)...max(old, new)
        guard stride(from: 0.0, through: 1, by: step).contains(where: span.contains) else { return }
        MainActor.assumeIsolated { NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now) }
    }

    // MARK: The theme

    /// Arc's builder: none without a colour, a single colour, or a gradient whose third colour is an overlay that
    /// fades in from clear. Both palettes come from the key colour, and so does whether the sidebar's content is
    /// dark, by contrast with the two titles under Arc's default bias of 0.
    var theme: WindowTheme? {
        theme(for: state)
    }

    func theme(for state: State) -> WindowTheme? {
        // Saved gradients can carry colors and palettes the editor's wheel cannot reproduce.
        if state.hasSameColors(as: initialState) {
            guard state.modifiers != initialState.modifiers,
                var theme = originalTheme, case .single(var background) = theme.background
            else { return originalTheme }
            switch background.style {
            case .color(.blendedGradient(var gradient)):
                gradient.modifiers = state.modifiers
                background.style = .color(.blendedGradient(gradient))
            case .color(.blendedSingleColor(var single)):
                single.modifiers = state.modifiers
                background.style = .color(.blendedSingleColor(single))
            case .color(.basicColor(let basic)):
                background.style = .color(
                    .blendedSingleColor(
                        .init(
                            color: basic.color, translucencyStyle: basic.translucencyStyle, modifiers: state.modifiers))
                )
            }
            theme.background = .single(background)
            return theme
        }
        guard let key = state.primaryColor else { return nil }
        let colors = Self.companions(of: key, count: state.numberOfColors, wheel: state.wheel).map {
            ThemeColor($0.nsColor)
        }
        let modifiers = state.modifiers
        let style: WindowTheme.ColorStyle =
            switch colors.count {
            case 1:
                .blendedSingleColor(
                    WindowTheme.BlendedSingleColor(color: colors[0], translucencyStyle: .light, modifiers: modifiers))
            case 2:
                .blendedGradient(
                    WindowTheme.BlendedGradient(
                        baseColors: colors, overlayColors: [], translucencyStyle: .light, modifiers: modifiers,
                        wheel: state.wheel))
            default:
                .blendedGradient(
                    WindowTheme.BlendedGradient(
                        baseColors: Array(colors.prefix(2)), overlayColors: [.black.opacity(0), colors[2]],
                        translucencyStyle: .light, modifiers: modifiers, wheel: state.wheel))
            }
        let palette = WindowTheme.PrimaryColorPalette(key: key.nsColor)
        let light = WindowTheme.SemanticColorPalette(palette, .light)
        let dark = WindowTheme.SemanticColorPalette(palette, .dark)
        let background = ThemeColor(key.nsColor)
        func contrast(_ title: ThemeColor) -> Double {
            let luminances = [title.over(background).luminance, background.luminance]
            return (luminances.max()! + 0.05) / (luminances.min()! + 0.05)
        }
        let bias = 0.0
        return WindowTheme(
            background: .single(
                WindowTheme.Background(
                    style: .color(style),
                    contentOverBackgroundAppearance: bias + contrast(dark.title) >= contrast(light.title)
                        ? .dark : .light,
                    isVibrant: true)),
            windowAppearance: originalTheme?.windowAppearance, primaryColorPalette: palette,
            semanticColorPalette: .appearanceBased(light: light, dark: dark))
    }
}

extension SpaceStyleEditor.State {
    fileprivate func hasSameColors(as other: Self) -> Bool {
        primaryColor == other.primaryColor && numberOfColors == other.numberOfColors && wheel == other.wheel
    }

    fileprivate var modifiers: WindowTheme.BlendedBackgroundModifiers {
        .init(noiseFactor: noiseFactor, intensityFactor: intensityFactor, overlay: overlay)
    }

    fileprivate mutating func apply(_ modifiers: WindowTheme.BlendedBackgroundModifiers) {
        noiseFactor = modifiers.noiseFactor
        intensityFactor = modifiers.intensityFactor
        overlay = modifiers.overlay
    }
}

/// A colour as Arc's editor works on it: the hue, saturation and lightness of its Display P3 components.
struct EditorColor: Hashable {
    var hue: Double
    var saturation: Double
    var lightness: Double

    init(hue: Double, saturation: Double, lightness: Double) {
        (self.hue, self.saturation, self.lightness) = (hue, saturation, lightness)
    }

    init(_ color: NSColor) {
        let color = color.usingColorSpace(.displayP3) ?? color
        let (r, g, b) = (Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent))
        let (top, bottom) = (max(r, g, b), min(r, g, b))
        lightness = (top + bottom) / 2
        let chroma = top - bottom
        guard chroma > 0 else {
            (hue, saturation) = (0, 0)
            return
        }
        saturation = lightness > 0.5 ? chroma / (2 - top - bottom) : chroma / (top + bottom)
        let sector =
            top == r
            ? ((g - b) / chroma).truncatingRemainder(dividingBy: 6)
            : top == g ? (b - r) / chroma + 2 : (r - g) / chroma + 4
        hue = (sector < 0 ? sector + 6 : sector) / 6
    }

    var nsColor: NSColor {
        func component(_ n: Double) -> CGFloat {
            let k = (n + hue * 12).truncatingRemainder(dividingBy: 12)
            return lightness - saturation * min(lightness, 1 - lightness) * max(-1, min(k - 3, 9 - k, 1))
        }
        return NSColor(colorSpace: .displayP3, components: [component(0), component(8), component(4), 1], count: 4)
    }

    /// As Arc, turned in the colour's own space.
    func turned(by degrees: Double) -> EditorColor {
        var hue = remainder(hue + degrees / 360, 1)
        if hue < 0 { hue += 1 }
        return EditorColor(hue: hue, saturation: saturation, lightness: lightness)
    }
}

extension ThemeColor {
    var nsColor: NSColor {
        NSColor(colorSpace: .extendedSRGB, components: [red, green, blue, alpha].map { CGFloat($0) }, count: 4)
    }
}

extension SpaceStyleEditor {
    /// Arc's 45 presets in its order, nine to a page: its brand colours, the same again as three close colours, then
    /// its pastel, drab and grey ones. Oa's own constants, from the values in Arc's colour assets.
    static let presetPages: [[ColorSet]] = {
        func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> EditorColor {
            EditorColor(NSColor(srgbRed: r, green: g, blue: b, alpha: 1))
        }
        func p3(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> EditorColor {
            EditorColor(NSColor(displayP3Red: r, green: g, blue: b, alpha: 1))
        }
        let linear = NSColorSpace(cgColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!)!
        let brand = [
            srgb(0.950, 0.918, 0.894), srgb(0.950, 0.608, 0.733), srgb(0.651, 0.447, 0.616),
            srgb(0.949, 0.369, 0.420),
            EditorColor(NSColor(colorSpace: linear, components: [1, 0.235, 0.097, 1], count: 4)),
            p3(0.950, 0.840, 0.428), p3(0.451, 0.897, 0.612), p3(0.496, 0.721, 0.838), p3(0.401, 0.404, 0.527),
        ]
        let pastel = [
            p3(0.994, 0.984, 0.981), p3(0.985, 0.917, 0.951), p3(0.924, 0.825, 0.918), p3(0.968, 0.804, 0.822),
            p3(0.980, 0.882, 0.834), p3(0.996, 0.977, 0.906), p3(0.894, 0.988, 0.926), p3(0.880, 0.950, 0.984),
            p3(0.774, 0.776, 0.888),
        ]
        let drab = [
            p3(0.294, 0.231, 0.345), p3(0.384, 0.220, 0.337), p3(0.522, 0.267, 0.267), p3(0.655, 0.439, 0.282),
            p3(0.820, 0.706, 0.416), p3(0.804, 0.800, 0.659), p3(0.518, 0.659, 0.522), p3(0.204, 0.376, 0.294),
            p3(0.176, 0.267, 0.408),
        ]
        let greyscale = [1, 0.9, 0.8, 0.7, 0.5, 0.4, 0.2, 0.1, 0].map { p3($0, $0, $0) }
        return [
            brand.map { ColorSet(keyColor: $0) },
            brand.map { ColorSet(keyColor: $0, companions: 2, wheel: .analogous) },
            pastel.map { ColorSet(keyColor: $0) },
            drab.map { ColorSet(keyColor: $0) },
            greyscale.map { ColorSet(keyColor: $0) },
        ]
    }()
}
