import SwiftUI

/// Arc's tooltip bubble: a continuous asymmetric capsule pinched toward the pointer, with optional subtitle and
/// keyboard-shortcut keycaps, rendered inside transparent shadow insets for its borderless child window.
struct OaToolTipView: View {
    static let shadowInsets = NSEdgeInsets(top: 16, left: 28, bottom: 40, right: 28)
    static let maxWidth: CGFloat = 296
    private static let pinchedRadius: CGFloat = 4
    private static let roundedRadius: CGFloat = 14

    let configuration: OaToolTipConfiguration
    let pinchedCorner: OaToolTipCorner
    let palette: OaToolTipPalette

    var body: some View {
        let shape = UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
        let symbols = configuration.shortcut?.symbols ?? []
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(configuration.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.title)
                    .multilineTextAlignment(.leading)
                if let subtitle = configuration.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(palette.subtitle)
                        .multilineTextAlignment(.leading)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if !symbols.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                        keyCap(symbol)
                    }
                }
            }
        }
        .padding(.leading, 11)
        .padding(.trailing, symbols.isEmpty ? 11 : 6)
        .padding(.vertical, configuration.subtitle == nil ? 5 : 6)
        .frame(minHeight: 28)
        .background {
            shape
                .fill(palette.background)
                .shadow(color: Color(.sRGB, red: 0.443, green: 0.329, blue: 0.165, opacity: 0.15), radius: 14, y: 8)
                .shadow(color: Color(white: 0.18, opacity: 0.15), radius: 4, y: 2)
        }
        .padding(.top, Self.shadowInsets.top)
        .padding(.leading, Self.shadowInsets.left)
        .padding(.bottom, Self.shadowInsets.bottom)
        .padding(.trailing, Self.shadowInsets.right)
    }

    private var cornerRadii: RectangleCornerRadii {
        let small = Self.pinchedRadius
        let large = Self.roundedRadius
        return RectangleCornerRadii(
            topLeading: pinchedCorner == .topLeading ? small : large,
            bottomLeading: pinchedCorner == .bottomLeading ? small : large,
            bottomTrailing: pinchedCorner == .bottomTrailing ? small : large,
            topTrailing: pinchedCorner == .topTrailing ? small : large
        )
    }

    private func keyCap(_ symbol: String) -> some View {
        let cap = RoundedRectangle(cornerRadius: 5, style: .continuous)
        return Text(symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(palette.keyForeground)
            .frame(minWidth: 21, minHeight: 17)
            .padding(.horizontal, 2)
            .background {
                cap.fill(palette.keyBorder).offset(y: 1.5)
                cap.fill(palette.keyBackground)
            }
            .overlay(cap.strokeBorder(palette.keyBorder, lineWidth: 1))
            .padding(.bottom, 1.5)
    }
}

private struct OaToolTipModifier: ViewModifier {
    let configuration: OaToolTipConfiguration?
    @Environment(\.oaToolTipController) private var controller
    @Environment(\.oaToolTipPalette) private var palette
    @State private var id = UUID()
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                hovered = inside
                sync()
            }
            .onChange(of: configuration) { _, _ in
                sync()
            }
            .onChange(of: palette) { sync() }
            .onDisappear {
                hovered = false
                controller?.unregister(id)
            }
    }

    private func sync() {
        guard let controller else { return }
        if hovered, let configuration {
            controller.register(id, configuration: configuration, palette: palette)
        } else {
            controller.unregister(id)
        }
    }
}

extension View {
    func oaToolTip(_ configuration: OaToolTipConfiguration?) -> some View {
        modifier(OaToolTipModifier(configuration: configuration))
    }

    func oaToolTip(
        _ title: String, subtitle: String? = nil, shortcut: ARCKeyboardShortcut? = nil,
        delay: TimeInterval = OaToolTipConfiguration.controlDelay, priority: Int = 0
    ) -> some View {
        oaToolTip(
            OaToolTipConfiguration(
                title: title, subtitle: subtitle, shortcut: shortcut, delay: delay, priority: priority))
    }
}

extension EnvironmentValues {
    @Entry var oaToolTipPalette = OaToolTipPalette.space(WindowTheme.default.semanticColorPalette[.light])
    @Entry var oaToolTipController: OaToolTipController?
}
