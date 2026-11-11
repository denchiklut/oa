import AppKit
import Foundation

/// PNGs in `favicons/<tabID>.png` beside the sidebar file, as Arc keeps its sidebar and archive favicon caches apart
/// from its sidebar store. Read on demand, written when a page shows a new one, pruned to the tabs that still exist.
@MainActor
final class FaviconCache {
    private let directory: URL
    private var images: [UUID: NSImage?] = [:]
    private var written: [UUID: Data?] = [:]

    init(directory: URL) {
        self.directory = directory.appendingPathComponent("favicons")
    }

    func image(for id: UUID) -> NSImage? {
        if let image = images[id] { return image }
        let image = bytes(for: id).flatMap { NSImage(data: $0) }
        images[id] = .some(image)
        return image
    }

    func set(_ image: NSImage, for id: UUID) {
        guard let png = image.pngData, png != bytes(for: id) else { return }
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try png.write(to: url(for: id), options: .atomic)
            written[id] = .some(png)
            images[id] = .some(image)
        } catch {
            NSLog("Oa: couldn't save a favicon: %@", "\(error)")
        }
    }

    func remove(for id: UUID) -> Bool {
        guard bytes(for: id) != nil else { return false }
        try? FileManager.default.removeItem(at: url(for: id))
        written[id] = .some(nil)
        images[id] = .some(nil)
        return true
    }

    func prune(keeping ids: Set<UUID>) {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in urls {
            let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent)
            guard let id, !ids.contains(id) else { continue }
            try? FileManager.default.removeItem(at: url)
            images[id] = nil
            written[id] = nil
        }
    }

    private func bytes(for id: UUID) -> Data? {
        if let data = written[id] { return data }
        let data = try? Data(contentsOf: url(for: id))
        written[id] = .some(data)
        return data
    }

    private func url(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("png")
    }
}

extension NSImage {
    fileprivate var pngData: Data? {
        tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?.representation(using: .png, properties: [:])
    }
}
