import Foundation
import Observation

/// Arc's `ModalItemSwitcher` state, the ⌃⇥ switcher's: a window's recent tabs as cards, one of them focused.
@MainActor
@Observable
final class ModalItemSwitcher {
    /// Arc's `CycleRecentTabsTarget`, the cases its menu items send.
    enum Target {
        case next, previous
    }

    static let maxNumberOfItemsToDisplay = 5

    /// One more than is shown, as Arc builds it, so the next tab is at hand when a card closes.
    private(set) var itemIDs: [UUID]
    private(set) var focusedItemID: UUID
    /// Tabs closed from the cards. A pinned tab or a Favorite outlives its close, and stays out while this is up.
    var closedItemIDs: Set<UUID> = []
    let presentationRequestTime = Date()

    var visibleItemIDs: [UUID] { Array(itemIDs.prefix(Self.maxNumberOfItemsToDisplay)) }

    /// As Arc: forward starts on the tab before the current one, which is the second card, or on the first when the
    /// window shows no tab; backward starts on the last card.
    init?(itemIDs: [UUID], currentID: UUID?, target: Target) {
        guard let first = itemIDs.first else { return nil }
        self.itemIDs = Array(itemIDs.prefix(Self.maxNumberOfItemsToDisplay + 1))
        focusedItemID = first
        let visible = visibleItemIDs
        switch target {
        case .next: focusedItemID = visible[first == currentID ? min(1, visible.count - 1) : 0]
        case .previous: focusedItemID = visible[visible.count - 1]
        }
    }

    func focus(_ id: UUID) {
        if visibleItemIDs.contains(id) { focusedItemID = id }
    }

    /// Wraps at either end, as Arc's `itemIdOffset(by:fromID:)`.
    func focusAdjacentItem(_ offset: Int) {
        let visible = visibleItemIDs
        guard let index = visible.firstIndex(of: focusedItemID) else { return }
        focusedItemID = visible[(index + offset + visible.count) % visible.count]
    }

    /// The list built again after a close, never empty. As Arc's `updateModalItemSwitcher`, the focus keeps its
    /// place in the row and not its tab, so it lands on the card that took a closed one's place.
    func update(itemIDs: [UUID]) {
        let index = visibleItemIDs.firstIndex(of: focusedItemID) ?? 0
        self.itemIDs = Array(itemIDs.prefix(Self.maxNumberOfItemsToDisplay + 1))
        let visible = visibleItemIDs
        focusedItemID = visible[min(index, visible.count - 1)]
    }
}
