import SwiftUI

/// Arc's paging container in the sidebar: a page per Space side by side, each the sidebar's width, scrolled by the
/// window's pager and cut at the sidebar's edges. The header above it and the dock below stay where they are. A
/// profile's Favorites sit over the pages of its Spaces: they stay put while the swipe is between two of them and
/// slide with the page when it leaves them, as Arc's app tray does. As in Arc's layout, a profile's Spaces count as
/// one run only where they are neighbours.
struct SidebarPagingContainerView: View {
    let model: WindowModel
    let layout: WindowLayoutController

    var body: some View {
        let width = layout.sidebarWidth
        let offset = layout.sidebarScrollOffset
        let spaces = model.state.spaces
        let groups = spaces.indices.filter { $0 == 0 || spaces[$0].profileID != spaces[$0 - 1].profileID }
        ZStack(alignment: .topLeading) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(spaces) { space in
                    let favorites = model.state.favorites(for: space.id).count
                    SidebarSpacePage(model: model, layout: layout, space: space)
                        .padding(.top, FavoritesGrid.height(for: favorites, in: width) + 16)
                        .frame(width: width)
                        .allowsHitTesting(space.id == model.selectedSpaceID)
                        .accessibilityHidden(space.id != model.selectedSpaceID)
                }
            }
            .offset(x: -offset)
            ForEach(Array(groups.enumerated()), id: \.element) { position, first in
                let last = (position + 1 < groups.count ? groups[position + 1] : spaces.count) - 1
                let shown = spaces[first...last].contains { $0.id == model.selectedSpaceID }
                FavoritesGrid(model: model, layout: layout, favorites: model.state.favorites(for: spaces[first].id))
                    .padding(8)
                    .frame(width: width)
                    .offset(x: min(max(offset, CGFloat(first) * width), CGFloat(last) * width) - offset)
                    .allowsHitTesting(shown)
                    .accessibilityHidden(!shown)
            }
        }
        .frame(width: width, alignment: .topLeading)
        .clipped()
    }
}

/// A Space's page: its pinned tabs, the divider and its unpinned tabs, with its own scroll position.
private struct SidebarSpacePage: View {
    let model: WindowModel
    let layout: WindowLayoutController
    let space: SidebarSpace
    @State private var overTabs = false

    var body: some View {
        let unpinned = model.state.tabs(in: space.id, pinned: false)
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(model.state.tabs(in: space.id, pinned: true)) { row($0) }
                if !unpinned.isEmpty { clearDivider }
                ForEach(unpinned) { row($0) }
            }
            .padding(8)
        }
        .onHover { overTabs = $0 }
        .onDrop(of: [.plainText], delegate: TabDrop { model.unfavorite($0) })
    }

    private func row(_ tab: SidebarTab) -> TabRow {
        TabRow(model: model, layout: layout, tab: tab, spaceID: space.id)
    }

    /// Arc's divider above the unpinned tabs, with Clear while the pointer is over the sidebar.
    private var clearDivider: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(height: 1)
            if overTabs {
                Button("Clear") { model.clearTabs() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .help("Clear unselected Today tabs")
            }
        }
        .frame(height: 16)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }
}
