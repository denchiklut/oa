import DevKit
import SwiftUI

/// Arc's split view in the page's place, as measured: the panes share the card's area by their factors, side by side
/// or stacked, 10 pt apart and none under 220 pt, so panes that don't fit run past the window's edge.
struct SplitViewContentPanes: View {
    /// Arc's `defaultDraggerHandleWidth` and `defaultMinimumPaneWidth`.
    static let draggerHandleWidth: CGFloat = 10
    static let minimumPaneWidth: CGFloat = 220

    let model: WindowModel
    /// The panes' lengths when a drag began, which it adds its translation to.
    @State private var dragStart: [CGFloat]?

    var body: some View {
        let panes = model.splitViewPanes
        let tabIDs = model.presentedTabIDs
        let splitID = model.selectedTabID.flatMap(model.state.splitViewID(containing:))
        let vertical = splitID.flatMap(model.state.splitView)?.layoutOrientation == .vertical
        // Oa's own: equal panes while one is empty. Arc's sizes with an empty pane beside resized ones weren't seen.
        let resizes = panes.count == tabIDs.count
        let equal = panes.map { _ in 1 / CGFloat(panes.count) }
        let shares = resizes ? splitID.map(model.paneShares(of:)) ?? equal : equal
        GeometryReader { geometry in
            let room =
                (vertical ? geometry.size.height : geometry.size.width)
                - Self.draggerHandleWidth * CGFloat(panes.count - 1)
            let lengths = shares.map { max(room * $0, Self.minimumPaneWidth) }
            let layout = vertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
            layout {
                ForEach(Array(panes.enumerated()), id: \.element) { index, pane in
                    Group {
                        switch pane {
                        case .tab(let tabID):
                            SplitViewContentPane(
                                model: model, tabID: tabID, splitID: splitID,
                                width: vertical ? geometry.size.width : lengths[index])
                        case .empty:
                            SplitViewContentPlaceholderView(model: model)
                        }
                    }
                    .frame(width: vertical ? nil : lengths[index], height: vertical ? lengths[index] : nil)
                    if index < panes.count - 1, let splitID, resizes {
                        SplitViewDraggerHandleView(isVertical: vertical)
                            .gesture(
                                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                                    .onChanged { value in
                                        let start = dragStart ?? lengths
                                        dragStart = start
                                        let moved = vertical ? value.translation.height : value.translation.width
                                        if moved != 0 {
                                            resize(splitID, tabIDs, from: start, at: index, by: moved, ended: false)
                                        }
                                    }
                                    .onEnded { value in
                                        let moved = vertical ? value.translation.height : value.translation.width
                                        // A click moves nothing, and leaves a double click's sizes alone.
                                        if moved != 0, let dragStart {
                                            resize(splitID, tabIDs, from: dragStart, at: index, by: moved, ended: true)
                                        }
                                        dragStart = nil
                                    }
                            )
                            // As measured on Arc: a double click gives the two panes beside the handle equal
                            // parts, over about 0.19 s easing out.
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded {
                                    var equal = lengths
                                    equal[index] = (lengths[index] + lengths[index + 1]) / 2
                                    equal[index + 1] = equal[index]
                                    withAnimation(.easeOut(duration: 0.19)) {
                                        model.resizeSplitViewPanes(splitID, to: factors(tabIDs, equal), ended: true)
                                    }
                                }
                            )
                    } else if index < panes.count - 1 {
                        Color.clear.frame(
                            width: vertical ? nil : Self.draggerHandleWidth,
                            height: vertical ? Self.draggerHandleWidth : nil)
                    }
                }
            }
        }
    }

    /// As measured on Arc: the handle follows the pointer with no snapping, and neither pane beside it goes under
    /// the minimum.
    private func resize(
        _ splitID: UUID, _ tabIDs: [UUID], from start: [CGFloat], at index: Int, by moved: CGFloat, ended: Bool
    ) {
        var lengths = start
        let total = start[index] + start[index + 1]
        lengths[index] = min(max(start[index] + moved, Self.minimumPaneWidth), total - Self.minimumPaneWidth)
        lengths[index + 1] = total - lengths[index]
        model.resizeSplitViewPanes(splitID, to: factors(tabIDs, lengths), ended: ended)
    }

    private func factors(_ tabIDs: [UUID], _ lengths: [CGFloat]) -> [UUID: CGFloat] {
        let total = lengths.reduce(0, +)
        return Dictionary(uniqueKeysWithValues: zip(tabIDs, lengths.map { $0 / total }))
    }
}

