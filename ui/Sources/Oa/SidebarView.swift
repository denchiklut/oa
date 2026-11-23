import DevKit
import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    let model: WindowModel
    let layout: WindowLayoutController
    @State private var overLibraryButton = false
    @State private var overFlyout = false
    @State private var showingFlyout = false
    @State private var pointerInside = false

    var body: some View {
        VStack(spacing: 0) {
            SidebarHeader(model: model, layout: layout)
            SidebarPagingContainerView(model: model, layout: layout)
            spaces
        }
        .overlay(alignment: .trailing) {
            EdgeFeedbackView(progress: layout.spaceCreationPull.progress, reveal: layout.spaceCreationPull.reveal)
        }
        .overlay(alignment: .bottomLeading) {
            if showingFlyout {
                DownloadsFlyout(model: model)
                    .onHover { overFlyout = $0 }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 40)
            }
        }
        // As Arc's hover regions: the button or the flyout keeps it up, and it outlasts the gap between them.
        .onChange(of: overLibraryButton || overFlyout) { _, over in
            guard !over else { return showingFlyout = true }
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                if !overLibraryButton, !overFlyout { showingFlyout = false }
            }
        }
        // The sidebar stays mounted under the Library, where the pointer's leaving isn't reported.
        .onChange(of: model.library == nil) {
            overLibraryButton = false
            overFlyout = false
            showingFlyout = false
            pointerInside = false
        }
        .frame(width: layout.sidebarWidth, alignment: .leading)
        .onHover { pointerInside = $0 }
        // As Arc: the floating panel brings them in with it.
        .environment(\.sidebarRevealsControls, pointerInside || layout.sidebarPresentation == .floating)
        .animation(.easeInOut(duration: 0.19), value: pointerInside)
    }

    /// Arc's dock as measured: 8 pt in from the sidebar's edges, a 32 pt Library button and plus with the Space items
    /// 2 pt from them, centred 25 pt above the bottom. On the Create a Space page the Library button and the plus go.
    /// Oa's own, by the author's decision: they fade in place as the Create a Space slot comes in, as open-arch's.
    private var spaces: some View {
        let creation = layout.dockSpaceCreationProgress
        // As measured in open-arch's recording: its disabled buttons sit at 0.86 of their fade while the panel is in.
        let fade = (1 - creation) * (model.spaceCreation == nil ? 1 : 0.86)
        return HStack(spacing: 2) {
            LibraryButton(model: model)
                .modifier(DockHoverFill())
                .onHover { overLibraryButton = $0 }
                .opacity(fade)
                .allowsHitTesting(creation == 0)
            SidebarDock(model: model, layout: layout)
            SidebarPlusButton(model: model, layout: layout)
                .modifier(DockHoverFill())
                .opacity(fade)
                .allowsHitTesting(creation == 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }
}

/// As Arc's: the Library button and the plus take the Space items' hover fill.
private struct DockHoverFill: ViewModifier {
    @State private var hovered = false
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(theme.dockHoverFill)
                    .opacity(hovered ? 1 : 0)
            }
            .onHover { hovered = $0 }
            .animation(.easeInOut(duration: 0.25), value: hovered)
    }
}

extension EnvironmentValues {
    /// Arc's one "pointer is in the sidebar" state, which shows the URL field's buttons and Clear together.
    @Entry var sidebarRevealsControls = false
}

@MainActor
enum SpaceDeletion {
    static func confirm(_ space: SidebarSpace, in model: WindowModel) {
        if !model.state.tabs(in: space.id).isEmpty {
            let alert = NSAlert()
            alert.messageText = "Delete your “\(space.name)” Space?"
            alert.informativeText = "This will archive all the tabs inside it."
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        model.deleteSpace(space.id)
    }
}

/// Arc's `SidebarDockView`: one item per sidebar page, so the Create a Space panel's too at its slot. Each slot is
/// clamp(width / items, 8, 34) wide and 32 tall, and the row is centred. Below 22 the dock is compact: the current and
/// the hovered item take 22 and the others share the rest, at least 8 each, scrolling once they don't fit.
/// Oa's own, by the author's choice: the current item keeps its icon and slot while another is hovered, where Arc's
/// becomes a 4 pt dot and gives the hovered one its slot.
private struct SidebarDock: View {
    let model: WindowModel
    let layout: WindowLayoutController
    @State private var hovered: WindowLayoutPage?

