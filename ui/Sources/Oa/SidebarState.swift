import Foundation

struct SidebarProfile: Identifiable, Hashable, Codable {
    /// The one profile until the app grows a profile list; the same UUID keys the engine context.
    static let defaultID = UUID(uuidString: "6B0F3E1A-0A5C-4F7B-9C1D-0A0A0A0A0A01")!
    let id: UUID
    var name: String
    let favoritesRootID: UUID
}

struct SidebarSpace: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    let profileID: UUID
    let pinnedRootID: UUID
    let unpinnedRootID: UUID
}

struct SidebarTab: Identifiable, Hashable {
    let id: UUID
    var title = ""
    var url: URL?
    var viewedAt: Date?
    /// Kept after the opener is gone, as Arc keeps its grouping.
    var openerID: UUID?

    var displayTitle: String { title.isEmpty ? url?.host() ?? "Untitled" : title }

    /// Whether `other` is this tab's saved address, ignoring a trailing slash on a bare host.
    func isAt(_ other: URL?) -> Bool {
        guard let url, let other else { return false }
        return normalized(url) == normalized(other)
    }

    private func normalized(_ url: URL) -> String {
        let text = url.absoluteString
        return url.path().count <= 1 && text.hasSuffix("/") ? String(text.dropLast()) : text
    }
}

struct SidebarArchivedTab: Identifiable, Hashable, Codable {
    enum Reason: String, Codable { case manual, auto }

    let id: UUID
    var title: String
    var url: URL?
    /// Nil for a Favorite's, which belongs to the profile: Arc files them under no Space.
    let spaceID: UUID?
    let archivedAt: Date
    let reason: Reason

    var displayTitle: String { title.isEmpty ? url?.host() ?? "Untitled" : title }

    var address: String {
        guard let url else { return "" }
        var text = url.absoluteString
        if let scheme = url.scheme { text = String(text.dropFirst(scheme.count + 3)) }
        return text.hasSuffix("/") ? String(text.dropLast()) : text
    }
}

/// A node of the sidebar tree. A tab entry takes its tab's ID, so moves keep identity.
struct SidebarItem: Identifiable, Hashable {
    enum Container: String, Codable { case favorites, pinned, unpinned }
    enum Kind: Hashable {
        case container(Container)
        case tab(SidebarTab)
        case folder(title: String)
        case splitView
    }

    let id: UUID
    var parentID: UUID?
    var kind: Kind
    var childIDs: [UUID] = []

    var tab: SidebarTab? {
        if case .tab(let tab) = kind { return tab }
        return nil
    }

    var container: Container? {
        if case .container(let container) = kind { return container }
        return nil
    }
}

struct SidebarTree {
    private(set) var items: [UUID: SidebarItem] = [:]
    private(set) var rootIDs: [UUID] = []

    init() {}

