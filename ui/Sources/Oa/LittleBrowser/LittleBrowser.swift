import AppKit
import Foundation

/// Arc's `LittleBrowser.State`. What Arc's `PersistedLittleBrowserState` codes is saved with the window, under
/// Arc's keys; the rest is rebuilt.
struct LittleBrowserState: Codable {
    /// Arc's `ModalContent.PresentationState`: `initial` while the window is its command bar alone.
    enum ModalState: Codable { case initial, presented }

    var session: LittleBrowserSession
    /// Oa's profile ID, where Arc writes its own profile value.
    var profile: UUID
    /// As Arc's: whether more than one profile was in use when the window was made.
    var shouldShowProfileIndicators: Bool
    var modalState: ModalState
    var downloads = LittleBrowserDownloads()
    /// Arc's `moveToListDestinationInfo`: the Space "Open in" names.
    var destinationSpaceID: UUID?
    var showsMoveMenu = false
    var showsTip = false

    private enum CodingKeys: String, CodingKey {
        case session, profile, shouldShowProfileIndicators, modalState, downloads
    }

    var isPresented: Bool { modalState == .presented }
}

/// Arc's `LittleBrowserSession`, replaced when a link reuses the window.
struct LittleBrowserSession: Codable {
    var id = UUID()
    var entryPoint: LittleBrowserEntryPoint
    var preferredFrame: WindowFrame
    var startTime = Date.now

    /// As Arc's `createLittleBrowserSession`: a link's window is anchored on the pointer, the others at the top
    /// right of the pointer's screen.
    init(entryPoint: LittleBrowserEntryPoint) {
        self.entryPoint = entryPoint
        let pointer = NSEvent.mouseLocation
        switch entryPoint {
        case .externalLink, .internalLink, .browserPopup: preferredFrame = WindowFrame(anchor: .center(pointer))
        case .mainMenu, .globalHotkey:
            let visible =
                (NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main)?.visibleFrame ?? .zero
            preferredFrame = WindowFrame(
                size: LittleBrowserFrame.preferredBarSize,
                anchor: .topRight(
                    NSPoint(
                        x: visible.maxX - LittleBrowserFrame.preferredMargin,
                        y: visible.maxY - LittleBrowserFrame.preferredMargin)))
        }
    }

    /// As Arc's: the screen that holds the anchor.
    var screen: NSScreen? {
        switch preferredFrame.anchor {
        case .center(let point), .topRight(let point): LittleBrowserFrame.screen(at: point)
        }
    }
}

/// Arc's `WindowFrame`, the anchors Oa has callers for.
struct WindowFrame: Codable {
    enum Anchor: Codable { case center(NSPoint), topRight(NSPoint) }

    var size: NSSize?
    var anchor: Anchor
}

/// Arc's `LittleBrowserEntryPoint`, the cases Oa has callers for.
enum LittleBrowserEntryPoint: Equatable, Codable {
    case mainMenu
    case globalHotkey
    case externalLink(URL)
    case internalLink(URL)
    case browserPopup

    private enum Key: String, CodingKey { case mainMenu, globalHotkey, externalLink, internalLink, browserPopup }

    /// As Arc's: what a later link is matched against, which a ⌘⌥-click's window never is.
    var url: URL? {
        switch self {
        case .externalLink(let url), .internalLink(let url): url
        case .mainMenu, .globalHotkey, .browserPopup: nil
        }
    }

    /// As seen in Arc: shown for a link from another app and the File menu's item, not the hot key's.
    var showsTip: Bool {
        switch self {
        case .externalLink, .mainMenu: true
        case .globalHotkey, .internalLink, .browserPopup: false
        }
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Key.self)
        switch values.allKeys.first {
        case .mainMenu: self = .mainMenu
        case .globalHotkey: self = .globalHotkey
        case .externalLink: self = .externalLink(try values.decode(URL.self, forKey: .externalLink))
        case .internalLink: self = .internalLink(try values.decode(URL.self, forKey: .internalLink))
        case .browserPopup: self = .browserPopup
        case nil:
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "no entry point"))
        }
    }

    /// As Arc's coding: the hot key is written as a link with no address, which doesn't read back, so its window's
    /// style reads as a standard one.
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: Key.self)
        switch self {
        case .mainMenu: try values.encode(true, forKey: .mainMenu)
        case .globalHotkey: try values.encode(true, forKey: .externalLink)
        case .externalLink(let url): try values.encode(url, forKey: .externalLink)
        case .internalLink(let url): try values.encode(url, forKey: .internalLink)
        case .browserPopup: try values.encode(true, forKey: .browserPopup)
        }
    }
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
    /// Arc's session keeps these for its bar, though the bar is laid out at `barSize` inside `screenMargin`.
    static let preferredBarSize = NSSize(width: 500, height: 300)
    static let preferredMargin: CGFloat = 16
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

    /// As Arc's first frame, from the session's anchor: a bar under its top right corner; a link's window down and
    /// right of the newest other Little window, at its size, else the saved size about the anchor.
    static func first(for session: LittleBrowserSession, after newest: NSWindow?) -> NSRect {
        switch session.preferredFrame.anchor {
        case .topRight(let corner):
            return constrained(
                NSRect(
                    x: corner.x - barSize.width, y: corner.y - barSize.height, width: barSize.width,
                    height: barSize.height),
                to: screen(at: corner))
        case .center(let point):
            guard let newest else { return centered(savedSize, on: point, screen: screen(at: point)) }
            return constrained(newest.frame.offsetBy(dx: cascade, dy: -cascade), to: newest.screen)
        }
    }

    /// As seen in Arc: a bar grows into the saved size about its own centre.
    static func page(growingFrom bar: NSRect, on screen: NSScreen?) -> NSRect {
        centered(savedSize, on: NSPoint(x: bar.midX, y: bar.midY), screen: screen)
    }

    static func screen(at point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
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
