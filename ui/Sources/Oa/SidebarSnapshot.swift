import Foundation

enum SnapshotError: Error {
    case newerVersion(Int)
    case invalid(String)
}

struct Versioned: Decodable {
    let version: Int
}

/// The on-disk shape of `SidebarState`: items in display order, each with its parent and children.
struct SidebarSnapshot: Codable {
    static let version = 1

    var version = SidebarSnapshot.version
    var profiles: [SidebarProfile]
    var spaces: [SidebarSpace]
    var tree: Tree
    var archive: [SidebarArchivedTab]
    var containers: Containers?

    private enum Key: String, CodingKey { case version, profiles, spaces, tree, archive, containers }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Key.self)
        version = try values.decode(Int.self, forKey: .version)
        profiles = try values.decode([SidebarProfile].self, forKey: .profiles)
        spaces = try values.decode([SidebarSpace].self, forKey: .spaces)
        tree = try values.decode(Tree.self, forKey: .tree)
        archive = try values.decodeIfPresent([SidebarArchivedTab].self, forKey: .archive) ?? []
        containers = try values.decodeIfPresent(Containers.self, forKey: .containers)
    }

    /// Arc's `sidebar.containers` past the global one, which is the rest of the file: an ordered dictionary written
    /// as key, value, key, value, as Arc's is. A value holds its Spaces and its items as the global sidebar does.
    struct Containers: Codable {
        struct Value: Codable {
            var spaces: [SidebarSpace]
            var tree: Tree
        }

        var entries: [(type: SidebarContainerType, value: Value)] = []

        init(entries: [(type: SidebarContainerType, value: Value)]) { self.entries = entries }

        init(from decoder: Decoder) throws {
            var values = try decoder.unkeyedContainer()
            while !values.isAtEnd {
                entries.append((try values.decode(SidebarContainerType.self), try values.decode(Value.self)))
            }
        }

        func encode(to encoder: Encoder) throws {
            var values = encoder.unkeyedContainer()
            for entry in entries {
                try values.encode(entry.type)
                try values.encode(entry.value)
            }
        }
    }

    struct Tree: Codable {
        var rootIDs: [UUID]
        var items: [Item]
    }

    struct Item: Codable {
        var id: UUID
        var parentID: UUID?
        var childIDs: [UUID]
        var kind: SidebarItem.Kind

        private enum Key: String, CodingKey {
            case id, parentID, childIDs, type, title, savedTitle, url, viewedAt, openerID, activeTabBeforeCreationID
            case container, splitView, customInfo, savedMuteStatus
        }

        private struct CustomInfo: Codable { var icon: String? }

        init(_ item: SidebarItem) {
            id = item.id
            parentID = item.parentID
            childIDs = item.childIDs
            kind = item.kind
        }

        var item: SidebarItem { SidebarItem(id: id, parentID: parentID, kind: kind, childIDs: childIDs) }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: Key.self)
            id = try values.decode(UUID.self, forKey: .id)
            parentID = try values.decodeIfPresent(UUID.self, forKey: .parentID)
            childIDs = try values.decodeIfPresent([UUID].self, forKey: .childIDs) ?? []
            let title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
            switch try values.decode(String.self, forKey: .type) {
            case "container": kind = .container(try values.decode(SidebarItem.Container.self, forKey: .container))
            case "tab":
                // As Arc's: the item's `title` is the user's name and `savedTitle` the page's. A file from before
                // names had only the page's, under `title`.
                let savedTitle = try values.decodeIfPresent(String.self, forKey: .savedTitle)
                kind = .tab(
                    SidebarTab(
                        id: id, title: savedTitle ?? title, url: try values.decodeIfPresent(URL.self, forKey: .url),
                        viewedAt: try values.decodeIfPresent(Date.self, forKey: .viewedAt),
                        openerID: try values.decodeIfPresent(UUID.self, forKey: .openerID),
                        activeTabBeforeCreationID: try values.decodeIfPresent(
                            UUID.self, forKey: .activeTabBeforeCreationID),
                        customTitle: savedTitle == nil || title.isEmpty ? nil : title,
                        icon: try values.decodeIfPresent(CustomInfo.self, forKey: .customInfo)?.icon,
                        muteStatus: try values.decodeIfPresent(SidebarTab.MuteStatus.self, forKey: .savedMuteStatus)))
            case "folder":
                kind = .folder(
                    SidebarFolder(
                        id: id, title: title,
                        icon: try values.decodeIfPresent(CustomInfo.self, forKey: .customInfo)?.icon))
            case "splitView":
                var data =
                    try values.decodeIfPresent(SidebarSplitViewData.self, forKey: .splitView)
                    ?? SidebarSplitViewData()
                data.title = title.isEmpty ? nil : title
                kind = .splitView(data)
            case let type:
                throw DecodingError.dataCorruptedError(
                    forKey: .type, in: values, debugDescription: "unknown item type \(type)")
            }
        }

        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: Key.self)
            try values.encode(id, forKey: .id)
            try values.encodeIfPresent(parentID, forKey: .parentID)
            if !childIDs.isEmpty { try values.encode(childIDs, forKey: .childIDs) }
            switch kind {
            case .container(let container):
                try values.encode("container", forKey: .type)
                try values.encode(container, forKey: .container)
            case .tab(let tab):
                try values.encode("tab", forKey: .type)
                try values.encodeIfPresent(tab.customTitle, forKey: .title)
                try values.encode(tab.title, forKey: .savedTitle)
                try values.encodeIfPresent(tab.url, forKey: .url)
                try values.encodeIfPresent(tab.viewedAt, forKey: .viewedAt)
                try values.encodeIfPresent(tab.openerID, forKey: .openerID)
                try values.encodeIfPresent(tab.activeTabBeforeCreationID, forKey: .activeTabBeforeCreationID)
                if let icon = tab.icon { try values.encode(CustomInfo(icon: icon), forKey: .customInfo) }
                try values.encodeIfPresent(tab.muteStatus, forKey: .savedMuteStatus)
            case .folder(let folder):
                try values.encode("folder", forKey: .type)
                try values.encode(folder.title, forKey: .title)
                if let icon = folder.icon { try values.encode(CustomInfo(icon: icon), forKey: .customInfo) }
            case .splitView(let data):
                try values.encode("splitView", forKey: .type)
                try values.encodeIfPresent(data.title, forKey: .title)
                try values.encode(data, forKey: .splitView)
            }
        }
    }

    init(state: SidebarState) {
        func tree(_ rootIDs: [UUID]) -> Tree {
            let items = rootIDs.flatMap { rootID in
                (state.tree[rootID].map { [$0] } ?? []) + state.tree.descendants(of: rootID)
            }
            return Tree(rootIDs: rootIDs, items: items.map(Item.init))
        }
        let saved = state.containers.filter {
            if case .incognito = $0.key { false } else { true }
        }
        .sorted { $0.value.id.uuidString < $1.value.id.uuidString }
        let containerRootIDs = Set(state.containers.values.map(\.unpinnedRootID))
        profiles = state.profiles
        spaces = state.spaces
        self.tree = tree(state.tree.rootIDs.filter { !containerRootIDs.contains($0) })
        archive = state.archive
        containers =
            saved.isEmpty
            ? nil
            : Containers(
                entries: saved.map { type, space in
                    (type, Containers.Value(spaces: [space], tree: tree([space.unpinnedRootID])))
                })
    }

    func state() throws -> SidebarState {
        let entries = containers?.entries ?? []
        let trees = [tree] + entries.map(\.value.tree)
        var state = SidebarState(
            profiles: profiles, spaces: spaces,
            tree: SidebarTree(rootIDs: trees.flatMap(\.rootIDs), items: trees.flatMap(\.items).map(\.item)),
            archive: archive)
        for entry in entries {
            guard entry.value.spaces.count == 1, var space = entry.value.spaces.first else {
                throw SnapshotError.invalid("container \(entry.type) hasn't one space")
            }
            // A file from before Arc's shape was matched, when a window's own Space had a pinned root, always empty.
            if let pinnedRootID = space.pinnedRootID, state.tree[pinnedRootID]?.childIDs.isEmpty == true {
                state.tree.removeRoot(pinnedRootID)
                space.pinnedRootID = nil
            }
            state.containers[entry.type] = space
        }
        try state.validate()
        return state
    }
}

