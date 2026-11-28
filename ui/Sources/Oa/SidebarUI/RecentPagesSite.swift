import DevKit
import Foundation
import Observation

@MainActor
@Observable
final class PreviewPreferences {
    private let defaults: UserDefaults
    var folders: Bool { didSet { defaults.set(folders, forKey: "folderPreviewEnabled") } }
    var recentPages: Bool { didSet { defaults.set(recentPages, forKey: "recentPagesPreviewEnabled") } }
    private var disabledSites: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        folders = defaults.object(forKey: "folderPreviewEnabled") as? Bool ?? true
        recentPages = defaults.object(forKey: "recentPagesPreviewEnabled") as? Bool ?? true
        disabledSites = Set(defaults.stringArray(forKey: "disabledRecentPagesSites") ?? [])
    }

    func isEnabled(_ site: RecentPagesSite) -> Bool { recentPages && !disabledSites.contains(site.rawValue) }

    func setEnabled(_ enabled: Bool, for site: RecentPagesSite) {
        if enabled { disabledSites.remove(site.rawValue) } else { disabledSites.insert(site.rawValue) }
        defaults.set(disabledSites.sorted(), forKey: "disabledRecentPagesSites")
    }
}

enum RecentPagesSite: String {
    case linear, notion, figma

    init?(url: URL?) {
        guard let url, ["http", "https"].contains(url.scheme?.lowercased()), let host = url.host()?.lowercased()
        else { return nil }
        switch host {
        case "linear.app", "www.linear.app": self = .linear
        case "figma.com", "www.figma.com": self = .figma
        case "notion.so", "www.notion.so", "notion.com", "www.notion.com", "app.notion.com": self = .notion
        default:
            guard host.hasSuffix(".notion.site") else { return nil }
            self = .notion
        }
    }

    var name: String { rawValue.capitalized }

    var emptyMessage: String {
        switch self {
        case .linear: "Recent Linear projects and issues appear here."
        case .notion: "Recent Notion docs appear here."
        case .figma: "Recent Figma files appear here."
        }
    }

    func documents(in history: [HistoryEntry]) -> [HistoryEntry] {
        var seen = Set<String>()
        var pages: [HistoryEntry] = []
        for entry in history {
            guard Self(url: entry.url) == self, let id = documentID(in: entry.url), seen.insert(id).inserted else {
                continue
            }
            var title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            for suffix in [" – " + name, " - " + name, " | " + name] where title.hasSuffix(suffix) {
                title.removeLast(suffix.count)
            }
            pages.append(HistoryEntry(url: entry.url, title: title.isEmpty ? entry.url.lastPathComponent : title))
            if pages.count == 5 { break }
        }
        return pages
    }

    // Oa groups visits to the same document, keeping its newest URL (including a selected Figma node).
    private func documentID(in url: URL) -> String? {
        let path = url.path().split(separator: "/")
        switch self {
        case .linear:
            guard path.count >= 3, ["issue", "project"].contains(path[1]) else { return nil }
            return path.prefix(3).joined(separator: "/").lowercased()
        case .figma:
            guard path.count >= 2, ["file", "design", "board", "proto", "slides", "deck", "make"].contains(path[0])
            else { return nil }
            return String(path[1])
        case .notion:
            guard let slug = path.last else { return nil }
            if let uuid = UUID(uuidString: String(slug)) {
                return uuid.uuidString.lowercased().replacingOccurrences(of: "-", with: "")
            }
            let id = slug.suffix(32)
            guard id.count == 32, id.allSatisfy(\.isHexDigit) else { return nil }
            return id.lowercased()
        }
    }
}
