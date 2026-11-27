import AppKit
import Foundation
import Observation

/// The engine the app programs against. Every call happens on the main thread.
@MainActor
public protocol BrowserApplication: AnyObject {
    var adBlocker: AdBlocker { get }
    /// Runs the app until it quits and returns the exit code. `ready` runs once, after the engine has started and
    /// before the event loop; the app sets its delegate and opens its windows there.
    func run(ready: @escaping @MainActor () -> Void) -> Int32
    /// As ADK's engine feature for Arc's restore switch: whether a profile's first browser brings its last session's
    /// pages back. Off until set; set it before the first window opens, and again when the switch changes, as Arc
    /// does.
    func setRestoresLastSession(_ restores: Bool)
    /// As ADK's `onFinishedRestoringWindows`: the windows of the last launch are back, and what the engine restored for
    /// a window that isn't goes.
    func finishedRestoringWindows()
    /// As Chrome's quit: each profile's session is saved and closed with the pages it has. Call it once the quit is
    /// certain.
    func saveSessionsForQuit()
    /// Finishes quitting after the app answered `applicationShouldTerminate` with `.terminateLater`. As Arc's, pages
    /// with unload handlers run them and close, the engine writes what it must keep, and the app exits with its
    /// windows as they are.
    func terminate()
    /// As ADK's `incognitoDisabled`: the app's `IncognitoModeAvailability` default is 1, as read at launch.
    var incognitoDisabled: Bool { get }
    /// As ADK's `BrowserContextID`: the profile's own context, or its incognito one, which shares its preferences
    /// and extensions, reads its history and keeps nothing once its last window has closed. As ADK's download
    /// manager per context, an incognito one's downloads are its own and leave the list with it.
    func browserContext(id: UUID, type: BrowserContextType) -> any BrowserContext
    /// The profiles the engine has, loaded or not, in the engine's own order, as ADK's `allProfiles()`.
    func allProfiles() -> [UUID]
    /// Whether a profile absent from `allProfiles()` is gone. Not for the stub, which lists only the profiles made
    /// through it and may share its data directory with Chromium's.
    var listsEveryProfile: Bool { get }
    /// Asked of the engine each time, as ADK's: the engine owns the name and the app keeps no copy.
    func userVisibleName(of profileID: UUID) -> String?
    /// A new profile, loaded; nil if the engine can't make one.
    func createBrowserContext(userVisibleName: String) async -> UUID?
    /// Lets go of the profile's engine objects, then deletes it with its data. True once the deletion is under way;
    /// never for `BrowserProfile.initialID`. The app drops the profile's pages and browsers first.
    func deleteBrowserContext(id: UUID) -> Bool
    /// Binds the app's window to the pages made for its `id`, once. Call it when the window opens.
    func attachWindow(_ window: NSWindow, id: UUID)
    /// Drops the window's remaining pages. Call it when the window closes.
    func closeWindow(id: UUID)
    /// Runs each of the window's `beforeunload` handlers in the engine's tab order, as quitting does, and stops at the
    /// first that keeps its page. Every page stays. True to leave.
    func askToLeave(windowID: UUID) async -> Bool
}

extension BrowserApplication {
    public func browserContext(id: UUID) -> any BrowserContext { browserContext(id: id, type: .normal) }
}

/// As ADK's `BrowserContextType`.
public enum BrowserContextType: Hashable, Sendable {
    case normal
    case incognito
}

public enum BrowserProfile {
    /// As ADK's `Profile.initial`: the profile every install has. It can't be deleted.
    public static let initialID = UUID(uuidString: "6B0F3E1A-0A5C-4F7B-9C1D-0A0A0A0A0A01")!
}

