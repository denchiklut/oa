import AppKit
import Observation

/// Arc's `ContentSnapshotClient`: pages' pictures kept in memory by page, for what shows a page that isn't drawn, as
/// its tab switcher's cards. Observable: a new picture changes its page's `snapshot`.
///
/// Arc's holds the tab thumbnails its engine hands up. Oa's own until the engine's thumbnails fill it: the app asks
/// as the page is hidden, and a picture goes with its page.
@MainActor
@Observable
public final class ContentSnapshotClient {
    private struct Entry {
        weak var page: (any Page)?
        var image: NSImage
    }

    /// Arc's cache holds 20 pages and drops the one stored or read longest ago.
    private static let maxCount = 20
    /// Oa's own, where a window's full frame would hold some 13 MB a page: a kept picture is no wider in pixels.
    /// The number is Arc's `ModalItemSwitcher.Constants.preferredSnapshotWidth`, which nothing in Arc reads.
    private static let preferredSnapshotWidth = 600

    private var entries: [UUID: Entry] = [:]
    @ObservationIgnored private var leastRecentlyUsed: [UUID] = []

    public init() {}

    public func snapshot(of page: any Page) -> NSImage? {
        guard let image = entries[page.id]?.image else { return nil }
        use(page.id)
        return image
    }

    /// Asks the page for its picture now, so while it still draws. The last one stays when it has nothing drawn.
    public func capture(_ page: any Page) {
        page.snapshot { [weak self, weak page] image in
            guard let self, let page, let image else { return }
            entries = entries.filter { $0.value.page != nil }
            entries[page.id] = Entry(page: page, image: Self.scaled(image))
            use(page.id)
            leastRecentlyUsed.removeAll { entries[$0] == nil }
            while leastRecentlyUsed.count > Self.maxCount { entries[leastRecentlyUsed.removeFirst()] = nil }
        }
    }

    private func use(_ id: UUID) {
        leastRecentlyUsed.removeAll { $0 == id }
        leastRecentlyUsed.append(id)
    }

    private static func scaled(_ image: NSImage) -> NSImage {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
            source.width > preferredSnapshotWidth, let space = source.colorSpace,
            let context = CGContext(
                data: nil, width: preferredSnapshotWidth,
                height: source.height * preferredSnapshotWidth / source.width, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
        else { return image }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
        return context.makeImage().map { NSImage(cgImage: $0, size: image.size) } ?? image
    }
}
