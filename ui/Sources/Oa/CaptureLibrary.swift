import AppKit
import Observation

@MainActor
@Observable
final class CaptureLibrary {
    let directory: URL
    private(set) var files: [URL]

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
        hidden = (try? JSONDecoder().decode(Set<URL>.self, from: Data(contentsOf: hiddenFile))) ?? []
        self.directory = directory.resolvingSymlinksInPath().appendingPathComponent("Captures", isDirectory: true)
        files =
            ((try? FileManager.default.contentsOfDirectory(at: self.directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "png" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func save(_ png: Data) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = Date.now.ISO8601Format().replacingOccurrences(of: ":", with: "-")
        let file = directory.appendingPathComponent("Capture \(stamp) \(UUID().uuidString).png")
        try png.write(to: file, options: .atomic)
        files.insert(file, at: 0)
        return file
    }

    func update(_ file: URL, with png: Data) throws {
        try png.write(to: file, options: .atomic)
        revisions[file] = UUID()
    }

    func remove(_ file: URL) throws {
        guard files.contains(file) else { return }
        try FileManager.default.removeItem(at: file)
        revisions[file] = nil
        files.removeAll { $0 == file }
    }
}
