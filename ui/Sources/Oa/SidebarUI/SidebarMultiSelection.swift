import Foundation

/// Arc's `multiSelectedItems`, which its tab list keeps as AppKit's outline view does: the rows ⌘-clicked, and the
/// last ⇧-click's range from the anchor, besides the window's selected tab. The window's own, not saved.
struct SidebarMultiSelection: Equatable {
    private var picked: [UUID] = []
    private var range: [UUID] = []
    /// The last row ⌘-clicked in, where a ⇧-click's range starts; else it starts at the selected tab.
    private(set) var anchorID: UUID?

    func contains(_ id: UUID) -> Bool { picked.contains(id) || range.contains(id) }

    mutating func toggle(_ id: UUID) {
        if contains(id) {
            remove(id)
        } else {
            picked.append(id)
            anchorID = id
        }
    }

    mutating func remove(_ id: UUID) {
        picked.removeAll { $0 == id }
        range.removeAll { $0 == id }
        if anchorID == id { anchorID = nil }
    }

    /// As AppKit's: a ⇧-click's range takes the place of the last one, and the rows ⌘-clicked stay.
    mutating func select(range ids: [UUID]) {
        range = ids
    }
}
