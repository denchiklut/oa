import AppKit
import SwiftUI

/// Arc's `PopoverBackgroundView` in its translucent style with the decorative border, layered as Arc does: shadow,
/// material, wash, content, outer rim, inner rim.
struct PopoverBackgroundView: ViewModifier {
    let cornerRadius: CGFloat
    let shadowColor: Color
    let shadowRadius: CGFloat
    let shadowY: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let hairline = 1 / displayScale
        content
            .clipShape(shape)
            .background {
                ZStack {
                    PopoverMaterial(isDark: isDark)
                    isDark ? Color(.sRGB, red: 0.065, green: 0.065, blue: 0.065, opacity: 0.7) : .white.opacity(0.7)
                }
                .clipShape(shape)
            }
            .overlay {
                ZStack {
                    shape.strokeBorder(.black.opacity(isDark ? 0.9 : 0.34), lineWidth: hairline)
                    // As Arc: inset by the outer rim, its radius less its own width.
                    if isDark {
                        RoundedRectangle(cornerRadius: cornerRadius - 1, style: .continuous)
                            .strokeBorder(.white.opacity(0.23), lineWidth: 1)
                            .padding(hairline)
                    }
                }
                .allowsHitTesting(false)
            }
            .background { ShadowView(shape: shape, color: shadowColor, radius: shadowRadius, y: shadowY) }
    }
}

/// Arc's default `TranslucencyConfiguration`. The appearance is set here so the material agrees with the inks,
/// which go by the app's appearance rather than the window theme's.
private struct PopoverMaterial: NSViewRepresentable {
    let isDark: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.state = .followsWindowActiveState
        view.blendingMode = .withinWindow
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    }
}