    /// Where the Create a Space slot last was, so it collapses there.
    @State private var creationIndex = 0

    var body: some View {
        let pages = layout.sidebarPages
        let page = layout.sidebarPage
        let creation = layout.dockSpaceCreationProgress
        // Oa's own, by the author's decision, as open-arch: the Create a Space slot stays, at no width while the panel
        // is closed, and grows with the dock's progress, the Spaces re-centring around it, where Arc's comes and goes
        // with the page.
        let items = self.items
        let transition = layout.dockSelectionTransition(in: pages)
        let current =
            transition?.current
            ?? (pages.isEmpty ? nil : pages[Int(min(max(page.rounded(), 0), CGFloat(pages.count - 1)))])
        let wide = hovered == nil || hovered == current ? 1 : 2
        GeometryReader { geometry in
            let normal = Slots(width: geometry.size.width, count: items.count - 1, wide: wide)
            let open = Slots(width: geometry.size.width, count: items.count, wide: wide)
            let compact = (creation < 0.5 ? normal : open).compact
            let row = HStack(spacing: 0) {
                ForEach(items, id: \.self) { item in
                    let isHovered = hovered == item
                    let isCreation = item == .spaceCreation
                    let isWide = item == current || isHovered
                    // As Arc: in the compact dock the hovered item is drawn as the current one. As open-arch, the
                    // Spaces dim as the Create a Space slot comes in, and its dot is the current one.
                    let paged =
                        transition.map { $0.selection[item, default: 0] }
                        ?? pages.firstIndex(of: item).map { max(0, 1 - abs(page - CGFloat($0))) } ?? 0
                    let selection = compact && isHovered || isCreation ? 1 : min(paged, 1 - creation)
                    let width =
                        isCreation
                        ? open.width(isWide) * creation
                        : normal.width(isWide) + (open.width(isWide) - normal.width(isWide)) * creation
                    SidebarDockItem(
                        model: model, layout: layout, item: item, selection: selection, isHovered: isHovered,
                        compact: compact
                    )
                    .scaleEffect(isCreation ? 0.5 + 0.5 * creation : 1)
                    .opacity(isCreation ? creation : 1)
                    .frame(width: width, height: 32)
                    .onHover { inside in hovered = inside ? item : hovered == item ? nil : hovered }
                }
            }
            if normal.total + (open.total - normal.total) * creation <= geometry.size.width {
                row.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // As Arc's: a Space change centres the current item over 0.16 s. Oa's own, by the author's choice:
                // it is centred at once as the dock appears or resizes too, where Arc's stays at the start.
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) { row }
                        .onAppear { proxy.scrollTo(WindowLayoutPage.space(model.selectedSpaceID), anchor: .center) }
                        .onChange(of: geometry.size.width) {
                            proxy.scrollTo(WindowLayoutPage.space(model.selectedSpaceID), anchor: .center)
                        }
                        .onChange(of: model.selectedSpaceID) { _, id in
                            withAnimation(.easeOut(duration: 0.16)) {
                                proxy.scrollTo(WindowLayoutPage.space(id), anchor: .center)
                            }
                        }
                }
            }
        }
        .frame(height: 32)
        .onChange(of: model.spaceCreationIndex) { _, index in
            if let index { creationIndex = index }
        }
    }

    private var items: [WindowLayoutPage] {
        var items = model.state.spaces.map { WindowLayoutPage.space($0.id) }
        items.insert(.spaceCreation, at: min(model.spaceCreationIndex ?? creationIndex, items.count))
        return items
    }

    private struct Slots {
        let unit: CGFloat
        let other: CGFloat
        let compact: Bool
        let total: CGFloat

        init(width: CGFloat, count: Int, wide: Int) {
            let n = CGFloat(max(count, 1))
            let wide = CGFloat(min(wide, count))
            unit = min(max(width / n, 8), 34)
            compact = unit < 22
            other = n > wide ? max((width - 22 * wide) / (n - wide), 8) : 22
            total = compact ? 22 * wide + other * (n - wide) : unit * n
        }

        func width(_ wide: Bool) -> CGFloat { compact ? (wide ? 22 : other) : unit }
    }
}

