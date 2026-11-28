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

/// Arc's `BaseModels.LiveCalendarInterval` (`0x100c892a4`, `0x103742540`).
enum LiveCalendarInterval: String, CaseIterable, Codable, Hashable, Sendable {
    case never
    case onStart
    case twoMinutesBefore
    case fiveMinutesBefore
    case tenMinutesBefore

    var title: String {
        switch self {
        case .never: "Never"
        case .onStart: "On Start"
        case .twoMinutesBefore: "Two Minutes Before"
        case .fiveMinutesBefore: "Five Minutes Before"
        case .tenMinutesBefore: "Ten Minutes Before"
        }
    }

    var leadMinutes: Int? {
        switch self {
        case .never: nil
        case .onStart: 0
        case .twoMinutesBefore: 2
        case .fiveMinutesBefore: 5
        case .tenMinutesBefore: 10
        }
    }
}

/// Favorite unread badge sites supported in Oa. Arc's `TopApp` matches `mail.google.com`, `web.whatsapp.com`, and
/// `twitter.com`; matching `x.com` under `twitter` is Oa's own extension.
enum FavoriteUnreadBadge: Equatable, Sendable {
    case gmail
    case whatsApp
    case twitter

    var defaultsHost: String {
        switch self {
        case .gmail: "mail.google.com"
        case .whatsApp: "web.whatsapp.com"
        case .twitter: "twitter.com"
        }
    }

    static func matching(url: URL?) -> FavoriteUnreadBadge? {
        guard let host = url?.host()?.lowercased() else { return nil }
        if isSubdomain(host, of: "mail.google.com") { return .gmail }
        if isSubdomain(host, of: "web.whatsapp.com") { return .whatsApp }
        if isSubdomain(host, of: "twitter.com") || isSubdomain(host, of: "x.com") { return .twitter }
        return nil
    }

    private static func isSubdomain(_ host: String, of domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }
}

/// Supported tab preview types, matching Arc's `BaseModels.PreviewType`. Notion Calendar carries its originating
/// tab ID so its connected calendar account is resolved per `(profileID, tabID)` rather than assuming Google `/u/0`.
enum PreviewType: Hashable, Sendable {
    case gmail(inboxNumber: Int)
    case googleCalendar(accountNumber: Int)
    case notionCalendar(tabID: UUID)
    case recentPages(RecentPagesDomain)

    var isCalendar: Bool {
        switch self {
        case .googleCalendar, .notionCalendar: true
        case .gmail, .recentPages: false
        }
    }

    var isNotionCalendar: Bool {
        if case .notionCalendar = self { return true }
        return false
    }

    var headerTitle: String {
        switch self {
        case .gmail: "Unread"
        case .googleCalendar, .notionCalendar: "Upcoming"
        case .recentPages: "Recent"
        }
    }

    var disableActionTitle: String {
        switch self {
        case .gmail: "Disable Gmail Preview"
        case .googleCalendar: "Disable Calendar Preview"
        case .notionCalendar: "Disable Notion Calendar Preview"
        case .recentPages: "Disable Recent Pages Preview"
        }
    }

    var ctaURL: URL {
        switch self {
        case .gmail(let inbox):
            URL(string: "https://mail.google.com/mail/u/\(inbox)/#compose")!
        case .googleCalendar(let account):
            URL(string: "https://calendar.google.com/calendar/u/\(account)/r/eventedit")!
        case .notionCalendar:
            URL(string: "https://calendar.notion.so/event/create")!
        case .recentPages(let domain):
            domain.ctaURL
        }
    }

    var ctaTooltip: String {
        switch self {
        case .gmail: "New Email"
        case .googleCalendar, .notionCalendar: "New Event"
        case .recentPages(let domain): domain.ctaTooltip
        }
    }

