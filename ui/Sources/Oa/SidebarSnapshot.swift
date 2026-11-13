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

    private enum Key: String, CodingKey { case version, profiles, spaces, tree, archive }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Key.self)
        version = try values.decode(Int.self, forKey: .version)
        profiles = try values.decode([SidebarProfile].self, forKey: .profiles)
        spaces = try values.decode([SidebarSpace].self, forKey: .spaces)
        tree = try values.decode(Tree.self, forKey: .tree)
        archive = try values.decodeIfPresent([SidebarArchivedTab].self, forKey: .archive) ?? []
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
            case id, parentID, childIDs, type, title, url, viewedAt, openerID, container
        }

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
                kind = .tab(
                    SidebarTab(
                        id: id, title: title, url: try values.decodeIfPresent(URL.self, forKey: .url),
                        viewedAt: try values.decodeIfPresent(Date.self, forKey: .viewedAt),
                        openerID: try values.decodeIfPresent(UUID.self, forKey: .openerID)))
            case "folder": kind = .folder(title: title)
            case "splitView": kind = .splitView
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
                try values.encode(tab.title, forKey: .title)
                try values.encodeIfPresent(tab.url, forKey: .url)
                try values.encodeIfPresent(tab.viewedAt, forKey: .viewedAt)
                try values.encodeIfPresent(tab.openerID, forKey: .openerID)
            case .folder(let title):
                try values.encode("folder", forKey: .type)
                try values.encode(title, forKey: .title)
            case .splitView:
                try values.encode("splitView", forKey: .type)
            }
        }
    }

    init(state: SidebarState) {
        profiles = state.profiles
        spaces = state.spaces
        let items = state.tree.rootIDs.flatMap { rootID in
            (state.tree[rootID].map { [$0] } ?? []) + state.tree.descendants(of: rootID)
        }
        tree = Tree(rootIDs: state.tree.rootIDs, items: items.map(Item.init))
        archive = state.archive
    }

    func state() throws -> SidebarState {
        let state = SidebarState(
            profiles: profiles, spaces: spaces, tree: SidebarTree(rootIDs: tree.rootIDs, items: tree.items.map(\.item)),
            archive: archive)
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
            try check(profile(space.profileID) != nil, "space \(space.id) has no profile")
            try check(tree.rootIDs.contains(space.pinnedRootID), "space \(space.id) has no pinned root")
            try check(tree.rootIDs.contains(space.unpinnedRootID), "space \(space.id) has no unpinned root")
            try check(tree[space.pinnedRootID]?.container == .pinned, "bad pinned root for \(space.id)")
            try check(tree[space.unpinnedRootID]?.container == .unpinned, "bad unpinned root for \(space.id)")
        }
    }
}

struct WindowRecord: Codable {
    let id: UUID
    var selectedSpaceID: UUID
    var lastActiveDates: [UUID: Date]
    var createdDates: [UUID: Date]

    private enum Key: String, CodingKey { case id, selectedSpaceID, lastActiveDates, createdDates }

    init(id: UUID, selectedSpaceID: UUID, lastActiveDates: [UUID: Date], createdDates: [UUID: Date]) {
        self.id = id
        self.selectedSpaceID = selectedSpaceID
        self.lastActiveDates = lastActiveDates
        self.createdDates = createdDates
    }

    /// The dates are by tab ID string, so each is a JSON object; a file from before them has none.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Key.self)
        id = try values.decode(UUID.self, forKey: .id)
        selectedSpaceID = try values.decode(UUID.self, forKey: .selectedSpaceID)
        func dates(_ key: Key) throws -> [UUID: Date] {
            let stored = try values.decodeIfPresent([String: Date].self, forKey: key) ?? [:]
            return Dictionary(stored.compactMap { id, date in UUID(uuidString: id).map { ($0, date) } }) { $1 }
        }
        lastActiveDates = try dates(.lastActiveDates)
        createdDates = try dates(.createdDates)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: Key.self)
        try values.encode(id, forKey: .id)
        try values.encode(selectedSpaceID, forKey: .selectedSpaceID)
        func stored(_ dates: [UUID: Date]) -> [String: Date] {
            Dictionary(uniqueKeysWithValues: dates.map { ($0.key.uuidString, $0.value) })
        }
        try values.encode(stored(lastActiveDates), forKey: .lastActiveDates)
        try values.encode(stored(createdDates), forKey: .createdDates)
    }
}

struct WindowsSnapshot: Codable {
    static let version = 1

    var version = WindowsSnapshot.version
    var windows: [WindowRecord]
}
