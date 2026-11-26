import DevKit
import SwiftUI

/// As Arc: the toolbar takes its colour from the page's top right corner.
struct PageToolbar: View {
    /// Arc's key. LIKELY kept across launches as Arc's default is; one setting for every window, as seen in Arc.
    static let key = "topBarURLEnabled"
    static var isShown: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    let model: WindowModel
    let layout: WindowLayoutController
    @State private var showingSiteControls = false
    /// As Arc's toolbar when its page changes: the page's last colour, else its host's cached one, else white, until
    /// the page's next sample.
    @State private var initialColor: NSColor?
    @State private var toolbarWidth: CGFloat = 0
    @State private var naturalURLWidth: CGFloat = 0
    @Environment(\.theme) private var windowTheme

    init(model: WindowModel, layout: WindowLayoutController) {
        self.model = model
        self.layout = layout
        _initialColor = State(initialValue: model.page.map(model.topBarColors.startingColor))
    }

    var body: some View {
        // Oa's own with no page, where Arc's colours aren't known: the empty card shows through, under the window
        // theme's inks.
        let color = model.page.flatMap { model.topBarColors.appliedColor(for: $0) } ?? initialColor
        let theme = color.map(Theme.init(toolbarOver:)) ?? windowTheme
        let showsSidebarButton = model.sidebarMode == .noChrome
        let navigationSize = CGSize(width: 32, height: 24)
        let navigationSpacing: CGFloat = 5
        let leadingWidth: CGFloat =
            5 + (showsSidebarButton ? navigationSize.width + navigationSpacing : 0) + navigationSize.width * 3
            + navigationSpacing * 2
        let trailingFixed: CGFloat = 5 + 32 + 4 + 32
        // As Arc's `TopBarPanelView`: 36 pt per pinned extension slot, showing the trailing pins that fit between
        // the centred URL (at least 150 pt) and Site Controls.
        let pinned = model.pinnedExtensionActions
        let maxCenter = max(150, toolbarWidth - 2 * leadingWidth - 16)
        let shownCenter = min(max(naturalURLWidth, 150), maxCenter)
        let rightRoom = max(0, (toolbarWidth - shownCenter) / 2 - trailingFixed - 8)
        let maxExtensions = toolbarWidth > 0 ? Int(floor(rightRoom / 36)) : pinned.count
        let shownExtensions = Array(pinned.suffix(max(0, maxExtensions)))
        let extensionsWidth = CGFloat(shownExtensions.count) * 36
        let centerPadding = max(leadingWidth + 12, trailingFixed + extensionsWidth + 12)
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 0) {
                    if showsSidebarButton {
                        Button {
                            layout.setSidebarMode(.anchored)
                        } label: {
                            Image(systemName: "sidebar.left")
                                .font(.system(size: 16))
                                .frame(width: navigationSize.width, height: navigationSize.height)
                        }
                        .buttonStyle(ChromeButtonStyle())
                        .help("Show Sidebar")
                        .accessibilityLabel("Show Sidebar")
                        .padding(.trailing, navigationSpacing)
                    }
                    NavigationButtons(page: model.page, size: navigationSize, spacing: navigationSpacing)
                    Spacer()
                    if !shownExtensions.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(shownExtensions) { action in
                                PinnedExtensionButton(
                                    model: model, action: action, size: CGSize(width: 32, height: 28), cornerRadius: 6)
                            }
                        }
                        .padding(.trailing, 4)
                    }
                    SiteControlsButton(
                        model: model, size: CGSize(width: 32, height: 28), showingSiteControls: $showingSiteControls)
                    SplitViewMenuButton(model: model)
                        .padding(.leading, 4)
                }
                .padding(.leading, 5)
                .padding(.trailing, 5)
                // The host is centred: Arc balances copy link with a second button after it.
                HStack(spacing: 3) {
                    CopyLinkButton(model: model, size: 24)
                        .opacity(model.address == nil ? 0 : 1)
                    // As Arc: the URL opens the command bar to edit it, rather than being edited in place.
                    Button {
                        model.openCommandBar(.currentTab)
                    } label: {
                        ToolbarAddressLabel(url: model.address, placeholder: "Search or Enter URL…")
                            .frame(height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Color.clear.frame(width: 24)
                }
                .padding(.horizontal, centerPadding)
            }
            .frame(height: 32)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                toolbarWidth = $0
            }
            .background {
                HStack(spacing: 3) {
                    Color.clear.frame(width: 24)
                    ToolbarAddressLabel(url: model.address, placeholder: "Search or Enter URL…")
                    Color.clear.frame(width: 24)
                }
                .fixedSize()
                .hidden()
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.width
                } action: {
                    naturalURLWidth = $0
                }
            }
            (theme.isDark ? Color.white : .black).opacity(0.05).frame(height: 1)
        }
        .environment(\.theme, theme)
        .background(color.map { Color(nsColor: $0) } ?? .clear)
        // As Arc: a sample fades in; the colour a page's toolbar starts with doesn't.
        .animation(.easeInOut(duration: 0.18), value: color)
        .background(WindowDragRegion())
    }
}

extension TopBarColorClient {
    /// As Arc's toolbar when its page changes: the page's last colour, else its host's cached one, else white.
    func startingColor(for page: any Page) -> NSColor {
        appliedColor(for: page) ?? cachedColor(for: page) ?? .white
    }
}

/// As seen in Arc: a menu at the pointer that opens an empty pane on a side of the page, as Add Split View does,
/// and off while no tab is selected. Its ink and fills were measured over white and #111111.
private struct SplitViewMenuButton: View {
    let model: WindowModel

    var body: some View {
        PointerMenuButton {
            let item = { (title: String, index: Int, orientation: SidebarSplitViewData.LayoutOrientation) in
                MenuActionItem(title) { [model] in model.addSplitViewPane(at: index, orientation: orientation) }
            }
            let menu = NSMenu()
            menu.items = [
                item("Add Right Split", 1, .horizontal), item("Add Left Split", 0, .horizontal), .separator(),
                item("Add Top Split", 0, .vertical), item("Add Bottom Split", 1, .vertical),
            ]
            return menu
        } label: {
            Image(systemName: "square.split.2x1")
                .font(.system(size: 14))
                .frame(width: 32, height: 24)
        }
        .buttonStyle(Style())
        .disabled(!model.canAddSplitViewPane)
        .help("Split View Options")
        .accessibilityLabel("Split View Menu")
    }

    private struct Style: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View { Glyph(configuration: configuration) }

        private struct Glyph: View {
            let configuration: Configuration
            @Environment(\.isEnabled) private var isEnabled
            @Environment(\.theme) private var theme
            @State private var hovering = false

            var body: some View {
                let ink: Color = theme.isDark ? .white : .black
                configuration.label
                    .foregroundStyle(isEnabled ? ink.opacity(theme.isDark ? 0.67 : 0.55) : theme.disabledIcon)
                    .background(
                        ink.opacity(fill), in: RoundedRectangle(cornerRadius: 6)
                    )
                    .contentShape(Rectangle())
                    .onHover { hovering = $0 }
                    .animation(.easeOut(duration: 0.14), value: hovering)
            }

            private var fill: Double {
                guard isEnabled else { return 0 }
                if configuration.isPressed { return theme.isDark ? 0.13 : 0.09 }
                return hovering ? (theme.isDark ? 0.09 : 0.05) : 0
            }
        }
    }
}
