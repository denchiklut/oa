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
}