/// Arc's `SidebarDockItemView`. A Space's icon cross-fades between a grey resting copy and an active one in the
/// Space's own theme colour; a Space without an icon is a dot. `selection` is how far the item is the current one.
private struct SidebarDockItem: View {
    let model: WindowModel
    let layout: WindowLayoutController
    let item: WindowLayoutPage
    let selection: CGFloat
    let isHovered: Bool
    let compact: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        switch item {
        case .space(let id):
            if let space = model.state.space(id) {
                Button {
                    model.selectSpace(space.id)
                } label: {
                    content(icon: space.icon, tint: tint(space))
                }
                .buttonStyle(PressStyle())
                .help(space.name)
                .accessibilityLabel(space.name)
                .spaceContextMenu(isEnabled: !model.coversWindow) {
                    SpaceMenu(model: model, layout: layout, space: space)
                }
            }
        case .spaceCreation:
            content(icon: nil, tint: theme.dockInk).accessibilityLabel("New Space")
        case .home:
            EmptyView()
        }
    }

    /// As Arc's `LayoutTraits`.
    private func content(icon: String?, tint: Color) -> some View {
        let rest = theme.dockRestAlpha
        let highlight = isHovered ? 0.7 : rest
        return ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(theme.dockHoverFill)
                .opacity(isHovered && !compact ? 1 : 0)
            if compact && selection <= 0 && !isHovered {
                Circle().fill(theme.dockInk).frame(width: 4, height: 4).opacity(rest)
            } else if let icon {
                let active = (isHovered ? 0.7 : 0) + selection * (1 - (isHovered ? 0.7 : 0))
                ZStack {
                    SpaceIconGlyph(icon: icon)
                        .foregroundStyle(theme.dockInk)
                        .modifier(RestingEmoji(isEmoji: !icon.allSatisfy(\.isASCII), isDark: theme.isDark))
                        .opacity((isHovered ? 0 : rest) * (1 - selection))
                    SpaceIconGlyph(icon: icon).foregroundStyle(tint).opacity(active)
                }
                .font(.system(size: 13, weight: .semibold))
            } else {
                Circle().fill(theme.dockInk).frame(width: 8, height: 8).opacity(highlight + selection * (1 - highlight))
            }
        }
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.25), value: isHovered)
    }

    /// As measured on Arc, the hovered or current icon takes its own Space's `maxContrastColor`, not the window's.
    /// Oa's own: a Space without a theme stays grey, as Arc's icon colour is optional and its source isn't traced.
    private func tint(_ space: SidebarSpace) -> Color {
        guard let windowTheme = model.customTheme(of: space) else { return theme.dockInk }
        return windowTheme.semanticColorPalette[theme.isDark ? .dark : .light].maxContrastColor.color
    }

    private struct PressStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .animation(.timingCurve(0.215, 0.61, 0.355, 1, duration: 0.13), value: configuration.isPressed)
        }
    }

    /// Arc draws a resting emoji through `CIColorMonochrome` in grey 0.5 (light) or 0.8 (dark).
    private struct RestingEmoji: ViewModifier {
        let isEmoji: Bool
        let isDark: Bool

        func body(content: Content) -> some View {
            if isEmoji {
                content.grayscale(1).colorMultiply(Color(white: isDark ? 0.8 : 0.5))
            } else {
                content
            }
        }
    }
}

/// Arc's grid (`AppTrayCollectionViewLayout`): tiles 47 pt tall with 8 pt gaps filling the row, at most four and
/// never narrower than 47 pt; columns from the count as `rows = ⌈n / most⌉`, `cols = ⌈n / rows⌉`, the last row
/// left-aligned. While a drag is over it, the grid makes the slot it would land in and the tiles slide to their new
/// places as Arc's do.
struct FavoritesGrid: View {
    struct Layout {
        let rows: Int
        let columns: Int
        let tileWidth: CGFloat