    init(rootIDs: [UUID], items: [SidebarItem]) {
        self.rootIDs = rootIDs
        self.items = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    subscript(id: UUID) -> SidebarItem? { items[id] }

    func tab(_ id: UUID) -> SidebarTab? { items[id]?.tab }

    func rootID(of id: UUID) -> UUID? {
        guard var item = items[id] else { return nil }
        while let parentID = item.parentID, let parent = items[parentID] { item = parent }
        return item.id
    }

    /// Items under `id` in display order, depth first.
    func descendants(of id: UUID) -> [SidebarItem] {
        (items[id]?.childIDs ?? []).flatMap { childID in
            items[childID].map { [$0] + descendants(of: childID) } ?? []
        }
    }

    func tabs(under id: UUID) -> [SidebarTab] { descendants(of: id).compactMap(\.tab) }

    func location(of id: UUID) -> (parentID: UUID, index: Int)? {
        guard let parentID = items[id]?.parentID, let index = items[parentID]?.childIDs.firstIndex(of: id) else {
            return nil
        }
        return (parentID, index)
    }

    mutating func addRoot(_ container: SidebarItem.Container, id: UUID) {
        items[id] = SidebarItem(id: id, kind: .container(container))
        rootIDs.append(id)
    }

    mutating func removeRoot(_ id: UUID) {
        rootIDs.removeAll { $0 == id }
        removeSubtree(id)
    }

    mutating func append(_ item: SidebarItem, to parentID: UUID) {
        insert(item, into: parentID, at: items[parentID]?.childIDs.count ?? 0)
    }

    /// Two windows can bring back one Archive entry; Arc's sidebar also takes an ID once.
    mutating func insert(_ item: SidebarItem, into parentID: UUID, at index: Int) {
        guard let parent = items[parentID], items[item.id] == nil else { return }
        var item = item
        item.parentID = parentID
        items[item.id] = item
        items[parentID]?.childIDs.insert(item.id, at: min(max(index, 0), parent.childIDs.count))
    }

    /// Removes the item and everything under it. Returns its position in its parent.
    @discardableResult
    mutating func remove(_ id: UUID) -> Int? {
        let index = detach(id)
        removeSubtree(id)
        return index
    }

    /// Appends when `index` is nil.
    mutating func move(_ id: UUID, into parentID: UUID, at index: Int? = nil) {
        guard let oldParentID = items[id]?.parentID, items[parentID] != nil else { return }
        let from = detach(id) ?? 0
        var at = index ?? Int.max
        if oldParentID == parentID, from < at { at -= 1 }
        items[id]?.parentID = parentID
        let count = items[parentID]?.childIDs.count ?? 0
        items[parentID]?.childIDs.insert(id, at: min(max(at, 0), count))
    }

    mutating func update(_ id: UUID, _ change: (inout SidebarItem) -> Void) {
        guard var item = items[id] else { return }
        change(&item)
        items[id] = item
    }

    @discardableResult
    private mutating func detach(_ id: UUID) -> Int? {
        guard let parentID = items[id]?.parentID, let index = items[parentID]?.childIDs.firstIndex(of: id) else {
            return nil
        }
        items[parentID]?.childIDs.remove(at: index)
        return index
    }

    private mutating func removeSubtree(_ id: UUID) {
        for child in items[id]?.childIDs ?? [] { removeSubtree(child) }
        items.removeValue(forKey: id)
    }
}

/// The app's source of truth for the sidebar. Windows hold selection only.
struct SidebarState {
    /// Arc's default; unpinned tabs idle this long are archived, and there is no off.
    static let autoArchiveAge: TimeInterval = 12 * 60 * 60

    var profiles: [SidebarProfile] = []
    var spaces: [SidebarSpace] = []
    var tree = SidebarTree()
    /// Oldest first.
    var archive: [SidebarArchivedTab] = []

    static func initial() -> SidebarState {
        var state = SidebarState()
        let profile = state.addProfile(name: "Personal", id: SidebarProfile.defaultID)
        let space = state.addSpace(name: "Personal", profileID: profile.id)
        state.appendTab(SidebarTab(id: UUID(), url: URL(string: "https://www.wikipedia.org/")), in: space.id)
        return state
    }

    func profile(_ id: UUID) -> SidebarProfile? { profiles.first { $0.id == id } }

    var tabCount: Int { tree.items.values.filter { $0.tab != nil }.count }

    func space(_ id: UUID) -> SidebarSpace? { spaces.first { $0.id == id } }

    func space(containing tabID: UUID) -> SidebarSpace? {
        guard tree.tab(tabID) != nil, let rootID = tree.rootID(of: tabID) else { return nil }
        return spaces.first { $0.pinnedRootID == rootID || $0.unpinnedRootID == rootID }
    }

    func isPinned(_ tabID: UUID) -> Bool {
        space(containing: tabID)?.pinnedRootID == tree.rootID(of: tabID)
    }

    func isFavorite(_ tabID: UUID) -> Bool {
        guard let rootID = tree.rootID(of: tabID) else { return false }
        return profiles.contains { $0.favoritesRootID == rootID }
    }

    /// Pinned tabs and Favorites keep their saved address, as in Arc.
    func keepsAddress(_ tabID: UUID) -> Bool { isPinned(tabID) || isFavorite(tabID) }

    /// As Arc: a tab that keeps its address takes a favicon only from its own site, and once it has one and the page
    /// can go back, only from the saved address itself.
    func takesFavicon(_ tabID: UUID, at url: URL?, canGoBack: Bool, hasSaved: Bool) -> Bool {
        guard keepsAddress(tabID), let tab = tree.tab(tabID), let saved = tab.url, let url else { return true }
        return hasSaved && canGoBack ? tab.isAt(url) : saved.host() == url.host()
    }

    func profile(containing tabID: UUID) -> SidebarProfile? {
        guard tree.tab(tabID) != nil, let rootID = tree.rootID(of: tabID) else { return nil }
        return profiles.first { $0.favoritesRootID == rootID }
            ?? space(containing: tabID).flatMap { profile($0.profileID) }
    }

    /// The Space's profile's Favorites, shown in every Space of the profile as Arc does.
    func favorites(for spaceID: UUID) -> [SidebarTab] {
        guard let space = space(spaceID), let profile = profile(space.profileID) else { return [] }
        return tree.tabs(under: profile.favoritesRootID)
    }

