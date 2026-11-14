import DevKit
import SwiftUI

/// Arc's header row beside the window buttons: back, forward and reload, 32 pt buttons from x 135 on the line 23.5 pt
/// below the window's top. Arc's sidebar toggle at x 77 waits for the hidden sidebar.
struct SidebarHeader: View {
    static let height: CGFloat = 46

    let model: WindowModel

    var body: some View {
        NavigationButtons(page: model.page, size: CGSize(width: 32, height: 32), spacing: 2)
            .padding(.leading, 135)
            .padding(.top, 7.5)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: Self.height, alignment: .top)
            .background(WindowDragRegion())
    }
}

struct NavigationButtons: View {
    let page: (any Page)?
    let size: CGSize
    let spacing: CGFloat

    var body: some View {
        HStack(spacing: spacing) {
            button("arrow.left", 17, "Go back") { page?.goBack() }
                .disabled(!(page?.canGoBack ?? false))
            button("arrow.right", 17, "Go forward") { page?.goForward() }
                .disabled(!(page?.canGoForward ?? false))
            button(page?.isLoading == true ? "xmark" : "arrow.clockwise", 16, "Reload this page") {
                if page?.isLoading == true { page?.stopLoading() } else { page?.reload() }
            }
            .disabled(page == nil)
        }
        .buttonStyle(ChromeButtonStyle())
    }

    private func button(
        _ symbol: String, _ points: CGFloat, _ label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: points))
                .frame(width: size.width, height: size.height)
        }
        .accessibilityLabel(label)
    }
}

/// The theme's icon colours and nothing else: Arc showed no hover fill on its header controls.
struct ChromeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Glyph(label: configuration.label)
    }

    private struct Glyph: View {
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.theme) private var theme
        let label: Configuration.Label

        var body: some View {
            label
                .foregroundStyle(isEnabled ? theme.icon : theme.disabledIcon)
                .contentShape(Rectangle())
        }
    }
}
