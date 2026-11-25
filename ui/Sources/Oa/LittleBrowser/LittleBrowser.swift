import AppKit
import Foundation

/// Arc's `LittleBrowser.State`, the part a Little window's model keeps. Arc saves it with the window for the
/// relaunch after an update; Oa has no such relaunch, so it lives with the window.
struct LittleBrowserState {
    /// Arc's `LittleBrowserEntryPoint`, the cases Oa has callers for.
    enum EntryPoint: Equatable {
        case mainMenu
        case globalHotkey
        case externalLink(URL)
        case internalLink(URL)
        case browserPopup(URL)

        /// As Arc's: what a later link is matched against, which a ⌘⌥-click's window never is.
        var reusableURL: URL? {
            switch self {
            case .externalLink(let url), .internalLink(let url): url
            case .mainMenu, .globalHotkey, .browserPopup: nil
            }
        }

        var url: URL? {
            switch self {
            case .externalLink(let url), .internalLink(let url), .browserPopup(let url): url
            case .mainMenu, .globalHotkey: nil
            }
        }

        /// As seen in Arc: shown for a link from another app and the File menu's item, not the hot key's.
        var showsTip: Bool {
            switch self {
            case .externalLink, .mainMenu: true
            case .globalHotkey, .internalLink, .browserPopup: false
            }
        }
    }

    var entryPoint: EntryPoint
    /// Arc's `modalState`: `initial` while the window is its command bar alone.
    var isPresented: Bool
    /// Arc's `moveToListDestinationInfo`: the Space "Open in" names.
    var destinationSpaceID: UUID?
    var showsMoveMenu = false
    var showsTip = false
}

/// Arc's defaults for Little Arc, under its keys.
enum LittleBrowserPreferences {
    static let globalHotkeyKey = "globalLittleBrowserHotkeyEnabled"
    static let optionCommandClickKey = "optionCommandClickLittleArcEntryPointEnabled"
    static let externalLinksKey = "openExternalLinksInLittleBrowserEnabled"
    static let autoArchiveThresholdKey = "autoArchiveLittleArcTimeThreshold"
    static let domainToProfileKey = "domainToProfilePreferences"
    static let tipCountKey = "littleBrowserNUXPresentationCount"
    static let bypassProfileDialogKey = "shouldBypassConfirmLittleBrowserProfileDialog"
    /// Arc's ID for New Little Arc Window, whose shortcut the global hot key follows.
    static let shortcutID = "showLittleArc"

    static func register() {
        UserDefaults.standard.register(
            defaults: [globalHotkeyKey: true, optionCommandClickKey: true, externalLinksKey: true])
    }

    static var opensOnOptionCommandClick: Bool { UserDefaults.standard.bool(forKey: optionCommandClickKey) }
    static var opensExternalLinks: Bool { UserDefaults.standard.bool(forKey: externalLinksKey) }

    static var autoArchiveThreshold: AutoArchiveLittleArcThreshold {
        UserDefaults.standard.string(forKey: autoArchiveThresholdKey).flatMap(AutoArchiveLittleArcThreshold.init)
            ?? .sixHours
    }

    /// As Arc's `URL.preferredProfile`: the profile a Little window of the host was last switched to.
    static func preferredProfile(for url: URL) -> UUID? {
        guard let host = url.host(),
            let stored = UserDefaults.standard.dictionary(forKey: domainToProfileKey)?[host] as? String
        else { return nil }
        return UUID(uuidString: stored)
    }

    static func setPreferredProfile(_ profileID: UUID, for url: URL) {
        guard let host = url.host() else { return }
        var stored = UserDefaults.standard.dictionary(forKey: domainToProfileKey) ?? [:]
        stored[host] = profileID.uuidString
        UserDefaults.standard.set(stored, forKey: domainToProfileKey)
    }
}

/// Arc's setting 71, the three its picker offers and the one it keeps for testing.
enum AutoArchiveLittleArcThreshold: String, CaseIterable, Identifiable {
    case twentySeconds, oneHour, sixHours, twelveHours

    static let offered: [Self] = [.oneHour, .sixHours, .twelveHours]

    var id: Self { self }

    var seconds: TimeInterval {
        switch self {
        case .twentySeconds: 20
        case .oneHour: 3600
        case .sixHours: 6 * 3600
        case .twelveHours: 12 * 3600
        }
    }

    var title: String {
        switch self {
        case .twentySeconds: "20 seconds"
        case .oneHour: "1 hour"
        case .sixHours: "6 hours"
        case .twelveHours: "12 hours"
        }
    }
}

/// Where Arc puts a Little window, as its Peek layout controller does.
enum LittleBrowserFrame {
    static let barSize = NSSize(width: 490, height: 329)
    static let defaultPageSize = NSSize(width: 1185, height: 832)
    static let minSize = NSSize(width: 300, height: 360)
    static let screenMargin: CGFloat = 20
    static let cascade: CGFloat = 30
    /// Arc's key, which its Peek windows share: the last page window's frame, written when one is moved or its
    /// resize ends.
    static let savedRectKey = "ModalWindowController_rect"

    static var savedSize: NSSize {
        guard let stored = UserDefaults.standard.string(forKey: savedRectKey) else { return defaultPageSize }
        let size = NSRectFromString(stored).size
        return size.width >= minSize.width && size.height >= minSize.height ? size : defaultPageSize
    }

    static func save(_ frame: NSRect) {
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: savedRectKey)
    }

    static func bar(on screen: NSScreen?) -> NSRect {
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? .zero
        return NSRect(
            x: visible.maxX - screenMargin - barSize.width, y: visible.maxY - screenMargin - barSize.height,
            width: barSize.width, height: barSize.height)
    }

    /// As seen in Arc: a bar grows into the saved size about its own centre.
    static func page(growingFrom bar: NSRect, on screen: NSScreen?) -> NSRect {
        centered(savedSize, on: NSPoint(x: bar.midX, y: bar.midY), screen: screen)
    }

    /// As seen in Arc: a link's window is down and right of the newest other Little window, at its size, else the
    /// saved size about the pointer.
    static func page(after newest: NSRect?, pointer: NSPoint, on screen: NSScreen?) -> NSRect {
        guard let newest else { return centered(savedSize, on: pointer, screen: screen) }
        return constrained(newest.offsetBy(dx: cascade, dy: -cascade), to: screen)
    }

    private static func centered(_ size: NSSize, on point: NSPoint, screen: NSScreen?) -> NSRect {
        constrained(
            NSRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height),
            to: screen)
    }

    private static func constrained(_ frame: NSRect, to screen: NSScreen?) -> NSRect {
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame.insetBy(dx: screenMargin, dy: screenMargin) else {
            return frame
        }
        var frame = frame
        frame.size.width = min(frame.width, visible.width)
        frame.size.height = min(frame.height, visible.height)
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        return frame
    }
}
