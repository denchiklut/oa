import DevKit
import Foundation

/// What ⇧⌘T puts back, as a step of Arc's `ClosedSidebarItemsCache`: the tab itself with where it was, so it
/// returns after its Archive entry is gone, or a Peek with the tab it was over.
struct ClosedPage {
    enum Place {
        case tab(parentID: UUID, index: Int)
        case peek(ownerID: UUID)
    }

    /// The tab's ID, or the ID of the Peek's Archive entry.
    let id: UUID
    let title: String
    let url: URL?
    let place: Place
    let sessionID: PageSessionID?
    /// The tab whole, with its name, icon and sound, as Arc's step keeps the item; nil for a Peek.
    var tab: SidebarTab?

    var reopenedTab: SidebarTab {
        var tab = tab ?? SidebarTab(id: id, title: title, url: url)
        tab.viewedAt = .now
        return tab
    }
}

struct ClosedSplitView {
    let id: UUID
    let data: SidebarSplitViewData
    let parentID: UUID
    let index: Int
    let tabIDs: [UUID]
}

/// A deleted folder subtree kept for Undo, so ⌘Z puts its nested folders, splits and tabs back in order.
struct ClosedFolder {
    let root: SidebarItem
    let index: Int
    let spaceID: UUID
    let descendants: [SidebarItem]
    let depth: Int

    var id: UUID { root.id }
}

/// Arc's `CloseItemsCompletionToast`.
enum CloseItemsCompletionToast {
    case clearedTabs
}

/// An entry of Arc's stack: one close, of a tab or of several at once, whose steps go back one per press. It goes
/// on the stack with its first step, so a close that every page refused leaves the stack as it was.
struct ClosedGroup: Equatable {
    let id = UUID()
    /// What Edit ▸ Undo calls the close, as Arc's `UndoGroup.undoPrompt`.
    let undoPrompt: String
    /// As Arc's `focusedTabItemID`: the tab the window was showing, which an undo shows again.
    var focusedTabID: UUID?
    var completionToast: CloseItemsCompletionToast?
    /// A split closed whole, which an undo rebuilds with its ID, as Arc's does.
    var splitView: ClosedSplitView?
    /// A folder deleted whole, which an undo rebuilds with its hierarchy and tabs.
    var folder: ClosedFolder?
    /// The tabs of a close of several, in the order their steps go on, whatever order their pages end in.
    var order: [UUID] = []
    /// Their list as it was before the close, so each goes back between its old neighbours in any order.
    var siblings: [UUID] = []
    var steps: [ClosedPage] = []

    static func == (lhs: ClosedGroup, rhs: ClosedGroup) -> Bool { lhs.id == rhs.id }

    mutating func add(_ step: ClosedPage) {
        let order = order
        let rank = { (id: UUID) in order.firstIndex(of: id) ?? order.count }
        steps.insert(step, at: steps.firstIndex { rank($0.id) > rank(step.id) } ?? steps.count)
    }

    /// Where a step goes back: after the nearest of its old neighbours above that is there again, else at the top.
    func index(of id: UUID, among present: [UUID]) -> Int? {
        guard let old = siblings.firstIndex(of: id) else { return nil }
        return siblings[..<old].reversed().lazy.compactMap { present.firstIndex(of: $0) }.first.map { $0 + 1 } ?? 0
    }
}