/// A profile's engine side: separate cookies, storage and history.
@MainActor
public protocol BrowserContext: AnyObject {
    var id: UUID { get }
    /// Without an event back, as ADK's: the next `userVisibleName(of:)` reads it.
    func setUserVisibleName(_ name: String)
    /// A page with an `id` of its own in the app's window `windowID`, in the background; nil if the engine can't.
    /// A closed page's `sessionID` brings its history back where it can (`restored`); else the app issues the `load`.
    func makePage(windowID: UUID, restoring sessionID: PageSessionID?) async -> (page: any Page, restored: Bool)?
    /// The settings of `url`'s site that differ from the engine's defaults, in page info's order, as ArcCore's
    /// `getChangedContentSettingsForOrigin:`. Nil until the profile has loaded.
    func changedSiteSettings(for url: URL) -> [SiteSetting]?
    /// For the site's whole origin, without reloading its pages, as Chrome's site settings page sets it.
    func setSiteSetting(_ type: SiteSettingType, to value: SiteSettingValue, for url: URL)
    /// The engine's history text search, newest first, as ADK's history query with a search text and a result limit.
    /// It matches words of a page's URL and title, so a host can find another site's page.
    func history(matching text: String, maxResults: Int) async -> [HistoryEntry]
    /// The icon the profile's favicon service keeps for a page, nil when it has none.
    func favicon(forPageAt url: URL) async -> NSImage?
    /// As ADK's download manager for the context: one per profile, alive as long as it.
    var downloads: any Downloads { get }
    /// As ArcCore's `ArcBrowserContextPreferences`: one per profile, kept current by the engine.
    var preferences: any BrowserContextPreferences { get }
    /// Chromium's omnibox for this profile. ArcCore keeps one per window.
    func makeAutocomplete() -> any Autocomplete
    /// As ArcCore's `ArcBrowserContextExtensions`: one per profile, kept current by the engine.
    var extensions: any Extensions { get }
    /// The app window's side in this profile, as ADK's `Browser`: one per window and profile, alive while the app
    /// holds it. As ADK's `ensureBrowserCreated`, a window asks for one in each profile as it appears: the engine's
    /// browser is made then, and a profile's first starts the restore of its last session.
    func browser(windowID: UUID, type: BrowserType) -> any Browser
}

/// As ADK's browser type: a little window's browser is the engine's popup, which holds its pages like any other and
/// never comes back with a session.
public enum BrowserType: Sendable {
    case normal
    case popup
}

extension BrowserContext {
    /// As Arc's `siteSearchDominantColor`: the dominant colour of the favicon of the newest page the history search
    /// finds for `host`, darkened. Nil without such a page, icon or colour. Asked each time, as Arc keeps no cache.
    public func siteSearchDominantColor(host: String) async -> NSColor? {
        guard let entry = await history(matching: host, maxResults: 1).first,
            let icon = await favicon(forPageAt: entry.url)
        else { return nil }
        return DominantColor.color(of: icon)?.darkened(byLightness: 0.15)
    }
}

public struct HistoryEntry: Sendable, Equatable {
    public let url: URL
    public let title: String

    public init(url: URL, title: String) {
        self.url = url
        self.title = title
    }
}

/// A profile's extensions as the engine installs and runs them. Observable: the engine's events change `items`.
@MainActor
public protocol Extensions: AnyObject, Observable {
    /// By name; empty until the profile's extension system is ready.
    var items: [BrowserExtension] { get }
    /// Installs JSON Formatter on first Developer Mode entry in this profile.
    func installJSONFormatterIfNeeded()
    func setEnabled(_ enabled: Bool, id: BrowserExtension.ID)
    /// Without asking. The engine's own removal paths ask through the page.
    func uninstall(_ id: BrowserExtension.ID)
}

/// As ADK's `BrowserExtension`.
public struct BrowserExtension: Identifiable, Sendable, Equatable {
    public static let jsonFormatterID = "bcjindcccaagfpapjjmafapmmgkkhgoa"

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
    /// As ADK's `onReceivedRestoredWebContents`: once, when the session restore the browser waited for is over, the
    /// pages the engine restored into the window in this profile. None is a batch too. The app binds each to its tab,
    /// or drops it.
    case restoredPages([RestoredPage])
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
    /// Every engine but Chromium's starter packs, as ArcCore's `getSearchEngines`; empty until loaded.
    var searchEngines: [SearchEngine] { get }
    var defaultSearchEngine: SearchEngine? { get }
    /// As the user's choice, as ArcCore's `setDefaultSearchEngine:`.
    func setDefaultSearchEngine(_ engine: SearchEngine)
    /// Active, as ArcCore's `addSearchEngine:error:`; an engine with the same keyword stays as it is.
    func addSearchEngine(_ engine: SearchEngine)
    /// Chromium's suggestions from the default engine, as ArcCore's `searchSuggestEnabled`.
    var includesSearchSuggestions: Bool { get set }
}

