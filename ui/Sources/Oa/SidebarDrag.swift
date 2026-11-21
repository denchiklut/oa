import SwiftUI

/// Arc's sidebar drag as measured: past 4 pt a translucent copy of the row or tile follows the pointer while the
/// rows stay put, a drop line marks the gap in the list, and over the Favorites the grid opens a slot and the copy
/// turns into a tile. Arc runs it on AppKit's drag session over its outline and collection views; Oa draws it in
/// SwiftUI, after open-arch, so the copy can morph and the grid can reflow under it.
@MainActor @Observable
final class SidebarDrag {
    nonisolated static let space = "SidebarDrag"

    enum Section: Equatable {
        case favorites
        case pinned
        case today
    }

    struct Target: Equatable {
        var section: Section
        /// Among the list's rows as they stand, the dragged one included; among the Favorites, which it has left,
        /// without it.
        var index: Int
        var line: CGRect?
    }

    struct RowFrame {
        var rect: CGRect
        var spaceID: UUID
    }

    struct ListFrame {
        var area = CGRect.zero
        var pinnedTop: CGFloat = 0
        var divider: CGRect?
        var newTab = CGRect.zero
    }

    @ObservationIgnored var rows: [UUID: RowFrame] = [:]
    @ObservationIgnored var lists: [UUID: ListFrame] = [:]
    /// The current Space's Favorites with their insets, and the slot they open.
    @ObservationIgnored var grid = CGRect.zero
    @ObservationIgnored var gap = CGRect.zero
    @ObservationIgnored var tiles: [UUID: CGRect] = [:]
    /// Where the window's page or panes are.
    @ObservationIgnored var pageArea = CGRect.zero

    private(set) var tab: SidebarTab?
    private(set) var source: Section?
    private(set) var target: Target?
    private(set) var location = CGPoint.zero
    /// 0 a row, 1 a tile.
    private(set) var morph: CGFloat = 0
    private(set) var glyph = SidebarCellButton.Glyph.close
    private(set) var settling = false
    private(set) var rowSize = CGSize.zero
    private(set) var tileSize = CGSize.zero
    private(set) var rowAnchor = CGPoint.zero
    private(set) var tileAnchor = CGPoint.zero
    @ObservationIgnored private var origin = CGRect.zero
    /// The tab the window showed before the press selected the dragged one.
    @ObservationIgnored private var previousTabID: UUID?
    @ObservationIgnored private var showsPrevious = false
    /// As measured on Arc: the edge of a pane the pointer entered, which holds until the pane's middle.
    @ObservationIgnored private var heldEdge: (pane: Int, edge: Edge)?

    private enum Edge {
        case left
        case right
        case top
        case bottom
    }

    var lineRect: CGRect? { settling ? nil : target?.line }

    func update(
        _ tab: SidebarTab, from section: Section, glyph: SidebarCellButton.Glyph, at location: CGPoint,
        start: CGPoint, previous: UUID? = nil, model: WindowModel, layout: WindowLayoutController
    ) {
        guard !settling else { return }
        if self.tab?.id != tab.id {
            guard hypot(location.x - start.x, location.y - start.y) >= 4 else { return }
            begin(tab, from: section, glyph: glyph, start: start, model: model, layout: layout)
            previousTabID = previous
        }
        self.location = location
        let next = target(at: location, model: model)
        if next != target { target = next }
        let dropTarget = next == nil ? splitViewDropTarget(at: location, model: model) : nil
        if dropTarget != model.proposedSplitViewDropTarget { model.proposedSplitViewDropTarget = dropTarget }
        let shape: CGFloat = next?.section == .favorites ? 1 : 0
        if next != nil, shape != morph {
            withAnimation(.easeInOut(duration: shape == 1 ? 0.28 : 0.2)) { morph = shape }
        }
    }

