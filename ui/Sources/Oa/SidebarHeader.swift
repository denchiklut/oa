import DevKit
import SwiftUI

/// Arc's header beside the window buttons: back, forward and reload, 32 pt buttons from x 135 on the line 23.5 pt
/// below the window's top, over the URL field. Arc's sidebar toggle at x 77 waits for the hidden sidebar.
struct SidebarHeader: View {
    let model: WindowModel

    var body: some View {
        VStack(spacing: 0) {
            NavigationButtons(page: model.page, size: CGSize(width: 32, height: 32), spacing: 2)
                .padding(.leading, 135)
                .padding(.top, 7.5)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: 46, alignment: .top)
                .background(WindowDragRegion())
            SidebarAddressField(model: model)
                .padding(.horizontal, 8)
        }
    }
}

/// Arc's URL field as measured: 36 pt tall, 8 pt in from the sidebar's edges, showing the page's host; copy link and
/// Site Controls at its end while the pointer is over it.
private struct SidebarAddressField: View {
    let model: WindowModel
    @State private var hovering = false
    @Environment(\.theme) private var theme

    var body: some View {
        // As Arc: the URL opens the command bar to edit it, rather than being edited in place.
        Button {
            model.openCommandBar(.currentTab)
        } label: {
            HStack(spacing: 3) {
                if let label = model.addressLabel {
                    Text(label)
                        .foregroundStyle(theme.addressText)
                        .padding(.leading, 12)
                } else {
                    Image(systemName: "magnifyingglass")
                        .frame(width: 24, height: 24)
                        .padding(.leading, 6)
                    Text("Search or Enter URL…")
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(theme.secondaryText)
            .frame(height: 36)
            .background(theme.fieldFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            if model.address != nil {
                HStack(spacing: -2) {
                    CopyLinkButton(model: model, size: 30)
                        .opacity(hovering ? 1 : 0)
                    SiteControlsButton(model: model, size: CGSize(width: 30, height: 30), isShown: hovering)
                }
                .padding(.trailing, 4)
            }
        }
        .overlay(alignment: .bottom) { LoadProgress(page: model.page) }
        .onHover { hovering = $0 }
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
