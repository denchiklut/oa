import DevKit
import Foundation
import Observation

/// App-wide cache and refresh coordinator for tab previews, badges, calendar subtitles, and expanded Live Calendar
/// items, mirroring Arc's `PreviewsDataClient` and `LiveCalendars`.
@MainActor
@Observable
final class PreviewsStore {
    struct Key: Hashable, Sendable {
        let profileID: UUID
        let type: PreviewType

        var storageKey: String {
            switch type {
            case .gmail(let inbox): "\(profileID.uuidString):gmail:\(inbox)"
            case .googleCalendar(let account): "\(profileID.uuidString):gcal:\(account)"
            case .notionCalendar(let tabID): "\(profileID.uuidString):notion:\(tabID.uuidString)"
            case .recentPages(let domain): "\(profileID.uuidString):recent:\(domain.rawValue)"
            }
        }
    }

    /// Arc's `AppTrayBadgingProvider` (`0x1002e492c`): Gmail dot shows only for unread mail newer than 2 hours.
    private static let gmailBadgeWindow: TimeInterval = 7200
    /// Arc's `LiveCalendars.maxMinutesVisibleAfterStart` / `AppTrayConstants.GoogleCalendar`: 10 minutes.
    private static let maxMinutesAfterStart = 10
    private static let dismissedEventsKey = "oaLiveCalendarDismissedEvents"

    private(set) var records: [Key: PreviewRecord] = [:]
    private(set) var dismissedCalendarEvents: [String: Set<String>]
    @ObservationIgnored private var inFlight: Set<Key> = []
    @ObservationIgnored private var periodicTask: Task<Void, Never>?

    init() {
        let stored = UserDefaults.standard.dictionary(forKey: Self.dismissedEventsKey) as? [String: [String]] ?? [:]
        dismissedCalendarEvents = stored.mapValues(Set.init)
    }

    func record(for type: PreviewType, profileID: UUID) -> PreviewRecord? {
        records[Key(profileID: profileID, type: type)]
    }

    func resolvedNotionAccount(for tabID: UUID, url: URL?, profileID: UUID, settings: PreviewSettings = .shared) -> Int?
    {
        settings.notionCalendarAccount(for: tabID, profileID: profileID)
            ?? PreviewType.explicitGoogleAccountNumber(in: url)
    }

    func connectNotionCalendar(
        tabID: UUID, url: URL?, accountNumber: Int?, profileID: UUID, using engine: any BrowserApplication
    ) {
        let settings = PreviewSettings.shared
        settings.setNotionCalendarAccount(accountNumber, for: tabID, profileID: profileID)
        let type = PreviewType.notionCalendar(tabID: tabID)
        let key = Key(profileID: profileID, type: type)
        if accountNumber == nil {
            inFlight.remove(key)
            records[key] = PreviewRecord(state: .disconnected, lastRefreshed: .now)
        } else {
            records[key] = PreviewRecord(state: .loading, lastRefreshed: nil)
            refresh(type, sourceURL: url, profileID: profileID, using: engine, force: true)
        }
    }

