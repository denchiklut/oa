import AppKit
import Observation

@MainActor
@Observable
final class CaptureLibrary {
    let directory: URL
    private(set) var items: [MediaItem]

    private struct Metadata: Codable {
        let date: Date
        let address: String?
    }

    private(set) var revisions: [URL: UUID] = [:]

    private let hiddenFile: URL
    private(set) var hidden: Set<URL>

    func hide(_ file: URL) throws {
        let next = hidden.union([file])
        try JSONEncoder().encode(next).write(to: hiddenFile, options: .atomic)
        hidden = next
    }

    init(directory: URL) {
        hiddenFile = directory.appendingPathComponent("hidden-media.json")
        let hiddenFiles = (try? JSONDecoder().decode([URL].self, from: Data(contentsOf: hiddenFile))) ?? []
        hidden = Set(hiddenFiles.map(MediaItem.canonicalFile))
        self.directory = directory.resolvingSymlinksInPath().appendingPathComponent("Captures", isDirectory: true)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .creationDateKey]
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: self.directory, includingPropertiesForKeys: Array(keys))) ?? []
        items = files.compactMap { entry -> MediaItem? in
            let file = MediaItem.canonicalFile(entry)
            guard file.pathExtension == "png", let values = try? file.resourceValues(forKeys: keys),
                values.isRegularFile == true
            else { return nil }
            let metadata = (try? Data(contentsOf: file.appendingPathExtension("json"))).flatMap {
                try? JSONDecoder().decode(Metadata.self, from: $0)
            }
            return MediaItem(
                file: file, date: metadata?.date ?? values.creationDate ?? .distantPast, isMovie: false,
                captureTitle: metadata?.address ?? file.lastPathComponent)
        }.sorted(by: MediaItem.newestFirst)
    }

    func save(_ png: Data, from source: URL?) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let date = Date.now
        let stamp = date.ISO8601Format().replacingOccurrences(of: ":", with: "-")
        let file = MediaItem.canonicalFile(
            directory.appendingPathComponent("Capture \(stamp) \(UUID().uuidString).png"))
        // Keep the page address in the library, outside the PNG that gets shared or exported.
        var components = source.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: true) }
        components?.user = nil
        components?.password = nil
        let address = components?.url.map { CommandBarRanking.readable($0) }
        let metadataFile = file.appendingPathExtension("json")
        try JSONEncoder().encode(Metadata(date: date, address: address)).write(to: metadataFile, options: .atomic)
        do {
            try png.write(to: file, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: metadataFile)
            throw error
        }
        items.insert(
            MediaItem(file: file, date: date, isMovie: false, captureTitle: address ?? file.lastPathComponent), at: 0)
        return file
    }

    func update(_ file: URL, with png: Data) throws {
        try png.write(to: file, options: .atomic)
        revisions[file] = UUID()
    }

    func remove(_ file: URL) throws {
        guard items.contains(where: { $0.file == file }) else { return }
        try FileManager.default.removeItem(at: file)
        revisions[file] = nil
        items.removeAll { $0.file == file }
        try? FileManager.default.removeItem(at: file.appendingPathExtension("json"))
    }
}
