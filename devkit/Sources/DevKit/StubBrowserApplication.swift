import AppKit
import Foundation
import Observation

/// An engine without a web engine: pages are placeholders. UI work runs on it without a Chromium build.
@MainActor
public final class StubBrowserApplication: BrowserApplication {
    private var contexts: [UUID: StubBrowserContext] = [:]
    private var incognitoContexts: [UUID: StubBrowserContext] = [:]
    public let adBlocker: AdBlocker
    public let incognitoDisabled = UserDefaults.standard.integer(forKey: "IncognitoModeAvailability") == 1
    private let profilesFile: URL
    /// What Chromium's profile storage is to the live engine: the stub's profiles and names, kept across launches.
    private var profiles: [StubProfile] {
        didSet {
            try? FileManager.default.createDirectory(
                at: profilesFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(profiles).write(to: profilesFile, options: .atomic)
        }
    }

    public init(directory: URL) {
        adBlocker = AdBlocker(directory: directory, apply: { _ in true }, exclude: { _ in })
        profilesFile = directory.appendingPathComponent("StubProfiles.json")
        profiles = (try? JSONDecoder().decode([StubProfile].self, from: Data(contentsOf: profilesFile))) ?? []
    }

    public func run(ready: @escaping @MainActor () -> Void) -> Int32 {
        let application = NSApplication.shared
        ready()
        application.run()
        return 0
    }

    public func setRestoresLastSession(_ restores: Bool) {}
    public func finishedRestoringWindows() {}
    public func saveSessionsForQuit() {}

    public func terminate() {
        NSApplication.shared.reply(toApplicationShouldTerminate: true)
    }

    public func browserContext(id: UUID, type: BrowserContextType) -> any BrowserContext {
        let parent = contexts[id] ?? StubBrowserContext(id: id) { [weak self] in self?.name(id, $0) }
        contexts[id] = parent
        guard type == .incognito else { return parent }
        if let context = incognitoContexts[id] { return context }
        let context = StubBrowserContext(sharingWith: parent)
        incognitoContexts[id] = context
        return context
    }

    public func allProfiles() -> [UUID] { profiles.map(\.id) }
    public let listsEveryProfile = false

    public func userVisibleName(of profileID: UUID) -> String? { profiles.first { $0.id == profileID }?.name }

    public func createBrowserContext(userVisibleName: String) async -> UUID? {
        let profile = StubProfile(id: UUID(), name: userVisibleName)
        profiles.append(profile)
        return profile.id
    }

    public func deleteBrowserContext(id: UUID) -> Bool {
        guard id != BrowserProfile.initialID, profiles.contains(where: { $0.id == id }) else { return false }
        contexts[id] = nil
        incognitoContexts[id] = nil
        profiles.removeAll { $0.id == id }
        return true
    }

    private func name(_ id: UUID, _ name: String) {
        if let index = profiles.firstIndex(where: { $0.id == id }) {
            profiles[index].name = name
        } else {
            profiles.append(StubProfile(id: id, name: name))
        }
    }

    public func attachWindow(_ window: NSWindow, id: UUID) {}

    public func closeWindow(id: UUID) {}

    public func askToLeave(windowID: UUID) async -> Bool {
        await StubPage.askToLeave(windowID: windowID)
    }
}

private struct StubProfile: Codable {
    let id: UUID
    var name: String
}

@MainActor
final class StubBrowserContext: BrowserContext {
    let id: UUID
    private let name: (String) -> Void
    private let stubDownloads: StubDownloads
    var downloads: any Downloads { stubDownloads }
    let preferences: any BrowserContextPreferences
    private let stubExtensions: StubExtensions
    var extensions: any Extensions { stubExtensions }
    private var browsers: [UUID: WeakBrowser] = [:]

    private let isIncognito: Bool

    init(id: UUID, name: @escaping (String) -> Void) {
        self.id = id
        self.name = name
        isIncognito = false
        stubDownloads = StubDownloads()
        preferences = StubPreferences()
        stubExtensions = StubExtensions()
    }

    /// An incognito context, on its profile's preferences and extensions. Its downloads are its own, and the stub
    /// keeps them listed after its windows have closed, where the engine drops them.
    init(sharingWith parent: StubBrowserContext) {
        id = parent.id
        name = parent.name
        isIncognito = true
        stubDownloads = StubDownloads()
        preferences = parent.preferences
        stubExtensions = parent.stubExtensions
    }

