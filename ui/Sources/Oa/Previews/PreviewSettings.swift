import Foundation
import Observation

/// Arc's preview settings, stored under Arc's UserDefaults keys.
@MainActor
@Observable
final class PreviewSettings {
    static let shared = PreviewSettings()

    private static let folderKey = "folderPreviewEnabled"
    private static let calendarKey = "calendarPreviewEnabled"
    private static let gmailKey = "gmailPreviewEnabled"
    private static let recentPagesKey = "recentPagesPreviewEnabled"
    private static let badgingDisabledHostsKey = "topAppsBadgingDisabledHosts"
    private static let subtitleDisabledHostsKey = "topAppsSubtitleDisabledHosts"
    private static let liveCalendarHoverKey = "liveCalendarHoverPreviewEnabled"

    var folderEnabled: Bool {
        didSet { UserDefaults.standard.set(folderEnabled, forKey: Self.folderKey) }
    }
    var calendarEnabled: Bool {
        didSet { UserDefaults.standard.set(calendarEnabled, forKey: Self.calendarKey) }
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

    init() {
        let defaults = UserDefaults.standard
        folderEnabled = defaults.object(forKey: Self.folderKey) as? Bool ?? true
        calendarEnabled = defaults.object(forKey: Self.calendarKey) as? Bool ?? true
        gmailEnabled = defaults.object(forKey: Self.gmailKey) as? Bool ?? true
        recentPagesEnabled = defaults.object(forKey: Self.recentPagesKey) as? Bool ?? true
        liveCalendarHoverEnabled = defaults.object(forKey: Self.liveCalendarHoverKey) as? Bool ?? true
        badgingDisabledHosts = Set(defaults.stringArray(forKey: Self.badgingDisabledHostsKey) ?? [])
        subtitleDisabledHosts = Set(defaults.stringArray(forKey: Self.subtitleDisabledHostsKey) ?? [])
    }

    func isEnabled(for type: PreviewType) -> Bool {
        switch type {
        case .gmail: gmailEnabled
        case .googleCalendar: calendarEnabled && liveCalendarHoverEnabled
        case .recentPages: recentPagesEnabled
        }
    }

    func isBadgingEnabled(forHost host: String) -> Bool {
        !badgingDisabledHosts.contains(host.lowercased())
    }

    func toggleBadging(forHost host: String) {
        let normalized = host.lowercased()
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
}
