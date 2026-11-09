import Foundation

/// `sidebar.json` and `windows.json` in the data directory. A file that can't be read or comes from a newer
/// version is kept as it is and not written for the rest of the launch.
///
/// Before the first overwrite of `sidebar.json` each launch, the bytes the launch started from go to a dated copy
/// beside it, named by their save time, and the copies are pruned to Arc's documented tiers.
@MainActor
final class SidebarPersistence {
    private let directory: URL
    private let sidebarURL: URL
    private let windowsURL: URL
    private var written: [URL: Data] = [:]
    private var disabled: Set<URL> = []
    private var copied = false
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

    /// The dated copies, newest first.
    func backups() -> [SidebarBackup] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.compactMap(SidebarBackup.init).sorted { $0.date > $1.date }
    }

    func read(_ backup: SidebarBackup) throws -> SidebarState {
        try decode(SidebarSnapshot.self, from: Data(contentsOf: backup.url), version: SidebarSnapshot.version).state()
    }

    /// The current file goes to a dated copy first, so a restore is undoable from the same list. A file kept unread
    /// this launch is readable again from here.
    func restore(_ backup: SidebarBackup) throws {
        let data = try Data(contentsOf: backup.url)
        _ = try decode(SidebarSnapshot.self, from: data, version: SidebarSnapshot.version).state()
        try keepCopy()
        try data.write(to: sidebarURL, options: .atomic)
        written[sidebarURL] = data
        disabled.remove(sidebarURL)
    }

    private func load<Snapshot: Decodable, Value>(
        _ type: Snapshot.Type, from url: URL, version supported: Int, _ convert: (Snapshot) throws -> Value
    ) -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let value = try convert(try decode(type, from: data, version: supported))
            written[url] = data
            return value
        } catch {
            disabled.insert(url)
            NSLog("Oa: keeping %@ as it is, not saving it this launch: %@", url.lastPathComponent, "\(error)")
            return nil
        }
    }

    private func decode<Snapshot: Decodable>(_ type: Snapshot.Type, from data: Data, version supported: Int) throws
        -> Snapshot
    {
        let version = try decoder.decode(Versioned.self, from: data).version
        guard version <= supported else { throw SnapshotError.newerVersion(version) }
        return try decoder.decode(Snapshot.self, from: data)
    }

    private func write<Snapshot: Encodable>(_ snapshot: Snapshot, to url: URL) {
        guard !disabled.contains(url) else { return }
        do {
            let data = try encoder.encode(snapshot)
            guard written[url] != data else { return }
            if url == sidebarURL, !copied { try keepCopy() }
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try data.write(to: url, options: .atomic)
            written[url] = data
        } catch {
            NSLog("Oa: couldn't save %@: %@", url.lastPathComponent, "\(error)")
        }
    }

    /// A copy named by the file's save time; the same bytes found again at a later launch add nothing.
    private func keepCopy() throws {
        copied = true
        guard let saved = try? sidebarURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        else { return }
        let copy = directory.appendingPathComponent(SidebarBackup.name(for: saved))
        if !FileManager.default.fileExists(atPath: copy.path) {
            try FileManager.default.copyItem(at: sidebarURL, to: copy)
        }
        prune()
    }

    /// Arc's documented tiers: the newest 10 of today, one a day for the 10 days before, one a week for the month
    /// before that, one a month for the year before that.
    private func prune() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let days = calendar.date(byAdding: .day, value: -10, to: today)!
        let weeks = calendar.date(byAdding: .month, value: -1, to: days)!
        let months = calendar.date(byAdding: .year, value: -1, to: weeks)!
        var kept: [Calendar.Component: Set<Date>] = [:]
        var todays = 0
        for backup in backups() {
            var keep = false
            if backup.date >= today {
                todays += 1
                keep = todays <= 10
            } else if let unit: Calendar.Component = backup.date >= days
                ? .day : backup.date >= weeks ? .weekOfYear : backup.date >= months ? .month : nil,
                let start = calendar.dateInterval(of: unit, for: backup.date)?.start
            {
                keep = kept[unit, default: []].insert(start).inserted
            }
            if !keep { try? FileManager.default.removeItem(at: backup.url) }
        }
    }
}

/// A dated copy of `sidebar.json`, `sidebar.YYYY-MM-DD-HH-MM-SS-mmm.json`, stamped in local time with the save
/// time of the bytes it holds.
struct SidebarBackup: Hashable {
    let url: URL
    let date: Date

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss-SSS"
        return formatter
    }()

    static func name(for date: Date) -> String { "sidebar.\(formatter.string(from: date)).json" }

    init?(url: URL) {
        let name = url.lastPathComponent
        guard name.hasPrefix("sidebar."), name.hasSuffix(".json"),
            let date = Self.formatter.date(from: String(name.dropFirst("sidebar.".count).dropLast(".json".count)))
        else { return nil }
        self.url = url
        self.date = date
    }
}
