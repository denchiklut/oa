import Foundation

/// Arc's `SidebarSplitViewData`, on a sidebar item whose children are its tabs in pane order.
struct SidebarSplitViewData: Hashable {
    enum LayoutOrientation: String, Codable {
        case horizontal
        case vertical
    }

    /// Arc's `maxNumberSplit`.
    static let maxNumberSplit = 4

    /// A pane's share of the split. As Arc stores them: none while the panes are equal, and a pane left out takes
    /// an equal part of what the others leave.
    var itemWidthFactors: [UUID: CGFloat] = [:]
    var layoutOrientation = LayoutOrientation.horizontal
    /// Arc keeps it as the split item's own `title`, not with this data.
    var title: String?
    /// Arc's `customInfo.iconType`, kept as a Space's icon is: an SF Symbol's name or an emoji.
    var icon: String?

    func shares(of tabIDs: [UUID]) -> [CGFloat] {
        let known = tabIDs.compactMap { itemWidthFactors[$0] }
        let rest = max(1 - known.reduce(0, +), 0) / CGFloat(max(tabIDs.count - known.count, 1))
        let shares = tabIDs.map { itemWidthFactors[$0] ?? rest }
        let total = shares.reduce(0, +)
        return total > 0 ? shares.map { $0 / total } : tabIDs.map { _ in 1 / CGFloat(tabIDs.count) }
    }
}

extension SidebarSplitViewData: Codable {
    private enum Key: String, CodingKey { case itemWidthFactors, layoutOrientation, customInfo }
    private struct CustomInfo: Codable { var icon: String? }

    /// The factors as Arc writes them: a flat list of an item's ID and its factor in turn.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Key.self)
        layoutOrientation =
            try values.decodeIfPresent(LayoutOrientation.self, forKey: .layoutOrientation) ?? .horizontal
        icon = try values.decodeIfPresent(CustomInfo.self, forKey: .customInfo)?.icon
        guard values.contains(.itemWidthFactors) else { return }
        var factors = try values.nestedUnkeyedContainer(forKey: .itemWidthFactors)
        while !factors.isAtEnd { itemWidthFactors[try factors.decode(UUID.self)] = try factors.decode(CGFloat.self) }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: Key.self)
        try values.encode(layoutOrientation, forKey: .layoutOrientation)
        if let icon { try values.encode(CustomInfo(icon: icon), forKey: .customInfo) }
        var factors = values.nestedUnkeyedContainer(forKey: .itemWidthFactors)
        for (id, factor) in itemWidthFactors.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            try factors.encode(id)
            try factors.encode(factor)
        }
    }
}

/// A pane of the split a window shows: a tab's, or the empty one Add Split View opens until the command bar fills it,
/// as Arc's content with a placeholder blueprint.
enum SplitViewPane: Hashable {
    case tab(UUID)
    case empty
    /// Where a dragged tab would go.
    case dropTarget
}

/// Arc's `ProposedDropTargetInfo`: what a tab dragged over the page would do, among the window's panes.
struct SplitViewDropTarget: Equatable {
    enum Target: Equatable {
        case replaceContent(Int)
        case insertContent(Int)
    }

    var target: Target
    var layoutOrientation: SidebarSplitViewData.LayoutOrientation
}

/// Arc's `WindowSplitViewLayout`.
struct WindowSplitViewLayout {
    let splitID: UUID
    var itemWidthFactors: [UUID: CGFloat]
}

enum SidebarEntry: Identifiable, Hashable {
    case tab(SidebarTab)
    case splitView(id: UUID, tabs: [SidebarTab])

    var id: UUID {
        switch self {
        case .tab(let tab): tab.id
        case .splitView(let id, _): id
        }
    }

    var tabs: [SidebarTab] {
        switch self {
        case .tab(let tab): [tab]
        case .splitView(_, let tabs): tabs
        }
    }
}

extension SidebarState {
    func splitViewID(containing tabID: UUID) -> UUID? {
        guard let parentID = tree[tabID]?.parentID, case .splitView = tree[parentID]?.kind else { return nil }
        return parentID
    }

    func splitView(_ id: UUID) -> SidebarSplitViewData? {
        if case .splitView(let data) = tree[id]?.kind { return data }
        return nil
    }

    /// What a window shows with `tabID`: its split's tabs in pane order, or the tab alone.
    func presentedTabIDs(with tabID: UUID) -> [UUID] {
        splitViewID(containing: tabID).flatMap { tree[$0]?.childIDs } ?? [tabID]
    }