    /// Over a place, the tab moves there at once and the copy glides onto it; elsewhere it glides back.
    func finish(model: WindowModel, layout: WindowLayoutController) {
        guard let tab, !settling else { return }
        heldEdge = nil
        if model.proposedSplitViewDropTarget != nil {
            model.acceptSplitViewDrop(of: tab.id)
            self.tab = nil
            source = nil
            showsPrevious = false
            return layout.setHold(.drag, false)
        }
        // Oa's own: a tab dropped anywhere else is the selected one, as before it was dragged over the page.
        if showsPrevious { model.select(tab.id) }
        showsPrevious = false
        settling = true
        let target = target
        if let target {
            switch target.section {
            case .favorites:
                let favorites = model.state.favorites(for: model.selectedSpaceID)
                let from = source == .favorites ? favorites.firstIndex { $0.id == tab.id } : nil
                // The grid's index leaves the tile out; the tree counts it where it was.
                model.favorite(
                    tab.id, at: from.map { $0 < target.index ? target.index + 1 : target.index } ?? target.index)
            case .pinned, .today:
                model.move(tab.id, pinned: target.section == .pinned, at: target.index)
            }
        }
        let before = rows[tab.id]?.rect
        Task {
            // The row's new frame comes with the layout after the move; a row that stays put reports none.
            for _ in 0..<(target.map { $0.section != .favorites } == true ? 8 : 1) {
                try? await Task.sleep(for: .milliseconds(15))
                if let rect = rows[tab.id]?.rect, rect != before { break }
            }
            let landing =
                switch target?.section {
                case .favorites: gap
                case .pinned, .today: rows[tab.id]?.rect.insetBy(dx: 0, dy: 2) ?? origin
                case nil: origin
                }
            let anchor = morph == 1 ? tileAnchor : rowAnchor
            withAnimation(.easeOut(duration: 0.16)) {
                location = CGPoint(x: landing.minX + anchor.x, y: landing.minY + anchor.y)
            }
            try? await Task.sleep(for: .milliseconds(280))
            self.tab = nil
            source = nil
            self.target = nil
            settling = false
            layout.setHold(.drag, false)
        }
    }

    private func begin(
        _ tab: SidebarTab, from section: Section, glyph: SidebarCellButton.Glyph, start: CGPoint, model: WindowModel,
        layout: WindowLayoutController
    ) {
        let others = model.state.favorites(for: model.selectedSpaceID).filter { $0.id != tab.id }.count
        let slots = FavoritesGrid.Layout(count: others + 1, width: layout.sidebarWidth)
        rowSize = CGSize(width: layout.sidebarWidth - 16, height: 36)
        tileSize = CGSize(width: slots.tileWidth, height: 47)
        if section == .favorites, let rect = tiles[tab.id] {
            origin = rect
            tileAnchor = CGPoint(x: start.x - rect.minX, y: start.y - rect.minY)
            rowAnchor = CGPoint(x: 18 + tileAnchor.x - rect.width / 2, y: tileAnchor.y * 36 / 47)
            morph = 1
        } else {
            let card = rows[tab.id]?.rect.insetBy(dx: 0, dy: 2) ?? CGRect(origin: start, size: rowSize)
            origin = card
            rowAnchor = CGPoint(x: start.x - card.minX, y: start.y - card.minY)
            tileAnchor = CGPoint(
                x: min(max(tileSize.width / 2 + rowAnchor.x - 18, 6), tileSize.width - 6), y: rowAnchor.y * 47 / 36)
            morph = 0
        }
        self.tab = tab
        source = section
        self.glyph = glyph
        layout.setHold(.drag, true)
    }

