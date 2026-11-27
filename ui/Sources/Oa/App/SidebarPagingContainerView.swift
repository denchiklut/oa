import AppKit
import DevKit
import SwiftUI

/// Arc's paging container in the sidebar: a page per Space side by side, each the sidebar's width, scrolled by the
/// window's pager and cut at the sidebar's edges. The header above it and the dock below stay where they are. A
/// profile's Favorites sit over the pages of its Spaces: they stay put while the swipe is between two of them and
/// slide with the page when it leaves them, as Arc's app tray does. As in Arc's layout, a profile's Spaces count as
/// one run only where they are neighbours.
struct SidebarPagingContainerView: View {
    let model: WindowModel
    let layout: WindowLayoutController
    let showsDownloads: Bool
    @AppStorage(PageToolbar.key) private var showsToolbar = false
    @Environment(\.sidebarDrag) private var drag

    var body: some View {
        let width = layout.sidebarWidth
        let offset = layout.sidebarScrollOffset
        let fade = layout.spaceCreationFade
        let hidesScrollIndicators = layout.isPaging || layout.libraryProgress > 0
        // The URL field takes no room while the panel comes or goes, so the Space's page keeps its place below it.
        let below: CGFloat = layout.addressFieldShift != nil && !showsToolbar ? SidebarAddressField.height : 0
        // The Create a Space page has no Space, and breaks a profile's run of Spaces as another profile's would.
        let pages = layout.sidebarPages.map { page -> SidebarSpace? in
            if case .space(let id) = page { model.state.space(id) } else { nil }
        }
        // A window with a sidebar of its own has no Favorites, as Arc's.
        let global = model.sidebarContext == .global
        let runs = pages.indices.compactMap { first -> (space: SidebarSpace, pages: ClosedRange<Int>)? in
            guard global, let space = pages[first], first == 0 || pages[first - 1]?.profileID != space.profileID else {
                return nil
            }
            let last = (first..<pages.count).prefix { pages[$0]?.profileID == space.profileID }.last ?? first
            return (space, first...last)
        }
        ZStack(alignment: .topLeading) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(zip(layout.sidebarPages, pages)), id: \.0) { _, space in
                    if let space {
                        let current = space.id == model.selectedSpaceID && model.spaceCreation == nil
                        let favorites = model.state.favoriteEntries(for: space.id)
                        let tiles = FavoritesGrid.slots(favorites, drag: current ? drag : nil)
                        let trayExtensions =
                            global && !showsToolbar
                            ? PinnedExtensionLayout.trayActions(
                                model.pinnedExtensionActions(for: space.profileID), sidebarWidth: width,
                                hasFavorites: !favorites.isEmpty)
                            : []
                        let extensionsHeight = PinnedExtensionsGrid.height(for: trayExtensions.count, in: width)
                        let trayHeight =
                            FavoritesGrid.height(for: tiles.filter { !$0.isLifted }.count, in: width) + 16
                            + (extensionsHeight > 0 ? extensionsHeight + 8 : 0)
                        SidebarSpacePage(
                            model: model, layout: layout, space: space,
                            hidesScrollIndicators: hidesScrollIndicators, showsDownloads: showsDownloads
                        )
                        .padding(.top, global ? trayHeight : 0)
                        .frame(width: width)
                        .allowsHitTesting(current)
                        .accessibilityHidden(!current)
                    } else {
                        Color.clear.frame(width: width)
                    }
                }
            }
            .offset(x: -offset)
            ForEach(runs, id: \.space.id) { run in
                let (first, last) = (run.pages.lowerBound, run.pages.upperBound)
                let shown =
                    model.spaceCreation == nil && pages[run.pages].contains { $0?.id == model.selectedSpaceID }
                let favorites = model.state.favoriteEntries(for: run.space.id)
                let trayExtensions =
                    !showsToolbar
                    ? PinnedExtensionLayout.trayActions(
                        model.pinnedExtensionActions(for: run.space.profileID), sidebarWidth: width,
                        hasFavorites: !favorites.isEmpty)
                    : []
                VStack(alignment: .leading, spacing: 0) {
                    if !trayExtensions.isEmpty {
                        PinnedExtensionsGrid(model: model, layout: layout, actions: trayExtensions)
                            .padding(.top, 8)
                            .padding(.horizontal, 8)
                    }
                    FavoritesGrid(
                        model: model, layout: layout, slots: FavoritesGrid.slots(favorites, drag: shown ? drag : nil)
                    )
                    .padding(8)
                    .frame(width: width)
                    .sidebarDragFrame { if shown { drag?.grid = $0 } }
                }
                .frame(width: width)
                .offset(x: min(max(offset, CGFloat(first) * width), CGFloat(last) * width) - offset)
                .allowsHitTesting(shown)
                .accessibilityHidden(!shown)
            }
        }
        .offset(y: below)
        .opacity(fade.map { $0.panel == nil ? 1 - $0.pages : $0.pages } ?? 1)
        .overlay(alignment: .topLeading) {
            // While it fades in, the panel is over the window's Space's page rather than at its own.
            if let creation = model.spaceCreation, let index = model.spaceCreationIndex {
                SpaceCreationView(model: model, creation: creation)
                    .frame(width: width)
                    .offset(x: fade == nil ? CGFloat(index) * width - offset : 0)
                    .opacity(fade.map { Double($0.pages) } ?? 1)
            }
            if let fade, let panel = fade.panel {
                SpaceCreationView(model: model, creation: panel, focusesName: false)
                    .frame(width: width)
                    .opacity(1 - fade.pages)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: width, alignment: .topLeading)
        .clipped()
    }
}

