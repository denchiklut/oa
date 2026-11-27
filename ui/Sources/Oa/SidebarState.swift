import DevKit
import Foundation

/// Arc's `SidebarContainerType` for a window's own sidebar, by window ID.
enum SidebarContainerType: Hashable, Codable {
    case standalone(UUID)
    /// Never saved, as Arc's.
    case incognito(UUID)
    case littleBrowser(UUID)
}

/// Arc's `StandardWindowState.SidebarContext`: the sidebar a window shows.
enum SidebarContext: Codable {
    case global
    case standalone
    case incognito
}

/// Arc's `WindowStyle`, coded as Arc's: the case's name over its state.
enum WindowStyle: Codable {
    case standard(sidebarContext: SidebarContext)
    case little(LittleBrowserState)

    private enum Key: String, CodingKey { case standard, little }
    private enum StandardKey: String, CodingKey { case sidebarContext }

    var sidebarContext: SidebarContext? {
        if case .standard(let context) = self { context } else { nil }
    }

    func container(of windowID: UUID) -> SidebarContainerType? {
        switch self {
        case .standard(.global): nil
        case .standard(.standalone): .standalone(windowID)
        case .standard(.incognito): .incognito(windowID)
        case .little: .littleBrowser(windowID)
        }
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Key.self)
        if values.contains(.little) {
            self = .little(try values.decode(LittleBrowserState.self, forKey: .little))
        } else {
            let standard = try values.nestedContainer(keyedBy: StandardKey.self, forKey: .standard)
            self = .standard(sidebarContext: try standard.decode(SidebarContext.self, forKey: .sidebarContext))
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: Key.self)
        switch self {
        case .standard(let context):
            var standard = values.nestedContainer(keyedBy: StandardKey.self, forKey: .standard)
            try standard.encode(context, forKey: .sidebarContext)
        case .little(let state): try values.encode(state, forKey: .little)
        }
    }
}

/// What the sidebar keeps for a profile: its Favorites, as Arc's `topAppsContainerIDs`. The engine owns the list of
/// profiles and their names.
struct SidebarProfile: Identifiable, Hashable, Codable {
    static let defaultID = BrowserProfile.initialID
    let id: UUID
    let favoritesRootID: UUID
    /// A name the engine hasn't taken yet: an older sidebar.json's, or a new install's "Personal".
    var pendingName: String?

    /// Oa remembers dismissal for the profile that owns these Favorites.
    var dismissedFavoritesHint: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, favoritesRootID, pendingName = "name", dismissedFavoritesHint
    }
}

struct SidebarSpace: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var profileID: UUID
    /// None in a window's own sidebar, as Arc's, whose Space there has only an unpinned container.
    var pinnedRootID: UUID?
    let unpinnedRootID: UUID
    var customInfo: CustomInfo?

    /// As Arc's `customInfo`, which also holds the Space's icon.
    struct CustomInfo: Hashable, Codable {
        var windowTheme: WindowTheme?
        var icon: String?
    }

    /// As Arc: a Space without a theme shows the default.
    var theme: WindowTheme { customInfo?.windowTheme ?? .default }
    var icon: String? { customInfo?.icon }

    func rootID(pinned: Bool) -> UUID? { pinned ? pinnedRootID : unpinnedRootID }
}

struct SidebarTab: Identifiable, Hashable {
    /// Arc's `MuteStatus`, written once the tab was muted or unmuted.
    enum MuteStatus: String, Codable {
        case mute
        case allowAudio
    }

    let id: UUID
    var title = ""
    var url: URL?
    var viewedAt: Date?
    /// Kept after the opener is gone, as Arc keeps its grouping.
    var openerID: UUID?
    /// As Arc's: the opener, else the tab shown when this one was made.
    var activeTabBeforeCreationID: UUID?
    /// Arc's item `title`: the user's name for the tab, which wins over the page's, `title` here being Arc's
    /// `savedTitle`.
    var customTitle: String?
    /// Arc's `customInfo.iconType`, drawn in place of the favicon and kept as a Space's icon is: an SF Symbol's name
    /// or an emoji.
    var icon: String?
    /// Arc's `savedMuteStatus`, given to the tab's next page.
    var muteStatus: MuteStatus?

