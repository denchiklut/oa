import DevKit
import SwiftUI

/// Arc's toolbar along the top of the page, shown by View ▸ Show Toolbar: back, forward and reload at its start,
/// the host in the middle behind copy link, then Site Controls and the Split View menu at its end.
/// It takes the colour of its page's top right corner, as Arc's does, and one view is one page's toolbar.
struct PageToolbar: View {
    /// Arc's key. LIKELY kept across launches as Arc's default is; one setting for every window, as seen in Arc.
    static let key = "topBarURLEnabled"
    static var isShown: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    let model: WindowModel
    @State private var showingSiteControls = false
    /// As Arc's toolbar when its page changes: the page's last colour, else its host's cached one, else white, until
    /// the page's next sample.
    @State private var initialColor: NSColor?
    @Environment(\.theme) private var windowTheme

    init(model: WindowModel) {
        self.model = model
        _initialColor = State(initialValue: model.page.map(model.topBarColors.startingColor))
    }

    var body: some View {
        // Oa's own with no page, where Arc's colours aren't known: the empty card shows through, under the window
        // theme's inks.
        let color = model.page.flatMap { model.topBarColors.appliedColor(for: $0) } ?? initialColor
        let theme = color.map(Theme.init(toolbarOver:)) ?? windowTheme
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 0) {
                    NavigationButtons(page: model.page, size: CGSize(width: 32, height: 24), spacing: 5)
                    Spacer()
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
                        Text(model.addressLabel ?? "Search or Enter URL…")
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .foregroundStyle(model.address == nil ? theme.secondaryText : theme.addressText)
                            .frame(height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Color.clear.frame(width: 24)
                }
                .padding(.horizontal, 130)
            }
            .frame(height: 32)
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