    func refresh(
        _ type: PreviewType, sourceURL: URL? = nil, profileID: UUID, using engine: any BrowserApplication,
        force: Bool = false
    ) {
        let key = Key(profileID: profileID, type: type)
        if case .notionCalendar(let tabID) = type,
            resolvedNotionAccount(for: tabID, url: sourceURL, profileID: profileID) == nil
        {
            records[key] = PreviewRecord(state: .disconnected, lastRefreshed: .now)
            return
        }
        guard !inFlight.contains(key) else { return }
        if !force, let existing = records[key], let last = existing.lastRefreshed,
            Date.now.timeIntervalSince(last) < type.staleInterval
        {
            return
        }
        inFlight.insert(key)
        if records[key] == nil || records[key]?.state == .disconnected {
            records[key] = PreviewRecord(state: .loading, lastRefreshed: nil)
        }
        let context = engine.browserContext(id: profileID)
        let notionAccount: Int? =
            if case .notionCalendar(let tabID) = type {
                resolvedNotionAccount(for: tabID, url: sourceURL, profileID: profileID)
            } else {
                nil
            }
        Task { [weak self] in
            let next: PreviewState
            switch type {
            case .recentPages(let domain):
                next = await RecentPagesFetcher.fetch(domain, in: context)
            case .gmail(let inbox):
                next = await GmailPreviewFetcher.fetch(inboxNumber: inbox, in: context)
            case .googleCalendar(let account):
                next = await LiveCalendarFetcher.fetch(accountNumber: account, isNotionCalendar: false, in: context)
            case .notionCalendar:
                if let account = notionAccount {
                    next = await LiveCalendarFetcher.fetch(
                        accountNumber: account, isNotionCalendar: true, in: context)
                } else {
                    next = .disconnected
                }
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

    /// Keeps Favorite Gmail badges, Calendar subtitles, and Live Calendar banners fresh in the background.
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
                guard let type = PreviewType.matching(url: tab.url, tabID: tab.id) else { continue }
                switch type {
                case .gmail where settings.gmailEnabled:
                    refresh(type, sourceURL: tab.url, profileID: profile.id, using: engine)
                case .googleCalendar where settings.calendarEnabled:
                    refresh(type, sourceURL: tab.url, profileID: profile.id, using: engine)
                case .notionCalendar where settings.notionCalendarEnabled:
                    refresh(type, sourceURL: tab.url, profileID: profile.id, using: engine)
                default:
                    break
                }
            }
        }
    }

    /// Arc's Favorite tile unread badge (Gmail red dot for unread mail < 2 hours old; WhatsApp red dot and Twitter
    /// gray dot from a leading `(N)` count in the live page title).
    func unreadBadge(
        for tab: SidebarTab, liveTitle: String?, profileID: UUID, settings: PreviewSettings, now: Date = .now
    ) -> FavoriteUnreadBadge? {
        guard let badge = FavoriteUnreadBadge.matching(url: tab.url),
            settings.isBadgingEnabled(forHost: badge.defaultsHost)
        else { return nil }
        switch badge {
        case .gmail:
            guard settings.gmailEnabled, let type = PreviewType.matching(url: tab.url, tabID: tab.id),
                case .loaded(.gmail(_, let emails)) = record(for: type, profileID: profileID)?.state
            else { return nil }
            let hasRecentUnread = emails.contains { email in
                guard let date = email.date else { return false }
                return now.timeIntervalSince(date) < Self.gmailBadgeWindow
            }
            return hasRecentUnread ? .gmail : nil
        case .whatsApp:
            return liveTitle.flatMap(Self.leadingTitleUnreadCount) ?? 0 >= 1 ? .whatsApp : nil
        case .twitter:
            return liveTitle.flatMap(Self.leadingTitleUnreadCount) ?? 0 >= 1 ? .twitter : nil
        }
    }

    /// Arc's compact Favorite tile subtitle (`0x101d1a510` & `0x3a6dfe0`): `1–59m` before start, `Now` within one
    /// minute before or after start, then `1–9m ago` while the event is still running.
    func calendarSubtitle(
        for tab: SidebarTab, profileID: UUID, settings: PreviewSettings, now: Date = .now
    ) -> (text: String, isImminent: Bool)? {
        guard let type = PreviewType.matching(url: tab.url, tabID: tab.id), type.isCalendar,
            settings.isCalendarEnabled(isNotionCalendar: type.isNotionCalendar),
            let host = PreviewType.calendarDefaultsHost(for: tab.url),
            settings.isSubtitleEnabled(forHost: host),
            case .loaded(.calendar(_, _, _, let events)) = record(for: type, profileID: profileID)?.state
        else { return nil }

        for event in events where !event.isAllDay && event.end > now {
            if let text = Self.compactCalendarSubtitle(for: event, now: now) {
                let minutesUntilStart = Int(event.start.timeIntervalSince(now) / 60)
                return (text, minutesUntilStart <= 10)
            }
        }
        return nil
    }