    var displayTitle: String { customTitle ?? (title.isEmpty ? url?.host() ?? "Untitled" : title) }

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

    /// Arc's `ArchivedItemSource`, stored as Arc's is: the Space the item was in, or a Blank Window's own sidebar or
    /// a Little window, which are gone with their windows.
    enum Source: Hashable, Codable { case space(UUID), standaloneSidebar, littleArc }

    let id: UUID
    var title: String
    var url: URL?
    /// Nil for a Favorite's, which belongs to the profile: Arc files them under no Space.
    let source: Source?
    let archivedAt: Date
    let reason: Reason

    var spaceID: UUID? { if case .space(let id) = source { id } else { nil } }

    var displayTitle: String { title.isEmpty ? url?.host() ?? "Untitled" : title }

    var address: String {
        guard let url else { return "" }
        var text = url.absoluteString
        if let scheme = url.scheme { text = String(text.dropFirst(scheme.count + 3)) }
        return text.hasSuffix("/") ? String(text.dropLast()) : text
    }
}

extension SidebarArchivedTab {
    private enum EarlierKey: String, CodingKey { case spaceID }

    /// A file from before `source` has the Space's ID alone.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        url = try values.decodeIfPresent(URL.self, forKey: .url)
        let earlier = try decoder.container(keyedBy: EarlierKey.self).decodeIfPresent(UUID.self, forKey: .spaceID)
        source = try values.decodeIfPresent(Source.self, forKey: .source) ?? earlier.map(Source.space)
        archivedAt = try values.decode(Date.self, forKey: .archivedAt)
        reason = try values.decode(Reason.self, forKey: .reason)
    }
}

struct SidebarFolder: Identifiable, Hashable {
    let id: UUID
    var title: String
    /// Arc's `customInfo.iconType`, rendered as a monochrome mask on the folder's front flap.
    var icon: String?

    var displayTitle: String { title.isEmpty ? "Untitled" : title }
}

/// A node of the sidebar tree. A tab entry takes its tab's ID, so moves keep identity.
struct SidebarItem: Identifiable, Hashable {
    enum Container: String, Codable { case favorites, pinned, unpinned }
    enum Kind: Hashable {
        case container(Container)
        case tab(SidebarTab)
        case folder(SidebarFolder)
        case splitView(SidebarSplitViewData)
    }

    let id: UUID
    var parentID: UUID?
    var kind: Kind
    var childIDs: [UUID] = []

    var tab: SidebarTab? {
        if case .tab(let tab) = kind { return tab }
        return nil
    }