    /// Arc's page drop. Over the page the window shows what it showed before the press, as Arc's does once the drag
    /// begins. An edge of a pane inserts there and the rest of it replaces its tab. As measured on a lone page: the
    /// outer 40 % at the sides, 50 pt at the top and 40 pt at the bottom, and an edge once entered holds over the
    /// half its preview takes. In a split, whose edges weren't measured: those of its orientation while it has room,
    /// LIKELY by Arc's other sizes, a third of the pane up to 80 pt at the sides and 50 pt at the ends, with no hold.
    /// Oa's own for now: only a tab that can be in a split, so not a pinned one or a Favorite.
    private func splitViewDropTarget(at point: CGPoint, model: WindowModel) -> SplitViewDropTarget? {
        guard let tab, pageArea.contains(point), model.library == nil, !model.coversWindow else {
            heldEdge = nil
            return nil
        }
        if !showsPrevious, let previousTabID, previousTabID != tab.id, model.selectedTabID == tab.id {
            model.select(previousTabID)
            showsPrevious = true
        }
        let tabIDs = model.presentedTabIDs
        guard let anchorID = model.selectedTabID, !tabIDs.contains(tab.id),
            model.state.canJoinSplitView(tab.id, of: anchorID)
        else { return nil }
        let splitID = model.state.splitViewID(containing: anchorID)
        let orientation = model.splitViewLayoutOrientation
        let frames = SplitViewContentPanes.frames(
            splitID.map(model.paneShares(of:)) ?? [1], in: pageArea, vertical: orientation == .vertical)
        guard let pane = frames.firstIndex(where: { $0.insetBy(dx: -5, dy: -5).contains(point) }) else { return nil }
        let frame = frames[pane]
        let x = (point.x - frame.minX) / frame.width
        let y = (point.y - frame.minY) / frame.height
        var edge: Edge?
        if splitID == nil {
            let holds =
                switch heldEdge?.edge {
                case .left: x < 0.5
                case .right: x > 0.5
                case .top: y < 0.5
                case .bottom: y > 0.5
                case nil: false
                }
            if holds {
                edge = heldEdge?.edge
            } else if point.y <= frame.minY + min(frame.height / 3, 50) {
                edge = .top
            } else if point.y >= frame.maxY - 40 {
                edge = .bottom
            } else if x <= 0.4 {
                edge = .left
            } else if x >= 0.6 {
                edge = .right
            }
        } else if orientation == .horizontal {
            let side = min(frame.width / 3, 80)
            edge = point.x <= frame.minX + side ? .left : point.x >= frame.maxX - side ? .right : nil
        } else {
            let end = min(frame.height / 3, 50)
            edge = point.y <= frame.minY + end ? .top : point.y >= frame.maxY - end ? .bottom : nil
        }
        guard let edge, tabIDs.count < SidebarSplitViewData.maxNumberSplit else {
            heldEdge = nil
            return SplitViewDropTarget(target: .replaceContent(pane), layoutOrientation: orientation)
        }
        heldEdge = (pane, edge)
        return SplitViewDropTarget(
            target: .insertContent(edge == .left || edge == .top ? pane : pane + 1),
            layoutOrientation: splitID != nil ? orientation : edge == .left || edge == .right ? .horizontal : .vertical)
    }

    /// The pointer picks the place, as AppKit's drag destinations do: among the Favorites the slot under it, in the
    /// list the gap between the rows around it.
    private func target(at point: CGPoint, model: WindowModel) -> Target? {
        guard let tab, let list = lists[model.selectedSpaceID] else { return nil }
        if grid.contains(point) {
            let others = model.state.favorites(for: model.selectedSpaceID).filter { $0.id != tab.id }.count
            let slots = FavoritesGrid.Layout(count: others + 1, width: grid.width)
            let column = Int((point.x - grid.minX - 4) / (slots.tileWidth + 8))
            let row = Int((point.y - grid.minY - 4) / 55)
            let index = min(max(row, 0), slots.rows - 1) * slots.columns + min(max(column, 0), slots.columns - 1)
            return Target(section: .favorites, index: min(index, others))
        }
        guard list.area.contains(point) else { return nil }
        let pinnedIDs = model.state.tabs(in: model.selectedSpaceID, pinned: true).map(\.id)
        let boundary =
            list.divider?.midY ?? (list.newTab != .zero ? list.newTab.minY : nil)
            ?? pinnedIDs.compactMap { rows[$0]?.rect.maxY }.max() ?? list.pinnedTop
        let pinned = point.y < boundary
        let ids = pinned ? pinnedIDs : model.state.entries(in: model.selectedSpaceID, pinned: false).map(\.id)
        let index = ids.filter { (rows[$0]?.rect.midY ?? .infinity) < point.y }.count
        let y: CGFloat =
            if index < ids.count, let rect = rows[ids[index]]?.rect {
                rect.minY - 0.5
            } else if let last = ids.last, let rect = rows[last]?.rect {
                rect.maxY + 0.5
            } else {
                pinned ? list.pinnedTop : list.newTab.maxY + 0.5
            }
        let line = CGRect(x: list.area.minX + 16, y: y - 3, width: list.area.width - 27.5, height: 6)
        return Target(section: pinned ? .pinned : .today, index: index, line: line)
    }
}

