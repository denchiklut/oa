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
        let spaces = model.state.spaces
        let reveal = layout.spaceCreationReveal
        let selected = spaces.firstIndex { $0.id == model.selectedSpaceID } ?? 0
        // Under the cross-fade the Space the window showed stays where it was as it fades.
        let offset = reveal < 1 ? CGFloat(selected) * width : layout.sidebarScrollOffset
        let groups = spaces.indices.filter { $0 == 0 || spaces[$0].profileID != spaces[$0 - 1].profileID }
        ZStack(alignment: .topLeading) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(spaces) { space in
                    let current = space.id == model.selectedSpaceID
                    let tiles = FavoritesGrid.slots(model.state.favorites(for: space.id), drag: current ? drag : nil)
                    SidebarSpacePage(model: model, layout: layout, space: space)
                        .padding(.top, FavoritesGrid.height(for: tiles.filter { !$0.isLifted }.count, in: width) + 16)
                        .frame(width: width)
                        .allowsHitTesting(space.id == model.selectedSpaceID)
                        .accessibilityHidden(space.id != model.selectedSpaceID)
                }
            }
            .offset(x: -offset)
            ForEach(Array(groups.enumerated()), id: \.element) { position, first in
                let last = (position + 1 < groups.count ? groups[position + 1] : spaces.count) - 1
                let shown = spaces[first...last].contains { $0.id == model.selectedSpaceID }
                let favorites = model.state.favorites(for: spaces[first].id)
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
        .opacity(1 - (reveal < 1 ? reveal : 0))
        .overlay(alignment: .topLeading) {
            if let creation = model.spaceCreation {
                SpaceCreationView(model: model, creation: creation)
                    .frame(width: width)
                    .offset(x: reveal < 1 ? 0 : CGFloat(spaces.count) * width - layout.sidebarScrollOffset)
                    .opacity(reveal)
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
        let items =
            model.state.tabs(in: space.id, pinned: true).map(Item.tab) + (unpinned.isEmpty ? [] : [.divider])
            + [.newTab] + unpinned.map(Item.tab)
        ScrollView {
            // Not lazy: a drag reads every row's frame and the section boundary, scrolled out of view or not.
            VStack(spacing: 1) {
                SpaceNameRow(model: model, layout: layout, space: space)
                    .sidebarDragFrame { drag?.lists[space.id, default: .init()].pinnedTop = $0.maxY + 0.5 }
                ForEach(items) { item in
                    switch item {
                    case .tab(let tab):
                        TabRow(model: model, layout: layout, tab: tab, spaceID: space.id)
                            .transition(.opacity)
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
/// menu. The chevron Arc shows on hover is left out until what it does is known.
private struct SpaceNameRow: View {
    let model: WindowModel
    let layout: WindowLayoutController
    let space: SidebarSpace
    @State private var over = false
    @State private var hovering = false
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            if let icon = space.icon {
                SpaceIconGlyph(icon: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.sectionHeaderText)
                    .frame(width: 26, height: 26)
                    .padding(.trailing, 2)
            }
            Text(space.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.sectionHeaderText)
                .lineLimit(1)
            Spacer(minLength: 0)
            if hovering {
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
        .padding(.leading, space.icon == nil ? 8 : 5)
        .padding(.trailing, 6)
        .frame(height: 36)
        .background(
            hovering ? theme.itemFill : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .contentShape(Rectangle())
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