    func setUserVisibleName(_ name: String) { self.name(name) }

    func makePage(windowID: UUID, restoring sessionID: PageSessionID?) async -> (page: any Page, restored: Bool)? {
        if let sessionID,
            let page = StubPage.restore(
                sessionID, id: UUID(), windowID: windowID, downloads: stubDownloads, extensions: stubExtensions)
        {
            return (page, true)
        }
        let page = StubPage(id: UUID(), windowID: windowID, downloads: stubDownloads, extensions: stubExtensions)
        page.isIncognito = isIncognito
        return (page, false)
    }

    func browser(windowID: UUID) -> any Browser {
        if let browser = browsers[windowID]?.browser { return browser }
        let browser = StubBrowser(windowID: windowID, extensions: stubExtensions, downloads: stubDownloads)
        browsers = browsers.filter { $0.value.browser != nil }
        browsers[windowID] = WeakBrowser(browser: browser)
        return browser
    }

    func makeAutocomplete() -> any Autocomplete { StubAutocomplete(preferences: preferences) }

    /// The stub's remembered pages whose URL or title holds every word of `text`, in their order.
    func history(matching text: String, maxResults: Int) async -> [HistoryEntry] {
        let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }
        let found = StubAutocomplete.history.filter { page in
            words.allSatisfy { (page.url + " " + page.title).lowercased().contains($0) }
        }
        return found.prefix(maxResults).compactMap { page in
            URL(string: page.url).map { HistoryEntry(url: $0, title: page.title) }
        }
    }

    func favicon(forPageAt url: URL) async -> NSImage? { StubPage.icon(for: url) }

    func changedSiteSettings(for url: URL) -> [SiteSetting]? {
        guard let host = url.host() else { return [] }
        return SiteSettingType.allCases.compactMap { type in
            StubPage.siteSettings["\(host) \(type)"].map { SiteSetting(type: type, value: $0) }
        }
    }

    func setSiteSetting(_ type: SiteSettingType, to value: SiteSettingValue, for url: URL) {
        guard let host = url.host() else { return }
        StubPage.siteSettings["\(host) \(type)"] = value == .default ? nil : value
    }
}

private struct WeakBrowser {
    weak var browser: StubBrowser?
}

@MainActor
@Observable
final class StubPreferences: BrowserContextPreferences {
    var downloadDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    var asksWhereToSaveDownloads = false
    /// As a profile Arc makes: its popular site searches from the start.
    private(set) var searchEngines =
        [
            SearchEngine(name: "Google", keyword: "google.com", url: "https://www.google.com/search?q={searchTerms}"),
            SearchEngine(name: "DuckDuckGo", keyword: "duckduckgo.com", url: "https://duckduckgo.com/?q={searchTerms}"),
            SearchEngine(
                name: "Microsoft Bing", keyword: "bing.com", url: "https://www.bing.com/search?q={searchTerms}"),
        ] + SearchEngine.enginesToAutoActivate.map(\.engine)
    private(set) var defaultSearchEngine: SearchEngine?
    var includesSearchSuggestions = true

    init() { defaultSearchEngine = searchEngines.first }

    func setDefaultSearchEngine(_ engine: SearchEngine) { defaultSearchEngine = engine }

    func addSearchEngine(_ engine: SearchEngine) {
        if !searchEngines.contains(where: { $0.keyword == engine.keyword }) { searchEngines.append(engine) }
    }
}

/// What you typed, some remembered pages and one suggestion, in Chromium's order: the first 8 as its combined result,
/// all of them as the providers' own.
@MainActor
@Observable
final class StubAutocomplete: Autocomplete {
    private(set) var matches: [AutocompleteMatch] = []
    private(set) var additionalMatches: [AutocompleteMatch] = []
    private(set) var input: AutocompleteInput?
    private(set) var isDone = true
    @ObservationIgnored private let preferences: any BrowserContextPreferences
    @ObservationIgnored private var deleted: Set<String> = []

    static let history: [(title: String, url: String, visits: Int)] =
        [
            ("Apple", "https://www.apple.com/", 12),
            ("Google", "https://www.google.com/", 9),
            ("Wikipedia, the free encyclopedia", "https://en.wikipedia.org/wiki/Main_Page", 7),
            ("GitHub", "https://github.com/", 30),
            ("Hacker News", "https://news.ycombinator.com/", 4),
            ("Example Domain", "https://example.com/", 1),
        ] + (1...12).map { ("Field Notes \($0)", "https://notes.example/\($0)", $0) }

