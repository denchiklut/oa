import Foundation
import Observation

@MainActor
@Observable
public final class AdBlocker {
    public private(set) var isEnabled: Bool
    public private(set) var selectedLists: Set<String>
    public private(set) var excludedHosts: Set<String>
    public private(set) var isApplying = false
    public private(set) var isDownloading = false
    public var error: String? { settingsError ?? applyError ?? updateError }

    private var settingsError: String?
    private var applyError: String?
    private var updateError: String?

    @ObservationIgnored private let settingsURL: URL
    @ObservationIgnored private let cache: BlockListCache
    @ObservationIgnored private let apply: @MainActor ([String]) async -> Bool
    @ObservationIgnored private let exclude: @MainActor ([String]) -> Void
    @ObservationIgnored private var updates: Task<Void, Never>?
    @ObservationIgnored private var revision = 0

    public init(
        directory: URL, apply: @escaping @MainActor ([String]) async -> Bool,
        exclude: @escaping @MainActor ([String]) -> Void
    ) {
        settingsURL = directory.appendingPathComponent("AdBlockSettings.json")
        let settings =
            (try? Data(contentsOf: settingsURL)).flatMap { try? JSONDecoder().decode(Settings.self, from: $0) }
            ?? Settings()
        isEnabled = settings.enabled
        selectedLists = settings.lists
        excludedHosts = settings.excludedHosts
        cache = BlockListCache(directory: directory)
        self.apply = apply
        self.exclude = exclude
    }

    public func start() async {
        let current = revision
        exclude(Array(excludedHosts))
        await applyRules()
        if current == revision { scheduleUpdates() }
    }

    public func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        changed()
    }

    public func setList(_ id: String, enabled: Bool) {
        guard BlockListCache.feeds.contains(where: { $0.id == id }) else { return }
        if enabled { selectedLists.insert(id) } else { selectedLists.remove(id) }
        changed()
    }

    public func isExcluded(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        return excludedHosts.contains(host)
    }

    public func setExcluded(_ excluded: Bool, for url: URL) {
        guard let host = url.host()?.lowercased(), ["http", "https"].contains(url.scheme ?? "") else { return }
        if excluded { excludedHosts.insert(host) } else { excludedHosts.remove(host) }
        exclude(Array(excludedHosts))
        save()
    }

    private func changed() {
        revision += 1
        save()
        updates?.cancel()
        updates = Task { [weak self] in
            guard let self else { return }
            await applyRules()
            guard !Task.isCancelled else { return }
            scheduleUpdates()
        }
    }

    private func applyRules() async {
        let current = revision
        isApplying = true
        let texts = isEnabled ? await cache.contents(for: selectedLists) : []
        guard current == revision, !Task.isCancelled else { return }
        let success = await apply(texts)
        guard current == revision, !Task.isCancelled else { return }
        isApplying = false
        applyError = success ? nil : "Couldn’t apply ad-blocking rules."
    }

    private func scheduleUpdates() {
        updates?.cancel()
        isDownloading = false
        guard isEnabled else { return }
        updates = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let current = revision
                isDownloading = await cache.isMissing(selectedLists)
                let result = await cache.refresh(selectedLists)
                let missing = await cache.isMissing(selectedLists)
                guard !Task.isCancelled, current == revision else { return }
                isDownloading = false
                if result.changed { await applyRules() }
                updateError =
                    !result.failed
                    ? nil
                    : missing ? "Couldn’t download filters." : "Couldn’t update filters. Saved rules are still in use."
                do { try await Task.sleep(for: .seconds(3600)) } catch { return }
            }
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let settings = Settings(enabled: isEnabled, lists: selectedLists, excludedHosts: excludedHosts)
            try JSONEncoder().encode(settings).write(to: settingsURL, options: .atomic)
            settingsError = nil
        } catch { settingsError = "Couldn’t save ad-blocker settings." }
    }

    private struct Settings: Codable {
        var enabled = false
        var lists: Set<String> = ["EasyList", "EasyPrivacy"]
        var excludedHosts: Set<String> = []
    }
}

private actor BlockListCache {
    struct Feed: Sendable {
        let id: String
        let urls: [URL]
    }

    static let feeds = ["EasyList", "EasyPrivacy"].map {
        Feed(id: $0, urls: [URL(string: "https://easylist.to/easylist/\($0.lowercased()).txt")!])
    }

    private struct Content: Codable {
        var url: URL
        var text: String
        var lastUpdated: Date?
        var etag: String?
    }

    private struct Archive: Codable {
        var version = 1
        var lists: [String: [Content]] = [:]
    }

    private let file: URL
    private var archive: Archive?

    init(directory: URL) { file = directory.appendingPathComponent("BlockList.json") }

    func contents(for selected: Set<String>) -> [String] {
        load()
        return Self.feeds.filter { selected.contains($0.id) }.map { feed in
            let contents = archive?.lists[feed.id] ?? []
            return contents.isEmpty ? "[Adblock Plus 2.0]" : contents.map(\.text).joined(separator: "\n")
        }
    }

    func isMissing(_ selected: Set<String>) -> Bool {
        load()
        return Self.feeds.contains { selected.contains($0.id) && (archive?.lists[$0.id] ?? []).isEmpty }
    }

    func refresh(_ selected: Set<String>) async -> (changed: Bool, failed: Bool) {
        load()
        var changed = false
        var failed = false
        for feed in Self.feeds where selected.contains(feed.id) {
            let old = archive?.lists[feed.id] ?? []
            var next: [Content] = []
            var replaced = false
            do {
                for url in feed.urls {
                    try Task.checkCancellation()
                    let cached = old.first { $0.url == url }
                    if let date = cached?.lastUpdated, Date().timeIntervalSince(date) < 10800, let cached {
                        next.append(cached)
                        continue
                    }
                    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
                    request.setValue(cached?.etag ?? "", forHTTPHeaderField: "If-None-Match")
                    let (data, response) = try await URLSession.shared.data(for: request)
                    try Task.checkCancellation()
                    guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                    if response.statusCode == 304, let cached {
                        next.append(cached)
                    } else if response.statusCode == 200, let text = String(data: data, encoding: .utf8) {
                        next.append(
                            Content(
                                url: url, text: text, lastUpdated: Date(),
                                etag: response.value(forHTTPHeaderField: "ETag")))
                        replaced = true
                    } else {
                        throw URLError(.badServerResponse)
                    }
                }
                if replaced {
                    archive?.lists[feed.id] = next
                    changed = true
                }
            } catch is CancellationError { break } catch { failed = true }
        }
        if changed, let archive {
            do {
                try FileManager.default.createDirectory(
                    at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(archive).write(to: file, options: .atomic)
            } catch { failed = true }
        }
        return (changed, failed)
    }

    private func load() {
        guard archive == nil else { return }
        let saved = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Archive.self, from: $0) }
        archive = saved?.version == 1 ? saved : Archive()
    }
}
