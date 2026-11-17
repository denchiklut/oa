import SwiftUI

/// Arc's container for a hidden sidebar that floats over the page, around the one sidebar view the docked mode shows:
/// 5 pt in from the window's left, top and bottom, the theme over a blur of the page, a white rim at 30% and a soft
/// shadow. Docking it morphs the same view back, so the page never shows through in between.
struct FloatingSidebarBackgroundView<Sidebar: View>: View {
    /// Arc's code: 12 pt from macOS 26, 8 pt before.
    private static var cornerRadius: CGFloat { if #available(macOS 26, *) { 12 } else { 8 } }

    let background: WindowTheme.Background
    let windowSize: CGSize
    let isFloating: Bool
    @ViewBuilder let sidebar: Sidebar

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: isFloating ? Self.cornerRadius : 0)
        let inset = WindowLayoutController.floatingInset
        sidebar
            // The blur, rim and shadow are gone while docked rather than clear: under a docked sidebar that fades
            // or shrinks they would show.
            .background {
                if isFloating {
                    WindowSurface(
                        background: background, floats: true,
                        window: CGRect(origin: CGPoint(x: -inset, y: -inset), size: windowSize))
                }
            }
            .clipShape(shape)
            .overlay {
                if isFloating { shape.strokeBorder(.white.opacity(0.3)) }
            }
            // Fitted to Arc's `CellDropShadow` as captured over a white page. Cut out under the panel, whose blur
            // would pick it up.
            .background {
                if isFloating {
                    shape
                        .fill(.black)
                        .shadow(color: .black.opacity(0.16), radius: 4, y: 1)
                        .mask {
                            Rectangle()
                                .padding(-16)
                                .overlay { shape.blendMode(.destinationOut) }
                                .compositingGroup()
                        }
                }
            }
            .padding([.top, .leading, .bottom], isFloating ? inset : 0)
    }
}
