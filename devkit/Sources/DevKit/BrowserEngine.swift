import AppKit
import Foundation
import Observation

/// The engine the app programs against. Every call happens on the main thread.
@MainActor
public protocol BrowserApplication: AnyObject {
    /// Runs the app until it quits and returns the exit code. `ready` runs once, after the engine has started and
    /// before the event loop; the app sets its delegate and opens its windows there.
    func run(ready: @escaping @MainActor () -> Void) -> Int32
    /// Finishes quitting after the app answered `applicationShouldTerminate` with `.terminateLater`.
    func terminate()
    func browserContext(id: UUID) -> any BrowserContext
    /// Binds the app's window to the pages made for its `id`, once. Call it when the window opens.
    func attachWindow(_ window: NSWindow, id: UUID)
    /// Drops the window's remaining pages. Call it when the window closes.
    func closeWindow(id: UUID)
    /// Runs each of the window's `beforeunload` handlers in the engine's tab order, as quitting does, and stops at the
    /// first that keeps its page. Every page stays. True to leave.
    func askToLeave(windowID: UUID) async -> Bool
}

/// A profile's engine side: separate cookies, storage and history.
@MainActor
public protocol BrowserContext: AnyObject {
    var id: UUID { get }
    /// A page with an `id` of its own in the app's window `windowID`, in the background; nil if the engine can't.
    /// A closed page's `sessionID` brings its history back where it can (`restored`); else the app issues the `load`.
    func makePage(windowID: UUID, restoring sessionID: PageSessionID?) async -> (page: any Page, restored: Bool)?
    /// The settings of `url`'s site that differ from the engine's defaults, in page info's order, as ArcCore's
    /// `getChangedContentSettingsForOrigin:`. Nil until the profile has loaded.
    func changedSiteSettings(for url: URL) -> [SiteSetting]?
    /// For the site's whole origin, without reloading its pages, as Chrome's site settings page sets it.
    func setSiteSetting(_ type: SiteSettingType, to value: SiteSettingValue, for url: URL)
    /// As ADK's download manager for the context: one per profile, alive as long as it.
    var downloads: any Downloads { get }
}

/// A profile's downloads, running and remembered by the engine. Observable: the engine's events change `items`,
/// nothing polls. Opening, revealing, copying and trashing a file are the app's, as in Arc.
@MainActor
public protocol Downloads: AnyObject, Observable {
    /// Oldest first; empty until the engine has read the profile's history.
    var items: [Download] { get }
    func pause(_ id: Download.ID)
    func resume(_ id: Download.ID)
    /// The partial file goes.
    func cancel(_ id: Download.ID)
    /// Forgets it, in the engine's history too, cancelling it first if it runs. A finished file stays.
    func remove(_ id: Download.ID)
}

public struct Download: Identifiable, Sendable, Equatable {
    /// As ADK's `DownloadFeatures.Status`: not started until the engine has chosen the file, and an interrupted
    /// download reads as failed.
    public enum Status: Sendable, Equatable {
        case notStarted, inProgress, paused, finished, failed, cancelled
    }

    /// The engine's, the same after a relaunch.
    public let id: String
    public var status: Status
    public var receivedBytes: Int64
    /// Nil while the size is unknown.
    public var totalBytes: Int64?
    public var bytesPerSecond: Int64
    /// Nil while the engine has no estimate.
    public var secondsRemaining: Int?
    /// Where the file goes, nil until the engine has chosen.
    public var file: URL?
    public var sourceURL: URL?
    public var startedAt: Date
    /// The page that started it, while that page is open.
    public var pageID: UUID?

    public init(
        id: String, status: Status, receivedBytes: Int64 = 0, totalBytes: Int64? = nil, bytesPerSecond: Int64 = 0,
        secondsRemaining: Int? = nil, file: URL? = nil, sourceURL: URL? = nil, startedAt: Date = .now,
        pageID: UUID? = nil
    ) {
        self.id = id
        self.status = status
        self.receivedBytes = receivedBytes
        self.totalBytes = totalBytes
        self.bytesPerSecond = bytesPerSecond
        self.secondsRemaining = secondsRemaining
        self.file = file
        self.sourceURL = sourceURL
        self.startedAt = startedAt
        self.pageID = pageID
    }
}

