import AppKit

/// Arc's app-wide appearance: its `appearance` default holds Aqua or DarkAqua, and Automatic removes it to follow
/// macOS. `NSApp.appearance` carries it to the windows, menus and pages.
@MainActor
enum AppAppearance {
    static let key = "appearance"

    static func restore() {
        let name = UserDefaults.standard.string(forKey: key).map { NSAppearance.Name($0) }
        NSApplication.shared.appearance = name.flatMap(NSAppearance.init(named:))
    }

    /// As Arc's `onSetAppAppearance`.
    static func set(_ name: NSAppearance.Name?) {
        NSApplication.shared.appearance = name.flatMap(NSAppearance.init(named:))
        if let name {
            UserDefaults.standard.set(name.rawValue, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// As Arc's menu, from `NSApp.appearance` rather than the default.
    static var current: NSAppearance.Name? { NSApplication.shared.appearance?.name }
}
