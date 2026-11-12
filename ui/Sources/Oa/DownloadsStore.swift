import AppKit
import DevKit
import Foundation
import Network
import Observation
import UniformTypeIdentifiers

/// Every profile's downloads as one list, as Arc's Library shows them, and the app's side of them: which open when
/// they finish.
@MainActor
@Observable
final class DownloadsStore {
    struct Entry: Identifiable, Equatable {
        let download: Download
        let profileID: UUID

        var id: Download.ID { download.id }
    }

    private(set) var openingWhenFinished: Set<Download.ID> = []
    @ObservationIgnored private let engine: any BrowserApplication
    @ObservationIgnored private let sidebar: SidebarStore

    /// Reading the list loads every profile, so past downloads are there from launch.
    init(engine: any BrowserApplication, sidebar: SidebarStore) {
        self.engine = engine
        self.sidebar = sidebar
        watch()
    }

    /// Newest first. A download the engine hasn't placed yet has no row, as none shows in Arc for a Save sheet
    /// that was cancelled.
    var entries: [Entry] {
        sidebar.state.profiles.flatMap { profile in
            engine.browserContext(id: profile.id).downloads.items.filter { $0.file != nil }
                .map { Entry(download: $0, profileID: profile.id) }
        }
        .sorted { $0.download.startedAt > $1.download.startedAt }
    }

    var running: [Entry] { entries.filter(\.isRunning) }

    /// One ring for all that run, as Arc's Library button has: nil when none does.
    var progress: Double? {
        let running = running
        guard !running.isEmpty else { return nil }
        let total = running.reduce(0) { $0 + ($1.download.totalBytes ?? 0) }
        let received = running.reduce(0) { $0 + $1.download.receivedBytes }
        return total > 0 ? min(1, Double(received) / Double(total)) : 0
    }

    /// What Arc's Library page leaves out when it opens: cancelled, failed, and finished with the file gone.
    var gone: Set<Download.ID> {
        Set(
            entries.filter {
                switch $0.download.status {
                case .cancelled, .failed: true
                case .finished: !$0.fileExists
                default: false
                }
            }
            .map(\.id))
    }

    func toggleOpenWhenFinished(_ entry: Entry) {
        guard entry.isRunning else { return }
        if openingWhenFinished.remove(entry.id) == nil { openingWhenFinished.insert(entry.id) }
    }

    func open(_ entry: Entry) {
        if let file = entry.download.file { NSWorkspace.shared.open(file) }
    }

    func reveal(_ entry: Entry) {
        if let file = entry.download.file { NSWorkspace.shared.activateFileViewerSelecting([file]) }
    }

    func share(_ entry: Entry, with service: NSSharingService.Name) {
        if let file = entry.download.file { NSSharingService(named: service)?.perform(withItems: [file]) }
    }

    private func watch() {
        withObservationTracking {
            _ = entries
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.openFinished()
                self?.watch()
            }
        }
    }

    private func openFinished() {
        guard !openingWhenFinished.isEmpty else { return }
        let entries = entries
        for id in openingWhenFinished {
            let entry = entries.first { $0.id == id }
            if entry?.isRunning == true { continue }
            openingWhenFinished.remove(id)
            if let entry, entry.download.status == .finished { open(entry) }
        }
    }
}

extension DownloadsStore.Entry {
    var name: String { download.file?.lastPathComponent ?? "" }
    /// As Arc names it; it names none for a bare address such as 127.0.0.1.
    var host: String? {
        guard let host = download.sourceURL?.host(), IPv4Address(host) == nil, IPv6Address(host) == nil else {
            return nil
        }
        return host
    }
    var isRunning: Bool { download.status == .inProgress || download.status == .paused }
    var fileExists: Bool { download.file.map { FileManager.default.fileExists(atPath: $0.path) } ?? false }

    var fraction: Double {
        guard let total = download.totalBytes, total > 0 else { return 0 }
        return min(1, Double(download.receivedBytes) / Double(total))
    }

    /// The app a click on it opens, as Arc names it in "Open in ‹App›".
    var application: String? {
        guard let file = download.file, let app = NSWorkspace.shared.urlForApplication(toOpen: file) else {
            return nil
        }
        return FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
    }

    /// Arc's type words; nil for a file it has none for.
    var kind: String? {
        guard let type = download.file.flatMap({ UTType(filenameExtension: $0.pathExtension) }) else { return nil }
        let words: [(UTType, String)] = [
            (.image, "Image"), (.diskImage, "Disk Image"), (.pdf, "PDF"), (.video, "Video"), (.movie, "Movie"),
            (.audio, "Audio"), (.zip, "Zip Archive"), (.archive, "Archive"),
        ]
        return words.first { type.conforms(to: $0.0) }?.1
    }
}

/// Arc's words for a download, as its Library and flyout showed them.
enum DownloadText {
    /// The Library page's line under the name.
    static func subtitle(_ entry: DownloadsStore.Entry, opening: Bool) -> String {
        let from = entry.host.map { "from \($0)" }
        switch entry.download.status {
        case .inProgress, .notStarted: return opening ? self.opening(entry) : progress(entry.download)
        case .paused: return "Paused"
        case .failed: return "Failed to Download"
        case .cancelled: return ["Cancelled", from].compactMap { $0 }.joined(separator: " · ")
        case .finished: return [entry.kind ?? "Download", from].compactMap { $0 }.joined(separator: " ")
        }
    }

    static func opening(_ entry: DownloadsStore.Entry) -> String {
        "Opening… (\(Int(entry.fraction * 100))%)"
    }

    /// "50.8/94.4 MB · 45s": bytes and the time left, without the speed.
    static func progress(_ download: Download) -> String {
        let total = download.totalBytes ?? 0
        let unit = units.first { max(total, download.receivedBytes) >= $0.size } ?? units[units.count - 1]
        let number = { (bytes: Int64) in String(format: "%.\(unit.digits)f", Double(bytes) / Double(unit.size)) }
        let bytes = total > 0 ? "\(number(download.receivedBytes))/\(number(total))" : number(download.receivedBytes)
        return (["\(bytes) \(unit.name)"] + (download.secondsRemaining.map { [timeLeft($0)] } ?? []))
            .joined(separator: " · ")
    }

    static func timeLeft(_ seconds: Int) -> String {
        switch seconds {
        case ..<60: "\(seconds)s"
        case ..<3600: "\(seconds / 60)m \(seconds % 60)s"
        default: "\(seconds / 3600)h \(seconds % 3600 / 60)m"
        }
    }

    /// The Library's groups: Today, Yesterday, N days ago, then weeks.
    static func day(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        let days =
            calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now))
            .day ?? 0
        switch days {
        case ...0: return "Today"
        case 1: return "Yesterday"
        case ..<7: return "\(days) days ago"
        case ..<14: return "1 week ago"
        default: return "\(days / 7) weeks ago"
        }
    }

    static func age(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: min(date, .now), relativeTo: .now)
    }

    private static let units: [(size: Int64, name: String, digits: Int)] = [
        (1_000_000_000, "GB", 1), (1_000_000, "MB", 1), (1000, "KB", 0), (1, "bytes", 0),
    ]
}
