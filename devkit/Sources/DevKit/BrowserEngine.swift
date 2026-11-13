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
    /// As ArcCore's `ArcBrowserContextPreferences`: one per profile, kept current by the engine.
    var preferences: any BrowserContextPreferences { get }
    /// Chromium's omnibox for this profile. ArcCore keeps one per window.
    func makeAutocomplete() -> any Autocomplete
    /// As ArcCore's `ArcBrowserContextExtensions`: one per profile, kept current by the engine.
    var extensions: any Extensions { get }
    /// The app window's side in this profile, as ADK's `Browser`: one per window and profile, alive while the app
    /// holds it.
    func browser(windowID: UUID) -> any Browser
}

/// A profile's extensions as the engine installs and runs them. Observable: the engine's events change `items`.
@MainActor
public protocol Extensions: AnyObject, Observable {
    /// By name; empty until the profile's extension system is ready.
    var items: [BrowserExtension] { get }
    func setEnabled(_ enabled: Bool, id: BrowserExtension.ID)
    /// Without asking. The engine's own removal paths ask through the page.
    func uninstall(_ id: BrowserExtension.ID)
}

/// As ADK's `BrowserExtension`.
public struct BrowserExtension: Identifiable, Sendable, Equatable {
    public let id: String
    public var name: String
    public var description: String
    public var version: String
    public var isEnabled: Bool
    public var hasAction: Bool
    public var isFromWebStore: Bool

    public init(
        id: String, name: String, description: String = "", version: String = "", isEnabled: Bool = true,
        hasAction: Bool = true, isFromWebStore: Bool = true
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.version = version
        self.isEnabled = isEnabled
        self.hasAction = hasAction
        self.isFromWebStore = isFromWebStore
    }
}

/// One app window in one profile, as ADK's `Browser`. Observable: the engine's events change the actions and the
/// popup.
@MainActor
public protocol Browser: AnyObject, Observable {
    /// The extensions' toolbar actions for the window's selected page, by name, as ADK's toolbar action details.
    var extensionActions: [ExtensionAction] { get }
    /// The popup an action opened, until it closes. One shows at a time.
    var extensionPopup: ExtensionPopup? { get }
    var events: AsyncStream<BrowserEvent> { get }
    /// As a click on its toolbar button: its popup, its click event or its side panel.
    func runExtensionAction(_ id: ExtensionAction.ID)
    func setExtensionPinned(_ pinned: Bool, id: ExtensionAction.ID)
    /// The engine's menu for the action, at the mouse.
    func showExtensionMenu(for id: ExtensionAction.ID)
    func closeExtensionPopup()
}

public enum BrowserEvent {
    /// The engine put a page in the window itself, as an extension's `chrome.tabs.create` does. The app installs it
    /// under a tab, or drops it.
    case opened(any Page, isActive: Bool)
}

/// As ADK's `BrowserExtensionToolbarActionDetails` with its toolbar position.
public struct ExtensionAction: Identifiable, Equatable {
    public let id: String
    public var name: String
    public var tooltip: String
    /// With the badge drawn in.
    public var icon: NSImage?
    public var isEnabled: Bool
    /// Among the profile's pinned extensions; nil when it isn't pinned.
    public var pinnedPosition: Int?

    public init(
        id: String, name: String, tooltip: String = "", icon: NSImage? = nil, isEnabled: Bool = true,
        pinnedPosition: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.tooltip = tooltip
        self.icon = icon
        self.isEnabled = isEnabled
        self.pinnedPosition = pinnedPosition
    }
}

/// An action's popup page, as ADK's `BrowserExtensionPopup`. Observable: the page sizes itself.
@MainActor
@Observable
public final class ExtensionPopup {
    public let extensionID: String
    /// The engine's until the popup closes; attach it while the popup is shown.
    public let view: NSView
    public var size: CGSize
    @ObservationIgnored private let focusView: () -> Void

    public init(extensionID: String, view: NSView, size: CGSize, focus: @escaping () -> Void = {}) {
        self.extensionID = extensionID
        self.view = view
        self.size = size
        focusView = focus
    }

    /// Gives the page the keyboard once its view is in a window.
    public func focus() { focusView() }
}

/// A profile's preferences, observable: the engine reports them once the profile has loaded and after every change,
/// Chrome's settings page included. A value set reads back with the report that follows.
@MainActor
public protocol BrowserContextPreferences: AnyObject, Observable {
    /// Where the profile's downloads go and a Save panel starts, as ArcCore's `downloadFilePath`; nil until loaded.
    var downloadDirectory: URL? { get set }
    /// The engine asks where to save each download in its Save panel, as ArcCore's `promptForDownloadPath`.
    var asksWhereToSaveDownloads: Bool { get set }
    /// The engines Chrome's settings offer as the default, as ArcCore's `getSearchEngines`; empty until loaded.
    var searchEngines: [SearchEngine] { get }
    var defaultSearchEngine: SearchEngine? { get }
    /// As the user's choice, as ArcCore's `setDefaultSearchEngine:`.
    func setDefaultSearchEngine(_ engine: SearchEngine)
    /// Chromium's suggestions from the default engine, as ArcCore's `searchSuggestEnabled`.
    var includesSearchSuggestions: Bool { get set }
}

/// As ArcCore's `ArcSearchEngine`.
public struct SearchEngine: Identifiable, Sendable, Equatable {
    public var id: String { keyword }
    public let name: String
    public let keyword: String
    /// Chromium's URL template, with `{searchTerms}`.
    public let url: String
    public let faviconURL: URL?
    public let isPrepopulated: Bool