    /// A window on `spaceID` can select the Space's own tabs and its profile's Favorites.
    func isSelectable(_ tabID: UUID, in spaceID: UUID) -> Bool {
        space(containing: tabID)?.id == spaceID || favorites(for: spaceID).contains { $0.id == tabID }
    }

    func tabs(in spaceID: UUID, pinned: Bool) -> [SidebarTab] {
        guard let space = space(spaceID) else { return [] }
        return tree.tabs(under: pinned ? space.pinnedRootID : space.unpinnedRootID)
    }

    /// The Space's own tabs, pinned then unpinned.
    func tabs(in spaceID: UUID) -> [SidebarTab] {
        tabs(in: spaceID, pinned: true) + tabs(in: spaceID, pinned: false)
    }

    /// Favorites, pinned, then unpinned: the order of the sidebar and of ⌘1–⌘9, as in Arc.
    func selectableTabs(in spaceID: UUID) -> [SidebarTab] {
        favorites(for: spaceID) + tabs(in: spaceID)
    }

    func firstTabID(in spaceID: UUID) -> UUID? {
        (tabs(in: spaceID, pinned: false).first ?? tabs(in: spaceID, pinned: true).first)?.id
    }

    @discardableResult
    mutating func addProfile(name: String, id: UUID = UUID()) -> SidebarProfile {
        let profile = SidebarProfile(id: id, name: name, favoritesRootID: UUID())
        tree.addRoot(.favorites, id: profile.favoritesRootID)
        profiles.append(profile)
        return profile
    }

    @discardableResult
    mutating func addSpace(name: String, profileID: UUID) -> SidebarSpace {
        let space = SidebarSpace(
            id: UUID(), name: name, profileID: profileID, pinnedRootID: UUID(), unpinnedRootID: UUID())
        tree.addRoot(.pinned, id: space.pinnedRootID)
        tree.addRoot(.unpinned, id: space.unpinnedRootID)
        spaces.append(space)
        return space
    }

    mutating func renameSpace(_ id: UUID, to name: String) {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces[index].name = name
    }

    /// The last Space stays.
    mutating func removeSpace(_ id: UUID, at date: Date = .now) {
        guard spaces.count > 1, let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        for tab in tabs(in: id) { archiveTab(tab.id, reason: .manual, at: date) }
        let space = spaces.remove(at: index)
        tree.removeRoot(space.pinnedRootID)
        tree.removeRoot(space.unpinnedRootID)
    }

    mutating func appendTab(_ tab: SidebarTab, in spaceID: UUID) {
        guard let space = space(spaceID) else { return }
        tree.append(SidebarItem(id: tab.id, kind: .tab(tab)), to: space.unpinnedRootID)
    }

    /// As Arc: after the opener's last descendant; a pinned opener's group sits at the top of the unpinned section,
    /// a Favorite's at the top of the shown Space's.
    mutating func openTab(_ tab: SidebarTab, from openerID: UUID, in shownSpaceID: UUID) {
        guard let space = space(containing: openerID) ?? space(shownSpaceID) else { return }
        let siblings = tree[space.unpinnedRootID]?.childIDs ?? []
        var group: Set<UUID> = [openerID]
        var index = siblings.firstIndex(of: openerID).map { $0 + 1 } ?? 0
        while index < siblings.count, let parent = tree.tab(siblings[index])?.openerID, group.contains(parent) {
            group.insert(siblings[index])
            index += 1
        }
        tree.insert(SidebarItem(id: tab.id, kind: .tab(tab)), into: space.unpinnedRootID, at: index)
    }

    /// Where an Archive Peek's Expand lands, as in Arc.
    mutating func insertTab(_ tab: SidebarTab, atTopOf spaceID: UUID) {
        guard let space = space(spaceID) else { return }
        tree.insert(SidebarItem(id: tab.id, kind: .tab(tab)), into: space.unpinnedRootID, at: 0)
    }

    /// As Arc: the next tab below with the same opener, else the nearest above, else the opener.
    func openerSuccessor(of tabID: UUID) -> UUID? {
        guard let openerID = tree.tab(tabID)?.openerID, let space = space(containing: tabID) else { return nil }
        let tabs = selectableTabs(in: space.id)
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return nil }
        if let below = tabs[(index + 1)...].first(where: { $0.openerID == openerID }) { return below.id }
        if let above = tabs[..<index].last(where: { $0.openerID == openerID }) { return above.id }
        return tabs.contains { $0.id == openerID } ? openerID : nil
    }

