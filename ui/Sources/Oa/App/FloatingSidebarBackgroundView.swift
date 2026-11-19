import SwiftUI

/// Arc's container for a hidden sidebar that floats over the page, around the one sidebar view the docked mode shows:
/// 5 pt in from the window's left, top and bottom, a white rim at 30% and a soft shadow. Docking it morphs the same
/// view back, so the page never shows through in between. Oa's own, by the author's decision, as open-arch: its
/// background is the window's own, cut out where it sits, where Arc's is the theme over a blur of the page, so the
/// sidebar's colour doesn't change as it docks or floats.
struct FloatingSidebarBackgroundView<Sidebar: View>: View {
    /// Arc's code: 12 pt from macOS 26, 8 pt before.
    private static var cornerRadius: CGFloat { if #available(macOS 26, *) { 12 } else { 8 } }

    let background: WindowTheme.Background
    let next: WindowSurface.Next?
    let windowSize: CGSize
    let isFloating: Bool
    /// Still a panel while docking, as open-arch: the background stays under the sidebar until the page has slid out
    /// from under it, while the shape goes with `isFloating`.
    let isPanel: Bool
    @ViewBuilder let sidebar: Sidebar

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: isFloating ? Self.cornerRadius : 0)
        let inset = isFloating ? WindowLayoutController.floatingInset : 0
        sidebar
            // The background, rim and shadow are gone while docked rather than clear: under a docked sidebar that
            // fades or shrinks they would show.
            .background {
                if isPanel {
                    // Switched at once, as open-arch: it matches the window's where it sits, and half faded the page
                    // sliding under it would show.
                    WindowSurface(
                        background: background, next: next,
                        window: CGRect(origin: CGPoint(x: -inset, y: -inset), size: windowSize)
                    )
                    .transition(.identity)
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
            .padding([.top, .leading, .bottom], inset)
    }
}