/// A Space's page: its name, its pinned tabs and folders, the divider, New Tab and its Today tabs, with its own scroll
/// position.
private struct SidebarSpacePage: View {
    private enum Item: Identifiable {
        static let dividerID = UUID()
        static let newTabID = UUID()

        case row(SidebarRow)
        case divider
        case newTab

        var id: UUID {
            switch self {
            case .row(let row): row.id
            case .divider: Self.dividerID
            case .newTab: Self.newTabID
            }
        }
    }

    let model: WindowModel
    let layout: WindowLayoutController
    let space: SidebarSpace
    let hidesScrollIndicators: Bool
    let showsDownloads: Bool
    @State private var canScrollDown = false
    @Environment(\.sidebarDrag) private var drag
    @Environment(\.sidebarRevealsControls) private var revealed

    var body: some View {
        let unpinned = model.state.unpinnedRows(in: space.id).map(Item.row)
        let collapsed = model.collapsedPinnedSpaces.contains(space.id)
        let pinned = model.visiblePinnedRows(in: space.id).map(Item.row)
        let pinnedIDs = Set(pinned.map(\.id))
        // As seen in Arc: a window's own sidebar has no pinned section, so no divider.
        let global = model.sidebarContext == .global
        let items = pinned + (unpinned.isEmpty || !global ? [] : [.divider]) + [.newTab] + unpinned
        ScrollViewReader { proxy in
            ScrollView {
                // Not lazy: a drag reads every row's frame and the section boundary, scrolled out of view or not.
                VStack(spacing: 1) {
                    if global {
                        SpaceNameRow(model: model, layout: layout, space: space)
                            .sidebarDragFrame { drag?.lists[space.id, default: .init()].pinnedTop = $0.maxY + 0.5 }
                    } else {
                        ProfileIndicatorView(model: model, space: space)
                    }
                    ForEach(items) { item in
                        switch item {
                        case .row(let row):
                            switch row.entry {
                            case .tab(let tab):
                                // As measured on Arc: collapsing takes the pinned rows away at once, and expanding
                                // fades them in where they go.
                                TabRow(model: model, layout: layout, tab: tab, spaceID: space.id, depth: row.depth)
                                    .transition(
                                        pinnedIDs.contains(tab.id)
                                            ? .asymmetric(
                                                insertion: .opacity.animation(.easeOut(duration: 0.08)),
                                                removal: .identity)
                                            : .opacity)
                            case .folder(let folder):
                                FolderRowView(
                                    model: model, layout: layout, folder: folder, spaceID: space.id, depth: row.depth,
                                    isExpanded: row.isExpanded, isPeeked: row.isPeeked
                                )
                                .transition(
                                    .asymmetric(
                                        insertion: .opacity.animation(.easeOut(duration: 0.08)), removal: .identity))
                            case .splitView(let id, let tabs):
                                SplitViewCellView(
                                    model: model, layout: layout, splitID: id, tabs: tabs, spaceID: space.id,
                                    depth: row.depth
                                )
                                .transition(.opacity)
                            }
                        case .divider:
                            ClearDivider(model: model, spaceID: space.id, showsClear: revealed)
                                .sidebarDragFrame { drag?.lists[space.id, default: .init()].divider = $0 }
                                .onDisappear { drag?.lists[space.id]?.divider = nil }
                        case .newTab:
                            NewTabRow(model: model, isCurrent: space.id == model.selectedSpaceID)
                                .sidebarDragFrame { drag?.lists[space.id, default: .init()].newTab = $0 }
                        }
                    }
                }
                .padding([.horizontal, .bottom], 8)
                .id(space.id)
                .onGeometryChange(for: Bool.self) { geometry in
                    guard let viewport = geometry.bounds(of: .scrollView(axis: .vertical)) else { return false }
                    return geometry.size.height > viewport.maxY + 1
                } action: {
                    canScrollDown = $0
                }
                // As measured on Arc: the rows below a collapsing pinned section spring up, and down as it expands.
                .animation(
                    collapsed
                        ? .spring(response: 0.125, dampingFraction: 0.94)
                        : .spring(response: 0.135, dampingFraction: 0.9),
                    value: collapsed
                )
                // As measured on Arc: an archived row fades where it is while the rows below close up.
                .animation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.12), value: items.map(\.id))
                // Oa's own: hide the scrollbar while paging between Spaces or into the Library.
                .background { SpaceScroller(hidesWhilePaging: hidesScrollIndicators) }
            }
            .onChange(of: model.editingFolderID) { _, id in
                guard let id, space.id == model.selectedSpaceID else { return }
                withAnimation(.easeOut(duration: 0.16)) { proxy.scrollTo(id, anchor: .center) }
            }
            .overlay(alignment: .bottom) {
                if canScrollDown, !showsDownloads, !hidesScrollIndicators {
                    ScrollToBottomButton {
                        proxy.scrollTo(space.id, anchor: .bottom)
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        // As Arc's: the list's empty space and its rows without a menu of their own give the Space's.
        .spaceContextMenu(
            isEnabled: global && space.id == model.selectedSpaceID && model.library == nil && !model.coversWindow
        ) {
            SpaceMenu(model: model, layout: layout, space: space)
        }
        .sidebarDragFrame { drag?.lists[space.id, default: .init()].area = $0 }
    }
}

private struct ScrollToBottomButton: View {
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2), action)
        } label: {
            Image(systemName: "arrow.down")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.94), in: Circle())
                .shadow(color: .black.opacity(0.14), radius: 3, y: 1)
                // Arc's 28 pt button briefly reaches 31 pt before settling at 30 pt.
                .scaleEffect(hovering ? 30.0 / 28 : 1)
                .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.36), value: hovering)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("Scroll to Bottom")
        .oaToolTip("Scroll to Bottom")
    }
}

