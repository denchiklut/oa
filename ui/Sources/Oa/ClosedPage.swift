import DevKit
import Foundation

/// What ⇧⌘T puts back, as a step of Arc's `ClosedSidebarItemsCache`: the tab itself with where it was, so it
/// returns after its Archive entry is gone.
struct ClosedPage {
    let id: UUID
    let title: String
    let url: URL?
    let parentID: UUID
    let index: Int
    let sessionID: PageSessionID?
}
