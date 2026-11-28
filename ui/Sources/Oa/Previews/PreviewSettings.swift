import Foundation
import Observation

/// Arc's preview settings, stored under Arc's UserDefaults keys.
@MainActor
@Observable
final class PreviewSettings {
    static let shared = PreviewSettings()

    private static let folderKey = "folderPreviewEnabled"
    private static let calendarKey = "calendarPreviewEnabled"
    private static let notionCalendarKey = "cronPreviewEnabled"
    private static let gmailKey = "gmailPreviewEnabled"
    private static let recentPagesKey = "recentPagesPreviewEnabled"
    private static let badgingDisabledHostsKey = "topAppsBadgingDisabledHosts"
    private static let subtitleDisabledHostsKey = "topAppsSubtitleDisabledHosts"
    private static let liveCalendarHoverKey = "liveCalendarHoverPreviewEnabled"
    private static let liveCalendarNotificationsKey = "liveCalendarNotificationPreferences"
    /// Oa's own: per-(profile, tab) Google Calendar account number bound to a Notion Calendar tab.
    private static let notionCalendarAccountsKey = "oaNotionCalendarAccounts"

    var folderEnabled: Bool {
        didSet { UserDefaults.standard.set(folderEnabled, forKey: Self.folderKey) }
    }
    var calendarEnabled: Bool {
        didSet { UserDefaults.standard.set(calendarEnabled, forKey: Self.calendarKey) }
    }
    var notionCalendarEnabled: Bool {
        didSet { UserDefaults.standard.set(notionCalendarEnabled, forKey: Self.notionCalendarKey) }
    }
    var gmailEnabled: Bool {
        didSet { UserDefaults.standard.set(gmailEnabled, forKey: Self.gmailKey) }
    }
    var recentPagesEnabled: Bool {
        didSet { UserDefaults.standard.set(recentPagesEnabled, forKey: Self.recentPagesKey) }
    }
    var liveCalendarHoverEnabled: Bool {
        didSet { UserDefaults.standard.set(liveCalendarHoverEnabled, forKey: Self.liveCalendarHoverKey) }
    }
    var badgingDisabledHosts: Set<String> {
        didSet { UserDefaults.standard.set(Array(badgingDisabledHosts).sorted(), forKey: Self.badgingDisabledHostsKey) }
    }
    var subtitleDisabledHosts: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(subtitleDisabledHosts).sorted(), forKey: Self.subtitleDisabledHostsKey)
        }
    }
    var liveCalendarNotificationIntervals: [String: String] {
        didSet {
            UserDefaults.standard.set(liveCalendarNotificationIntervals, forKey: Self.liveCalendarNotificationsKey)
        }
    }
    var notionCalendarAccounts: [String: Int] {
        didSet { UserDefaults.standard.set(notionCalendarAccounts, forKey: Self.notionCalendarAccountsKey) }
    }

    init() {
        let defaults = UserDefaults.standard
        folderEnabled = defaults.object(forKey: Self.folderKey) as? Bool ?? true
        calendarEnabled = defaults.object(forKey: Self.calendarKey) as? Bool ?? true
        notionCalendarEnabled = defaults.object(forKey: Self.notionCalendarKey) as? Bool ?? true
        gmailEnabled = defaults.object(forKey: Self.gmailKey) as? Bool ?? true
        recentPagesEnabled = defaults.object(forKey: Self.recentPagesKey) as? Bool ?? true
        liveCalendarHoverEnabled = defaults.object(forKey: Self.liveCalendarHoverKey) as? Bool ?? true
        badgingDisabledHosts = Set(defaults.stringArray(forKey: Self.badgingDisabledHostsKey) ?? [])
        subtitleDisabledHosts = Set(defaults.stringArray(forKey: Self.subtitleDisabledHostsKey) ?? [])
        liveCalendarNotificationIntervals =
            defaults.dictionary(forKey: Self.liveCalendarNotificationsKey) as? [String: String] ?? [:]
        notionCalendarAccounts = defaults.dictionary(forKey: Self.notionCalendarAccountsKey) as? [String: Int] ?? [:]
    }

    func isCalendarEnabled(isNotionCalendar: Bool) -> Bool {
        isNotionCalendar ? notionCalendarEnabled : calendarEnabled
    }

    func isEnabled(for type: PreviewType) -> Bool {
        switch type {
        case .gmail: gmailEnabled
        case .googleCalendar: calendarEnabled && liveCalendarHoverEnabled
        case .notionCalendar: notionCalendarEnabled && liveCalendarHoverEnabled
        case .recentPages: recentPagesEnabled
        }
    }

    func disable(for type: PreviewType) {
        switch type {
        case .gmail: gmailEnabled = false
        case .googleCalendar: calendarEnabled = false
        case .notionCalendar: notionCalendarEnabled = false
        case .recentPages: recentPagesEnabled = false
        }
    }

    func isBadgingEnabled(forHost host: String) -> Bool {
        !badgingDisabledHosts.contains(Self.normalizedBadgeHost(host))
    }

    func toggleBadging(forHost host: String) {
        let normalized = Self.normalizedBadgeHost(host)
        if badgingDisabledHosts.contains(normalized) {
            badgingDisabledHosts.remove(normalized)
        } else {
            badgingDisabledHosts.insert(normalized)
        }
    }

    func isSubtitleEnabled(forHost host: String) -> Bool {
        !subtitleDisabledHosts.contains(host.lowercased())
    }

    func toggleSubtitle(forHost host: String) {
        let normalized = host.lowercased()
        if subtitleDisabledHosts.contains(normalized) {
            subtitleDisabledHosts.remove(normalized)
        } else {
            subtitleDisabledHosts.insert(normalized)
        }
    }

    func liveCalendarInterval(for profileID: UUID) -> LiveCalendarInterval {
        liveCalendarNotificationIntervals[profileID.uuidString].flatMap(LiveCalendarInterval.init(rawValue:))
            ?? .fiveMinutesBefore
    }

    func setLiveCalendarInterval(_ interval: LiveCalendarInterval, for profileID: UUID) {
        liveCalendarNotificationIntervals[profileID.uuidString] = interval.rawValue
    }

    func notionCalendarAccount(for tabID: UUID, profileID: UUID) -> Int? {
        notionCalendarAccounts[Self.notionAccountKey(tabID: tabID, profileID: profileID)]
    }

    func setNotionCalendarAccount(_ accountNumber: Int?, for tabID: UUID, profileID: UUID) {
        let key = Self.notionAccountKey(tabID: tabID, profileID: profileID)
        if let accountNumber {
            notionCalendarAccounts[key] = max(0, accountNumber)
        } else {
            notionCalendarAccounts.removeValue(forKey: key)
        }
    }

    private static func notionAccountKey(tabID: UUID, profileID: UUID) -> String {
        "\(profileID.uuidString):\(tabID.uuidString)"
    }

    private static func normalizedBadgeHost(_ host: String) -> String {
        let lowered = host.lowercased()
        if lowered == "x.com" || lowered.hasSuffix(".x.com") { return "twitter.com" }
        return lowered
    }
}