/// Arc's `SplitViewDraggerHandleView` as measured: the gap between two panes, with a 2 × 24 pt grip in its middle
/// that brightens under the pointer, and the resize cursor over it.
private struct SplitViewDraggerHandleView: View {
    let isVertical: Bool
    @State private var hovering = false
    @Environment(\.windowColorScheme) private var colorScheme

    var body: some View {
        // As measured over Arc's default theme: white 29 % and 56 % under the pointer in dark, black 19 % in light,
        // where its hover wasn't measured.
        let dark = colorScheme == .dark
        let ink = dark ? Color.white.opacity(hovering ? 0.56 : 0.29) : Color.black.opacity(hovering ? 0.37 : 0.19)
        let width = SplitViewContentPanes.draggerHandleWidth
        Color.clear
            .frame(width: isVertical ? nil : width, height: isVertical ? width : nil)
            .overlay {
                Capsule().fill(ink).frame(width: isVertical ? 24 : 2, height: isVertical ? 2 : 24)
            }
            .contentShape(Rectangle())
            // Arc's `grabberHoverAnimationDuration`.
            .animation(.easeOut(duration: 0.16), value: hovering)
            .onHover { inside in
                hovering = inside
                if inside { (isVertical ? NSCursor.resizeUpDown : .resizeLeftRight).push() } else { NSCursor.pop() }
            }
    }
}

/// A pane as measured on Arc: its bar over its page in a card of its own, and on the focused one a 2 pt outline
/// inside the card's edge with a glow into the gaps beside it.
private struct SplitViewContentPane: View {
    let model: WindowModel
    let tabID: UUID
    let splitID: UUID?
    let width: CGFloat
    @Environment(\.windowColorScheme) private var colorScheme

