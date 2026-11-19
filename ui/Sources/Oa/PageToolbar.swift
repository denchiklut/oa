import SwiftUI

/// Arc's toolbar along the top of the page, shown by View ▸ Show Toolbar: back, forward and reload at its start,
/// the host in the middle behind copy link, Site Controls 41 pt from its end, where Arc's Split View button follows.
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
        let colors = model.topBarColors
        _initialColor = State(
            initialValue: model.page.map { colors.appliedColor(for: $0) ?? colors.cachedColor(for: $0) ?? .white })
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
                }
                .padding(.leading, 5)
                .padding(.trailing, 41)
                // The host is centred: Arc balances copy link with a second button after it.
                HStack(spacing: 3) {
                    CopyLinkButton(model: model, size: 24)
                        .opacity(model.address == nil ? 0 : 1)
                    // As Arc: the URL opens the command bar to edit it, rather than being edited in place.
                    Button {
                        model.openCommandBar(.currentTab)
                    } label: {
                        Text(model.addressLabel ?? "Search or Enter URL…")
                            .font(.system(size: 13, weight: .semibold))
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