extension SidebarState {
    func validate() throws {
        func check(_ condition: Bool, _ message: @autoclosure () -> String) throws {
            if !condition { throw SnapshotError.invalid(message()) }
        }
        try check(!profiles.isEmpty && !spaces.isEmpty, "no profiles or no spaces")
        var visited = Set<UUID>()
        func visit(_ id: UUID, parent: UUID?) throws {
            guard let item = tree[id] else { throw SnapshotError.invalid("missing item \(id)") }
            try check(item.parentID == parent, "parent mismatch for \(id)")
            try check(visited.insert(id).inserted, "item \(id) reached twice")
            for child in item.childIDs { try visit(child, parent: id) }
        }
        for rootID in tree.rootIDs {
            try check(tree[rootID]?.container != nil, "root \(rootID) isn't a container")
            try visit(rootID, parent: nil)
        }
        try check(visited.count == tree.items.count, "unreachable items")
        for entry in archive { try check(tree[entry.id] == nil, "archived tab \(entry.id) is also in the tree") }
        for profile in profiles {
            try check(tree.rootIDs.contains(profile.favoritesRootID), "profile \(profile.id) has no favorites root")
            try check(tree[profile.favoritesRootID]?.container == .favorites, "bad favorites root for \(profile.id)")
        }
        for space in spaces {
            try check(space.pinnedRootID != nil, "space \(space.id) has no pinned root")
        }
        for space in allSpaces {
            try check(profile(space.profileID) != nil, "space \(space.id) has no profile")
            if let pinnedRootID = space.pinnedRootID {
                try check(tree.rootIDs.contains(pinnedRootID), "space \(space.id) has no pinned root")
                try check(tree[pinnedRootID]?.container == .pinned, "bad pinned root for \(space.id)")
            }
            try check(tree.rootIDs.contains(space.unpinnedRootID), "space \(space.id) has no unpinned root")
            try check(tree[space.unpinnedRootID]?.container == .unpinned, "bad unpinned root for \(space.id)")
        }
    }
}