    func signInURL(resolvedAccount: Int? = nil) -> URL? {
        switch self {
        case .gmail(let inbox):
            URL(string: "https://mail.google.com/mail/u/\(inbox)/")
        case .googleCalendar(let account):
            URL(string: "https://calendar.google.com/calendar/u/\(account)/r")
        case .notionCalendar:
            if let resolvedAccount {
                URL(string: "https://calendar.google.com/calendar/u/\(resolvedAccount)/r")
            } else {
                URL(string: "https://calendar.notion.so/")
            }
        case .recentPages:
            nil
        }
    }

    var staleInterval: TimeInterval {
        switch self {
        case .recentPages: 20
        case .gmail: 60
        case .googleCalendar, .notionCalendar: 300
        }
    }

    static func matching(url: URL?, tabID: UUID? = nil) -> PreviewType? {
        guard let url, let host = url.host()?.lowercased() else { return nil }
        if host == "mail.google.com" || host.hasSuffix(".mail.google.com") {
            return .gmail(inboxNumber: explicitGoogleAccountNumber(in: url) ?? 0)
        }
        if host == "calendar.google.com" || host.hasSuffix(".calendar.google.com") {
            return .googleCalendar(accountNumber: explicitGoogleAccountNumber(in: url) ?? 0)
        }
        if host == "calendar.notion.so" || host.hasSuffix(".calendar.notion.so")
            || host == "calendar.notion.com" || host.hasSuffix(".calendar.notion.com")
        {
            guard let tabID else { return nil }
            return .notionCalendar(tabID: tabID)
        }
        for domain in RecentPagesDomain.allCases where domain.matches(url) {
            return .recentPages(domain)
        }
        return nil
    }

    static func isCalendarHost(_ url: URL?) -> Bool {
        guard let host = url?.host()?.lowercased() else { return false }
        return host == "calendar.google.com" || host.hasSuffix(".calendar.google.com")
            || host == "calendar.notion.so" || host.hasSuffix(".calendar.notion.so")
            || host == "calendar.notion.com" || host.hasSuffix(".calendar.notion.com")
    }

    static func calendarDefaultsHost(for url: URL?) -> String? {
        guard let host = url?.host()?.lowercased() else { return nil }
        if host == "calendar.google.com" || host.hasSuffix(".calendar.google.com") { return "calendar.google.com" }
        if host == "calendar.notion.so" || host.hasSuffix(".calendar.notion.so")
            || host == "calendar.notion.com" || host.hasSuffix(".calendar.notion.com")
        {
            return "calendar.notion.so"
        }
        return nil
    }

    /// Parses an explicit Google account index from `/u/<N>` or `?authuser=<N>`.
    static func explicitGoogleAccountNumber(in url: URL?) -> Int? {
        guard let url else { return nil }
        let parts = url.path.split(separator: "/")
        if let uIndex = parts.firstIndex(of: "u"), uIndex + 1 < parts.count,
            let number = Int(parts[uIndex + 1]), number >= 0
        {
            return number
        }
        if let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
            let value = queryItems.first(where: { $0.name.lowercased() == "authuser" })?.value,
            let number = Int(value), number >= 0
        {
            return number
        }
        return nil
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

struct LiveCalendarActiveEvent: Equatable, Sendable {
    let key: PreviewsStore.Key
    let tabID: UUID
    let event: CalendarEventItem
    let isNotionCalendar: Bool
}

enum SidebarPreviewContent: Equatable, Sendable {
    case recentPages(RecentPagesDomain, [RecentPageItem])
    case gmail(inboxNumber: Int, [UnreadEmailItem])
    case calendar(accountNumber: Int, isNotionCalendar: Bool, accountEmail: String?, [CalendarEventItem])
}

enum PreviewState: Equatable, Sendable {
    case loading
    case loaded(SidebarPreviewContent)
    case signedOut
    case disconnected
    case failed
}

struct PreviewRecord: Equatable, Sendable {
    var state: PreviewState
    var lastRefreshed: Date?
}
