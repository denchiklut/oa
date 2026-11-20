import AppKit
import Observation

/// Arc's `ContentSnapshotClient`: pages' pictures kept in memory by page, for what shows a page that isn't drawn, as
/// its tab switcher's cards. Observable: a new picture changes its page's `snapshot`. As in Arc it is handed the
/// thumbnails the engine makes of a page, and a picture goes with its page.
@MainActor
@Observable
public final class ContentSnapshotClient {
    private struct Entry {
        weak var page: (any Page)?
        var image: NSImage
    }

    /// Arc's cache holds 20 pages and drops the one stored or read longest ago.
    private static let maxCount = 20

    private var entries: [UUID: Entry] = [:]
    @ObservationIgnored private var leastRecentlyUsed: [UUID] = []

    public init() {}

    public func snapshot(of page: any Page) -> NSImage? {
        guard let image = entries[page.id]?.image else { return nil }
        use(page.id)
        return image
    }

    public func storeSnapshot(_ image: NSImage, of page: any Page) {
        entries = entries.filter { $0.value.page != nil }
        entries[page.id] = Entry(page: page, image: image)
        use(page.id)
        leastRecentlyUsed.removeAll { entries[$0] == nil }
        while leastRecentlyUsed.count > Self.maxCount { entries[leastRecentlyUsed.removeFirst()] = nil }
    }

    private func use(_ id: UUID) {
        leastRecentlyUsed.removeAll { $0 == id }
        leastRecentlyUsed.append(id)
    }
}
