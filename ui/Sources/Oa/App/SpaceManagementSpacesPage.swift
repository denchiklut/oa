import AppKit
import SwiftUI

/// Arc's Spaces page of the Library: a card for each Space in a row that scrolls sideways, 24 pt apart and 24 pt in,
/// each 240 pt wide and 96 pt shorter than the row, then the item that adds a Space. A row that fits is centred.
struct SpaceManagementSpacesPage: View {
    /// What the page asks of the Library's width for a count of Spaces, as Arc's: the cards, the item that adds one,
    /// and room for the rail.
    static func contentWidth(for spaces: Int) -> CGFloat { 264 * CGFloat(spaces) + 216 }

    let model: WindowModel
    let layout: WindowLayoutController
    /// The Library's progress into the window, to 1, and what the page card keeps clear at its start among the
    /// Spaces: the gap between the Library and the card on the way is that much of what is left.
    let progress: CGFloat
    let pageInset: CGFloat
    @State private var scroll: CGFloat = 0
    @State private var drag: SpaceManagementDrag?

    var body: some View {
        GeometryReader { geometry in
            let viewport = SpaceManagementViewport(
                width: geometry.size.width, spaces: model.state.spaces.count, scroll: scroll, pageInset: pageInset,
                progress: progress)
            ScrollView(.horizontal) {
                HStack(spacing: 24) {
                    ForEach(Array(model.state.spaces.enumerated()), id: \.element.id) { index, space in
                        let isDragged = drag?.spaceID == space.id
                        SpaceManagementCollectionViewItem(model: model, layout: layout, space: space) {
                            move(space.id, from: index, by: $0)
                        } dropped: {
                            drop()
                        }
                        .frame(width: 240, height: max(geometry.size.height - 96, 0))
                        .offset(x: shift(forCardAt: index))
                        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: drag?.target)
                        .offset(isDragged ? drag?.translation ?? .zero : .zero)
                        .scaleEffect(isDragged ? 1.03 : 1)
                        .opacity(isDragged ? 0.9 : 1)
                        .zIndex(isDragged ? 1 : 0)
                    }
                    SpaceManagementAddSpaceView(model: model)
                }
                .padding(.horizontal, 24)
                .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                .background {
                    GeometryReader { content in
                        Color.clear.preference(
                            key: Scroll.self, value: -content.frame(in: .named(SpaceManagementDrag.space)).minX)
                    }
                    ScrollKeeping(offset: layout.spacesPageScroll) { layout.spacesPageScroll = $0 }
                }
            }
            .coordinateSpace(name: SpaceManagementDrag.space)
            .onPreferenceChange(Scroll.self) { scroll = $0 }
            // The scroll view reaches left by what the row is moved, so the row keeps its place in it.
            .frame(width: viewport.clip + viewport.travel)
            .offset(x: -viewport.travel)
            .frame(width: viewport.clip, alignment: .leading)
            .clipped()
            .frame(width: geometry.size.width, alignment: .leading)
        }
    }

    /// How far a card stands aside for the slot the dragged one would drop into.
    private func shift(forCardAt index: Int) -> CGFloat {
        guard let drag, index != drag.source else { return 0 }
        if drag.source < drag.target, index > drag.source, index <= drag.target { return -264 }
        if drag.source > drag.target, index >= drag.target, index < drag.source { return 264 }
        return 0
    }

    private func move(_ spaceID: UUID, from index: Int, by translation: CGSize) {
        if drag == nil { drag = SpaceManagementDrag(spaceID: spaceID, source: index) }
        guard drag?.spaceID == spaceID else { return }
        drag?.translation = translation
        let slots = Int((translation.width / 264).rounded())
        drag?.target = min(max(index + slots, 0), model.state.spaces.count - 1)
    }

    private func drop() {
        guard let drag else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            model.moveSpace(drag.spaceID, to: drag.target)
            self.drag = nil
        }
    }

    private enum Scroll: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
    }
}

/// Puts the row's scroll view back at `offset` once its content is laid out, then reports where it scrolls. SwiftUI
/// doesn't lay the content out again as it scrolls, and takes a scroll point only from macOS 15.
private struct ScrollKeeping: NSViewRepresentable {
    let offset: CGFloat
    let scrolled: (CGFloat) -> Void

    func makeNSView(context: Context) -> Keeper { Keeper(offset: offset, scrolled: scrolled) }

    func updateNSView(_ view: Keeper, context: Context) { view.scrolled = scrolled }

    final class Keeper: NSView {
        var scrolled: (CGFloat) -> Void
        private var offset: CGFloat?

        init(offset: CGFloat, scrolled: @escaping (CGFloat) -> Void) {
            self.offset = offset
            self.scrolled = scrolled
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            guard let target = offset, bounds.width > 0, let scrollView = enclosingScrollView else { return }
            offset = nil
            let clip = scrollView.contentView
            let origin = NSPoint(x: target, y: clip.bounds.minY)
            clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size)).origin)
            scrollView.reflectScrolledClipView(clip)
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(clipScrolled), name: NSView.boundsDidChangeNotification, object: clip)
        }

        @objc private func clipScrolled(_ notification: Notification) {
            if let clip = notification.object as? NSClipView { scrolled(clip.bounds.minX) }
        }
    }
}