extension EnvironmentValues {
    @Entry var sidebarDrag: SidebarDrag?
}

extension View {
    func sidebarDragFrame(_ report: @escaping (CGRect) -> Void) -> some View {
        onGeometryChange(for: CGRect.self) {
            $0.frame(in: .named(SidebarDrag.space))
        } action: {
            report($0)
        }
    }
}

/// Over the window, so the copy passes over the page's edge as Arc's does.
struct SidebarDragLayer: View {
    let model: WindowModel
    let drag: SidebarDrag

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let line = drag.lineRect {
                SidebarDropLine()
                    .frame(width: line.width, height: line.height)
                    .offset(x: line.minX, y: line.minY)
            }
            if let tab = drag.tab {
                SidebarDragPreview(model: model, drag: drag, tab: tab, morph: drag.morph)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// Arc's drop line: 2 pt with a 6 pt ring at its leading end, in Arc's `dropHighlightColor` as measured.
private struct SidebarDropLine: View {
    private static let color = Color(.sRGB, red: 0x1E / 255, green: 0x29 / 255, blue: 1)

    var body: some View {
        HStack(spacing: 0) {
            Circle().strokeBorder(Self.color, lineWidth: 2).frame(width: 6, height: 6)
            Rectangle().fill(Self.color).frame(height: 2)
        }
    }
}

/// The lifted copy: the selected row's card or the selected tile, laid out from `morph` so SwiftUI animates the
/// whole turn between them.
private struct SidebarDragPreview: View, Animatable {
    let model: WindowModel
    let drag: SidebarDrag
    let tab: SidebarTab
    var morph: CGFloat
    @Environment(\.theme) private var theme

    nonisolated var animatableData: CGFloat {
        get { morph }
        set { morph = newValue }
    }

    var body: some View {
        let t = min(max(morph, 0), 1)
        let width = drag.rowSize.width + (drag.tileSize.width - drag.rowSize.width) * t
        let height = drag.rowSize.height + (drag.tileSize.height - drag.rowSize.height) * t
        let anchor = CGPoint(
            x: drag.rowAnchor.x + (drag.tileAnchor.x - drag.rowAnchor.x) * t,
            y: drag.rowAnchor.y + (drag.tileAnchor.y - drag.rowAnchor.y) * t)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let favicon = model.favicon(for: tab)
        ZStack(alignment: .topLeading) {
            shape.fill(theme.selectedCard).opacity(1 - t)
            shape.fill(theme.selectedTile).opacity(t)
            if let favicon { AppTrayRing(favicon: favicon, tileWidth: width).opacity(t) }
            Text(model.title(for: tab))
                .font(.system(size: 14))
                .foregroundStyle(theme.foreground)
                .lineLimit(1)
                .frame(width: max(drag.rowSize.width - 36 - 40, 1), height: height, alignment: .leading)
                .offset(x: 36)
                .opacity(max(0, 1 - t * 4))
            CellGlyph(glyph: drag.glyph)
                .frame(width: 24, height: 24)
                .offset(x: width - 30, y: (height - 24) / 2)
                .opacity(max(0, 1 - t * 4))
            TabFavicon(model: model, tab: tab)
                .frame(width: 16, height: 16)
                .offset(x: 10 + (width / 2 - 18) * t, y: (height - 16) / 2)
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipShape(shape)
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        .opacity(0.7)
        .offset(x: drag.location.x - anchor.x, y: drag.location.y - anchor.y)
    }
}