/// Arc's `SidebarSectionHeaderView`: the Space's name, a hover card after a moment and the "⋯" with the Space's
/// menu. As Arc's, a click folds the Space's pinned tabs away or back, with a chevron in the icon's place on hover and
/// while folded; a Space with no pinned tabs has no chevron, and a click renames it there.
private struct SpaceNameRow: View {
    let model: WindowModel
    let layout: WindowLayoutController
    let space: SidebarSpace
    @State private var over = false
    @State private var hovering = false
    @State private var renaming = false
    @State private var draft = ""
    @FocusState private var renameFocused: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        let hasPinned = model.state.hasPinnedItems(in: space.id)
        let collapsed = hasPinned && model.collapsedPinnedSpaces.contains(space.id)
        let showsChevron = hasPinned && (hovering || collapsed)
        HStack(spacing: 0) {
            if showsChevron || space.icon != nil {
                Group {
                    if showsChevron {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.sectionHeaderText)
                            .rotationEffect(.degrees(collapsed ? -90 : 0))
                            .animation(.easeOut(duration: 0.1), value: collapsed)
                    } else if let icon = space.icon {
                        // As measured on Arc: in the Space's `maxContrastColor`, the name starting where titles do.
                        SpaceIconGlyph(icon: icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.maxContrast)
                    }
                }
                .frame(width: 26, height: 26)
                .padding(.trailing, 5)
            }
            if renaming {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .focused($renameFocused)
                    .onSubmit(commitRename)
                    .onExitCommand { renaming = false }
                    .onAppear { renameFocused = true }
                Button("Done", action: commitRename)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
            } else {
                Text(space.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.sectionHeaderText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if hovering, !renaming {
                PointerMenuButton {
                    SpaceMenu(model: model, layout: layout, space: space).make()
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.tertiaryText)
                }
                .buttonStyle(CellButtonStyle())
                .oaToolTip("More")
            }
        }
        .padding(.leading, showsChevron || space.icon != nil ? 5 : 8)
        .padding(.trailing, 6)
        .frame(height: 36)
        .background(
            hovering ? theme.itemFill : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard !renaming else { return }
            if hasPinned {
                model.togglePinnedSection(of: space.id)
            } else {
                draft = space.name
                renaming = true
            }
        }
        // As Arc's, which hangs it from the header's icon view.
        .popover(
            isPresented: pickingIcon, attachmentAnchor: .rect(.rect(CGRect(x: 5, y: 5, width: 26, height: 26))),
            arrowEdge: .bottom
        ) {
            SpaceIconPicker(selection: space.icon) { icon in
                model.setSpaceIcon(icon, for: space.id)
                layout.iconPickerSpaceID = nil
            }
        }
        .onChange(of: pickingIcon.wrappedValue) { layout.setHold(.popover, $1) }
        .onHover { over = $0 }
        // As measured on Arc: the hover shows ≈ 135 ms after the pointer arrives, and goes at once.
        .task(id: over) {
            guard over else { return hovering = false }
            try? await Task.sleep(for: .milliseconds(135))
            if !Task.isCancelled { hovering = true }
        }
        .frame(height: 38, alignment: .top)
    }

    private func commitRename() {
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { model.renameSpace(space.id, to: name) }
        renaming = false
    }

    private var pickingIcon: Binding<Bool> {
        Binding {
            layout.iconPickerSpaceID == space.id
        } set: {
            if !$0, layout.iconPickerSpaceID == space.id { layout.iconPickerSpaceID = nil }
        }
    }
}

