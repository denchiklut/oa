import SwiftUI

/// Arc's paging container in the sidebar: a page per Space side by side, each the sidebar's width, scrolled by the
/// window's pager and cut at the sidebar's edges. The header above it and the dock below stay where they are.
struct SidebarPagingContainerView: View {
    let model: WindowModel
    let layout: WindowLayoutController

    var body: some View {
        let width = layout.sidebarWidth
        VStack(spacing: 0) {
            FavoritesGrid(model: model, layout: layout, favorites: model.favorites)
                .padding(8)
            HStack(alignment: .top, spacing: 0) {
                ForEach(model.state.spaces) { space in
                    SidebarSpacePage(model: model, layout: layout, space: space)
                        .frame(width: width)
                        .allowsHitTesting(space.id == model.selectedSpaceID)
                        .accessibilityHidden(space.id != model.selectedSpaceID)
                }
            }
            .offset(x: -layout.sidebarScrollOffset)
            .frame(width: width, alignment: .topLeading)
            .clipped()
        }
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