        init(count: Int, width: CGFloat) {
            let most = min(4, max(1, Int((width - 8) / 55)))
            rows = max(1, (count + most - 1) / most)
            columns = max(1, (count + rows - 1) / rows)
            tileWidth = (width - 16 - CGFloat(columns - 1) * 8) / CGFloat(columns)
        }

        var height: CGFloat { CGFloat(rows) * 47 + CGFloat(rows - 1) * 8 }

        func origin(of index: Int) -> CGPoint {
            CGPoint(x: CGFloat(index % columns) * (tileWidth + 8), y: CGFloat(index / columns) * 55)
        }
    }

    struct Slot: Identifiable {
        static let gapID = UUID()
        let id: UUID
        let tab: SidebarTab?
        var splitTabs: [SidebarTab]?
        /// The dragged tile: out of the layout but mounted, so its drag goes on.
        var isLifted = false

        init(id: UUID, tab: SidebarTab?, splitTabs: [SidebarTab]? = nil, isLifted: Bool = false) {
            self.id = id
            self.tab = tab
            self.splitTabs = splitTabs
            self.isLifted = isLifted
        }

        init(_ entry: SidebarEntry) {
            switch entry {
            case .tab(let tab): self.init(id: tab.id, tab: tab)
            case .splitView(let id, let tabs): self.init(id: id, tab: nil, splitTabs: tabs)
            }
        }
    }

    let model: WindowModel
    let layout: WindowLayoutController
    let slots: [Slot]

    /// The tiles as the drag leaves them: a dragged tile has left its place, and the slot opens where it would land.
    static func slots(_ favorites: [SidebarEntry], drag: SidebarDrag?) -> [Slot] {
        guard let drag, let dragged = drag.entry else { return favorites.map(Slot.init) }
        var slots = favorites.filter { $0.id != dragged.id }.map(Slot.init)
        if let target = drag.target, target.section == .favorites {
            slots.insert(Slot(id: Slot.gapID, tab: nil), at: min(target.index, slots.count))
        }
        if favorites.contains(where: { $0.id == dragged.id }) {
            var lifted = Slot(dragged)
            lifted.isLifted = true
            slots.append(lifted)
        }
        return slots
    }

    /// What the grid takes of the sidebar's height, so a Space's page starts under its profile's grid. It changes at
    /// once, so the list jumps as Arc's does.
    static func height(for count: Int, in width: CGFloat) -> CGFloat {
        Layout(count: count, width: width).height
    }

    @Environment(\.sidebarDrag) private var drag

    var body: some View {
        let shown = slots.filter { !$0.isLifted }
        let grid = Layout(count: shown.count, width: layout.sidebarWidth)
        ZStack(alignment: .topLeading) {
            if shown.isEmpty {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .foregroundStyle(.quaternary)
                    .frame(width: 47, height: 47)
            }
            ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                let origin = grid.origin(of: slot.isLifted ? 0 : index)
                Group {
                    if let tab = slot.tab {
                        FavoriteTile(model: model, layout: layout, tab: tab, width: grid.tileWidth)
                    } else if let tabs = slot.splitTabs {
                        FavoriteSplitTile(
                            model: model, layout: layout, splitID: slot.id, tabs: tabs, width: grid.tileWidth)
                    } else {
                        Color.clear.sidebarDragFrame { drag?.gap = $0 }
                    }
                }
                .frame(width: grid.tileWidth, height: 47)
                .padding(.leading, origin.x)
                .padding(.top, origin.y)
                .opacity(slot.isLifted ? 0 : 1)
            }
        }
        .animation(.spring(response: 0.23, dampingFraction: 1), value: shown.map(\.id))
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: grid.height, alignment: .top)
    }
}

