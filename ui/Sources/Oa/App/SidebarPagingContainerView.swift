import SwiftUI

/// Arc's paging container in the sidebar: a page per Space side by side, each the sidebar's width, scrolled by the
/// window's pager and cut at the sidebar's edges. The header above it and the dock below stay where they are. A
/// profile's Favorites sit over the pages of its Spaces: they stay put while the swipe is between two of them and
/// slide with the page when it leaves them, as Arc's app tray does. As in Arc's layout, a profile's Spaces count as
/// one run only where they are neighbours.
struct SidebarPagingContainerView: View {
    let model: WindowModel
    let layout: WindowLayoutController
    @Environment(\.sidebarDrag) private var drag

    var body: some View {
        let width = layout.sidebarWidth
        let offset = layout.sidebarScrollOffset
        // The Create a Space page has no Space, and breaks a profile's run of Spaces as another profile's would.
        let pages = layout.sidebarPages.map { page -> SidebarSpace? in
            if case .space(let id) = page { model.state.space(id) } else { nil }
        }
        let runs = pages.indices.compactMap { first -> (space: SidebarSpace, pages: ClosedRange<Int>)? in
            guard let space = pages[first], first == 0 || pages[first - 1]?.profileID != space.profileID else {
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
                        let tiles = FavoritesGrid.slots(
                            model.state.favorites(for: space.id), drag: current ? drag : nil)
                        SidebarSpacePage(model: model, layout: layout, space: space)
                            .padding(
                                .top, FavoritesGrid.height(for: tiles.filter { !$0.isLifted }.count, in: width) + 16
                            )
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
                let favorites = model.state.favorites(for: run.space.id)
                FavoritesGrid(
                    model: model, layout: layout, slots: FavoritesGrid.slots(favorites, drag: shown ? drag : nil)
                )
                .padding(8)
                .sidebarDragFrame { if shown { drag?.grid = $0 } }
                .frame(width: width)
                .offset(x: min(max(offset, CGFloat(first) * width), CGFloat(last) * width) - offset)
                .allowsHitTesting(shown)
                .accessibilityHidden(!shown)
            }
        }
        .overlay(alignment: .topLeading) {
            if let creation = model.spaceCreation, let index = model.spaceCreationIndex {
                SpaceCreationView(model: model, creation: creation)
                    .frame(width: width)
                    .offset(x: CGFloat(index) * width - offset)
            }
        }
        .frame(width: width, alignment: .topLeading)
        .clipped()
    }
}

/// A Space's page: its name, its pinned tabs, the divider, New Tab and its Today tabs, with its own scroll position.
private struct SidebarSpacePage: View {
    private enum Item: Identifiable {
        static let dividerID = UUID()
        static let newTabID = UUID()

        case tab(SidebarTab)
        case divider
        case newTab

        var id: UUID {
            switch self {
            case .tab(let tab): tab.id
            case .divider: Self.dividerID
            case .newTab: Self.newTabID
            }
        }
    }

    let model: WindowModel
    let layout: WindowLayoutController
    let space: SidebarSpace
    @Environment(\.sidebarDrag) private var drag
    @Environment(\.sidebarRevealsControls) private var revealed

    var body: some View {
        let unpinned = model.state.tabs(in: space.id, pinned: false)
        let collapsed = model.collapsedPinnedSpaces.contains(space.id)
        // As Arc: a collapsed section still shows its selected tab.
        let pinned = model.state.tabs(in: space.id, pinned: true).filter { !collapsed || $0.id == model.selectedTabID }
        let pinnedIDs = Set(pinned.map(\.id))
        let items =
            pinned.map(Item.tab) + (unpinned.isEmpty ? [] : [.divider]) + [.newTab] + unpinned.map(Item.tab)
        ScrollView {
            // Not lazy: a drag reads every row's frame and the section boundary, scrolled out of view or not.
            VStack(spacing: 1) {
                SpaceNameRow(model: model, layout: layout, space: space)
                    .sidebarDragFrame { drag?.lists[space.id, default: .init()].pinnedTop = $0.maxY + 0.5 }
                ForEach(items) { item in
                    switch item {
                    case .tab(let tab):
                        // As measured on Arc: collapsing takes the pinned rows away at once, and expanding fades
                        // them in where they go.
                        TabRow(model: model, layout: layout, tab: tab, spaceID: space.id)
                            .transition(
                                pinnedIDs.contains(tab.id)
                                    ? .asymmetric(
                                        insertion: .opacity.animation(.easeOut(duration: 0.08)), removal: .identity)
                                    : .opacity)
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
            // As measured on Arc: the rows below a collapsing pinned section spring up, and down as it expands.
            .animation(
                collapsed
                    ? .spring(response: 0.125, dampingFraction: 0.94) : .spring(response: 0.135, dampingFraction: 0.9),
                value: collapsed
            )
            // As measured on Arc: an archived row fades where it is while the rows below close up.
            .animation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.12), value: items.map(\.id))
        }
        // As Arc's: the list's empty space and its rows without a menu of their own give the Space's.
        .spaceContextMenu(isEnabled: space.id == model.selectedSpaceID && model.library == nil && !model.coversWindow) {
            SpaceMenu(model: model, layout: layout, space: space)
        }
        .sidebarDragFrame { drag?.lists[space.id, default: .init()].area = $0 }
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
        let hasPinned = !model.state.tabs(in: space.id, pinned: true).isEmpty
        let collapsed = hasPinned && model.collapsedPinnedSpaces.contains(space.id)
        let showsChevron = hasPinned && (hovering || collapsed)
        HStack(spacing: 0) {
            if showsChevron || space.icon != nil {
                Group {
                    if showsChevron {
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(collapsed ? -90 : 0))
                            .animation(.easeOut(duration: 0.1), value: collapsed)
                    } else if let icon = space.icon {
                        SpaceIconGlyph(icon: icon)
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.sectionHeaderText)
                .frame(width: 26, height: 26)
                .padding(.trailing, 2)
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
                SpaceMenuButton {
                    SpaceMenu(model: model, layout: layout, space: space)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.tertiaryText)
                }
                .buttonStyle(CellButtonStyle())
                .help("More")
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
        .popover(isPresented: pickingIcon, arrowEdge: .bottom) {
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
                .help(clearsAll ? "Clear Today tabs" : "Clear unselected Today tabs")
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