/// The settings page info lists on macOS, in its order, as ADK's `ArcContentSettingsType`.
public enum SiteSettingType: Int, Sendable, CaseIterable {
    case geolocation, geolocationWithOptions, camera, cameraPanTiltZoom, microphone, sensors, notifications
    case javascript, images, popups, windowManagement, ads, backgroundSync, sound, automaticDownloads, midiSysex
    case clipboardReadWrite, usbGuard, hidGuard, serialGuard, fileSystemWriteGuard, localFonts, bluetoothGuard
    case bluetoothScanning, handTracking, vr, ar, idleDetection, federatedIdentityAPI, automaticPictureInPicture
    case capturedSurfaceControl, automaticFullscreen, keyboardLock, pointerLock, webAppInstallation, localNetwork
    case loopbackNetwork
}

/// Chromium's `ContentSetting`; `default` resets the site's own value.
public enum SiteSettingValue: Int, Sendable {
    case `default`, allow, block, ask, sessionOnly
}

public struct SiteSetting: Sendable, Equatable {
    public let type: SiteSettingType
    public var value: SiteSettingValue

    public init(type: SiteSettingType, value: SiteSettingValue) {
        self.type = type
        self.value = value
    }
}

/// The engine's record of a closed page, valid until the app quits.
public struct PageSessionID: RawRepresentable, Hashable, Sendable {
    public let rawValue: Int32
    public init(rawValue: Int32) { self.rawValue = rawValue }
}

/// One page and its history. Observable, so views that read it update as it loads.
@MainActor
public protocol Page: AnyObject, Observable {
    /// The page's own identity, never its tab's, as Arc's content IDs are.
    var id: UUID { get }
    var url: URL? { get }
    var title: String { get }
    var isLoading: Bool { get }
    var loadProgress: Double { get }
    var canGoBack: Bool { get }
    var canGoForward: Bool { get }
    /// The icon the engine's favicon driver chose for the page, nil until it has one.
    var favicon: NSImage? { get }
    var securityLevel: SecurityLevel { get }
    /// Nil from a navigation's start until its document loads or fails, as Arc's ADK reports it.
    var navigationResult: NavigationResult? { get }
    /// While the page captures from them, as ADK's media session state reports.
    var isCameraOn: Bool { get }
    var isMicrophoneOn: Bool { get }
    /// Why the renderer is gone, nil once a new one is ready, as after a reload.
    var crash: PageCrash? { get }
    /// A page that keeps its address, as a pinned tab does: a link to another host opens a new page instead of
    /// navigating this one.
    var keepsAddress: Bool { get set }
    /// Attach it only while the page is shown: a view outside a window is hidden to the engine.
    var view: NSView { get }
    var events: AsyncStream<PageEvent> { get }

    func load(_ url: URL)
    func goBack()
    func goForward()
    func reload()
    func stopLoading()
    func activate()
    /// Moves the live page into another of the app's windows. History and the engine's tab identity stay.
    func move(toWindow windowID: UUID)
    /// Asks now for the page's last frame, for a window it leaves, as Arc's ADK does with a completion so a move need
    /// not wait for it. Nil while it has nothing drawn.
    func snapshot(_ completion: @escaping @MainActor (NSImage?) -> Void)
    /// Closes as the user would: unload handlers run, and `closed` or `closeCancelled` follows.
    func close()
    /// Ends the page without unload handlers. Events end.
    func drop()
}

