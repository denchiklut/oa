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

struct RecentPage {
    let url: URL
    let title: String
    var issueID: String?
    var visitTime: Date?

    var subtitle: String? {
        guard let visitTime else { return issueID }
        let age = abs(visitTime.timeIntervalSinceNow) < 60 ? "Just now" : DownloadText.age(visitTime)
        return [issueID, age].compactMap { $0 }.joined(separator: " • ")
    }
}

enum RecentPagesSite: String {
    case linear, notion, figma

    init?(url: URL?) {
        guard let url, ["http", "https"].contains(url.scheme?.lowercased()), let host = url.host()?.lowercased()
        else { return nil }
        switch host {
        case let host where host == "linear.app" || host.hasSuffix(".linear.app"): self = .linear
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

    func documents(in history: [HistoryEntry]) -> [RecentPage] {
        let now = Date.now
        let cutoff = now.addingTimeInterval(-30 * 86_400)
        var seen = Set<String>()
        var pages: [RecentPage] = []
        for entry in history where Self(url: entry.url) == self {
            let path = entry.url.path().split(separator: "/")
            let id: String
            var title = entry.title
            var issueID: String?
            switch self {
            case .linear:
                guard title != "Inbox", title != "Linear", let visit = entry.visitTime,
                    (cutoff...now).contains(visit)
                else { continue }
                if let index = path.dropFirst().firstIndex(of: "issue"), index + 1 < path.count {
                    issueID = path[index + 1].uppercased()
                    id = path.prefix(index + 2).joined(separator: "/").lowercased()
                } else {
                    id = entry.url.absoluteString
                }
                if let issueID, title.hasPrefix(issueID) { title.removeFirst(issueID.count) }
                title = title.trimmingCharacters(in: .whitespaces)
            case .figma:
                guard path.count >= 2, ["file", "design", "board", "proto", "slides", "deck", "make"].contains(path[0])
                else { continue }
                id = String(path[1])
            case .notion:
                guard let slug = path.last else { continue }
                let pageID =
                    UUID(uuidString: String(slug))?.uuidString.replacingOccurrences(of: "-", with: "")
                    ?? String(slug.suffix(32))
                guard pageID.count == 32, pageID.allSatisfy(\.isHexDigit) else { continue }
                id = pageID.lowercased()
            }
            if self != .linear {
                title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                for suffix in [" – " + name, " - " + name, " | " + name] where title.hasSuffix(suffix) {
                    title.removeLast(suffix.count)
                }
            }
            guard seen.insert(id).inserted else { continue }
            pages.append(
                RecentPage(
                    url: entry.url, title: title.isEmpty ? entry.url.lastPathComponent : title,
                    issueID: issueID, visitTime: self == .linear ? entry.visitTime : nil))
            if pages.count == 5 { break }
        }
        return pages
    }

}