    func entries(in spaceID: UUID, pinned: Bool) -> [SidebarEntry] {
        guard let space = space(spaceID) else { return [] }
        return (tree[pinned ? space.pinnedRootID : space.unpinnedRootID]?.childIDs ?? []).compactMap { id in
            if let tab = tree.tab(id) { return .tab(tab) }
            if splitView(id) != nil { return .splitView(id: id, tabs: tree.tabs(under: id)) }
            return nil
        }
    }

    /// The Space a tab goes into a split in: its own, or for a Favorite the one shown.
    private func splitViewSpace(of tabID: UUID, shown spaceID: UUID) -> UUID? {
        isFavorite(tabID) ? (isSelectable(tabID, in: spaceID) ? spaceID : nil) : space(containing: tabID)?.id
    }

    /// As seen in Arc: a Favorite split takes no pane, its Add Tab… off.
    func canAddSplitViewPane(beside anchorID: UUID, in spaceID: UUID) -> Bool {
        splitViewSpace(of: anchorID, shown: spaceID) == spaceID
            && !(isFavorite(anchorID) && splitViewID(containing: anchorID) != nil)
            && presentedTabIDs(with: anchorID).count < SidebarSplitViewData.maxNumberSplit
    }

    func canOpenInSplitView(_ tabID: UUID, beside anchorID: UUID, in spaceID: UUID) -> Bool {
        canAddSplitViewPane(beside: anchorID, in: spaceID) && canJoinSplitView(tabID, of: anchorID, in: spaceID)
    }

    func canJoinSplitView(_ tabID: UUID, of anchorID: UUID, in spaceID: UUID) -> Bool {
        tabID != anchorID && splitViewID(containing: tabID) == nil
            && splitViewSpace(of: tabID, shown: spaceID) == spaceID
            && splitViewSpace(of: anchorID, shown: spaceID) == spaceID
    }

    /// As seen in Arc: a lone pinned tab or Favorite goes into a split as its own item, at the top of the Space's
    /// list, and a copy of it keeps its place. Returns the copy's ID.
    mutating func takeIntoSplitView(_ tabID: UUID, in spaceID: UUID) -> UUID? {
        guard keepsAddress(tabID), splitViewID(containing: tabID) == nil, let tab = tree.tab(tabID),
            let place = tree.location(of: tabID), let space = space(containing: tabID) ?? space(spaceID)
        else { return nil }
        let copy = SidebarTab(id: UUID(), title: tab.title, url: tab.url, viewedAt: .now)
        tree.insert(SidebarItem(id: copy.id, kind: .tab(copy)), into: place.parentID, at: place.index)
        tree.move(tabID, into: space.unpinnedRootID, at: 0)
        return copy.id
    }

    /// As Arc's `presentSplitViewWindowContent` with `newPane`: the tab becomes pane `index`, the last when nil, of the
    /// anchor's split, whose panes are equal again as Arc resets them, or of a split made where a lone anchor was.
    mutating func openInSplitView(_ tabID: UUID, beside anchorID: UUID, in spaceID: UUID, at index: Int? = nil) {
        guard canOpenInSplitView(tabID, beside: anchorID, in: spaceID) else { return }
        if let splitID = splitViewID(containing: anchorID) {
            tree.move(tabID, into: splitID, at: index)
            updateSplitView(splitID) { $0.itemWidthFactors = [:] }
        } else if let place = tree.location(of: anchorID) {
            let splitID = UUID()
            tree.insert(
                SidebarItem(id: splitID, kind: .splitView(SidebarSplitViewData())), into: place.parentID,
                at: place.index)
            tree.move(anchorID, into: splitID)
            tree.move(tabID, into: splitID, at: index)
        }
    }

    /// As seen in Arc: the tab takes the pane and its factor, and the pane's tab is a plain one again right after the
    /// split.
    mutating func replaceSplitViewPane(_ targetID: UUID, with tabID: UUID, in spaceID: UUID) {
        guard canJoinSplitView(tabID, of: targetID, in: spaceID), let splitID = splitViewID(containing: targetID),
            let pane = tree.location(of: targetID), let place = tree.location(of: splitID)
        else { return }
        tree.move(tabID, into: splitID, at: pane.index)
        tree.move(targetID, into: place.parentID, at: place.index + 1)
        updateSplitView(splitID) { $0.itemWidthFactors[tabID] = $0.itemWidthFactors.removeValue(forKey: targetID) }
    }