/// Oa's own, by the author's decision, after open-arch: the card itself lifts and follows the pointer, the others
/// stand aside for the slot it would drop into, and it springs into that slot. Arc's is an AppKit drag session: the
/// card leaves its slot open and a copy of it follows the pointer (arc-spaces-card-drag-static.md).
private struct SpaceManagementDrag {
    static let space = "SpaceManagementSpacesPage"

    let spaceID: UUID
    let source: Int
    var target: Int
    var translation = CGSize.zero

    init(spaceID: UUID, source: Int) {
        self.spaceID = spaceID
        self.source = source
        target = source
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
    let layout: WindowLayoutController
    let space: SidebarSpace
    var moved: ((CGSize) -> Void)?
    var dropped: (() -> Void)?
    @State private var isPickingIcon = false
    @State private var isEditingName = false
    @Environment(\.windowColorScheme) private var windowColorScheme

    var body: some View {
        let background = space.theme.background[windowColorScheme]
        let appearance = background.contentOverBackgroundAppearance
        let theme = Theme(palette: space.theme.semanticColorPalette[appearance.colorScheme], appearance: appearance)
        let unpinned = model.state.tabs(in: space.id, pinned: false)
        VStack(alignment: .leading, spacing: 0) {
            SpaceManagementCardHeader(
                model: model, space: space, isPickingIcon: $isPickingIcon, isEditingName: $isEditingName
            )
            .padding([.horizontal, .top], 8)
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(model.state.tabs(in: space.id, pinned: true)) { row($0) }
                    // As Arc's card: Clear shows without the pointer over it.
                    if !unpinned.isEmpty {
                        ClearDivider(model: model, spaceID: space.id, showsClear: true, inCard: true)
                    }
                    ForEach(unpinned) { row($0) }
                }
                .padding([.horizontal, .bottom], 8)
                .animation(
                    .timingCurve(0.25, 0.1, 0.25, 1, duration: 0.12), value: model.state.tabs(in: space.id).map(\.id))
            }
            footer
        }
        .environment(\.colorScheme, appearance.colorScheme)
        .environment(\.theme, theme)
        .background { WindowSurface(background: background).environment(\.colorScheme, windowColorScheme) }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        // As Arc's: under the card, its `EaselBackground` casts the shadow.
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(appearance.colorScheme == .dark ? Color.black.opacity(0.5) : .white.opacity(0.85))
                .shadow(color: .black.opacity(0.15), radius: 12, y: 1)
        }
    }

    /// Arc's `SpaceControlsView`: the handle and "⋯", 28 pt each with GrayA4 under the pointer.
    private var footer: some View {
        HStack(spacing: 0) {
            SpaceManagementDraggerView()
                .gesture(
                    DragGesture(minimumDistance: 3, coordinateSpace: .named(SpaceManagementDrag.space))
                        .onChanged { moved?($0.translation) }
                        .onEnded { _ in dropped?() }
                )
            Spacer(minLength: 0)
            SpaceMenuButton {
                SpaceMenu(model: model, space: space, inLibrary: true) {
                    // Oa's own: where Arc's card shows the picker is unknown, so the header's opens.
                    isPickingIcon = true
                } rename: {
                    isEditingName = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(SpaceManagementControlStyle())
            .help("More options")
            .accessibilityLabel("More options")
        }
        .foregroundStyle(.primary.opacity(0.5))
        .padding(8)
    }

    private func row(_ tab: SidebarTab) -> some View {
        TabRow(model: model, layout: layout, tab: tab, spaceID: space.id, place: .card)
            .transition(.opacity)
    }
}

/// Arc's `SpaceManagementDrggerView`: the open hand over it, as Arc's cursor rect.
private struct SpaceManagementDraggerView: View {
    @State private var isHovered = false

    var body: some View {
        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 28, height: 28)
            .background(isHovered ? ARCUIColor.grayA4 : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onHover { inside in
                isHovered = inside
                if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
            }
            .help("Drag to Reorder Space")
            .accessibilityLabel("Drag to Reorder Space")
    }
}

private struct SpaceManagementControlStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverFill(configuration: configuration)
    }

    private struct HoverFill: View {
        let configuration: Configuration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .background(
                    isHovered ? ARCUIColor.grayA4 : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .onHover { isHovered = $0 }
        }
    }
}

/// Arc's item after the last card: a 30 pt `CircularProgressView` with a plus in a 48 pt square, activated under the
/// pointer.
private struct SpaceManagementAddSpaceView: View {
    let model: WindowModel
    @State private var isActivated = false

    var body: some View {
        Button {
            model.beginSpaceCreation()
        } label: {
            CircularProgressView(symbol: "plus", isActivated: isActivated)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("New Space")
        .accessibilityLabel("New Space")
        .onHover { isActivated = $0 }
    }
}