public enum PageEvent {
    /// The page opened another page, live in this page's window with its opener kept. The app installs it under a
    /// tab, or drops it.
    case opened(any Page, url: URL?, disposition: OpenDisposition)
    /// The page asked to be shown, as `window.focus()` and a `window.open` reusing a named page do. The app selects
    /// its tab or ignores it.
    case wantsActivation
    /// The page asked for a dialog; the app shows it and answers it once.
    case dialog(PageDialog)
    /// The engine closed the dialog: a navigation, a tab switch, a close. No answer is expected.
    case dialogDismissed(PageDialog)
    /// The page asked for permissions, while its tab is the selected one; the app answers it once.
    case permissionRequest(PagePermissionRequest)
    /// The engine took the request down: after the answer, or on a navigation, a close or a tab switch, which asks
    /// again when the tab is back, as Arc's ADK does.
    case permissionRequestClosed(PagePermissionRequest)
    /// A `beforeunload` handler kept the page after `close()`.
    case closeCancelled
    /// The page is gone, after `close()` or without the app asking, with the engine's record of it if it kept one.
    case closed(PageSessionID?)
}

/// What a page asked with `alert`, `confirm`, `prompt` or a `beforeunload` handler.
@MainActor
public final class PageDialog {
    public enum Kind: Equatable {
        case alert
        case confirm
        case prompt(defaultText: String)
        case beforeUnload(isReload: Bool)
    }

    public let kind: Kind
    /// Chrome's line above the message: "host says", empty for `beforeUnload`.
    public let title: String
    public let message: String
    /// From the page's seventh dialog on, as Arc offers it; `suppress` answers the page's later dialogs unasked.
    public let offersSuppression: Bool
    private var reply: ((Bool, String, Bool) -> Void)?

    public init(
        kind: Kind, title: String, message: String, offersSuppression: Bool = false,
        reply: @escaping (_ accepted: Bool, _ text: String, _ suppress: Bool) -> Void
    ) {
        self.kind = kind
        self.title = title
        self.message = message
        self.offersSuppression = offersSuppression
        self.reply = reply
    }

    public func accept(text: String = "", suppress: Bool = false) {
        reply?(true, text, suppress)
        reply = nil
    }

    public func cancel(suppress: Bool = false) {
        reply?(false, "", suppress)
        reply = nil
    }
}

/// The engine's permission request types, as ADK mirrors Chromium's.
public enum PermissionKind: Sendable, Equatable {
    case ambientLogin
    case ar
    case cameraPanTiltZoom
    case camera
    case capturedSurfaceControl
    case clipboard
    case topLevelStorageAccess
    case quota
    case fileSystemAccess
    case geolocation
    case handTracking
    case identityProvider
    case idleDetection
    case localFonts
    case localNetwork
    case loopbackNetwork
    case microphone
    case midiSysex
    case multipleDownloads
    case notifications
    case keyboardLock
    case pointerLock
    case protocolHandler
    case sensors
    case storageAccess
    case vr
    case webAppInstallation
    case windowManagement
}

public enum PermissionResponse: Sendable {
    case allow
    case allowThisTime
    case deny
    /// Closed unanswered; nothing is saved for the site.
    case dismiss
}

/// What a page asked for at once: one site, one or more kinds the engine merged, as camera and microphone are.
@MainActor
public final class PagePermissionRequest {
    /// The host as the engine's prompts show it, or an extension's name.
    public let nameOrOrigin: String
    public let nameIsOrigin: Bool
    public let kinds: [PermissionKind]
    private var reply: ((PermissionResponse) -> Void)?

    public init(
        nameOrOrigin: String, nameIsOrigin: Bool = true, kinds: [PermissionKind],
        reply: @escaping (PermissionResponse) -> Void
    ) {
        self.nameOrOrigin = nameOrOrigin
        self.nameIsOrigin = nameIsOrigin
        self.kinds = kinds
        self.reply = reply
    }

    public func respond(_ response: PermissionResponse) {
        reply?(response)
        reply = nil
    }
}

public enum OpenDisposition: Sendable, Equatable {
    case foregroundTab
    case backgroundTab
    case newWindow
    case popup
}

/// Why a page's renderer is gone.
public enum PageCrash: Sendable, Equatable {
    case crashed
    case killed
    case outOfMemory
}

/// Chromium's security level for the page's visible URL.
public enum NavigationResult: Sendable, Equatable {
    case loaded
    case failed
}

public enum SecurityLevel: Sendable, Equatable {
    case neutral
    case secure
    case warning
    case dangerous
}
