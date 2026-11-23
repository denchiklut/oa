import Foundation

/// Arc's "When opening Arc, restore windows from previous session". AppKit brings the windows back whatever it says;
/// the switch decides whether the last session's pages come with them.
enum RestoreWindowsPreference {
    /// Arc's key, on when absent, as Arc registers it.
    static let key = "arc_quitAlwaysKeepsWindows"
    private static let systemKey = "NSQuitAlwaysKeepsWindows"

    /// As Arc's launch: the first time, the key takes the system's "Close windows when quitting an application".
    /// AppKit is then told to keep the windows always, and the key carries the choice.
    static func registerAtLaunch() {
        let defaults = UserDefaults.standard
        let existed = defaults.object(forKey: key) != nil
        defaults.register(defaults: [key: true, systemKey: true])
        if !existed { defaults.set(defaults.bool(forKey: systemKey), forKey: key) }
        defaults.set(true, forKey: systemKey)
    }

    /// As Arc's engine flag, set at launch: never with `ApplePersistenceIgnoreState`. Arc's update relaunch also
    /// turns it on; Oa has no such relaunch.
    static var restoresLastSession: Bool {
        let defaults = UserDefaults.standard
        return !defaults.bool(forKey: "ApplePersistenceIgnoreState") && defaults.bool(forKey: key)
    }
}
