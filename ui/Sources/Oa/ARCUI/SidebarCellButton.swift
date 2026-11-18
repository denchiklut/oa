import SwiftUI

/// Arc's `SidebarCellButton` with its close content: two 14 × 2 pt bars, crossed for ✕ and flat for −, turning
/// between the two with the button's spring.
struct SidebarCellButton: View {
    enum Glyph {
        case close
        case minus
    }

    let glyph: Glyph
    let action: () -> Void

    var body: some View {
        Button(action: action) { CellGlyph(glyph: glyph) }
            .buttonStyle(CellButtonStyle())
    }
}

struct CellGlyph: View {
    let glyph: SidebarCellButton.Glyph
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            bar(angle: glyph == .close ? 45 : 0)
            bar(angle: glyph == .close ? -45 : 0)
        }
        .frame(width: 14, height: 14)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: glyph)
    }

    private func bar(angle: Double) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(theme.icon)
            .frame(width: 14, height: 2)
            .rotationEffect(.degrees(angle))
    }
}

/// The 24 pt square Arc's sidebar buttons share: `GrayA4` fading in under the pointer, `GrayA5` and a 0.95 spring
/// while pressed.
struct CellButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CellButtonBody(configuration: configuration)
    }

    private struct CellButtonBody: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
            configuration.label
                .frame(width: 24, height: 24)
                .background {
                    shape.fill(configuration.isPressed ? ARCUIColor.grayA5 : ARCUIColor.grayA4)
                        .opacity(hovering || configuration.isPressed ? 1 : 0)
                        .animation(.easeOut(duration: 0.1), value: hovering)
                }
                .contentShape(shape)
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
                .onHover { hovering = $0 }
        }
    }
}