    /// Arc's `LiveCalendars` active meeting selection for the expanded Favorites inline item.
    func activeLiveCalendarEvent(
        for profileID: UUID, in state: SidebarState, settings: PreviewSettings, now: Date = .now
    ) -> LiveCalendarActiveEvent? {
        guard let profile = state.profile(profileID),
            let leadMinutes = settings.liveCalendarInterval(for: profileID).leadMinutes
        else { return nil }

        var best: LiveCalendarActiveEvent?
        for tab in state.tree.tabs(under: profile.favoritesRootID) {
            guard let type = PreviewType.matching(url: tab.url, tabID: tab.id), type.isCalendar,
                settings.isCalendarEnabled(isNotionCalendar: type.isNotionCalendar)
            else { continue }
            let key = Key(profileID: profileID, type: type)
            guard case .loaded(.calendar(_, let isNotion, _, let events)) = records[key]?.state else { continue }
            let dismissed = dismissedCalendarEvents[key.storageKey] ?? []
            for event in events where !event.isAllDay && event.joinLink != nil && event.end > now {
                guard !dismissed.contains(event.id) else { continue }
                let secondsUntilStart = event.start.timeIntervalSince(now)
                let withinLead = secondsUntilStart <= Double(leadMinutes * 60)
                let withinAfterStart = -secondsUntilStart < Double(Self.maxMinutesAfterStart * 60)
                guard withinLead && withinAfterStart else { continue }
                if best == nil || event.start < best!.event.start {
                    best = LiveCalendarActiveEvent(
                        key: key, tabID: tab.id, event: event, isNotionCalendar: isNotion)
                }
            }
        }
        return best
    }

    func dismissLiveCalendarEvent(_ eventID: String, for key: Key) {
        var set = dismissedCalendarEvents[key.storageKey] ?? []
        set.insert(eventID)
        dismissedCalendarEvents[key.storageKey] = set
        persistDismissedEvents()
    }

    /// Arc's `gCalendarSubtitleText(minutesUntilStart:durationInMinutes:)` (`0x101d1a510`).
    static func compactCalendarSubtitle(for event: CalendarEventItem, now: Date) -> String? {
        guard event.end > now else { return nil }
        let minutesUntilStart = Int(event.start.timeIntervalSince(now) / 60)
        if minutesUntilStart == 0 { return "Now" }
        if minutesUntilStart >= 1 && minutesUntilStart < 60 { return "\(minutesUntilStart)m" }
        if minutesUntilStart < 0 {
            let minutesAgo = -minutesUntilStart
            let durationMinutes = max(1, Int(event.end.timeIntervalSince(event.start) / 60))
            if minutesAgo <= 9 && minutesAgo < durationMinutes { return "\(minutesAgo)m ago" }
        }
        return nil
    }

    /// Arc's `LiveCalendarItemView` countdown copy (`0x101d19fc0`): `in Nm`, `Now`, `Nm ago`.
    static func liveCalendarCountdown(for event: CalendarEventItem, now: Date) -> String {
        let minutesUntilStart = Int(event.start.timeIntervalSince(now) / 60)
        if minutesUntilStart == 0 { return "Now" }
        if minutesUntilStart > 0 { return "in \(minutesUntilStart)m" }
        return "\(-minutesUntilStart)m ago"
    }

    /// Leading `(N)` unread counter used by WhatsApp Web and Twitter/X page titles.
    static func leadingTitleUnreadCount(_ title: String) -> Int? {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("("), let close = trimmed.firstIndex(of: ")") else { return nil }
        let inside = trimmed[trimmed.index(after: trimmed.startIndex)..<close]
        guard !inside.isEmpty, inside.allSatisfy(\.isNumber) else { return nil }
        return Int(inside)
    }

    private func persistDismissedEvents() {
        UserDefaults.standard.set(
            dismissedCalendarEvents.mapValues { Array($0).sorted() }, forKey: Self.dismissedEventsKey)
    }
}
