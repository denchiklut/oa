import Foundation

/// Chromium's own settings pages the app opens for a profile, as ADK's `ChromiumSettings`.
public enum ChromiumSettings: Sendable {
    case searchEngines, passwords, privacy, notifications, creditCards, extensionShortcuts

    public var url: URL {
        let path =
            switch self {
            case .searchEngines: "settings/searchEngines"
            case .passwords: "password-manager/passwords"
            case .privacy: "settings/privacy"
            case .notifications: "settings/content/notifications"
            case .creditCards: "settings/payments"
            case .extensionShortcuts: "extensions/shortcuts"
            }
        return URL(string: "chrome://\(path)")!
    }
}