extension BrowserContextPreferences {
    /// As ADK's `activeSearchEngines`: the active and prepopulated engines, site searches first.
    public var activeSearchEngines: [SearchEngine] {
        let active = searchEngines.filter { $0.isActive || $0.isPrepopulated }
        return active.filter { !$0.isPrepopulated } + active.filter(\.isPrepopulated)
    }
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
    public let isActive: Bool

    public init(
        name: String, keyword: String, url: String, faviconURL: URL? = nil, isPrepopulated: Bool = true,
        isActive: Bool = true
    ) {
        self.name = name
        self.keyword = keyword
        self.url = url
        self.faviconURL = faviconURL
        self.isPrepopulated = isPrepopulated
        self.isActive = isActive
    }
}

extension SearchEngine {
    /// ADK's `enginesToAutoActivate`: Arc's popular site searches with their colours, in Arc's order. Arc writes the
    /// URLs with `%s`, which ArcCore stores as `{searchTerms}`.
    public static let enginesToAutoActivate: [(engine: SearchEngine, color: UInt32)] = [
        site(
            "Google Drive", "drive.google.com", "https://drive.google.com/drive/search?q=", 0x0F9D58,
            favicon: "https://drive.google.com/favicon.ico"),
        site(
            "Gmail", "mail.google.com", "https://mail.google.com/mail/ca/u/0/#apps/", 0xD44638,
            favicon: "https://mail.google.com/favicon.ico"),
        site(
            "Google Maps", "maps.google.com", "https://www.google.com/maps/search/", 0xFBBC05,
            favicon: "https://www.google.com/images/branding/product/ico/maps15_bnuw3a_32dp.ico"),
        site(
            "Google Calendar", "calendar.google.com", "https://calendar.google.com/calendar/u/0/r/search?q=", 0x9C27B0,
            favicon: "https://calendar.google.com/googlecalendar/images/favicons_2020q4/calendar_14.ico"),
        site(
            "Google Docs", "docs.google.com", "https://docs.google.com/document/u/0/?q=", 0x4285F4,
            favicon: "https://ssl.gstatic.com/docs/documents/images/kix-favicon7.ico"),
        site(
            "Dropbox", "dropbox.com", "https://www.dropbox.com/search/personal?&query=", 0x007EE5,
            favicon: "https://cfl.dropboxstatic.com/static/metaserver/static/images/favicon-vfl8lUR9B.ico"),
        site(
            "Amazon", "amazon.com", "https://www.amazon.com/s?k=", 0xFF9900,
            favicon: "https://www.amazon.com/favicon.ico"),
        site(
            "GitHub", "github.com", "https://github.com/search?q=", 0x743FC7,
            favicon: "https://github.com/favicon.ico"),
        site(
            "Figma", "figma.com", "https://www.figma.com/files/search?q=", 0xF24E1E,
            favicon: "https://static.figma.com/app/icon/1/favicon.png"),
        site("X", "x.com", "https://x.com/search?q=", 0x000000, favicon: "https://x.com/favicon.ico"),
        site("X", "twitter.com", "https://twitter.com/search?q=", 0x000000, favicon: "https://x.com/favicon.ico"),
        site(
            "YouTube", "youtube.com", "https://www.youtube.com/results?search_query=", 0xFF0000,
            favicon: "https://www.youtube.com/s/desktop/9318de79/img/favicon_32x32.png"),
        site(
            "Wikipedia", "wikipedia.org", "https://wikipedia.org/w/index.php?search=", 0xFFA500,
            favicon: "https://en.wikipedia.org/favicon.ico"),
        site(
            "Reddit", "reddit.com", "https://www.reddit.com/search/?q=", 0xFF4500,
            favicon: "https://reddit.com/favicon.ico"),
        site(
            "SoundCloud", "soundcloud.com", "https://soundcloud.com/search?q=", 0xF85216,
            favicon: "https://soundcloud.com/favicon.ico"),
        site(
            "Asana", "asana.com", "https://app.asana.com/0/search?q=", 0xF06A6A,
            favicon: "https://asana.com/favicon.ico"),
        site(
            "LinkedIn", "linkedin.com", "https://linkedin.com/search/results/all/?keywords=", 0x0B66C2,
            favicon: "https://www.linkedin.com/favicon.ico"),
        site(
            "Apple Music", "music.apple.com", "https://music.apple.com/us/search?term=", 0xFA2A44,
            favicon: "https://music.apple.com/favicon.ico"),
        site(
            "Spotify", "spotify.com", "https://open.spotify.com/search/", 0x1DB954,
            favicon: "https://www.scdn.co/i/_global/favicon.ico"),
    ]