    var folder: SidebarFolder? {
        if case .folder(let folder) = kind { return folder }
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

    func folder(_ id: UUID) -> SidebarFolder? { items[id]?.folder }

    func isDescendant(_ id: UUID, of ancestorID: UUID) -> Bool {
        var current = items[id]?.parentID
        while let parentID = current {
            if parentID == ancestorID { return true }
            current = items[parentID]?.parentID
        }
        return false
    }

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
        guard id != parentID, !isDescendant(parentID, of: id), let oldParentID = items[id]?.parentID,
            items[parentID] != nil
        else { return }
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
    var profiles: [SidebarProfile] = []
    var spaces: [SidebarSpace] = []
    var tree = SidebarTree()
    /// Oldest first.
    var archive: [SidebarArchivedTab] = []
    /// Arc's containers past the global sidebar, which is the rest of the state: a window's own sidebar, one Space
    /// with only its unpinned tabs. Their roots are in `tree` with the global ones.
    var containers: [SidebarContainerType: SidebarSpace] = [:]

    static func initial() -> SidebarState {
        var state = SidebarState()
        let profile = state.addProfile(SidebarProfile.defaultID, pendingName: "Personal")
        let space = state.addSpace(name: "Personal", profileID: profile.id)
        state.appendTab(SidebarTab(id: UUID(), url: URL(string: "https://www.wikipedia.org/")), in: space.id)
        return state
    }

    func profile(_ id: UUID) -> SidebarProfile? { profiles.first { $0.id == id } }

    /// Arc's `hasMultipleProfilesInUse`.
    var hasMultipleProfilesInUse: Bool { Set(spaces.map(\.profileID)).count > 1 }

    var tabCount: Int { tree.items.values.filter { $0.tab != nil }.count }

    func space(_ id: UUID) -> SidebarSpace? { allSpaces.first { $0.id == id } }

    /// The global sidebar's Spaces and the windows' own.
    var allSpaces: [SidebarSpace] { spaces + containers.values }

    func isGlobal(_ spaceID: UUID) -> Bool { spaces.contains { $0.id == spaceID } }

    /// Arc's `canMoveItems` enforces `depth(target) + childrenDepth(item) < 8` (up to 7 folder levels).
    static let maxFolderDepth = 7

    func space(containingItem id: UUID) -> SidebarSpace? {
        guard let rootID = tree.rootID(of: id) else { return nil }
        return allSpaces.first { $0.pinnedRootID == rootID || $0.unpinnedRootID == rootID }
    }

    func space(containing tabID: UUID) -> SidebarSpace? {
        guard tree.tab(tabID) != nil else { return nil }
        return space(containingItem: tabID)
    }

    func isPinnedItem(_ id: UUID) -> Bool {
        guard let pinnedRootID = space(containingItem: id)?.pinnedRootID else { return false }
        return tree.rootID(of: id) == pinnedRootID
    }

    func hasPinnedItems(in spaceID: UUID) -> Bool {
        guard let pinnedRootID = space(spaceID)?.pinnedRootID else { return false }
        return !(tree[pinnedRootID]?.childIDs.isEmpty ?? true)
    }

    /// Ancestor folder IDs of `id`, from its nearest enclosing folder up to the outermost.
    func folderAncestors(of id: UUID) -> [UUID] {
        var ancestors: [UUID] = []
        var current = tree[id]?.parentID
        while let parentID = current, let parent = tree[parentID] {
            if parent.folder != nil { ancestors.append(parentID) }
            current = parent.parentID
        }
        return ancestors
    }

    /// 0 for a global Space's pinned root, 1…7 for folders inside it, nil for non-pinned containers.
    func containerDepth(of containerID: UUID) -> Int? {
        guard let item = tree[containerID] else { return nil }
        if item.container == .pinned { return 0 }
        guard item.folder != nil, isPinnedItem(containerID) else { return nil }
        return folderAncestors(of: containerID).count + 1
    }

    /// 0 for a tab or split view; 1 for a leaf folder; 1 + max child depth for nested folders.
    func subtreeFolderDepth(of itemID: UUID) -> Int {
        guard tree.folder(itemID) != nil else { return 0 }
        let children = tree[itemID]?.childIDs ?? []
        return 1 + (children.map(subtreeFolderDepth(of:)).max() ?? 0)
    }

    func canCreateFolder(in parentID: UUID) -> Bool {
        containerDepth(of: parentID).map { $0 < Self.maxFolderDepth } ?? false
    }

    /// As Arc's `SidebarData.item(_:canHaveContext:)` and `canMoveItems`: folders live only in pinned sections at
    /// depth `< 8`, and never inside themselves.
    func canMoveItem(_ itemID: UUID, into parentID: UUID) -> Bool {
        guard let item = tree[itemID], let parent = tree[parentID], itemID != parentID,
            !tree.isDescendant(parentID, of: itemID)
        else { return false }
        guard item.container == nil else { return false }
        if item.folder != nil {
            guard let targetDepth = containerDepth(of: parentID) else { return false }
            return targetDepth + subtreeFolderDepth(of: itemID) <= Self.maxFolderDepth
        }
        return parent.container != nil || (parent.folder != nil && containerDepth(of: parentID) != nil)
    }

    /// Drops items whose ancestor is also in `ids`, keeping the original order.
    func topLevelItemIDs(in ids: [UUID]) -> [UUID] {
        let set = Set(ids)
        return ids.filter { id in !folderAncestors(of: id).contains(where: set.contains) }
    }

    /// As Arc's: an untitled Space on `profileID` with only an unpinned container, and no theme or Arc's incognito
    /// one.
    @discardableResult
    mutating func addContainer(_ type: SidebarContainerType, profileID: UUID) -> SidebarSpace {
        var space = SidebarSpace(id: UUID(), name: "", profileID: profileID, unpinnedRootID: UUID())
        if case .incognito = type { space.customInfo = SidebarSpace.CustomInfo(windowTheme: .incognito) }
        tree.addRoot(.unpinned, id: space.unpinnedRootID)
        containers[type] = space
        return space
    }

    /// As seen in Arc: its tabs go with it, not to the Archive.
    mutating func removeContainer(_ type: SidebarContainerType) {
        guard let space = containers.removeValue(forKey: type) else { return }
        tree.removeRoot(space.unpinnedRootID)
    }

    /// As seen in Arc: a Blank Window's last tab, and any incognito tab, closes without an Archive entry.
    mutating func removeTab(_ id: UUID) {
        guard tree.tab(id) != nil else { return }
        tree.remove(id)
    }

    func isPinned(_ tabID: UUID) -> Bool {
        tree.tab(tabID) != nil && isPinnedItem(tabID)
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
        guard isGlobal(spaceID), let space = space(spaceID), let profile = profile(space.profileID) else { return [] }
        return tree.tabs(under: profile.favoritesRootID)
    }

    /// A window on `spaceID` can select the Space's own tabs and its profile's Favorites.
    func isSelectable(_ tabID: UUID, in spaceID: UUID) -> Bool {
        space(containing: tabID)?.id == spaceID || favorites(for: spaceID).contains { $0.id == tabID }
    }

    func tabs(in spaceID: UUID, pinned: Bool) -> [SidebarTab] {
        guard let rootID = space(spaceID)?.rootID(pinned: pinned) else { return [] }
        return tree.tabs(under: rootID)
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
    mutating func addProfile(_ id: UUID, pendingName: String? = nil) -> SidebarProfile {
        let profile = SidebarProfile(id: id, favoritesRootID: UUID(), pendingName: pendingName)
        tree.addRoot(.favorites, id: profile.favoritesRootID)
        profiles.append(profile)
        return profile
    }

    /// As Arc: the profile's Favorites go with it, not to the Archive. A profile with a Space stays.
    mutating func removeProfile(_ id: UUID) {
        guard !allSpaces.contains(where: { $0.profileID == id }),
            let index = profiles.firstIndex(where: { $0.id == id })
        else { return }
        tree.removeRoot(profiles.remove(at: index).favoritesRootID)
    }

    @discardableResult
    mutating func addSpace(
        name: String, profileID: UUID, icon: String? = nil, theme: WindowTheme? = nil, after: UUID? = nil
    ) -> SidebarSpace {
        let pinnedRootID = UUID()
        let space = SidebarSpace(
            id: UUID(), name: name, profileID: profileID, pinnedRootID: pinnedRootID, unpinnedRootID: UUID(),
            customInfo: icon == nil && theme == nil ? nil : SidebarSpace.CustomInfo(windowTheme: theme, icon: icon))
        tree.addRoot(.pinned, id: pinnedRootID)
        tree.addRoot(.unpinned, id: space.unpinnedRootID)
        let index = after.flatMap { id in spaces.firstIndex { $0.id == id } }.map { $0 + 1 } ?? spaces.count
        spaces.insert(space, at: index)
        return space
    }

    mutating func setProfile(_ profileID: UUID, forSpaces spaceIDs: [UUID]) {
        guard profile(profileID) != nil else { return }
        for index in spaces.indices where spaceIDs.contains(spaces[index].id) { spaces[index].profileID = profileID }
        for (type, space) in containers where spaceIDs.contains(space.id) { containers[type]?.profileID = profileID }
    }

    mutating func moveSpace(_ id: UUID, to index: Int) {
        guard let from = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces.insert(spaces.remove(at: from), at: min(max(index, 0), spaces.count))
    }

    mutating func renameSpace(_ id: UUID, to name: String) {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces[index].name = name
    }

    mutating func setSpaceIcon(_ icon: String?, for id: UUID) {
        editCustomInfo(of: id) { $0.icon = icon }
    }

    mutating func setSpaceTheme(_ theme: WindowTheme?, for id: UUID) {
        editCustomInfo(of: id) { $0.windowTheme = theme }
    }

    private mutating func editCustomInfo(of id: UUID, _ change: (inout SidebarSpace.CustomInfo) -> Void) {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        var info = spaces[index].customInfo ?? SidebarSpace.CustomInfo()
        change(&info)
        spaces[index].customInfo = info.icon == nil && info.windowTheme == nil ? nil : info
    }

    /// The last Space stays.
    mutating func removeSpace(_ id: UUID, at date: Date = .now) {
        guard spaces.count > 1, let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        for tab in tabs(in: id) { archiveTab(tab.id, reason: .manual, at: date) }
        let space = spaces.remove(at: index)
        if let pinnedRootID = space.pinnedRootID { tree.removeRoot(pinnedRootID) }
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
    mutating func archiveTab(_ id: UUID, reason: SidebarArchivedTab.Reason, at date: Date = .now) {
        guard let tab = tree.tab(id) else { return }
        let source = archiveSource(space(containing: id)?.id)
        tree.remove(id)
        archive.append(
            SidebarArchivedTab(
                id: id, title: tab.customTitle ?? tab.title, url: tab.url, source: source, archivedAt: date,
                reason: reason))
    }

    /// A page without a row, a Peek's.
    mutating func archivePage(id: UUID, title: String, url: URL?, in spaceID: UUID?, at date: Date = .now) {
        archive.append(
            SidebarArchivedTab(
                id: id, title: title, url: url, source: archiveSource(spaceID), archivedAt: date, reason: .manual))
    }

    /// As Arc picks it by the window's style: a Blank Window's items are filed under its sidebar and a Little
    /// window's under Little Arc, not their Space.
    private func archiveSource(_ spaceID: UUID?) -> SidebarArchivedTab.Source? {
        guard let spaceID else { return nil }
        if isGlobal(spaceID) { return .space(spaceID) }
        if case .littleBrowser = containers.first(where: { $0.value.id == spaceID })?.key { return .littleArc }
        return .standaloneSidebar
    }

    /// To the top of the Space's unpinned tabs, as Arc's Restore.
    mutating func restoreArchived(_ id: UUID, in spaceID: UUID) {
        guard let index = archive.firstIndex(where: { $0.id == id }) else { return }
        let entry = archive.remove(at: index)
        guard let space = space(spaceID) else { return }
        let tab = SidebarTab(id: entry.id, title: entry.title, url: entry.url, viewedAt: .now)
        tree.insert(SidebarItem(id: tab.id, kind: .tab(tab)), into: space.unpinnedRootID, at: 0)
    }

    /// As Arc's ⇧⌘T: back where it was, or at the top of `fallbackSpaceID` when that place is gone, and out of the
    /// Archive if it is still there.
    mutating func reopenTab(_ tab: SidebarTab, in parentID: UUID, at index: Int, else fallbackSpaceID: UUID) {
        archive.removeAll { $0.id == tab.id }
        let item = SidebarItem(id: tab.id, kind: .tab(tab))
        let isFull = (tree[parentID]?.childIDs.count ?? 0) >= SidebarSplitViewData.maxNumberSplit
        if tree[parentID] != nil, splitView(parentID) == nil || !isFull {
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
    /// The unpinned tabs idle for their profile's `age` and not shown anywhere; shown and new tabs count as viewed
    /// now. Arc has no off.
    mutating func tabsDueForArchive(shown: Set<UUID>, at now: Date = .now, age: (UUID) -> TimeInterval) -> [UUID] {
        var due: [UUID] = []
        for space in spaces {
            let age = age(space.profileID)
            for tab in tabs(in: space.id, pinned: false) {
                if let viewedAt = tab.viewedAt, !shown.contains(tab.id), now.timeIntervalSince(viewedAt) > age {
                    due.append(tab.id)
                } else if tab.viewedAt == nil || shown.contains(tab.id) {
                    markViewed(tab.id, at: now)
                }
            }
        }
        return due
    }

    /// A move to the end of the other section. As seen in Arc, a split's tab takes its split whole, and an unpinned
    /// split goes to the top of the list.
    mutating func togglePin(_ tabID: UUID) {
        guard let space = space(containing: tabID), let pinnedRootID = space.pinnedRootID else { return }
        if let splitID = splitViewID(containing: tabID) {
            return isPinned(tabID)
                ? tree.move(splitID, into: space.unpinnedRootID, at: 0) : tree.move(splitID, into: pinnedRootID)
        }
        tree.move(tabID, into: isPinned(tabID) ? space.unpinnedRootID : pinnedRootID)
    }

    /// Into the profile's grid at `index`, where a drop lands in Arc; appended when nil, as Arc's Favorite Tab does.
    /// As seen in Arc, a split's tab takes its split whole.
    mutating func favoriteTab(_ tabID: UUID, at index: Int? = nil) {
        guard let profile = profile(containing: tabID) else { return }
        tree.move(splitViewID(containing: tabID) ?? tabID, into: profile.favoritesRootID, at: index)
    }

    /// As seen in Arc: last in the other profile's grid, with its ID.
    mutating func moveFavorite(_ tabID: UUID, toProfile profileID: UUID) {
        guard isFavorite(tabID), let profile = profile(profileID) else { return }
        tree.move(tabID, into: profile.favoritesRootID)
    }

    /// To the top of the Space's unpinned section. Arc moves it to that section; the position is Oa's own.
    mutating func unfavoriteTab(_ tabID: UUID, in spaceID: UUID) {
        guard isFavorite(tabID), let space = space(spaceID) else { return }
        tree.move(splitViewID(containing: tabID) ?? tabID, into: space.unpinnedRootID, at: 0)
    }

    /// The profile's Favorites as its grid shows them: a split is one tile.
    func favoriteEntries(for spaceID: UUID) -> [SidebarEntry] {
        guard isGlobal(spaceID), let space = space(spaceID), let profile = profile(space.profileID) else { return [] }
        return (tree[profile.favoritesRootID]?.childIDs ?? []).compactMap { id in
            if let tab = tree.tab(id) { return .tab(tab) }
            if splitView(id) != nil { return .splitView(id: id, tabs: tree.tabs(under: id)) }
            return nil
        }
    }

    /// As seen in Arc: an empty name gives the tab back its page's title.
    mutating func renameTab(_ tabID: UUID, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        tree.update(tabID) { item in
            guard var tab = item.tab else { return }
            tab.customTitle = title.isEmpty ? nil : title
            item.kind = .tab(tab)
        }
    }

    /// As seen in Arc: the copy right below, with the tab's name and icon, or at the top of the shown Space's Today
    /// for a Favorite's. A pin that left its address gives a pin at the page's, without the name.
    mutating func duplicateTab(_ tabID: UUID, in shownSpaceID: UUID, leftAddress: (url: URL, title: String)?) -> UUID? {
        guard let tab = tree.tab(tabID) else { return nil }
        var copy = SidebarTab(
            id: UUID(), title: tab.title, url: tab.url, viewedAt: .now, customTitle: tab.customTitle, icon: tab.icon)
        if let leftAddress {
            copy.url = leftAddress.url
            copy.title = leftAddress.title
            copy.customTitle = nil
        }
        if isFavorite(tabID) {
            insertTab(copy, atTopOf: shownSpaceID)
        } else if let place = tree.location(of: tabID) {
            tree.insert(SidebarItem(id: copy.id, kind: .tab(copy)), into: place.parentID, at: place.index + 1)
        }
        return copy.id
    }

    /// Arc's `updateSavedTabURL`: the address a pinned tab or Favorite opens at, whatever its page shows.
    mutating func setPinnedURL(_ tabID: UUID, to url: URL, title: String) {
        tree.update(tabID) { item in
            guard var tab = item.tab else { return }
            tab.url = url
            tab.title = title
            item.kind = .tab(tab)
        }
    }

    mutating func setMuteStatus(_ tabID: UUID, to status: SidebarTab.MuteStatus) {
        tree.update(tabID) { item in
            guard var tab = item.tab else { return }
            tab.muteStatus = status
            item.kind = .tab(tab)
        }
    }

    mutating func setTabIcon(_ tabID: UUID, to icon: String?) {
        tree.update(tabID) { item in
            guard var tab = item.tab else { return }
            tab.icon = icon
            item.kind = .tab(tab)
        }
    }

    /// Write-back from a live page. A tab that keeps its address takes the title only while the page is at it.
    mutating func setSavedPage(_ tabID: UUID, title: String?, url: URL?) {
        let keeps = keepsAddress(tabID)
        tree.update(tabID) { item in
            guard var tab = item.tab else { return }
            if let title, !title.isEmpty, !keeps || tab.isAt(url) { tab.title = title }
            if let url, !keeps { tab.url = url }
            item.kind = .tab(tab)
        }
    }

    // MARK: - Folders

    /// Appends to the end of `parentID` when `index` is nil, as Arc's `SidebarContainer.insertItems` resolves `-1`.
    @discardableResult
    mutating func createFolder(
        title: String = "", icon: String? = nil, in parentID: UUID, at index: Int? = nil
    ) -> SidebarFolder? {
        guard canCreateFolder(in: parentID) else { return nil }
        let folder = SidebarFolder(id: UUID(), title: title.trimmingCharacters(in: .whitespacesAndNewlines), icon: icon)
        let item = SidebarItem(id: folder.id, kind: .folder(folder))
        if let index { tree.insert(item, into: parentID, at: index) } else { tree.append(item, to: parentID) }
        return folder
    }

    /// As Arc's `createFolderFromItems`: wraps `itemIDs` in a new folder in `spaceID`'s pinned section (or their
    /// shared parent folder when all live in one), appending at the end.
    @discardableResult
    mutating func createFolder(wrapping itemIDs: [UUID], in spaceID: UUID, title: String = "") -> SidebarFolder? {
        guard let pinnedRootID = space(spaceID)?.pinnedRootID else { return nil }
        let roots = topLevelItemIDs(in: itemIDs)
        guard !roots.isEmpty,
            roots.allSatisfy({ space(containingItem: $0)?.id == spaceID && tree[$0]?.container == nil })
        else { return nil }
        let maxChildDepth = roots.map(subtreeFolderDepth(of:)).max() ?? 0
        guard maxChildDepth < Self.maxFolderDepth else { return nil }
        let sharedParents = Set(roots.compactMap { tree[$0]?.parentID })
        var targetParentID = pinnedRootID
        if sharedParents.count == 1, let candidate = sharedParents.first,
            let depth = containerDepth(of: candidate), depth + 1 + maxChildDepth <= Self.maxFolderDepth
        {
            targetParentID = candidate
        }
        guard let folder = createFolder(title: title, in: targetParentID) else { return nil }
        for itemID in roots where canMoveItem(itemID, into: folder.id) { tree.move(itemID, into: folder.id) }
        return folder
    }

    /// As Arc's `WindowData.updateCustomTitle` / `SidebarList.readableTitle`: an empty rename keeps the folder's
    /// previous non-empty title, or falls back to "Untitled" when it had none yet.
    mutating func renameFolder(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        tree.update(id) { item in
            guard var folder = item.folder else { return }
            if !trimmed.isEmpty {
                folder.title = trimmed
            } else if folder.title.isEmpty {
                folder.title = "Untitled"
            }
            item.kind = .folder(folder)
        }
    }

    mutating func setFolderIcon(_ id: UUID, to icon: String?) {
        tree.update(id) { item in
            guard var folder = item.folder else { return }
            folder.icon = icon
            item.kind = .folder(folder)
        }
    }

    mutating func moveItem(_ id: UUID, into parentID: UUID, at index: Int? = nil) {
        guard canMoveItem(id, into: parentID) else { return }
        tree.move(id, into: parentID, at: index)
    }

    mutating func moveItems(_ itemIDs: [UUID], into parentID: UUID, after anchorID: UUID?) {
        let roots = topLevelItemIDs(in: itemIDs)
        var previousID = anchorID
        for itemID in roots where canMoveItem(itemID, into: parentID) {
            let index = previousID.flatMap { tree[parentID]?.childIDs.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            tree.move(itemID, into: parentID, at: index)
            previousID = itemID
        }
    }

    mutating func removeFolder(_ id: UUID) {
        guard tree.folder(id) != nil else { return }
        tree.remove(id)
    }

    /// Captures a folder's hierarchy for Undo before its tabs are closed or removed.
    func closedFolder(_ id: UUID) -> ClosedFolder? {
        guard let root = tree[id], root.folder != nil, let place = tree.location(of: id),
            let spaceID = space(containingItem: id)?.id
        else { return nil }
        return ClosedFolder(
            root: root, index: place.index, spaceID: spaceID, descendants: tree.descendants(of: id),
            depth: subtreeFolderDepth(of: id))
    }

    /// The snapshot is in sidebar order, so every parent is back before its children.
    mutating func restoreFolder(_ closed: ClosedFolder, tabs: [SidebarTab], fallbackSpaceID: UUID) {
        guard tree[closed.id] == nil else { return }
        let destination: UUID?
        if let parentID = closed.root.parentID, let parentDepth = containerDepth(of: parentID),
            parentDepth + closed.depth <= Self.maxFolderDepth
        {
            destination = parentID
        } else {
            destination = space(closed.spaceID)?.pinnedRootID ?? space(fallbackSpaceID)?.pinnedRootID
        }
        guard let destination else { return }

        var root = closed.root
        root.childIDs = []
        tree.insert(root, into: destination, at: closed.index)
        let restored = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
        for var item in closed.descendants {
            guard let parentID = item.parentID, tree[item.id] == nil, tree[parentID] != nil else { continue }
            if item.tab != nil {
                guard let tab = restored[item.id] else { continue }
                item.kind = .tab(tab)
            }
            item.childIDs = []
            tree.append(item, to: parentID)
        }
        archive.removeAll { restored[$0.id] != nil && tree.tab($0.id) != nil }
    }

    /// Pinned rows visible in `spaceID`, expanding folders in `expanded` and peeking collapsed folders that contain a
    /// target in `peekedTargets` (selected tab or active Peek).
    func visiblePinnedRows(
        in spaceID: UUID, expanded: Set<UUID>, peekedTargets: Set<UUID>, sectionCollapsed: Bool
    ) -> [SidebarRow] {
        guard let pinnedRootID = space(spaceID)?.pinnedRootID else { return [] }
        if sectionCollapsed {
            var rows: [SidebarRow] = []
            var seen = Set<UUID>()
            for item in tree.descendants(of: pinnedRootID) {
                guard let tab = item.tab, peekedTargets.contains(tab.id) else { continue }
                if let splitID = splitViewID(containing: tab.id) {
                    if seen.insert(splitID).inserted {
                        rows.append(
                            SidebarRow(
                                entry: .splitView(id: splitID, tabs: tree.tabs(under: splitID)), depth: 0,
                                parentID: tree[splitID]?.parentID ?? pinnedRootID))
                    }
                } else if seen.insert(tab.id).inserted {
                    rows.append(SidebarRow(entry: .tab(tab), depth: 0, parentID: item.parentID ?? pinnedRootID))
                }
            }
            return rows
        }
        let targetFolders = Set(peekedTargets.flatMap(folderAncestors(of:)))
        var rows: [SidebarRow] = []
        func walk(_ parentID: UUID, depth: Int, peekOnly: Bool) {
            for childID in tree[parentID]?.childIDs ?? [] {
                guard let item = tree[childID] else { continue }
                switch item.kind {
                case .folder(let folder):
                    let hasTarget = targetFolders.contains(folder.id)
                    if peekOnly, !hasTarget { continue }
                    let isExpanded = !peekOnly && expanded.contains(folder.id)
                    let isPeeked = !isExpanded && hasTarget
                    rows.append(
                        SidebarRow(
                            entry: .folder(folder), depth: depth, parentID: parentID, isExpanded: isExpanded,
                            isPeeked: isPeeked))
                    if isExpanded {
                        walk(folder.id, depth: depth + 1, peekOnly: false)
                    } else if isPeeked {
                        walk(folder.id, depth: depth + 1, peekOnly: true)
                    }
                case .tab(let tab):
                    if peekOnly, !peekedTargets.contains(tab.id) { continue }
                    rows.append(SidebarRow(entry: .tab(tab), depth: depth, parentID: parentID))
                case .splitView:
                    let tabs = tree.tabs(under: childID)
                    let hasTarget = peekedTargets.contains(childID) || tabs.contains { peekedTargets.contains($0.id) }
                    if peekOnly, !hasTarget { continue }
                    rows.append(
                        SidebarRow(entry: .splitView(id: childID, tabs: tabs), depth: depth, parentID: parentID))
                case .container:
                    break
                }
            }
        }
        walk(pinnedRootID, depth: 0, peekOnly: false)
        return rows
    }

    func unpinnedRows(in spaceID: UUID) -> [SidebarRow] {
        guard let unpinnedRootID = space(spaceID)?.unpinnedRootID else { return [] }
        return entries(in: spaceID, pinned: false).map { SidebarRow(entry: $0, depth: 0, parentID: unpinnedRootID) }
    }
}
