import DevKit
import SwiftUI

/// Arc's split view in the page's place, as measured: the panes share the card's area by their factors, 10 pt apart
/// and none under 220 pt, so panes that don't fit run past the window's edge.
struct SplitViewContentPanes: View {
    /// Arc's `defaultDraggerHandleWidth` and `defaultMinimumPaneWidth`.
    static let draggerHandleWidth: CGFloat = 10
    static let minimumPaneWidth: CGFloat = 220

    let model: WindowModel
    let splitID: UUID

    var body: some View {
        let tabIDs = model.presentedTabIDs
        let shares = model.state.splitView(splitID)?.shares(of: tabIDs) ?? []
        GeometryReader { geometry in
            let room = geometry.size.width - Self.draggerHandleWidth * CGFloat(tabIDs.count - 1)
            HStack(spacing: Self.draggerHandleWidth) {
                ForEach(Array(zip(tabIDs, shares)), id: \.0) { tabID, share in
                    let width = max(room * share, Self.minimumPaneWidth)
                    SplitViewContentPane(model: model, tabID: tabID, width: width)
                        .frame(width: width)
                }
            }
        }
    }
}

/// A pane as measured on Arc: its bar over its page in a card of its own, and on the focused one a 2 pt outline
/// inside the card's edge with a glow into the gaps beside it.
private struct SplitViewContentPane: View {
    let model: WindowModel
    let tabID: UUID
    let width: CGFloat
    @Environment(\.windowColorScheme) private var colorScheme

    var body: some View {
        let page = model.pages[tabID]
        let focused = model.selectedTabID == tabID
        let dark = colorScheme == .dark
        // LIKELY 10 pt: read off one corner of Arc's pane.
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(spacing: 0) {
            ContentPanelTopBar(model: model, tabID: tabID, isFocused: focused, width: width)
                .id(page?.id)
                .zIndex(1)
            if let placeholder = model.placeholder(for: tabID) {
                PlaceholderView(image: placeholder)
            } else if let page {
                // A pane's host is made once its page is, after the window activated the page: the focused pane's
                // page takes the keyboard when the host is in the window.
                PageContentView(page: page) { model.activatePresented(page) }
                    .toast(of: model, on: page).pageRootBackground(page)
            } else {
                Color.clear
            }
        }
        .background(dark ? Color.black : .white)
        .clipShape(shape)
        .onChange(of: page?.id, initial: true) { _, _ in model.trackPaneToolbarPage(tabID, shown: true) }
        .onDisappear { model.trackPaneToolbarPage(tabID, shown: false) }
        .overlay {
            if focused { shape.strokeBorder(focusColor(dark: dark), lineWidth: 2) }
        }
        // As measured on Arc's default theme: beside the focused pane the gap is lighter by white 18 % at the pane's
        // edge and 5 % at 9 pt in dark, and darker by black 7 % at the edge in light. An unfocused pane keeps the
        // card's shadow.
        .background {
            shape
                .padding(1)
                .shadow(
                    color: focused ? (dark ? .white.opacity(0.44) : .black.opacity(0.17)) : .black.opacity(0.3),
                    radius: focused ? 9.5 : 4, y: focused ? 0 : 1)
        }
    }

    /// As measured on Arc's default theme, #2F39FF in dark and #1F2AFF in light: its palette's shaded and darkest
    /// entries. LIKELY the same entries on other themes, which weren't measured.
    private func focusColor(dark: Bool) -> Color {
        let palette = (model.space.map(model.theme(of:)) ?? .default).primaryColorPalette
        return (dark ? palette.shaded : palette.shadedDark).color
    }
}

/// Arc's `ContentPanel` bar on a split's pane, as measured: 32 pt in its page's colour as the window's toolbar takes
/// it, back and forward at its start, the host in the middle and the ✕ that closes the pane's tab at its end, on every
/// pane. Reload shows on the focused pane while it has the room.
struct ContentPanelTopBar: View {
    /// Oa's own cut: Arc's pane had no reload at 278 pt and one at 421 pt.
    static let reloadMinimumWidth: CGFloat = 300

    let model: WindowModel
    let tabID: UUID
    let isFocused: Bool
    let width: CGFloat
    @State private var initialColor: NSColor?
    @Environment(\.theme) private var windowTheme

    init(model: WindowModel, tabID: UUID, isFocused: Bool, width: CGFloat) {
        self.model = model
        self.tabID = tabID
        self.isFocused = isFocused
        self.width = width
        _initialColor = State(initialValue: model.pages[tabID].map(model.topBarColors.startingColor))
    }

    var body: some View {
        let page = model.pages[tabID]
        let color = page.flatMap { model.topBarColors.appliedColor(for: $0) } ?? initialColor
        let theme = color.map(Theme.init(toolbarOver:)) ?? windowTheme
        let showsReload = isFocused && width >= Self.reloadMinimumWidth
        ZStack {
            HStack(spacing: 0) {
                NavigationButtons(
                    page: page, size: CGSize(width: 32, height: 24), spacing: 5, showsReload: showsReload)
                Spacer()
                Button {
                    model.close(tabID)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13))
                        .frame(width: 32, height: 24)
                }
                .buttonStyle(ChromeButtonStyle())
                .accessibilityLabel("Close Split View Pane")
            }
            .padding(.horizontal, 5)
            // As Arc: the URL opens the command bar on its pane's tab.
            Button {
                model.select(tabID)
                model.openCommandBar(.currentTab)
            } label: {
                Text(model.addressLabel(of: tabID) ?? "Search or Enter URL…")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .foregroundStyle(page?.url == nil ? theme.secondaryText : theme.addressText)
                    .frame(height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, showsReload ? 116 : 79)
        }
        .frame(height: 32)
        .environment(\.theme, theme)
        // Oa's own: a click on the bar focuses its pane, as a click on its page does.
        .background {
            (color.map { Color(nsColor: $0) } ?? .clear)
                .contentShape(Rectangle())
                .onTapGesture { model.select(tabID) }
        }
        // As measured on Arc: a line over the page's first row, lighter on a dark bar.
        .overlay(alignment: .bottom) {
            (theme.isDark ? Color.white : .black).opacity(0.05).frame(height: 1).offset(y: 1)
        }
        .animation(.easeInOut(duration: 0.18), value: color)
    }
}