/// Arc's `AppTrayItemViewAppKit`, back to front: the selected white card and its shadow, the favicon's tint, the
/// body's fill (none when selected), the selection ring and the favicon. A tile has no button and no tooltip.
private struct FavoriteTile: View {
    let model: WindowModel
    let layout: WindowLayoutController
    let tab: SidebarTab
    let width: CGFloat
    @State private var hovering = false
    @State private var pressed = false
    @State private var pickingIcon = false
    @Environment(\.theme) private var theme
    @Environment(\.sidebarDrag) private var drag

    var body: some View {
        let selected = model.selectedTabID == tab.id
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        // As seen in Arc: the icon takes the favicon's place, and the selected tile's tint and ring follow its colour.
        let favicon = tab.icon.map(TabIconImage.image(for:)) ?? model.favicon(for: tab)
        ZStack {
            shape.fill(selected ? theme.selectedTile : .clear)
                .shadow(color: .black.opacity(selected ? 0.1 : 0), radius: 2, y: 1)
            if let favicon, selected {
                AppTrayVisualEffect(favicon: favicon, tileWidth: width)
                    .opacity(theme.isDark ? (hovering ? 0.3 : 0.2) : (hovering ? 0.1 : 0))
                    .animation(.easeOut(duration: 0.12), value: hovering)
                AppTrayRing(favicon: favicon, tileWidth: width)
            }
            shape.fill(selected ? .clear : hovering ? theme.itemHoveredFill : theme.itemFill)
                .animation(.easeOut(duration: hovering ? 0.14 : 0.1), value: hovering)
            if let favicon {
                Image(nsImage: favicon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .frame(width: width, height: 47)
        .overlay(alignment: .topTrailing) {
            if let peek = model.peeks[tab.id] { PeekBadge(favicon: peek.favicon).offset(x: 5, y: -5) }
        }
        // Arc's tiles carry the recording dot too (AppTray's `recordingIndicatorView`); the corner is Oa's own.
        .overlay(alignment: .topLeading) {
            if model.isRecording(tab) { RecordingDot().padding(6) }
        }
        .contentShape(shape)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(SidebarDrag.space))
                .onChanged { value in
                    if !pressed {
                        pressed = true
                        model.select(tab.id)
                    }
                    drag?.update(
                        .tab(tab), from: .favorites, glyph: .close, at: value.location, start: value.startLocation,
                        model: model, layout: layout)
                }
                .onEnded { _ in
                    pressed = false
                    drag?.finish(model: model, layout: layout)
                }
        )
        .popover(isPresented: $pickingIcon, arrowEdge: .bottom) {
            SpaceIconPicker(selection: tab.icon) { model.setTabIcon(tab.id, to: $0) }
        }
        .onHover { hovering = $0 }
        .sidebarDragFrame { drag?.tiles[tab.id] = $0 }
        .platformContextMenu(isEnabled: model.library == nil && !model.coversWindow) {
            TabContextMenu(model: model, tab: tab) { Task { pickingIcon = true } }.make()
        }
    }
}

/// A split Favorite as seen in Arc: one tile with a 12 pt favicon centred on each pane's part. Selected, one card with
/// the panes' favicons' tint and ring, the ring also between the parts; not selected, a card for each part, 2 pt apart.
/// A press selects the split with the pane the window focused in it last, and drags it whole as a tile's does.
private struct FavoriteSplitTile: View {
    let model: WindowModel
    let layout: WindowLayoutController
    let splitID: UUID
    let tabs: [SidebarTab]
    let width: CGFloat
    @State private var hovering = false
    @State private var pressed = false
    @State private var pickingIcon = false
    @Environment(\.theme) private var theme
    @Environment(\.sidebarDrag) private var drag