    /// As ADK's `resolvedSearchURL(for: "")`: the search URL without terms. Chromium's other `{…}` parameters go
    /// too, and `{google:baseURL}` reads as its default.
    public var emptySearchURL: URL? {
        URL(
            string: url.replacingOccurrences(of: "{google:baseURL}", with: "https://www.google.com/")
                .replacing(#/\{[^}]*\}/#, with: ""))
    }

    /// Arc's colour for the engine from `enginesToAutoActivate`, as its command bar looks it up: none for a
    /// prepopulated engine, then the entry with the engine's URL, then the first whose host the engine's host is or
    /// is under. So `www.youtube.com` finds YouTube's and `youtube.com` doesn't.
    public var autoActivatedColor: UInt32? {
        guard !isPrepopulated else { return nil }
        let table = SearchEngine.enginesToAutoActivate
        if let exact = table.first(where: { $0.engine.url == url }) { return exact.color }
        guard let host = emptySearchURL?.host() else { return nil }
        return table.first { entry in
            guard let domain = entry.engine.emptySearchURL?.host() else { return false }
            return host == domain || host.hasSuffix("." + domain)
                || host.split(separator: ".").contains(Substring(domain))
        }?.color
    }

    private static func site(
        _ name: String, _ keyword: String, _ url: String, _ color: UInt32, favicon: String
    ) -> (engine: SearchEngine, color: UInt32) {
        let engine = SearchEngine(
            name: name, keyword: keyword, url: url + "{searchTerms}", faviconURL: URL(string: favicon),
            isPrepopulated: false)
        return (engine, color)
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
    /// What happens to the context's downloads from now on, a stream per caller, as ADK's `downloadActions`: it
    /// starts with `initialized` once the engine has read the history.
    var events: AsyncStream<DownloadEvent> { get }
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
    /// As ADK's: the address the page that started it shows, while that page is open, else the file's.
    public var sourceURL: URL?
    /// The registrable domain of `sourceURL`, nil for an address without one, as an IP.
    public var sourceDomain: String?
    public var startedAt: Date
    /// The page that started it, while that page is open.
    public var pageID: UUID?
    /// That page's address, title and the engine's session ID for it, while it is open.
    public var pageURL: URL?
    public var pageTitle: String?
    public var pageSessionID: Int32?

    public init(
        id: String, status: Status, receivedBytes: Int64 = 0, totalBytes: Int64? = nil, bytesPerSecond: Int64 = 0,
        secondsRemaining: Int? = nil, file: URL? = nil, sourceURL: URL? = nil, sourceDomain: String? = nil,
        startedAt: Date = .now, pageID: UUID? = nil, pageURL: URL? = nil, pageTitle: String? = nil,
        pageSessionID: Int32? = nil
    ) {
        self.id = id
        self.status = status
        self.receivedBytes = receivedBytes
        self.totalBytes = totalBytes
        self.bytesPerSecond = bytesPerSecond
        self.secondsRemaining = secondsRemaining
        self.file = file
        self.sourceURL = sourceURL
        self.sourceDomain = sourceDomain
        self.startedAt = startedAt
        self.pageID = pageID
        self.pageURL = pageURL
        self.pageTitle = pageTitle
        self.pageSessionID = pageSessionID
    }
}

/// As ADK's download manager reports a context's downloads.
public enum DownloadEvent: Sendable {
    /// Every download the context has, sent first.
    case initialized([Download])
    case create(Download)
    /// It progressed or finished.
    case update(Download)
    case failed(Download)
    /// Cancelled, or with `shouldRemove` forgotten by the engine.
    case cancel(Download, shouldRemove: Bool)
    case paused(Download)
}

/// The event streams a `Downloads` hands out.
@MainActor
public final class DownloadEvents {
    private var continuations: [UUID: AsyncStream<DownloadEvent>.Continuation] = [:]

    public init() {}

    /// `initial` is nil until the engine has read the history; `initialize` sends it then.
    public func stream(initial: [Download]?) -> AsyncStream<DownloadEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<DownloadEvent>.makeStream()
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.continuations[id] = nil }
        }
        if let initial { continuation.yield(.initialized(initial)) }
        return stream
    }

