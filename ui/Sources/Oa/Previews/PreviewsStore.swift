import DevKit
import Foundation
import Observation

/// App-wide cache and refresh coordinator for tab previews, badges, and calendar subtitles, mirroring Arc's
/// `PreviewsDataClient` and `LiveCalendars`.
@MainActor
@Observable
final class PreviewsStore {
    struct Key: Hashable {
        let profileID: UUID
        let type: PreviewType
    }

    private(set) var records: [Key: PreviewRecord] = [:]
    @ObservationIgnored private var inFlight: Set<Key> = []
    @ObservationIgnored private var periodicTask: Task<Void, Never>?

    func record(for type: PreviewType, profileID: UUID) -> PreviewRecord? {
        records[Key(profileID: profileID, type: type)]
    }

    func refresh(
        _ type: PreviewType, profileID: UUID, using engine: any BrowserApplication, force: Bool = false
    ) {
        let key = Key(profileID: profileID, type: type)
        guard !inFlight.contains(key) else { return }
        if !force, let existing = records[key], let last = existing.lastRefreshed,
            Date.now.timeIntervalSince(last) < type.staleInterval
        {
            return
        }
        inFlight.insert(key)
        if records[key] == nil {
            records[key] = PreviewRecord(state: .loading, lastRefreshed: nil)
        }
        let context = engine.browserContext(id: profileID)
        Task { [weak self] in
            let next: PreviewState
            switch type {
            case .recentPages(let domain):
                next = await RecentPagesFetcher.fetch(domain, in: context)
            case .gmail(let inbox):
                next = await GmailPreviewFetcher.fetch(inboxNumber: inbox, in: context)
            case .googleCalendar(let account, let isNotion):
                next = await LiveCalendarFetcher.fetch(accountNumber: account, isNotionCalendar: isNotion, in: context)
            }
            guard let self else { return }
            inFlight.remove(key)
            // Keep previously loaded items when a transient refresh fails, as Arc does.
            if case .failed = next, case .loaded = records[key]?.state {
                records[key]?.lastRefreshed = .now
            } else {
                records[key] = PreviewRecord(state: next, lastRefreshed: .now)
            }
        }
    }

    /// Keeps Favorite Gmail badges and Calendar subtitles fresh in the background.
    func startPeriodicRefresh(in store: SidebarStore, using engine: any BrowserApplication) {
        guard periodicTask == nil else { return }
        periodicTask = Task { [weak self, weak store] in
            try? await Task.sleep(for: .seconds(2))
            while !Task.isCancelled {
                guard let self, let store, !store.quitting else { break }
                refreshFavoriteBackgroundPreviews(in: store, using: engine)
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func refreshFavoriteBackgroundPreviews(in store: SidebarStore, using engine: any BrowserApplication) {
        let settings = PreviewSettings.shared
        for profile in store.state.profiles {
            for tab in store.state.tree.tabs(under: profile.favoritesRootID) {
                guard let type = PreviewType.matching(url: tab.url) else { continue }
                switch type {
                case .gmail where settings.gmailEnabled:
                    refresh(type, profileID: profile.id, using: engine)
                case .googleCalendar where settings.calendarEnabled:
                    refresh(type, profileID: profile.id, using: engine)
                default:
                    break
                }
            }
        }
    }

    /// Arc's Favorite tile unread badge (Gmail or WhatsApp).
    func showsUnreadBadge(
        for tab: SidebarTab, liveTitle: String?, profileID: UUID, settings: PreviewSettings
    ) -> Bool {
        guard let url = tab.url, let host = url.host()?.lowercased(),
            settings.isBadgingEnabled(forHost: host)
        else { return false }
        if host == "mail.google.com" {
            guard settings.gmailEnabled, let type = PreviewType.matching(url: url) else { return false }
            if case .loaded(.gmail(_, let emails)) = record(for: type, profileID: profileID)?.state {
                return !emails.isEmpty
            }
            if let liveTitle, Self.titleIndicatesUnread(liveTitle) { return true }
            return false
        }
        if host == "web.whatsapp.com", let liveTitle {
            return Self.titleIndicatesUnread(liveTitle)
        }
        return false
    }

    /// Arc's compact Favorite tile subtitle for Google / Notion Calendar (e.g. `Now`, `12m`).
    func calendarSubtitle(
        for tab: SidebarTab, profileID: UUID, settings: PreviewSettings, now: Date = .now
    ) -> String? {
        guard settings.calendarEnabled, let url = tab.url, let host = url.host()?.lowercased(),
            settings.isSubtitleEnabled(forHost: host),
            let type = PreviewType.matching(url: url),
            case .googleCalendar = type,
            case .loaded(.calendar(_, _, let events)) = record(for: type, profileID: profileID)?.state
        else { return nil }

        for event in events where !event.isAllDay {
            let untilStart = event.start.timeIntervalSince(now)
            if untilStart <= 0 && event.end > now {
                if -untilStart <= 10 * 60 { return "Now" }
                continue
            }
            if untilStart > 0 && untilStart <= 60 * 60 {
                let minutes = max(1, Int(ceil(untilStart / 60)))
                return "\(minutes)m"
            }
        }
        return nil
    }

    private static func titleIndicatesUnread(_ title: String) -> Bool {
        guard let open = title.firstIndex(of: "("), let close = title[open...].firstIndex(of: ")") else { return false }
        let inside = title[title.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
        return (Int(inside) ?? 0) > 0
    }
}