    var body: some View {
        let selected = tabs.contains { $0.id == model.selectedTabID }
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let favicons = tabs.map(model.favicon(for:))
        let data = model.state.splitView(splitID)
        ZStack {
            // As seen in Arc: a split Favorite with an icon is one tile with only the icon. Its look selected, with
            // no favicon to tint by, is Oa's own.
            if let icon = data?.icon {
                shape.fill(selected ? theme.selectedTile : hovering ? theme.itemHoveredFill : theme.itemFill)
                    .shadow(color: .black.opacity(selected ? 0.1 : 0), radius: 2, y: 1)
                SpaceIconGlyph(icon: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.secondaryGlyph)
            } else if selected {
                shape.fill(theme.selectedTile).shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                SplitAppTrayVisualEffect(favicons: favicons, tileWidth: width)
                    .opacity(theme.isDark ? (hovering ? 0.3 : 0.2) : (hovering ? 0.1 : 0))
                SplitAppTrayRing(favicons: favicons, tileWidth: width)
            } else {
                HStack(spacing: 2) {
                    ForEach(tabs) { _ in shape.fill(hovering ? theme.itemHoveredFill : theme.itemFill) }
                }
                .animation(.easeOut(duration: hovering ? 0.14 : 0.1), value: hovering)
            }
            HStack(spacing: 2) {
                ForEach(data?.icon == nil ? tabs : []) { tab in
                    Group {
                        if let favicon = model.favicon(for: tab) {
                            Image(nsImage: favicon)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 12, height: 12)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(width: width, height: 47)
        .contentShape(shape)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(SidebarDrag.space))
                .onChanged { value in
                    if !pressed {
                        pressed = true
                        model.selectSplitView(splitID)
                    }
                    drag?.update(
                        .splitView(id: splitID, tabs: tabs), from: .favorites, glyph: .close, at: value.location,
                        start: value.startLocation, model: model, layout: layout)
                }
                .onEnded { _ in
                    pressed = false
                    drag?.finish(model: model, layout: layout)
                }
        )
        .popover(isPresented: $pickingIcon, arrowEdge: .bottom) {
            SpaceIconPicker(selection: data?.icon) { model.setSplitViewIcon(splitID, to: $0) }
        }
        .onHover { hovering = $0 }
        .sidebarDragFrame { drag?.tiles[splitID] = $0 }
        .contextMenu {
            // As seen in Arc's tile menu: no Rename… and no Remove Favorite; Archive Item archives its tabs.
            Button("Share Split View…") {}.disabled(true)
            Divider()
            Button("Separate All Tabs") { model.separateAllSplitViewChildren(splitID) }
            Button("Add Tab…") {}.disabled(true)
            Button(
                model.state.splitView(splitID)?.layoutOrientation == .vertical
                    ? "Convert to Horizontal Split View" : "Convert to Vertical Split View"
            ) { model.flipSplitViewLayoutOrientation(splitID) }
            Section("Tab Options") {
                ForEach(tabs) { tab in
                    Menu(model.title(for: tab)) {
                        Button("Separate from Split View") { model.separateFromSplitView(tab.id) }
                    }
                }
            }
            Divider()
            if data?.title != nil || data?.icon != nil {
                Button("Reset Name and Icon") { model.resetSplitViewNameAndIcon(splitID) }
            }
            Button("Change Icon…") { Task { pickingIcon = true } }
            Divider()
            // LIKELY as the cell's: the copy right after it, among the Favorites.
            Button("Duplicate") { model.duplicateSplitView(splitID) }
            SplitViewMoveMenu(model: model, splitID: splitID)
            Divider()
            Button("Archive Item") { model.closeSplitView(splitID) }
        }
    }
}

/// Arc's `ModalV2SidebarBadgeView`; with no favicon, the grey square measured in Arc.
private struct PeekBadge: View {
    private static let emptyFavicon = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(displayP3Red: 119 / 255, green: 118 / 255, blue: 130 / 255, alpha: 1)
                : NSColor(displayP3Red: 195 / 255, green: 194 / 255, blue: 196 / 255, alpha: 1)
        })

    let favicon: NSImage?

