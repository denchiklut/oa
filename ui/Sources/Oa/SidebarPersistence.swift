import Foundation

/// `sidebar.json` and `windows.json` in the data directory. A file that can't be read or comes from a newer
/// version is kept as it is and not written for the rest of the launch.
@MainActor
final class SidebarPersistence {
    private let directory: URL
    private let sidebarURL: URL
    private let windowsURL: URL
    private var written: [URL: Data] = [:]
    private var disabled: Set<URL> = []
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    init(directory: URL) {
        self.directory = directory
        sidebarURL = directory.appendingPathComponent("sidebar.json")
        windowsURL = directory.appendingPathComponent("windows.json")
    }

    func loadSidebar() -> SidebarState? {
        load(SidebarSnapshot.self, from: sidebarURL, version: SidebarSnapshot.version) { try $0.state() }
    }

    func loadWindows() -> [WindowRecord] {
        load(WindowsSnapshot.self, from: windowsURL, version: WindowsSnapshot.version, \.windows) ?? []
    }

    func save(_ state: SidebarState, windows: [WindowRecord]) {
        write(SidebarSnapshot(state: state), to: sidebarURL)
        write(WindowsSnapshot(windows: windows), to: windowsURL)
    }

    private func load<Snapshot: Decodable, Value>(
        _ type: Snapshot.Type, from url: URL, version supported: Int, _ convert: (Snapshot) throws -> Value
    ) -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let version = try decoder.decode(Versioned.self, from: data).version
            guard version <= supported else { throw SnapshotError.newerVersion(version) }
            let value = try convert(try decoder.decode(Snapshot.self, from: data))
            written[url] = data
            return value
        } catch {
            disabled.insert(url)
            NSLog("Oa: keeping %@ as it is, not saving it this launch: %@", url.lastPathComponent, "\(error)")
            return nil
        }
    }

    private func write<Snapshot: Encodable>(_ snapshot: Snapshot, to url: URL) {
        guard !disabled.contains(url) else { return }
        do {
            let data = try encoder.encode(snapshot)
            guard written[url] != data else { return }
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try data.write(to: url, options: .atomic)
            written[url] = data
        } catch {
            NSLog("Oa: couldn't save %@: %@", url.lastPathComponent, "\(error)")
        }
    }
}