    init(preferences: any BrowserContextPreferences) { self.preferences = preferences }

    func start(_ input: AutocompleteInput) {
        if input != self.input { self.input = input }
        let text = input.text.trimmingCharacters(in: .whitespaces)
        var result: [AutocompleteMatch] = []
        func add(
            _ kind: AutocompleteMatch.Kind, _ contents: String, _ description: String = "", url: URL?,
            relevance: Int, inline: String = "", deletable: Bool = false, visits: Int? = nil
        ) {
            result.append(
                AutocompleteMatch(
                    id: result.count, kind: kind, contents: contents, description: description, url: url,
                    fillIntoEdit: url?.absoluteString ?? contents, inlineAutocompletion: inline,
                    relevance: relevance, allowedToBeDefault: result.isEmpty, isDeletable: deletable,
                    typedCount: visits.map { _ in 0 }, visitCount: visits,
                    lastVisited: visits.map { Date(timeIntervalSinceNow: -86_400 / Double($0)) }))
        }
        guard !text.isEmpty else { return update([]) }
        if let keyword = input.keyword {
            let engine = preferences.searchEngines.first { $0.keyword == keyword }
            add(.searchOtherEngine, text, url: engine.flatMap { search(text, in: $0.url) }, relevance: 1300)
            return update(result)
        }
        let lowered = text.lowercased()
        let remembered = Self.history.filter {
            !deleted.contains($0.url)
                && ($0.title.lowercased().contains(lowered) || $0.url.lowercased().contains(lowered))
        }
        let typedURL = Self.url(from: text)
        if let typedURL { add(.urlWhatYouTyped, text, url: typedURL, relevance: 1400) }
        if let first = remembered.first, !input.preventsInlineAutocomplete,
            let host = URL(string: first.url)?.host(), host.hasPrefix(lowered)
        {
            add(
                .historyURL, first.url, first.title, url: URL(string: first.url), relevance: 1410,
                inline: String(host.dropFirst(lowered.count)), deletable: true, visits: first.visits)
        }
        add(.searchWhatYouTyped, text, url: search(text), relevance: typedURL == nil ? 1300 : 1200)
        for page in remembered where !result.contains(where: { $0.url?.absoluteString == page.url }) {
            add(
                .historyTitle, page.url, page.title, url: URL(string: page.url), relevance: 900, deletable: true,
                visits: page.visits)
        }
        if preferences.includesSearchSuggestions {
            add(.searchSuggest, "\(text) news", url: search("\(text) news"), relevance: 600)
        }
        update(result)
    }

    func stop() {}

    func delete(_ match: AutocompleteMatch) {
        guard match.isDeletable, let url = match.url?.absoluteString else { return }
        deleted.insert(url)
        update(additionalMatches.filter { $0.url?.absoluteString != url })
    }

    private func update(_ result: [AutocompleteMatch]) {
        func match(_ match: AutocompleteMatch, id: Int, rank: Int?) -> AutocompleteMatch {
            AutocompleteMatch(
                id: id, kind: match.kind, contents: match.contents, description: match.description, url: match.url,
                fillIntoEdit: match.fillIntoEdit, inlineAutocompletion: match.inlineAutocompletion,
                relevance: match.relevance, allowedToBeDefault: rank == 1, isDeletable: match.isDeletable,
                chromiumRank: rank, typedCount: match.typedCount, visitCount: match.visitCount,
                lastVisited: match.lastVisited)
        }
        let combined = result.prefix(8).enumerated().map { match($1, id: $0, rank: $0 + 1) }
        let additional = result.enumerated().map { match($1, id: combined.count + $0, rank: nil) }
        if combined != matches { matches = combined }
        if additional != additionalMatches { additionalMatches = additional }
    }

    private func search(_ text: String, in template: String? = nil) -> URL? {
        let template =
            template ?? preferences.defaultSearchEngine?.url ?? "https://www.google.com/search?q={searchTerms}"
        let terms = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        return URL(string: template.replacingOccurrences(of: "{searchTerms}", with: terms))
    }

    private static func url(from text: String) -> URL? {
        if let url = URL(string: text), url.scheme != nil, url.host() != nil || url.scheme == "file" { return url }
        guard !text.contains(" "), text.contains(".") else { return nil }
        return URL(string: "https://\(text)")
    }
}