    var body: some View {
        Group {
            if let favicon {
                Image(nsImage: favicon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Self.emptyFavicon)
                    .frame(width: 14, height: 14)
            }
        }
        .frame(width: 24, height: 24)
        .background(ARCUIColor.grayA4, in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Arc's recording dot, before the favicon while the tab's page uses the camera or microphone.
private struct RecordingDot: View {
    var body: some View {
        Circle()
            .fill(Color.red)
            .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5))
            .frame(width: 8, height: 8)
            .help("This tab is using your camera or microphone")
    }
}

/// A row's favicon as Arc's: 16 pt with 4 pt corners, or its `EmptyFavicon`, a 14 pt square in the palette's
/// `maxContrastColor` at the image's 0.28.
struct TabFavicon: View {
    let model: WindowModel
    let tab: SidebarTab
    @Environment(\.theme) private var theme

    var body: some View {
        if let icon = tab.icon {
            SpaceIconGlyph(icon: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.secondaryGlyph)
        } else if let icon = model.favicon(for: tab) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            RoundedRectangle(cornerRadius: 3)
                .fill(theme.maxContrast.opacity(0.28))
                .frame(width: 14, height: 14)
        }
    }
}

/// Arc's tab cell: a 40 pt row with a 36 pt card, selected on mouse-down, its button only under the pointer.
/// Reads the model itself, so a change to its tab's page, Peek or selection re-renders the row alone.
struct TabRow: View {
    /// As Arc's Spaces cards: the same cell, with no selection drawn, always ✕, the saved title, and a click that
    /// leaves the Library for the tab on mouse-up.
    enum Place {
        case sidebar
        case card
    }

    let model: WindowModel
    let layout: WindowLayoutController
    let tab: SidebarTab
    let spaceID: UUID
    var place = Place.sidebar
    @State private var hovering = false
    @State private var size = CGSize.zero
    @State private var pressed = false
    @State private var previousTabID: UUID?
    @State private var bounces = 0
    @State private var renaming = false
    @State private var draft = ""
    @State private var pickingIcon = false
    @FocusState private var renameFocused: Bool
    @Environment(\.theme) private var theme
    @Environment(\.sidebarDrag) private var drag