    public init(name: String, keyword: String, url: String, faviconURL: URL? = nil, isPrepopulated: Bool = true) {
        self.name = name
        self.keyword = keyword
        self.url = url
        self.faviconURL = faviconURL
        self.isPrepopulated = isPrepopulated
    }
}

/// Chromium's omnibox in one profile, as ADK's `ChromiumBrowser` runs it. Observable: each answer replaces the matches.
@MainActor
public protocol Autocomplete: AnyObject, Observable {
    /// As ADK's `rankedResults`: Chromium's combined result in its order, at most 8, only of ADK's kinds.
    var matches: [AutocompleteMatch] { get }
    /// As ADK's `additionalResults`: every provider's own matches, which include the ones the combined result left out.
    var additionalMatches: [AutocompleteMatch] { get }
    /// The start the matches answer; nil before any start has an answer.
    var input: AutocompleteInput? { get }
    /// Every provider has answered `input`.
    var isDone: Bool { get }
    /// Replaces a running query.
    func start(_ input: AutocompleteInput)
    func stop()
    /// Has the match's provider forget it, as ADK's `deleteAutocompleteMatch`.
    func delete(_ match: AutocompleteMatch)
}

/// The arguments of ArcCore's `autocomplete:cursorPosition:preventInlineAutocomplete:startFresh:keyword:`.
public struct AutocompleteInput: Sendable, Equatable {
    public var text: String
    /// In UTF-16 code units.
    public var cursorPosition: Int
    public var preventsInlineAutocomplete: Bool
    /// The first start of a command bar session.
    public var startsFresh: Bool
    /// A search engine's keyword when searching only it.
    public var keyword: String?
    /// The page the input edits, when it edits one.
    public var currentURL: URL?

    public init(
        text: String, cursorPosition: Int? = nil, preventsInlineAutocomplete: Bool = false, startsFresh: Bool = false,
        keyword: String? = nil, currentURL: URL? = nil
    ) {
        self.text = text
        self.cursorPosition = cursorPosition ?? text.utf16.count
        self.preventsInlineAutocomplete = preventsInlineAutocomplete
        self.startsFresh = startsFresh
        self.keyword = keyword
        self.currentURL = currentURL
    }
}

/// As ADK's `BrowserSearchResult`.
public struct AutocompleteMatch: Identifiable, Sendable, Equatable {
    /// ADK's `BrowserSearchResultType` with Chromium's type strings. ADK has no open-tab kind, and Arc never shows
    /// bookmark or calculator matches, so those are dropped.
    public enum Kind: String, Sendable {
        case urlWhatYouTyped = "url-what-you-typed"
        case searchWhatYouTyped = "search-what-you-typed"
        case historyURL = "history-url"
        case historyTitle = "history-title"
        case searchHistory = "search-history"
        case searchSuggest = "search-suggest"
        case searchSuggestEntity = "search-suggest-entity"
        case navSuggest = "navsuggest"
        case searchOtherEngine = "search-other-engine"
    }

    public let id: Int
    public let kind: Kind
    public let contents: String
    public let description: String
    public let url: URL?
    public let fillIntoEdit: String
    public let inlineAutocompletion: String
    public let relevance: Int
    public let allowedToBeDefault: Bool
    public let isDeletable: Bool
    /// 1-based, in Chromium's combined result, before ADK's kinds are kept; nil for an additional match.
    public let chromiumRank: Int?
    /// From Chromium's history providers, as ADK's `typedCount`, `visitCount` and `lastVisited`.
    public let typedCount: Int?
    public let visitCount: Int?
    public let lastVisited: Date?

    public init(
        id: Int, kind: Kind, contents: String, description: String = "", url: URL?, fillIntoEdit: String,
        inlineAutocompletion: String = "", relevance: Int, allowedToBeDefault: Bool = false, isDeletable: Bool = false,
        chromiumRank: Int? = nil, typedCount: Int? = nil, visitCount: Int? = nil, lastVisited: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.contents = contents
        self.description = description
        self.url = url
        self.fillIntoEdit = fillIntoEdit
        self.inlineAutocompletion = inlineAutocompletion
        self.relevance = relevance
        self.allowedToBeDefault = allowedToBeDefault
        self.isDeletable = isDeletable
        self.chromiumRank = chromiumRank
        self.typedCount = typedCount
        self.visitCount = visitCount
        self.lastVisited = lastVisited
    }
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
    /// tab, or drops it. `byPage` tells the page's own open, as a link, a Shift-click or `window.open`, from one the
    /// engine made for the user, as its page menu's Open Link in New Window.
    case opened(any Page, url: URL?, disposition: OpenDisposition, byPage: Bool)
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
    /// The engine asks before it installs or removes an extension, as ADK queues the consent on the page; the app
    /// answers it once.
    case extensionRequest(PageExtensionRequest)
    /// The engine took the request down unanswered, as when the extension went away meanwhile.
    case extensionRequestClosed(PageExtensionRequest)
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

/// As ADK's `WebContentExtensionInstallRequest`, and its like for a removal.
@MainActor
public final class PageExtensionRequest {
    public enum Kind: Sendable {
        case install
        case uninstall
    }

    public let kind: Kind
    public let extensionID: String
    public let name: String
    /// Nil for a removal.
    public let icon: NSImage?
    /// The engine's permission warnings, one line each.
    public let permissions: [String]
    private var reply: ((Bool) -> Void)?

    public init(
        kind: Kind, extensionID: String, name: String, icon: NSImage? = nil, permissions: [String] = [],
        reply: @escaping (Bool) -> Void
    ) {
        self.kind = kind
        self.extensionID = extensionID
        self.name = name
        self.icon = icon
        self.permissions = permissions
        self.reply = reply
    }

    public func respond(_ accepted: Bool) {
        reply?(accepted)
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
