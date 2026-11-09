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
    let spaceID: UUID
    let archivedAt: Date
    let reason: Reason
    /// Its index in the unpinned section; nil for a pinned tab archived with its Space.
    let position: Int?

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

    mutating func insert(_ item: SidebarItem, into parentID: UUID, at index: Int) {
        guard let parent = items[parentID] else { return }
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

    mutating func move(_ id: UUID, toEndOf parentID: UUID) {
        guard items[id] != nil, items[parentID] != nil else { return }
        detach(id)
        items[id]?.parentID = parentID
        items[parentID]?.childIDs.append(id)
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

    func space(_ id: UUID) -> SidebarSpace? { spaces.first { $0.id == id } }

    func space(containing tabID: UUID) -> SidebarSpace? {
        guard tree.tab(tabID) != nil, let rootID = tree.rootID(of: tabID) else { return nil }
        return spaces.first { $0.pinnedRootID == rootID || $0.unpinnedRootID == rootID }
    }

    func isPinned(_ tabID: UUID) -> Bool {
        space(containing: tabID)?.pinnedRootID == tree.rootID(of: tabID)
    }

    func tabs(in spaceID: UUID, pinned: Bool) -> [SidebarTab] {
        guard let space = space(spaceID) else { return [] }
        return tree.tabs(under: pinned ? space.pinnedRootID : space.unpinnedRootID)
    }

    /// Pinned then unpinned: the order of the sidebar and of ⌘1–⌘9.
    func selectableTabs(in spaceID: UUID) -> [SidebarTab] {
        tabs(in: spaceID, pinned: true) + tabs(in: spaceID, pinned: false)
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
        for tab in selectableTabs(in: id) { archiveTab(tab.id, reason: .manual, at: date) }
        let space = spaces.remove(at: index)
        tree.removeRoot(space.pinnedRootID)
        tree.removeRoot(space.unpinnedRootID)
    }

    mutating func appendTab(_ tab: SidebarTab, in spaceID: UUID) {
        guard let space = space(spaceID) else { return }
        tree.append(SidebarItem(id: tab.id, kind: .tab(tab)), to: space.unpinnedRootID)
    }

    mutating func archiveTab(_ id: UUID, reason: SidebarArchivedTab.Reason, at date: Date = .now) {
        guard let space = space(containing: id), let tab = tree.tab(id) else { return }
        let position = isPinned(id) ? nil : tree[space.unpinnedRootID]?.childIDs.firstIndex(of: id)
        tree.remove(id)
        archive.append(
            SidebarArchivedTab(
                id: id, title: tab.title, url: tab.url, spaceID: space.id, archivedAt: date, reason: reason,
                position: position))
    }

    /// Into `fallbackSpaceID` when its Space is gone. Returns the Space it went to.
    @discardableResult
    mutating func restoreArchived(_ id: UUID, in fallbackSpaceID: UUID, toOldPosition: Bool) -> UUID? {
        guard let index = archive.firstIndex(where: { $0.id == id }) else { return nil }
        let entry = archive.remove(at: index)
        guard let space = space(entry.spaceID) ?? space(fallbackSpaceID) else { return nil }
        let tab = SidebarTab(id: entry.id, title: entry.title, url: entry.url, viewedAt: .now)
        tree.insert(
            SidebarItem(id: tab.id, kind: .tab(tab)), into: space.unpinnedRootID,
            at: toOldPosition ? entry.position ?? 0 : 0)
        return space.id
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
    mutating func autoArchive(shown: Set<UUID>, at now: Date = .now) -> Bool {
        var archived = false
        for space in spaces {
            for tab in tabs(in: space.id, pinned: false) {
                if let viewedAt = tab.viewedAt, !shown.contains(tab.id),
                    now.timeIntervalSince(viewedAt) > SidebarState.autoArchiveAge
                {
                    archiveTab(tab.id, reason: .auto, at: now)
                    archived = true
                } else if tab.viewedAt == nil || shown.contains(tab.id) {
                    markViewed(tab.id, at: now)
                }
            }
        }
        return archived
    }

    /// A move to the end of the other section.
    mutating func togglePin(_ tabID: UUID) {
        guard let space = space(containing: tabID) else { return }
        tree.move(tabID, toEndOf: isPinned(tabID) ? space.unpinnedRootID : space.pinnedRootID)
    }

    /// Write-back from a live page. A pinned tab keeps its address and takes the title only while the page is at it.
    mutating func setSavedPage(_ tabID: UUID, title: String, url: URL?) {
        let pinned = isPinned(tabID)
        tree.update(tabID) { item in
            guard var tab = item.tab else { return }
            if !title.isEmpty, !pinned || tab.isAt(url) { tab.title = title }
            if let url, !pinned { tab.url = url }
            item.kind = .tab(tab)
        }
    }
}