struct WindowRecord: Codable {
    let id: UUID
    var selectedSpaceID: UUID
    var sidebarMode: SidebarMode
    var sidebarWidth: CGFloat
    var lastActiveDates: [UUID: Date]
    var createdDates: [UUID: Date]
    var collapsedPinnedSpaces: Set<UUID>
    /// Arc's per-window `expandedItems`: the folders open in this window.
    var expandedItems: Set<UUID>
    /// Oa's own key: the tab the window showed, which comes back shown with its page when the last session does.
    var selectedTabID: UUID?
    var style: WindowStyle

    private enum Key: String, CodingKey {
        case id, selectedSpaceID, sidebarMode, sidebarWidth, lastActiveDates, createdDates, selectedTabID, style
        case collapsedPinnedSpaces = "spacesWithCollapsedPinnedSections"
        case expandedItems
    }

    init(
        id: UUID, style: WindowStyle, selectedSpaceID: UUID, sidebarMode: SidebarMode,
        sidebarWidth: CGFloat, lastActiveDates: [UUID: Date], createdDates: [UUID: Date],
        collapsedPinnedSpaces: Set<UUID>, expandedItems: Set<UUID> = [], selectedTabID: UUID?
    ) {
        self.id = id
        self.style = style
        self.selectedSpaceID = selectedSpaceID
        self.sidebarMode = sidebarMode
        self.sidebarWidth = sidebarWidth
        self.lastActiveDates = lastActiveDates
        self.createdDates = createdDates
        self.collapsedPinnedSpaces = collapsedPinnedSpaces
        self.expandedItems = expandedItems
        self.selectedTabID = selectedTabID
    }

    /// The dates are by tab ID string, so each is a JSON object; a file from before them has none, and one from
    /// before the sidebar's mode and width has a docked sidebar of the default width.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Key.self)
        id = try values.decode(UUID.self, forKey: .id)
        selectedSpaceID = try values.decode(UUID.self, forKey: .selectedSpaceID)
        sidebarMode = try values.decodeIfPresent(SidebarMode.self, forKey: .sidebarMode) ?? .anchored
        sidebarWidth =
            try values.decodeIfPresent(CGFloat.self, forKey: .sidebarWidth) ?? SidebarViewPreferences.defaultWidth
        func dates(_ key: Key) throws -> [UUID: Date] {
            let stored = try values.decodeIfPresent([String: Date].self, forKey: key) ?? [:]
            return Dictionary(stored.compactMap { id, date in UUID(uuidString: id).map { ($0, date) } }) { $1 }
        }
        lastActiveDates = try dates(.lastActiveDates)
        createdDates = try dates(.createdDates)
        collapsedPinnedSpaces = try values.decodeIfPresent(Set<UUID>.self, forKey: .collapsedPinnedSpaces) ?? []
        expandedItems = try values.decodeIfPresent(Set<UUID>.self, forKey: .expandedItems) ?? []
        selectedTabID = try values.decodeIfPresent(UUID.self, forKey: .selectedTabID)
        // As Arc's: a style that doesn't read, as a hot key's Little window's, is a standard window's.
        style = (try? values.decode(WindowStyle.self, forKey: .style)) ?? .standard(sidebarContext: .global)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: Key.self)
        try values.encode(id, forKey: .id)
        try values.encode(selectedSpaceID, forKey: .selectedSpaceID)
        try values.encode(sidebarMode, forKey: .sidebarMode)
        try values.encode(sidebarWidth, forKey: .sidebarWidth)
        func stored(_ dates: [UUID: Date]) -> [String: Date] {
            Dictionary(uniqueKeysWithValues: dates.map { ($0.key.uuidString, $0.value) })
        }
        try values.encode(stored(lastActiveDates), forKey: .lastActiveDates)
        try values.encode(stored(createdDates), forKey: .createdDates)
        try values.encode(
            collapsedPinnedSpaces.sorted { $0.uuidString < $1.uuidString }, forKey: .collapsedPinnedSpaces)
        if !expandedItems.isEmpty {
            try values.encode(expandedItems.sorted { $0.uuidString < $1.uuidString }, forKey: .expandedItems)
        }
        try values.encodeIfPresent(selectedTabID, forKey: .selectedTabID)
        try values.encode(style, forKey: .style)
    }
}

struct WindowsSnapshot: Codable {
    static let version = 1

    var version = WindowsSnapshot.version
    var sidebarViewPreferences: SidebarViewPreferences?
    var windows: [WindowRecord]
}