    public func send(_ event: DownloadEvent) {
        continuations.values.forEach { $0.yield(event) }
    }

    /// As ADK's `onDownloadUpdated` picks the event by the download's status.
    public func sendUpdate(_ download: Download) {
        switch download.status {
        case .notStarted, .inProgress, .finished: send(.update(download))
        case .failed: send(.failed(download))
        case .cancelled: send(.cancel(download, shouldRemove: false))
        case .paused: send(.paused(download))
        }
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

/// A page the engine brought back from the last session, live in the window whose browser reports it.
public struct RestoredPage {
    /// The session ID of its tab in the last session, as Arc's restoration data keeps it.
    public let lastSessionID: Int32
    public let page: any Page

    public init(lastSessionID: Int32, page: any Page) {
        self.lastSessionID = lastSessionID
        self.page = page
    }
}

/// Identifies one committed frame document for its lifetime.
public struct PageFrameID: Hashable, Sendable {
    package let token: String
    package init(token: String) { self.token = token }
}

public enum StyleSheetResult: Int, Sendable {
    case inserted, frameGone, rendererCrashed, disconnected, timedOut, unsupported
}

/// One page and its history. Observable, so views that read it update as it loads.
@MainActor
public protocol Page: AnyObject, Observable {
    /// The link destination reported by the page, cleared when the pointer leaves it.
    var hoveredLink: URL? { get }
    /// The page's own identity, never its tab's, as Arc's content IDs are.
    var id: UUID { get }
    var url: URL? { get }
    var title: String { get }
    var isLoading: Bool { get }
    var loadProgress: Double { get }
    var canGoBack: Bool { get }
    var canGoForward: Bool { get }
    /// The engine's session ID of the page's tab, kept while the page lives, as Arc's restoration data stores it.
    var tabSessionID: Int32 { get }
    /// The profile whose context the page was made in, its own or its incognito one, as ADK's `BrowserContextID`.
    /// A move to another window keeps it.
    var profileID: UUID { get }
    /// The icon the engine's favicon driver chose for the page, nil until it has one.
    var favicon: NSImage? { get }
    var securityLevel: SecurityLevel { get }
    /// The requesting frame's origin while this page fills the display.
    var fullscreenOrigin: String? { get }
    func exitFullscreen()
    /// The page's root background colour from its compositor frames, as ADK's `rootBackgroundColor`: nil until the
    /// first frame, then kept across navigations and crashes.
    var rootBackgroundColor: NSColor? { get }
    /// Nil from a navigation's start until its document loads or fails, as Arc's ADK reports it.
    var navigationResult: NavigationResult? { get }
    /// While the page captures from them, as ADK's media session state reports.
    var isCameraOn: Bool { get }
    var isMicrophoneOn: Bool { get }
    /// While the page plays sound, as ADK's `isAudible`, muted or not.
    var isAudible: Bool { get }
    /// As ADK's `setWebContentsMuted`; kept across navigations.
    var isMuted: Bool { get set }
    /// While the page has the keyboard, as ADK's `hasFocus`: false again once its window isn't key.
    var hasFocus: Bool { get }
    /// What the user last selected in the page, as ArcCore's cached `selectedText`: a script's selection doesn't count
    /// and a navigation keeps it. Empty when nothing was selected.
    var selectedText: String { get }
    /// As ADK's `zoomLevel`, a factor: the engine's zoom for the page's host in its profile, so every page of the
    /// host follows a change.
    var zoomFactor: Float { get }
    /// While a pinch has scaled the page.
    var isPageScaled: Bool { get }
    /// The page's media, as ADK's media session.
    var mediaSession: any MediaSession { get }
    /// The page's DevTools, as ArcCore's `ArcWebContentsDevTools`.
    var devTools: any PageDevTools { get }
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
    /// As Chrome's ⇧⌘R: the page and its resources from the network, not the cache.
    func reloadBypassingCache()
    /// As ADK's `setZoomFactor`: kept for the page's host in its profile.
    func setZoomFactor(_ factor: Float)
    /// As ADK's `resetZoomAndScaleFactors`: 100 %, not the profile's default zoom, and the pinch undone.
    func resetZoomAndScaleFactors()
    /// As ADK's `save()`: Chrome's Save Page As panel over the page's window.
    func savePage()
    /// As ADK's `print()`: the engine's print preview for the page, which comes as a `webDialog` event. Nothing for a
    /// crashed page.
    func print()
    func stopLoading()
    func activate()
    /// As ADK's `performFindInPage`: never case-sensitive, scrolling to the active match, its results as `findResult`
    /// events. Empty text clears the find.
    func find(_ text: String, direction: FindDirection, findMatch: Bool)
    /// As ADK's `stopFindInPage`: the active match stays selected.
    func stopFinding()
    /// A new page with this one's history, as ADK's `cloneWebContent`: in the same window, hidden, loading its entry at
    /// once. Nil once the page is gone.
    func duplicate() -> (any Page)?
    /// Moves the live page into another of the app's windows. History and the engine's tab identity stay.
    func move(toWindow windowID: UUID)
    /// Live, committed frame documents in breadth-first order, starting at the main frame.
    var frameIDs: [PageFrameID] { get }
    /// Inserts author CSS into this document. A timeout leaves insertion unconfirmed.
    func insertStyleSheet(_ css: String, in frame: PageFrameID) async -> StyleSheetResult
    /// Asks now for the page's last frame, for a window it leaves, as Arc's ADK does with a completion so a move need
    /// not wait for it. Nil while it has nothing drawn.
    func snapshot(_ completion: @escaping @MainActor (NSImage?) -> Void)
    /// As ADK's thumbnail observing, which Arc starts when a page's view loads. While observed, the engine makes a
    /// small picture of the page by itself and each comes as a `thumbnail` event: after a load and after a URL
    /// change inside the document, shown or not, and as the page stops being shown.
    func startObservingThumbnails()
    func stopObservingThumbnails()
    /// Asks the engine for a picture of the page now, as ADK's `requestThumbnail()`, which starts the observing it
    /// needs. A shown page's comes as a `thumbnail` event, or not at all while a navigation loads; a hidden page's
    /// last one comes again.
    func requestThumbnail()
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
    /// The page menu's Open Link in Incognito Window, as ADK's `onOpenLinkInIncognitoWindow`: only the address. The
    /// engine offers it only on a page of a profile's own context.
    case openLinkInIncognitoWindow(URL)
    /// The page menu's Open Link in Little Oa, as ADK's `littleWindow` disposition, which the app answers by opening
    /// its own window: only the address.
    case openLinkInLittleWindow(URL)
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
    /// What the engine asks of the app's window for the page's picture-in-picture video.
    case pictureInPicture(PictureInPictureEvent)
    /// The engine shows a dialog of its own over the page, as ADK's `onShowWebUIDialog`: print preview, for one,
    /// after `print()` or the page's `window.print()`. The app shows it over the page's window.
    case webDialog(WebDialog)
    /// The dialog closed itself, from its own buttons or Escape, or with its page, as ADK's `onDidCloseWebUIDialog`.
    case webDialogClosed(WebDialog)
    /// The page consumed a key down, as ADK's `webContents:didConsumeKey:withModifierFlags:underlyingEventType:`
    /// for a raw key down: the key's code and the modifier flags of its event.
    case consumedKey(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags)
    /// A thumbnail the engine made of the page, at one pixel a point, as ADK's thumbnail listeners get every one:
    /// the answer to `requestThumbnail()`, or one the engine made by itself while observed.
    case thumbnail(NSImage)
    /// A result of the page's find, as ADK's `onFindInPageResult`: each one the engine has.
    case findResult(FindResult)
    /// A `beforeunload` handler kept the page after `close()`.
    case closeCancelled
    /// The page is gone, after `close()` or without the app asking, with the engine's record of it if it kept one.
    case closed(PageSessionID?)
}

/// Where a page's DevTools frontend asks to be shown, from its own Dock side setting, as ArcCore's
/// `ArcDevToolsDisplayStyle`.
public enum DevToolsDisplay: Sendable {
    case undocked, left, right, bottom
}

/// A page's DevTools, as ArcCore's `ArcWebContentsDevTools`: the engine's own frontend, which the app shows beside the
/// page or in a window. Observable.
@MainActor
public protocol PageDevTools: AnyObject, Observable {
    /// Nil while closed; set as the frontend opens and whenever its dock side changes.
    var display: DevToolsDisplay? { get }
    /// The frontend's view while it is displayed.
    var view: NSView? { get }
    /// As ADK's: opening lands on Elements every time.
    func setOpen(_ open: Bool)
    /// Elements with the element picker on; never closes.
    func inspect()
    /// Closes while Console shows, else opens on it, as ADK's toggle on the current panel.
    func toggleConsole()
    func toggleNetwork()
    /// Gives the frontend the keyboard once its view is in a window.
    func focus()
}

/// A page's media as the engine plays it, as ArcCore's `ArcWebContentsMediaSession`.
@MainActor
public protocol MediaSession: AnyObject {
    /// Nil while the page has no media session. Read when needed: it isn't observed yet.
    var state: MediaSessionState? { get }
    /// Asks the engine to show the page's video in picture-in-picture; the page's `pictureInPicture` events follow.
    /// False when the engine refuses: the page has such a video already, or no media session that can enter
    /// picture-in-picture. Whether the media plays is the app's check, as in Arc.
    @discardableResult func requestPictureInPicture() -> Bool
    /// Ends picture-in-picture and pauses the video or leaves it playing in the page, as ArcCore's
    /// `exitPictureInPicture:`. False when the page has no picture-in-picture video.
    @discardableResult func exitPictureInPicture(pausing: Bool) -> Bool
}

/// As ADK's `MediaSessionState` and `MediaContentType`.
public struct MediaSessionState: Sendable, Equatable {
    public enum Status: Sendable {
        case active, ducking, suspended, inactive
    }

    public enum ContentType: Sendable {
        case audioOnly, videoOnly, audioVideo
    }

    public var status: Status
    /// Nil while the engine can't tell.
    public var contentType: ContentType?

    public init(status: Status, contentType: ContentType?) {
        self.status = status
        self.contentType = contentType
    }
}

/// As ADKClient's `WebContentPiPAction`.
public enum PictureInPictureEvent: Sendable {
    /// The page's video went to picture-in-picture; `show` follows.
    case created(PictureInPictureController)
    case show
    /// Picture-in-picture ended, by the app's exit or the page's. `show` may follow again for the same controller.
    case hide
    case close
    /// The video's natural size.
    case resolutionChanged(CGSize)
    case destroyed
}

/// As ArcCore's `ArcWebContentsMediaSessionPiPController`.
@MainActor
public final class PictureInPictureController {
    /// Draws the video at whatever size it is given. The engine's until `destroyed`; attach it while it is shown.
    public let view: NSView
    /// The video element's bounds in its page.
    public let sourceBounds: CGRect

    public init(view: NSView, sourceBounds: CGRect) {
        self.view = view
        self.sourceBounds = sourceBounds
    }
}

/// A dialog the engine draws itself and the app shows over a page, as ADK's `ArcWebDialog`.
@MainActor
public final class WebDialog {
    public let title: String
    public let accessibleTitle: String
    public let preferredSize: CGSize
    public let minimumSize: CGSize
    /// Draws the dialog. The engine's until `webDialogClosed`; attach it while the dialog is shown.
    public let view: NSView

    public init(title: String, accessibleTitle: String, preferredSize: CGSize, minimumSize: CGSize, view: NSView) {
        self.title = title
        self.accessibleTitle = accessibleTitle
        self.preferredSize = preferredSize
        self.minimumSize = minimumSize
        self.view = view
    }
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
    /// As ADK's `splitView`: beside the page that opened it, in the app's split view.
    case splitView

    /// ADK's mapping of an engine's open: a foreground one while ⌥ is held, by the event that caused it, is a split
    /// view.
    @MainActor
    public static func withModifiers(_ disposition: OpenDisposition) -> OpenDisposition {
        disposition == .foregroundTab && NSApp.currentEvent?.modifierFlags.contains(.option) == true
            ? .splitView : disposition
    }
}

/// ADK's `FindInPageDirection`; ADK searches forward for `current`.
public enum FindDirection: Sendable {
    case backward, current, forward
}

/// ADK's `FindInPageResult`: -1 for what the engine doesn't know yet.
public struct FindResult: Sendable, Equatable {
    public var numberOfMatches: Int
    public var activeMatchOrdinal: Int

    public init(numberOfMatches: Int, activeMatchOrdinal: Int) {
        self.numberOfMatches = numberOfMatches
        self.activeMatchOrdinal = activeMatchOrdinal
    }
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