    /// As Arc's `removeItemsFromSplitView`: each tab goes right after its split, without its factor.
    mutating func removeFromSplitView(_ tabIDs: [UUID]) {
        for tabID in tabIDs {
            guard let splitID = splitViewID(containing: tabID), let place = tree.location(of: splitID) else {
                continue
            }
            tree.move(tabID, into: place.parentID, at: place.index + 1)
            updateSplitView(splitID) { $0.itemWidthFactors[tabID] = nil }
        }
    }

    /// Arc's Separate All Tabs: the tabs take the split's place in pane order.
    mutating func separateAllSplitViewChildren(_ splitID: UUID) {
        removeFromSplitView((tree[splitID]?.childIDs ?? []).reversed())
    }

    /// Arc's `movePanel`: a pane keeps its factor where it goes.
    mutating func moveSplitViewPane(_ tabID: UUID, by offset: Int) {
        guard let splitID = splitViewID(containing: tabID), let place = tree.location(of: tabID) else { return }
        tree.move(tabID, into: splitID, at: place.index + offset + (offset > 0 ? 1 : 0))
    }

    /// A closed split again, with its ID, data and place, holding those of its tabs that are back.
    mutating func restoreSplitView(_ closed: ClosedSplitView, tabs: [SidebarTab]) {
        guard tree[closed.id] == nil, tree[closed.parentID] != nil else { return }
        tree.insert(SidebarItem(id: closed.id, kind: .splitView(closed.data)), into: closed.parentID, at: closed.index)
        for tab in tabs where tree[tab.id] == nil {
            archive.removeAll { $0.id == tab.id }
            tree.append(SidebarItem(id: tab.id, kind: .tab(tab)), to: closed.id)
        }
    }

    /// As seen in Arc: a copy right after the split, with new tabs at the same addresses, its title, layout and
    /// sizes. Returns the new tabs' IDs.
    mutating func duplicateSplitView(_ id: UUID) -> [UUID] {
        guard var data = splitView(id), let place = tree.location(of: id) else { return [] }
        let tabs = tree.tabs(under: id)
        let copies = tabs.map { SidebarTab(id: UUID(), title: $0.title, url: $0.url, viewedAt: .now) }
        data.itemWidthFactors = Dictionary(
            uniqueKeysWithValues: zip(tabs, copies).compactMap { tab, copy in
                data.itemWidthFactors[tab.id].map { (copy.id, $0) }
            })
        let copyID = UUID()
        tree.insert(SidebarItem(id: copyID, kind: .splitView(data)), into: place.parentID, at: place.index + 1)
        for copy in copies { tree.append(SidebarItem(id: copy.id, kind: .tab(copy)), to: copyID) }
        return copies.map(\.id)
    }

    /// As seen in Arc: Move to ▸ puts the item at the top of the Space's list. A pinned one stays pinned, as seen
    /// for a move to another profile's Space; the top of the pinned list is Oa's own.
    mutating func move(_ id: UUID, toSpace spaceID: UUID) {
        guard let space = space(spaceID), let tabID = tree[id]?.childIDs.first else { return }
        tree.move(id, into: isPinned(tabID) ? space.pinnedRootID : space.unpinnedRootID, at: 0)
    }

    /// As seen in Arc: Reset Name and Icon clears both, and the cell shows the tabs again.
    mutating func resetSplitViewNameAndIcon(_ id: UUID) {
        updateSplitView(id) {
            $0.title = nil
            $0.icon = nil
        }
    }

    /// Oa's own: an empty title clears it, and the cell shows the tabs again.
    mutating func renameSplitView(_ id: UUID, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updateSplitView(id) { $0.title = title.isEmpty ? nil : title }
    }

    /// Arc's `updateSplitView(_:modify:)`.
    mutating func updateSplitView(_ id: UUID, _ modify: (inout SidebarSplitViewData) -> Void) {
        tree.update(id) { item in
            guard case .splitView(var data) = item.kind else { return }
            modify(&data)
            item.kind = .splitView(data)
        }
    }

    /// As seen in Arc: a split left with one tab is that tab again, where the split was. One left with none goes,
    /// Arc's zombie split.
    mutating func dissolveSplitViews() {
        for (id, item) in tree.items {
            guard case .splitView = item.kind, item.childIDs.count < 2, let place = tree.location(of: id) else {
                continue
            }
            if let tabID = item.childIDs.first { tree.move(tabID, into: place.parentID, at: place.index) }
            tree.remove(id)
        }
    }
}