/// Arc's profile indicator, where a window with a sidebar of its own has its Space's name: the profile's icon and
/// name in a pill, or in an incognito window "Incognito" with Clear beside it while it has tabs. Oa has no profile
/// icons yet, so the icon is the one the Spaces cards give a profile.
struct ProfileIndicatorView: View {
    let model: WindowModel
    let space: SidebarSpace
    @State private var hovering = false
    @State private var hoveringClear = false
    @Environment(\.theme) private var theme

    var body: some View {
        let incognito = model.sidebarContext == .incognito
        let name = incognito ? "Incognito" : model.profileName(space.profileID)
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: incognito ? "eye.slash" : "person.crop.circle")
                    .frame(width: 14, height: 14)
                Text(name)
                    .lineLimit(1)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(theme.secondaryText)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(theme.itemFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(incognito ? name : "Profile: \(name)")
            Spacer(minLength: 0)
            if incognito, !model.state.tabs(in: space.id).isEmpty {
                Button {
                    model.clearTabs(in: space.id)
                } label: {
                    Text("Clear")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(hoveringClear ? theme.foreground : theme.tertiaryText)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hoveringClear = $0 }
            } else if model.sidebarContext == .standalone, hovering, !model.state.tabs(in: space.id).isEmpty {
                // Arc's `moveToMainWindow` accessory, in Clear's slot while there are tabs; shown on hover, as seen.
                MoveToMainWindowButton(model: model)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 11)
        .frame(maxWidth: .infinity, minHeight: 36)
        .frame(height: 38, alignment: .top)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// Arc's `presentMoveAllTabsMenu:`: the global Spaces, with no New Space…, at the pointer.
private struct MoveToMainWindowButton: View {
    let model: WindowModel
    @State private var hovering = false
    @Environment(\.theme) private var theme

    var body: some View {
        Button {
            guard let window = model.window, let view = window.contentView else { return }
            let menu = NSMenu()
            menu.autoenablesItems = false
            for space in model.state.spaces {
                menu.addItem(
                    MenuActionItem(space.name) { [model] in model.moveAllItemsToGlobalWindow(toSpace: space.id) })
            }
            menu.appearance = window.effectiveAppearance
            menu.popUp(
                positioning: nil, at: view.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil),
                in: view)
        } label: {
            Text("Move to…")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(hovering ? theme.foreground : theme.tertiaryText)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .oaToolTip("Move to main window")
    }
}

/// Arc's `UnpinnedSectionDividerCellView`: its arrow and tooltip say whether Clear takes the selected tab too.
struct ClearDivider: View {
    let model: WindowModel
    let spaceID: UUID
    let showsClear: Bool
    var inCard = false
    @State private var hovering = false
    @Environment(\.theme) private var theme

    var body: some View {
        let clearsAll = inCard || model.clearsAllTabs(in: spaceID)
        HStack(spacing: 8) {
            Rectangle()
                .fill(theme.separator)
                .frame(height: 0.5)
            if showsClear {
                Button {
                    model.clearTabs(in: spaceID, all: inCard)
                } label: {
                    HStack(spacing: 4) {
                        if clearsAll { Image(systemName: "arrow.down") }
                        Text("Clear")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(hovering ? theme.foreground : theme.tertiaryText)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
                .oaToolTip(
                    clearsAll ? "Clear Today tabs" : "Clear unselected Today tabs",
                    shortcut: model.keyBindings.state.shortcut(for: "clearExplore"))
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 11)
        .frame(height: 24)
    }
}

/// Arc's `NewTabCellView`: a row above the Today tabs, drawn as the selected card while the bar makes a new tab.
private struct NewTabRow: View {
    let model: WindowModel
    let isCurrent: Bool
    @State private var hovering = false
    @Environment(\.theme) private var theme

    var body: some View {
        let active = isCurrent && model.commandBar?.destination == .newTab
        let card = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Button {
            model.openCommandBar(.newTab)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(active ? theme.foreground : theme.secondaryGlyph)
                    .frame(width: 24, height: 24)
                Text("New Tab")
                    .font(.system(size: 14))
                    .foregroundStyle(active ? theme.foreground : theme.secondaryText)
                Spacer(minLength: 0)
            }
            .padding(.leading, 6)
            .frame(height: 36)
            .background {
                card.fill(active ? theme.selectedCard : hovering ? theme.itemFill : .clear)
                    .shadow(color: active ? theme.selectedShadow : .clear, radius: 1, y: 1)
            }
            .contentShape(card)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .frame(height: 40)
    }
}