    var body: some View {
        let page = model.pages[tabID]
        // As seen in Arc: no pane is outlined while the empty one waits for the command bar.
        let focused = model.selectedTabID == tabID && model.emptySplitViewPaneIndex == nil
        let dark = colorScheme == .dark
        // LIKELY 10 pt: read off one corner of Arc's pane.
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(spacing: 0) {
            ContentPanelTopBar(model: model, tabID: tabID, splitID: splitID, isFocused: focused, width: width)
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
/// it, back and forward at its start, the host in the middle, the whole address in a stacked split, and the ✕ that
/// closes the pane's tab at its end, on every pane. On the focused pane, reload while it has the room and the Split
/// View menu before the ✕.
struct ContentPanelTopBar: View {
    /// Oa's own cut: Arc's pane had no reload at 278 pt and one at 421 pt.
    static let reloadMinimumWidth: CGFloat = 300

    let model: WindowModel
    let tabID: UUID
    let splitID: UUID?
    let isFocused: Bool
    let width: CGFloat
    @State private var initialColor: NSColor?
    @Environment(\.theme) private var windowTheme

    init(model: WindowModel, tabID: UUID, splitID: UUID?, isFocused: Bool, width: CGFloat) {
        self.model = model
        self.tabID = tabID
        self.splitID = splitID
        self.isFocused = isFocused
        self.width = width
        _initialColor = State(initialValue: model.pages[tabID].map(model.topBarColors.startingColor))
    }

    var body: some View {
        let page = model.pages[tabID]
        let color = page.flatMap { model.topBarColors.appliedColor(for: $0) } ?? initialColor
        let theme = color.map(Theme.init(toolbarOver:)) ?? windowTheme
        let showsReload = isFocused && width >= Self.reloadMinimumWidth
        let vertical = splitID.flatMap(model.state.splitView)?.layoutOrientation == .vertical
        ZStack {
            HStack(spacing: 0) {
                NavigationButtons(
                    page: page, size: CGSize(width: 32, height: 24), spacing: 5, showsReload: showsReload)
                Spacer()
                if isFocused, let splitID { splitViewMenu(splitID, vertical: vertical) }
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
                Text(model.addressLabel(of: tabID, whole: vertical) ?? "Search or Enter URL…")
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

    /// Arc's Split View Options, as seen: its items follow the split's orientation, a pane at an end can't move past
    /// it, a full split takes no pane, and Share Split View… isn't here.
    private func splitViewMenu(_ splitID: UUID, vertical: Bool) -> some View {
        let tabIDs = model.state.presentedTabIDs(with: tabID)
        let index = tabIDs.firstIndex(of: tabID) ?? 0
        return Menu {
            Button(vertical ? "Move Up" : "Move Left", systemImage: vertical ? "arrow.up.square" : "arrow.left.square")
            { model.moveSplitViewPane(tabID, by: -1) }
            .disabled(tabIDs.first == tabID)
            Button(
                vertical ? "Move Down" : "Move Right",
                systemImage: vertical ? "arrow.down.square" : "arrow.right.square"
            ) { model.moveSplitViewPane(tabID, by: 1) }
            .disabled(tabIDs.last == tabID)
            Divider()
            // As seen in Arc: after the pane first, then before it.
            Button(
                vertical ? "Add Top Split" : "Add Right Split",
                systemImage: vertical ? "rectangle.tophalf.inset.filled" : "rectangle.righthalf.inset.filled"
            ) { model.addSplitViewPane(at: vertical ? index : index + 1) }
            .disabled(!model.canAddSplitViewPane)
            Button(
                vertical ? "Add Bottom Split" : "Add Left Split",
                systemImage: vertical ? "rectangle.bottomhalf.inset.filled" : "rectangle.lefthalf.inset.filled"
            ) { model.addSplitViewPane(at: vertical ? index + 1 : index) }
            .disabled(!model.canAddSplitViewPane)
            Divider()
            Button("Separate Tab from Split", systemImage: "rectangle.portrait.and.arrow.right") {
                model.separateFromSplitView(tabID)
            }
            Button(
                vertical ? "Convert to Horizontal Split View" : "Convert to Vertical Split View",
                systemImage: vertical ? "square.split.2x1" : "square.split.1x2"
            ) { model.flipSplitViewLayoutOrientation(splitID) }
        } label: {
            Image(systemName: "square.split.2x1")
                .font(.system(size: 14))
                .frame(width: 32, height: 24)
        }
        .menuStyle(.button)
        .buttonStyle(ChromeButtonStyle())
        .menuIndicator(.hidden)
        .labelStyle(.titleAndIcon)
        .accessibilityLabel("Split View Menu")
        .fixedSize()
    }
}

/// Arc's `SplitViewContentPlaceholderView` as seen: the empty pane Add Split View opens, in the empty card's fill,
/// with the prompt in its bar, back and forward off, and a ✕ that takes it away.
private struct SplitViewContentPlaceholderView: View {
    let model: WindowModel
    @Environment(\.windowColorScheme) private var colorScheme
    @Environment(\.theme) private var theme

    var body: some View {
        let dark = colorScheme == .dark
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 0) {
                    NavigationButtons(page: nil, size: CGSize(width: 32, height: 24), spacing: 5, showsReload: false)
                    Spacer()
                    Button {
                        model.closeCommandBar()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13))
                            .frame(width: 32, height: 24)
                    }
                    .buttonStyle(ChromeButtonStyle())
                    .accessibilityLabel("Close Split View Pane")
                }
                .padding(.horizontal, 5)
                Text("Search or Enter URL…")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(theme.addressText)
                    .padding(.horizontal, 79)
            }
            .frame(height: 32)
            (dark ? Color.white : .black).opacity(0.05).frame(height: 1)
            Color.clear
        }
        .background(Color.white.opacity(dark ? 0.1 : 0.666))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