    mutating func archiveTab(_ id: UUID, reason: SidebarArchivedTab.Reason, at date: Date = .now) {
        guard let tab = tree.tab(id) else { return }
        let space = space(containing: id)
        tree.remove(id)
        archive.append(
            SidebarArchivedTab(
                id: id, title: tab.title, url: tab.url, spaceID: space?.id, archivedAt: date, reason: reason))
    }

    /// A page without a row, a Peek's.
    mutating func archivePage(id: UUID, title: String, url: URL?, in spaceID: UUID?, at date: Date = .now) {
        archive.append(
            SidebarArchivedTab(id: id, title: title, url: url, spaceID: spaceID, archivedAt: date, reason: .manual))
    }

    /// To the top of its Space, as Arc's Restore; into `fallbackSpaceID` when its Space is gone.
    mutating func restoreArchived(_ id: UUID, in fallbackSpaceID: UUID) {
        guard let index = archive.firstIndex(where: { $0.id == id }) else { return }
        let entry = archive.remove(at: index)
        guard let space = entry.spaceID.flatMap({ space($0) }) ?? space(fallbackSpaceID) else { return }
        let tab = SidebarTab(id: entry.id, title: entry.title, url: entry.url, viewedAt: .now)
        tree.insert(SidebarItem(id: tab.id, kind: .tab(tab)), into: space.unpinnedRootID, at: 0)
    }

    /// As Arc's ⇧⌘T: back where it was, or at the top of `fallbackSpaceID` when that place is gone, and out of the
    /// Archive if it is still there.
    mutating func reopenTab(_ tab: SidebarTab, in parentID: UUID, at index: Int, else fallbackSpaceID: UUID) {
        archive.removeAll { $0.id == tab.id }
        let item = SidebarItem(id: tab.id, kind: .tab(tab))
        if tree[parentID] != nil {
            tree.insert(item, into: parentID, at: index)
        } else if let space = space(fallbackSpaceID) {
            tree.insert(item, into: space.unpinnedRootID, at: 0)
        }
    }

    mutating func removeArchived(_ id: UUID) {
        archive.removeAll { $0.id == id }
    }

    mutating func clearArchive() {
        archive.removeAll()
    }

    mutating func markViewed(_ tabID: UUID, at date: Date = .now) {
        tree.update(tabID) { item in
            guard var tab = item.tab else { return }
            tab.viewedAt = date
            item.kind = .tab(tab)
        }
    }

    /// Tabs in `shown`, and tabs without a stamp yet, are stamped instead of archived.
    @discardableResult
    /// The unpinned tabs idle for `autoArchiveAge` and not shown anywhere; shown and new tabs count as viewed now.
    mutating func tabsDueForArchive(shown: Set<UUID>, at now: Date = .now) -> [UUID] {
        var due: [UUID] = []
        for space in spaces {
            for tab in tabs(in: space.id, pinned: false) {
                if let viewedAt = tab.viewedAt, !shown.contains(tab.id),
                    now.timeIntervalSince(viewedAt) > SidebarState.autoArchiveAge
                {
                    due.append(tab.id)
                } else if tab.viewedAt == nil || shown.contains(tab.id) {
                    markViewed(tab.id, at: now)
                }
            }
        }
        return due
    }

    /// A move to the end of the other section.
    mutating func togglePin(_ tabID: UUID) {
        guard let space = space(containing: tabID) else { return }
        tree.move(tabID, into: isPinned(tabID) ? space.unpinnedRootID : space.pinnedRootID)
    }

    /// Into the profile's grid at `index`, where a drop lands in Arc; appended when nil, as Arc's Favorite Tab does.
    mutating func favoriteTab(_ tabID: UUID, at index: Int? = nil) {
        guard let profile = profile(containing: tabID) else { return }
        tree.move(tabID, into: profile.favoritesRootID, at: index)
    }

    /// To the top of the Space's unpinned section. Arc moves it to that section; the position is Oa's own.
    mutating func unfavoriteTab(_ tabID: UUID, in spaceID: UUID) {
        guard isFavorite(tabID), let space = space(spaceID) else { return }
        tree.move(tabID, into: space.unpinnedRootID, at: 0)
    }

    /// Write-back from a live page. A tab that keeps its address takes the title only while the page is at it.
    mutating func setSavedPage(_ tabID: UUID, title: String, url: URL?) {
        let keeps = keepsAddress(tabID)
        tree.update(tabID) { item in
            guard var tab = item.tab else { return }
            if !title.isEmpty, !keeps || tab.isAt(url) { tab.title = title }
            if let url, !keeps { tab.url = url }
            item.kind = .tab(tab)
        }
    }
}
