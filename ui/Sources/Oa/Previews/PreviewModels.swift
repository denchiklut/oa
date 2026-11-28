import Foundation

/// Arc's `BaseModels.RecentPagesData.Domain`.
enum RecentPagesDomain: String, Hashable, Sendable, CaseIterable {
    case notion
    case figma
    case linear
    case confluence

    var displayName: String {
        switch self {
        case .notion: "Notion"
        case .figma: "Figma"
        case .linear: "Linear"
        case .confluence: "Confluence"
        }
    }

    var searchQuery: String {
        switch self {
        case .notion: "notion"
        case .figma: "figma.com"
        case .linear: "linear.app"
        case .confluence: "atlassian.net"
        }
    }

    var ctaURL: URL {
        switch self {
        case .notion: URL(string: "https://notion.so/new")!
        case .figma: URL(string: "https://figma.com/new")!
        case .linear: URL(string: "https://linear.app/new")!
        case .confluence: URL(string: "https://confluence.new")!
        }
    }

    var ctaTooltip: String {
        switch self {
        case .notion: "New Notion Page"
        case .figma: "New Figma File"
        case .linear: "New Issue"
        case .confluence: "New Confluence Page"
        }
    }

    var emptyState: String {
        switch self {
        case .notion: "Recent Notion docs appear here."
        case .figma: "Recent Figma files appear here."
        case .linear: "Recent Linear projects and issues appear here."
        case .confluence: "Recent Confluence pages appear here."
        }
    }

    func matches(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased(), url.scheme == "https" || url.scheme == "http" else { return false }
        switch self {
        case .notion:
            return host == "notion.so" || host.hasSuffix(".notion.so") || host == "notion.site"
                || host.hasSuffix(".notion.site")
        case .figma:
            return host == "figma.com" || host.hasSuffix(".figma.com")
        case .linear:
            return host == "linear.app" || host.hasSuffix(".linear.app")
        case .confluence:
            return (host == "atlassian.net" || host.hasSuffix(".atlassian.net"))
                && (url.path == "/wiki" || url.path.hasPrefix("/wiki/"))
        }
    }
}

/// Supported tab preview types, matching Arc's `BaseModels.PreviewType`.
enum PreviewType: Hashable, Sendable {
    case gmail(inboxNumber: Int)
    case googleCalendar(accountNumber: Int, isNotionCalendar: Bool)
    case recentPages(RecentPagesDomain)

    var headerTitle: String {
        switch self {
        case .gmail: "Unread"
        case .googleCalendar: "Upcoming"
        case .recentPages: "Recent"
        }
    }

    var ctaURL: URL {
        switch self {
        case .gmail(let inbox):
            URL(string: "https://mail.google.com/mail/u/\(inbox)/#compose")!
        case .googleCalendar(let account, let isNotion):
            isNotion
                ? URL(string: "https://calendar.notion.so/event/create")!
                : URL(string: "https://calendar.google.com/calendar/u/\(account)/r/eventedit")!
        case .recentPages(let domain):
            domain.ctaURL
        }
    }

    var ctaTooltip: String {
        switch self {
        case .gmail: "New Email"
        case .googleCalendar: "New Event"
        case .recentPages(let domain): domain.ctaTooltip
        }
    }

    var signInURL: URL? {
        switch self {
        case .gmail(let inbox):
            URL(string: "https://mail.google.com/mail/u/\(inbox)/")
        case .googleCalendar(let account, let isNotion):
            isNotion
                ? URL(string: "https://calendar.notion.so/")
                : URL(string: "https://calendar.google.com/calendar/u/\(account)/r")
        case .recentPages:
            nil
        }
    }

    var staleInterval: TimeInterval {
        switch self {
        case .recentPages: 20
        case .gmail: 60
        case .googleCalendar: 300
        }
    }

    static func matching(url: URL?) -> PreviewType? {
        guard let url, let host = url.host()?.lowercased() else { return nil }
        if host == "mail.google.com" {
            return .gmail(inboxNumber: googleAccountNumber(in: url.path))
        }
        if host == "calendar.google.com" {
            return .googleCalendar(accountNumber: googleAccountNumber(in: url.path), isNotionCalendar: false)
        }
        if host == "calendar.notion.so" || host == "calendar.notion.com" {
            return .googleCalendar(accountNumber: 0, isNotionCalendar: true)
        }
        for domain in RecentPagesDomain.allCases where domain.matches(url) {
            return .recentPages(domain)
        }
        return nil
    }

    private static func googleAccountNumber(in path: String) -> Int {
        let parts = path.split(separator: "/")
        if let uIndex = parts.firstIndex(of: "u"), uIndex + 1 < parts.count,
            let number = Int(parts[uIndex + 1]), number >= 0
        {
            return number
        }
        return 0
    }
}

struct RecentPageItem: Identifiable, Hashable, Sendable {
    var id: URL { url }
    let title: String
    let url: URL
    let lastVisited: Date?
}

struct UnreadEmailItem: Identifiable, Hashable, Sendable {
    var id: URL { url }
    let title: String
    let summary: String
    let sender: String
    let authorEmail: String?
    let date: Date?
    let url: URL
}

struct CalendarEventItem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let permalink: URL?
    let joinLink: URL?
    let location: String?
}

enum SidebarPreviewContent: Equatable, Sendable {
    case recentPages(RecentPagesDomain, [RecentPageItem])
    case gmail(inboxNumber: Int, [UnreadEmailItem])
    case calendar(accountNumber: Int, isNotionCalendar: Bool, [CalendarEventItem])
}

enum PreviewState: Equatable, Sendable {
    case loading
    case loaded(SidebarPreviewContent)
    case signedOut
    case failed
}

struct PreviewRecord: Equatable, Sendable {
    var state: PreviewState
    var lastRefreshed: Date?
}
