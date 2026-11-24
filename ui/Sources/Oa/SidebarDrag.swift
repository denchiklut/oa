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
        /// The row whose middle the tab is held on, which it would make a split with or join, last when held on the
        /// right half of a split's cell.
        var combine: UUID?
        var combinesLast = false
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

    /// A tab, or a split's cell or tile, which moves whole.
    private(set) var entry: SidebarEntry?
    /// The multi-selection the dragged row is in, in the sidebar's order, which moves with it.
    private(set) var memberIDs: [UUID] = []
    /// As seen in Arc's stack: the selected tab in front when it is a member, else the dragged row.
    private(set) var stack: [SidebarTab] = []
    /// A link dragged in from a page.
    @ObservationIgnored private var link = false
    private(set) var source: Section?
    private(set) var target: Target?
    private(set) var location = CGPoint.zero
    /// 0 a row, 1 a tile.
    private(set) var morph: CGFloat = 0
    /// 0 the row or tile, 1 Arc's page card, shown while the tab is over a place on the page.
    private(set) var pageCard: CGFloat = 0
    private(set) var cardSize = CGSize.zero
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
    /// As Arc's `dropHapticSubject`s, one per Space's list and grid: the last slot each was sent, kept across drags.
    @ObservationIgnored private var hapticSlots: [HapticSource: Int] = [:]
    /// The row under the pointer's middle band, and since when.
    @ObservationIgnored private var combineCandidate: (id: UUID, since: Date)?

    private struct HapticSource: Hashable {
        var spaceID: UUID
        var grid: Bool
    }

    private enum Edge {
        case left
        case right
        case top
        case bottom
    }

    var lineRect: CGRect? { settling ? nil : target?.line }

    func update(
        _ entry: SidebarEntry, from section: Section, glyph: SidebarCellButton.Glyph, at location: CGPoint,
        start: CGPoint, previous: UUID? = nil, members: [UUID] = [], model: WindowModel,
        layout: WindowLayoutController
    ) {
        guard !settling else { return }
        if self.entry?.id != entry.id {
            guard hypot(location.x - start.x, location.y - start.y) >= 4 else { return }
            begin(entry, from: section, glyph: glyph, start: start, members: members, model: model, layout: layout)
            previousTabID = previous
        }
        self.location = location
        retarget(model: model)
    }

    /// As seen in Arc: a link dragged from a page over the list shows the line, and over a split's cell joins it.
    func updateLink(at point: CGPoint, model: WindowModel) {
        link = true
        location = point
        retarget(model: model)
    }

    /// Where the link was let go.
    @discardableResult
    func endLink() -> Target? {
        defer {
            link = false
            combineCandidate = nil
            target = nil
        }
        return link ? target : nil
    }

    private func retarget(model: WindowModel) {
        let next = target(at: location, model: model)
        if next != target { target = next }
        if let next, next.combine == nil { tick(at: next, in: model.selectedSpaceID) }
        let dropTarget = next == nil ? splitViewDropTarget(at: location, model: model) : nil
        if dropTarget != model.proposedSplitViewDropTarget { model.proposedSplitViewDropTarget = dropTarget }
        // As measured on Arc: AppKit turns the drag image into the card over about 0.2 s.
        let card: CGFloat = dropTarget == nil ? 0 : 1
        if card == 1 { cardSize = pageCardSize(model: model) }
        if card != pageCard { withAnimation(.easeOut(duration: 0.2)) { pageCard = card } }
        let shape: CGFloat = next?.section == .favorites ? 1 : 0
        if next != nil, shape != morph {
            withAnimation(.easeInOut(duration: shape == 1 ? 0.28 : 0.2)) { morph = shape }
        }
    }

    /// As Arc: a tick when an insertion slot differs from the last one, which counts even with haptics off; a drop
    /// onto a row sends nothing.
    private func tick(at target: Target, in spaceID: UUID) {
        let source = HapticSource(spaceID: spaceID, grid: target.section == .favorites)
        guard hapticSlots.updateValue(target.index, forKey: source) != target.index,
            !TabReorderingHaptics.isDisabled
        else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    /// Over a place, the tab moves there at once and the copy glides onto it; elsewhere it glides back.
    func finish(model: WindowModel, layout: WindowLayoutController) {
        guard let entry, let tab = entry.tabs.first, !settling else { return }
        heldEdge = nil
        combineCandidate = nil
        // As seen in Arc: a drag ends the multi-selection however it ends.
        model.clearMultiSelection()
        let memberIDs = memberIDs
        self.memberIDs = []
        if model.proposedSplitViewDropTarget != nil || target?.combine != nil {
            if let combine = target?.combine, !memberIDs.isEmpty {
                model.combineIntoSplitView(memberIDs, onto: combine, last: target?.combinesLast == true)
            } else if let combine = target?.combine {
                model.combineIntoSplitView(tab.id, onto: combine, last: target?.combinesLast == true)
            } else {
                model.acceptSplitViewDrop(of: tab.id)
            }
            self.entry = nil
            stack = []
            target = nil
            source = nil
            showsPrevious = false
            pageCard = 0
            return layout.setHold(.drag, false)
        }
        // Oa's own: a tab dropped anywhere else is the selected one, as before it was dragged over the page.
        if showsPrevious {
            if case .splitView(let id, _) = entry { model.selectSplitView(id) } else { model.select(tab.id) }
        }
        showsPrevious = false
        settling = true
        let target = target
        if let target {
            switch target.section {
            case .favorites where !memberIDs.isEmpty:
                model.favorite(memberIDs, at: target.index)
            case .pinned where !memberIDs.isEmpty, .today where !memberIDs.isEmpty:
                let pinned = target.section == .pinned
                let ids = model.state.entries(in: model.selectedSpaceID, pinned: pinned).map(\.id)
                let anchorID = ids.prefix(target.index).last { !memberIDs.contains($0) }
                model.moveTabs(memberIDs, pinned: pinned, after: anchorID)
            case .favorites:
                let favorites = model.state.favoriteEntries(for: model.selectedSpaceID)
                let from = source == .favorites ? favorites.firstIndex { $0.id == entry.id } : nil
                // The grid's index leaves the tile out; the tree counts it where it was. A split's tab takes its
                // split.
                model.favorite(
                    tab.id, at: from.map { $0 < target.index ? target.index + 1 : target.index } ?? target.index)
            case .pinned, .today:
                model.move(entry.id, pinned: target.section == .pinned, at: target.index)
            }
        }
        let frontID = stack.first?.id ?? entry.id
        let before = rows[frontID]?.rect
        Task {
            // The row's new frame comes with the layout after the move; a row that stays put reports none.
            for _ in 0..<(target.map { $0.section != .favorites } == true ? 8 : 1) {
                try? await Task.sleep(for: .milliseconds(15))
                if let rect = rows[frontID]?.rect, rect != before { break }
            }
            let landing =
                switch target?.section {
                case .favorites: gap
                case .pinned, .today: rows[frontID]?.rect.insetBy(dx: 0, dy: 2) ?? origin
                case nil: origin
                }
            let anchor = morph == 1 ? tileAnchor : rowAnchor
            withAnimation(.easeOut(duration: 0.16)) {
                location = CGPoint(x: landing.minX + anchor.x, y: landing.minY + anchor.y)
            }
            try? await Task.sleep(for: .milliseconds(280))
            self.entry = nil
            stack = []
            source = nil
            self.target = nil
            settling = false
            pageCard = 0
            layout.setHold(.drag, false)
        }
    }

    private func begin(
        _ entry: SidebarEntry, from section: Section, glyph: SidebarCellButton.Glyph, start: CGPoint,
        members: [UUID], model: WindowModel, layout: WindowLayoutController
    ) {
        let others = model.state.favoriteEntries(for: model.selectedSpaceID).filter { $0.id != entry.id }.count
        let slots = FavoritesGrid.Layout(count: others + 1, width: layout.sidebarWidth)
        rowSize = CGSize(width: layout.sidebarWidth - 16, height: 36)
        tileSize = CGSize(width: slots.tileWidth, height: 47)
        if section == .favorites, let rect = tiles[entry.id] {
            origin = rect
            tileAnchor = CGPoint(x: start.x - rect.minX, y: start.y - rect.minY)
            rowAnchor = CGPoint(x: 18 + tileAnchor.x - rect.width / 2, y: tileAnchor.y * 36 / 47)
            morph = 1
        } else {
            let card = rows[entry.id]?.rect.insetBy(dx: 0, dy: 2) ?? CGRect(origin: start, size: rowSize)
            origin = card
            rowAnchor = CGPoint(x: start.x - card.minX, y: start.y - card.minY)
            tileAnchor = CGPoint(
                x: min(max(tileSize.width / 2 + rowAnchor.x - 18, 6), tileSize.width - 6), y: rowAnchor.y * 47 / 36)
            morph = 0
        }
        self.entry = entry
        memberIDs = members
        let frontID = model.selectedTabID.flatMap { members.contains($0) ? $0 : nil } ?? entry.id
        let tabs = members.compactMap { model.state.tree.tab($0) }
        stack = tabs.filter { $0.id == frontID } + tabs.filter { $0.id != frontID }
        source = section
        self.glyph = glyph
        layout.setHold(.drag, true)
    }

    /// Arc's page drop. Over the page the window shows what it showed before the press, as Arc's does once the drag
    /// begins. An edge of a pane inserts there and the rest of it replaces its tab. As measured on a lone page: the
    /// outer 40 % at the sides, 50 pt at the top and 40 pt at the bottom, and an edge once entered holds over the
    /// half its preview takes. In a split, whose edges weren't measured: those of its orientation while it has room,
    /// LIKELY by Arc's other sizes, a third of the pane up to 80 pt at the sides and 50 pt at the ends, with no hold.
    /// A pinned tab or a Favorite goes in as itself and a copy keeps its place, LIKELY as by Arc's other ways in.
    private func splitViewDropTarget(at point: CGPoint, model: WindowModel) -> SplitViewDropTarget? {
        // As seen in Arc: several rows over the page show no drop.
        guard let entry, memberIDs.isEmpty, pageArea.contains(point), model.library == nil, !model.coversWindow else {
            heldEdge = nil
            return nil
        }
        if !showsPrevious, let previousTabID, !entry.tabs.contains(where: { $0.id == previousTabID }),
            entry.tabs.contains(where: { $0.id == model.selectedTabID })
        {
            model.select(previousTabID)
            showsPrevious = true
        }
        let tabIDs = model.presentedTabIDs
        guard case .tab(let tab) = entry, let anchorID = model.selectedTabID, !tabIDs.contains(tab.id),
            model.state.canJoinSplitView(tab.id, of: anchorID, in: model.selectedSpaceID)
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

    /// As measured on Arc: the card is the pane one more pane would make, scaled to 249 pt for the page's height,
    /// so 176 pt wide over a lone page and 70 over a full split. A stacked split's is Oa's own, at the same scale.
    private func pageCardSize(model: WindowModel) -> CGSize {
        let splitID = model.selectedTabID.flatMap(model.state.splitViewID(containing:))
        let count = model.presentedTabIDs.count + 1
        let frames = SplitViewContentPanes.frames(
            Array(repeating: 1 / CGFloat(count), count: count), in: pageArea,
            vertical: splitID != nil && model.splitViewLayoutOrientation == .vertical)
        let scale = 249 / max(pageArea.height, 1)
        return CGSize(width: (frames.first?.width ?? 0) * scale, height: (frames.first?.height ?? 0) * scale)
    }

    /// The pointer picks the place, as AppKit's drag destinations do: among the Favorites the slot under it, in the
    /// list the gap between the rows around it.
    private func target(at point: CGPoint, model: WindowModel) -> Target? {
        guard entry != nil || link, let list = lists[model.selectedSpaceID] else { return nil }
        if grid.contains(point) {
            // A link dropped on the Favorites wasn't tried in Arc; Oa's own: nothing.
            guard let entry else { return nil }
            let others = model.state.favoriteEntries(for: model.selectedSpaceID).filter { $0.id != entry.id }.count
            let slots = FavoritesGrid.Layout(count: others + 1, width: grid.width)
            let column = Int((point.x - grid.minX - 4) / (slots.tileWidth + 8))
            let row = Int((point.y - grid.minY - 4) / 55)
            let index = min(max(row, 0), slots.rows - 1) * slots.columns + min(max(column, 0), slots.columns - 1)
            return Target(section: .favorites, index: min(index, others))
        }
        guard list.area.contains(point) else { return nil }
        let pinnedIDs = model.state.entries(in: model.selectedSpaceID, pinned: true).map(\.id)
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
        let section = pinned ? Section.pinned : .today
        if let combine = combineTarget(at: point, among: ids, model: model) {
            let last = model.state.splitView(combine) != nil && point.x > rows[combine]?.rect.midX ?? .infinity
            return Target(section: section, index: index, combine: combine, combinesLast: last)
        }
        let line = CGRect(x: list.area.minX + 16, y: y - 3, width: list.area.width - 27.5, height: 6)
        return Target(section: section, index: index, line: line)
    }

    /// As measured on Arc: a tab held on the middle half of another row for 0.2 s from entering it would make a split
    /// with it, or join its split, and on a row's edges the line comes back. A split's cell takes a dragged split
    /// nowhere, and a link only into a split: Arc's link held on a plain row goes into its tab's item, out of sight,
    /// so Oa's opens at the line.
    private func combineTarget(at point: CGPoint, among ids: [UUID], model: WindowModel) -> UUID? {
        let held: UUID? = if case .tab(let tab) = entry { tab.id } else { nil }
        let band = { (rect: CGRect) in rect.minY + 11 <= point.y && point.y <= rect.minY + 32 }
        let canCombine = { (id: UUID) in
            if !self.memberIDs.isEmpty { return !model.combinedTabIDs(self.memberIDs, onto: id).isEmpty }
            return held.map { model.canCombineIntoSplitView($0, onto: id) } ?? model.canDropLink(inSplitView: id)
        }
        guard held != nil || link,
            let id = ids.first(where: { rows[$0].map { $0.rect.contains(point) && band($0.rect) } == true }),
            canCombine(id)
        else {
            combineCandidate = nil
            return nil
        }
        guard let candidate = combineCandidate, candidate.id == id else {
            combineCandidate = (id, .now)
            Task {
                try? await Task.sleep(for: .milliseconds(200))
                if combineCandidate?.id == id { retarget(model: model) }
            }
            return target?.combine == id ? id : nil
        }
        return Date.now.timeIntervalSince(candidate.since) >= 0.19 ? id : nil
    }
}

extension EnvironmentValues {
    @Entry var sidebarDrag: SidebarDrag?
}

struct SidebarLinkDrop: DropDelegate {
    let model: WindowModel
    let drag: SidebarDrag

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.url]) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        drag.updateLink(at: info.location, model: model)
        return DropProposal(operation: drag.target == nil ? .forbidden : .copy)
    }

    func dropExited(info: DropInfo) { drag.endLink() }

    func performDrop(info: DropInfo) -> Bool {
        guard let target = drag.endLink(), let provider = info.itemProviders(for: [.url]).first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in
                if let splitID = target.combine {
                    model.openDroppedLink(url, inSplitView: splitID, last: target.combinesLast)
                } else {
                    model.openDroppedLink(url, pinned: target.section == .pinned, at: target.index)
                }
            }
        }
        return true
    }
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
            // As seen in Arc: held on a tab's row, the copy is gone into the row's preview of the split.
            if let entry = drag.entry, drag.target?.combine.map({ model.state.splitView($0) != nil }) ?? true {
                if drag.stack.isEmpty {
                    SidebarDragPreview(model: model, drag: drag, entry: entry, morph: drag.morph, card: drag.pageCard)
                } else {
                    // As seen in Arc: AppKit's stack, up to three rows each 6 pt down and right, the count at its
                    // corner.
                    let shown = Array(drag.stack.prefix(3).enumerated())
                    ForEach(shown.reversed(), id: \.element.id) { depth, tab in
                        SidebarDragPreview(
                            model: model, drag: drag, entry: .tab(tab), morph: drag.morph, depth: CGFloat(depth),
                            count: depth == 0 ? drag.stack.count : nil)
                    }
                }
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
/// whole turn between them. A split's copy carries its tabs' favicons, from their places in its cell to theirs in its
/// tile.
private struct SidebarDragPreview: View, Animatable {
    let model: WindowModel
    let drag: SidebarDrag
    let entry: SidebarEntry
    var morph: CGFloat
    var card: CGFloat = 0
    var depth: CGFloat = 0
    var count: Int?
    @Environment(\.theme) private var theme

    nonisolated var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(morph, card) }
        set {
            morph = newValue.first
            card = newValue.second
        }
    }

    var body: some View {
        let t = min(max(morph, 0), 1)
        let c = min(max(card, 0), 1)
        let baseWidth = drag.rowSize.width + (drag.tileSize.width - drag.rowSize.width) * t
        let baseHeight = drag.rowSize.height + (drag.tileSize.height - drag.rowSize.height) * t
        let baseAnchor = CGPoint(
            x: drag.rowAnchor.x + (drag.tileAnchor.x - drag.rowAnchor.x) * t,
            y: drag.rowAnchor.y + (drag.tileAnchor.y - drag.rowAnchor.y) * t)
        // As measured on Arc: the card keeps the pointer where it held the row, relatively.
        let cardAnchor = CGPoint(
            x: baseAnchor.x / max(baseWidth, 1) * drag.cardSize.width,
            y: baseAnchor.y / max(baseHeight, 1) * drag.cardSize.height)
        let width = baseWidth + (drag.cardSize.width - baseWidth) * c
        let height = baseHeight + (drag.cardSize.height - baseHeight) * c
        let anchor = CGPoint(
            x: baseAnchor.x + (cardAnchor.x - baseAnchor.x) * c, y: baseAnchor.y + (cardAnchor.y - baseAnchor.y) * c)
        let shape = RoundedRectangle(cornerRadius: 12 + 8 * c, style: .continuous)
        ZStack(alignment: .topLeading) {
            shape.fill(theme.selectedCard).opacity(1 - t)
            shape.fill(theme.selectedTile).opacity(t)
            switch entry {
            case .tab(let tab):
                if let favicon = model.favicon(for: tab) {
                    AppTrayRing(favicon: favicon, tileWidth: width).opacity(t)
                }
                title(model.title(for: tab), at: 36, height: height, t: t)
                glyph(width: width, height: height, t: t)
                TabFavicon(model: model, tab: tab)
                    .frame(width: 16, height: 16)
                    .offset(x: 10 + (width / 2 - 18) * t, y: (height - 16) / 2)
            case .splitView(let id, let tabs):
                SplitAppTrayRing(favicons: tabs.map(model.favicon(for:)), tileWidth: width).opacity(t)
                let data = model.state.splitView(id)
                if data?.title != nil || data?.icon != nil {
                    Group {
                        if let icon = data?.icon {
                            SpaceIconGlyph(icon: icon)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(theme.secondaryGlyph)
                        } else {
                            SplitViewCountBadge(model: model, count: tabs.count)
                        }
                    }
                    .frame(width: 24, height: 24)
                    .offset(x: 8.5, y: (height - 24) / 2)
                    .opacity(max(0, 1 - t * 4))
                    title(data?.title ?? "\(tabs.count) Tabs", at: 39, height: height, t: t)
                    glyph(width: width, height: height, t: t)
                } else {
                    // As measured on Arc: the cell as it is selected and under the pointer, each tab's card with its
                    // ✕, 4 pt in and 8.5 pt apart; as the tile, its parts 2 pt apart.
                    let count = CGFloat(tabs.count)
                    let row = (drag.rowSize.width - 8 - 8.5 * (count - 1)) / count
                    let tile = (drag.tileSize.width - 2 * (count - 1)) / count
                    ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                        let i = CGFloat(index)
                        let size = 16 - 4 * t
                        let rowX = 4 + i * (row + 8.5)
                        let tileX = i * (tile + 2) + (tile - size) / 2
                        Group {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(theme.isDark ? .white.opacity(0.07) : .black.opacity(0.08))
                                .frame(width: row, height: 28)
                                .offset(x: rowX, y: (height - 28) / 2)
                            CellGlyph(glyph: .close)
                                .frame(width: 24, height: 24)
                                .offset(x: rowX + row - 26, y: (height - 24) / 2)
                        }
                        .opacity(max(0, 1 - t * 4))
                        TabFavicon(model: model, tab: tab)
                            .scaleEffect(size / 16)
                            .frame(width: size, height: size)
                            .offset(x: rowX + 4.5 + (tileX - rowX - 4.5) * t, y: (height - size) / 2)
                    }
                }
            }
        }
        .opacity(1 - c)
        .frame(width: width, height: height, alignment: .topLeading)
        .overlay { if c > 0, case .tab(let tab) = entry { pageCardContent(tab).opacity(c) } }
        .clipShape(shape)
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        // As measured on Arc: a split's copy at 0.9, and the page card black at 0.9 over the page.
        .opacity({ if case .splitView = entry { 0.9 } else { 0.7 + 0.3 * c } }())
        .overlay(alignment: .topLeading) {
            if let count {
                // Arc's red 18 pt badge, on the stack's corner rather than left of it as Arc's, which the window
                // would cut off: Oa's drag is drawn in the window, Arc's in a screen-wide one.
                Text("\(count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Capsule().fill(Color(nsColor: .systemRed)))
                    .offset(x: -6, y: -9)
            }
        }
        .offset(x: drag.location.x - anchor.x + depth * 6, y: drag.location.y - anchor.y + depth * 6)
    }

    /// Arc's card over the page, as measured: black at 0.9, the 16 pt favicon centred 42 % down and the title in
    /// bold white centred 56 % down.
    private func pageCardContent(_ tab: SidebarTab) -> some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.9)
                TabFavicon(model: model, tab: tab)
                    .frame(width: 16, height: 16)
                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.42)
                Text(model.title(for: tab))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 8)
                    .frame(width: geometry.size.width)
                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.56)
            }
        }
    }

    private func title(_ text: String, at x: CGFloat, width: CGFloat? = nil, height: CGFloat, t: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(theme.foreground)
            .lineLimit(1)
            .frame(width: max(width ?? (drag.rowSize.width - x - 40), 1), height: height, alignment: .leading)
            .offset(x: x)
            .opacity(max(0, 1 - t * 4))
    }

    private func glyph(width: CGFloat, height: CGFloat, t: CGFloat) -> some View {
        CellGlyph(glyph: drag.glyph)
            .frame(width: 24, height: 24)
            .offset(x: width - 30, y: (height - 24) / 2)
            .opacity(max(0, 1 - t * 4))
    }
}

/// Arc's key, stored as the PiP one is: absent means on.
enum TabReorderingHaptics {
    static let key = "tabReorderingHapticsDisabled"

    static var isDisabled: Bool { UserDefaults.standard.bool(forKey: key) }
}
