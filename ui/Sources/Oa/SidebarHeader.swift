import DevKit
import SwiftUI

/// Arc's header: the window buttons 13 pt in, centred in a 40 pt row 4 pt below the window's top, then the sidebar
/// toggle at x 77 and back, forward and reload ending 6 pt from the sidebar's edge, 32 pt buttons on the same line,
/// over the URL field. With the toolbar shown the last three are on the page, and the header ends 36 pt down. Oa's
/// own: a sidebar too narrow for all of them drops those three; what Arc's header drops is unknown.
struct SidebarHeader: View {
    let model: WindowModel
    let layout: WindowLayoutController
    @AppStorage(PageToolbar.key) private var showsToolbar = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    layout.toggleSidebar()
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 16))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(ChromeButtonStyle())
                .accessibilityLabel(layout.sidebarPresentation == .locked ? "Hide sidebar" : "Lock sidebar")
                Spacer(minLength: 0)
                if !showsToolbar, layout.sidebarWidth >= 215 {
                    NavigationButtons(page: model.frontPage, size: CGSize(width: 32, height: 32), spacing: 2)
                }
            }
            .padding(.leading, 77)
            .padding(.trailing, 6)
            .padding(.top, 7.5)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: showsToolbar ? 36 : 46, alignment: .top)
            .background(WindowDragRegion())
            if !showsToolbar {
                SidebarAddressField(model: model, layout: layout)
                    .padding(.horizontal, 8)
            }
        }
        .overlay(alignment: .topLeading) {
            WindowStandardButtonsView()
                .padding(.leading, 13)
                .padding(.top, 17)
        }
    }
}

/// Arc's URL field as measured: 36 pt tall, 8 pt in from the sidebar's edges, showing the page's host; copy link and
/// Site Controls at its end while the pointer is over it, or while Site Controls or a permission prompt hangs from it.
private struct SidebarAddressField: View {
    let model: WindowModel
    let layout: WindowLayoutController
    @State private var hovering = false
    @State private var showingSiteControls = false
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
                    SiteControlsButton(
                        model: model, size: CGSize(width: 30, height: 30), showingSiteControls: $showingSiteControls)
                }
                .padding(.trailing, 4)
                .opacity(
                    hovering || showingSiteControls || model.permissionPromptBinding(inPeekToolbar: false).wrappedValue
                        ? 1 : 0)
            }
        }
        .onHover { hovering = $0 }
        .onChange(of: showingSiteControls || model.permissionPromptBinding(inPeekToolbar: false).wrappedValue) {
            layout.setHold(.popover, $1)
        }
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
