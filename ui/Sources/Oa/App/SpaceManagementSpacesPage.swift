import SwiftUI

/// Arc's Spaces page of the Library: a card for each Space in a row that scrolls sideways, 24 pt apart and 24 pt in,
/// each 240 pt wide and 96 pt shorter than the row, then the item that adds a Space. A row that fits is centred.
struct SpaceManagementSpacesPage: View {
    /// What the page asks of the Library's width for a count of Spaces, as Arc's: the cards, the item that adds one,
    /// and room for the rail.
    static func contentWidth(for spaces: Int) -> CGFloat { 264 * CGFloat(spaces) + 216 }

    let model: WindowModel
    /// The Library's progress into the window, to 1, and what the page card keeps clear at its start among the
    /// Spaces: the gap between the Library and the card on the way is that much of what is left.
    let progress: CGFloat
    let pageInset: CGFloat
    @State private var scroll: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let viewport = SpaceManagementViewport(
                width: geometry.size.width, spaces: model.state.spaces.count, scroll: scroll, pageInset: pageInset,
                progress: progress)
            ScrollView(.horizontal) {
                HStack(spacing: 24) {
                    ForEach(model.state.spaces) { space in
                        SpaceManagementCollectionViewItem(model: model, space: space)
                            .frame(width: 240, height: max(geometry.size.height - 96, 0))
                    }
                    SpaceManagementAddSpaceView(model: model)
                }
                .padding(.horizontal, 24)
                .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                .background {
                    GeometryReader { content in
                        Color.clear.preference(key: Scroll.self, value: -content.frame(in: .named(Scroll.space)).minX)
                    }
                }
            }
            .coordinateSpace(name: Scroll.space)
            .onPreferenceChange(Scroll.self) { scroll = $0 }
            // The scroll view reaches left by what the row is moved, so the row keeps its place in it.
            .frame(width: viewport.clip + viewport.travel)
            .offset(x: -viewport.travel)
            .frame(width: viewport.clip, alignment: .leading)
            .clipped()
            .frame(width: geometry.size.width, alignment: .leading)
        }
    }

    private enum Scroll: PreferenceKey {
        static let space = "SpaceManagementSpacesPage"
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
    }
}

/// Where the row of cards is cut while the Library comes in or leaves. Oa's own, by the author's decision, after
/// open-arch's `SpaceOverviewViewport`: Arc cuts the row at the Library's own edge all the way, mid-card and short of
/// the page card. Here the cut follows the page card's edge, and the one card the settled edge will cut is moved in
/// whole and slides under the edge as the Library settles. A settled edge in a gap moves nothing, and the item that
/// adds a Space, once in view, leaves with the cards. At rest the row is cut at the page card, as Arc's.
private struct SpaceManagementViewport {
    /// How far the row is moved toward the Library's start, and where it is cut.
    let travel: CGFloat
    let clip: CGFloat

    init(width: CGFloat, spaces: Int, scroll: CGFloat, pageInset: CGFloat, progress: CGFloat) {
        let progress = min(max(progress, 0), 1)
        let row = 264 * CGFloat(spaces) + 96
        var edge = width
        if row > width {
            let settled = width + scroll
            let card = ((settled - 24) / 264).rounded(.down)
            if settled > row - 72 {
                edge = max(width, row - scroll)
            } else if card >= 0, settled > 24 + card * 264, settled < 264 + card * 264 {
                edge = 264 + card * 264 - scroll
            }
        }
        travel = (edge - width) * (1 - progress)
        clip = min(width + pageInset * (1 - progress), edge - travel)
    }
}

/// Arc's card: the Space's sidebar under its name, with 12 pt corners and Arc's shadow. Arc's holds the Space's live
/// sidebar view. Oa's own until rows are shared with it: a row here only goes to its tab.
private struct SpaceManagementCollectionViewItem: View {
    let model: WindowModel
    let space: SidebarSpace
    @Environment(\.windowColorScheme) private var windowColorScheme

    var body: some View {
        let background = space.theme.background[windowColorScheme]
        let appearance = background.contentOverBackgroundAppearance
        let theme = Theme(palette: space.theme.semanticColorPalette[appearance.colorScheme], appearance: appearance)
        let unpinned = model.state.tabs(in: space.id, pinned: false)
        VStack(alignment: .leading, spacing: 0) {
            Text(space.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .padding(.horizontal, 13)
                .frame(height: 36)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.state.tabs(in: space.id, pinned: true)) { row($0) }
                    if !unpinned.isEmpty {
                        Rectangle()
                            .fill(Color.primary.opacity(0.1))
                            .frame(height: 1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 11)
                    }
                    ForEach(unpinned) { row($0) }
                }
                .padding(.horizontal, 8)
            }
        }
        .environment(\.colorScheme, appearance.colorScheme)
        .background { WindowSurface(background: background).environment(\.colorScheme, windowColorScheme) }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        // What casts the shadow sits a point inside the card, as the page's does.
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .padding(1)
                .shadow(color: .black.opacity(0.15), radius: 12, y: 1)
        }
    }

    private func row(_ tab: SidebarTab) -> some View {
        HStack(spacing: 6) {
            Group {
                if let icon = model.favicon(for: tab) {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.1))
                }
            }
            .frame(width: 16, height: 16)
            Text(model.title(for: tab))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(model.selectedTabIDs[space.id] == tab.id ? 0.12 : 0))
        )
        .contentShape(Rectangle())
        .onTapGesture { model.show(tab.id) }
    }
}

/// Arc's item after the last card: a 30 pt disc in the theme's cutout colour with a plus in its strongest, in a
/// 48 pt square. Under the pointer the two colours swap in 0.05 s and the disc then bounces once to 1.15, as Arc's
/// `CircularProgressView` does when activated; leaving swaps them back with no bounce. It asks for a name until the
/// Create a Space panel is here.
private struct SpaceManagementAddSpaceView: View {
    let model: WindowModel
    @Environment(\.theme) private var theme
    @State private var isActivated = false
    @State private var scale = 1.0

    var body: some View {
        Button {
            if let name = NamePrompt.run("New Space") { model.addSpace(named: name) }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isActivated ? theme.cutout : theme.maxContrast)
                .frame(width: 30, height: 30)
                .background(isActivated ? theme.maxContrast : theme.cutout, in: Circle())
                .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                .scaleEffect(scale)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("New Space")
        .accessibilityLabel("New Space")
        .onHover { inside in
            withAnimation(.linear(duration: 0.05)) { isActivated = inside }
            guard inside else { return }
            withAnimation(.easeOut(duration: 0.07).delay(0.05)) {
                scale = 1.15
            } completion: {
                withAnimation(.easeIn(duration: 0.07)) { scale = 1 }
            }
        }
    }
}