    var body: some View {
        let inCard = place == .card
        let pinned = model.state.isPinned(tab.id)
        let current = !inCard && model.selectedTabIDs[spaceID] == tab.id
        // As Arc: the New Tab row takes the selected look while the bar makes a tab.
        let selected = current && (spaceID != model.selectedSpaceID || model.commandBar?.destination != .newTab)
        // As Arc's `closeButtonAction`: a pinned tab that is shown, or has left its address, keeps its pin.
        let glyph: SidebarCellButton.Glyph =
            pinned && !inCard && (current || model.leftAddress(tab) != nil) ? .minus : .close
        let peek = model.peeks[tab.id]
        let dragged = !inCard && drag?.entry?.id == tab.id
        let combining = !inCard && drag?.target?.combine == tab.id
        let showsButton = hovering && !dragged && !combining
        let card = RoundedRectangle(cornerRadius: 12, style: .continuous)
        HStack(spacing: 0) {
            if model.isRecording(tab) { RecordingDot().padding(.trailing, 2) }
            TabFavicon(model: model, tab: tab)
                .frame(width: 24, height: 24)
            Group {
                if renaming {
                    renameField
                } else {
                    Text(inCard ? tab.displayTitle : model.title(for: tab))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .font(.system(size: 14))
            .foregroundStyle(theme.foreground)
            .padding(.leading, 6)
            Spacer(minLength: 0)
        }
        .padding(.leading, 6)
        .padding(.trailing, showsButton || peek != nil ? 31 : 10)
        .frame(height: 36)
        .background {
            card.fill(selected ? theme.selectedCard : hovering ? theme.itemFill : .clear)
                .shadow(color: selected ? theme.selectedShadow : .clear, radius: 1, y: 1)
        }
        .opacity(combining ? 0 : 1)
        .overlay {
            if combining, let held = drag?.entry?.tabs.first {
                SplitViewCombinePreview(model: model, tabs: [held, tab])
            }
        }
        .contentShape(card)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: inCard ? .local : .named(SidebarDrag.space))
                .onChanged { value in
                    if !pressed {
                        pressed = true
                        previousTabID = model.selectedTabIDs[spaceID]
                        if !inCard { model.select(tab.id) }
                    }
                    guard !inCard else { return }
                    drag?.update(
                        .tab(tab), from: pinned ? .pinned : .today, glyph: glyph, at: value.location,
                        start: value.startLocation, previous: previousTabID, model: model, layout: layout)
                }
                .onEnded { value in
                    pressed = false
                    guard inCard else {
                        drag?.finish(model: model, layout: layout)
                        return
                    }
                    guard CGRect(origin: .zero, size: size).contains(value.location) else { return }
                    layout.dismissSidebar()
                    model.show(tab.id)
                },
            including: renaming ? .subviews : .all
        )
        // As Arc's: the first click selects, the second opens the field.
        .simultaneousGesture(TapGesture(count: 2).onEnded { if !inCard { beginRename() } })
        .help(inCard || renaming ? "" : "\(model.title(for: tab))\nDouble-click to rename")
        .onGeometryChange(for: CGSize.self) {
            $0.size
        } action: {
            size = $0
        }
        .overlay(alignment: .trailing) {
            Group {
                if let peek {
                    PeekBadge(favicon: peek.favicon)
                } else if showsButton {
                    SidebarCellButton(glyph: glyph) {
                        if glyph == .minus {
                            bounces += 1
                            model.close(tab.id)
                        } else if pinned {
                            model.archivePinned(tab.id)
                        } else {
                            model.close(tab.id)
                        }
                    }
                    .help((glyph == .minus ? "Close and Keep Pinned" : "Archive this tab") + (current ? "  ⌘W" : ""))
                }
            }
            .padding(.trailing, 6)
        }
        .scaleEffect(pressed ? 0.99 : 1)
        .animation(.easeOut(duration: 0.1), value: pressed)
        // As Arc's drop: the row is in its new place at once, under the copy settling onto it.
        .opacity(dragged && drag?.settling == true ? 0 : 1)
        // As measured on Arc's −: the row drops to 0.89 and springs back.
        .keyframeAnimator(initialValue: 1.0, trigger: bounces) { content, scale in
            content.scaleEffect(scale)
        } keyframes: { _ in
            MoveKeyframe(0.89)
            SpringKeyframe(1, duration: 0.24, spring: Spring(response: 0.24, dampingRatio: 1))
        }
        // As seen in Arc: the picker hangs below the row, its arrow at the favicon.
        .popover(
            isPresented: $pickingIcon, attachmentAnchor: .rect(.rect(CGRect(x: 6, y: 2, width: 24, height: 36))),
            arrowEdge: .bottom
        ) {
            SpaceIconPicker(selection: tab.icon) { model.setTabIcon(tab.id, to: $0) }
        }
        .frame(height: 40)
        .onHover { hovering = $0 }
        .sidebarDragFrame { if !inCard { drag?.rows[tab.id] = SidebarDrag.RowFrame(rect: $0, spaceID: spaceID) } }
        .platformContextMenu(
            isEnabled: inCard
                ? model.library != nil
                : spaceID == model.selectedSpaceID && model.library == nil && !model.coversWindow
        ) {
            TabContextMenu(model: model, tab: tab, changeIcon: { Task { pickingIcon = true } }, rename: beginRename)
                .make()
        }
    }

    private func beginRename() {
        draft = tab.displayTitle
        renaming = true
    }

    /// As Arc's: Return or a click away keeps the name and Escape gives the old one back. Oa's own: a name left as it
    /// was isn't stored as the tab's.
    private var renameField: some View {
        TextField("Title", text: $draft)
            .textFieldStyle(.plain)
            .focused($renameFocused)
            .onSubmit { commitRename() }
            .onExitCommand { renaming = false }
            // After the menu has closed and given the window back its first responder.
            .task {
                try? await Task.sleep(for: .milliseconds(100))
                renameFocused = true
            }
            .onChange(of: renameFocused) { _, focused in if !focused { commitRename() } }
    }

    private func commitRename() {
        guard renaming else { return }
        renaming = false
        if tab.customTitle != nil || draft != tab.displayTitle { model.renameTab(tab.id, to: draft) }
    }
}
