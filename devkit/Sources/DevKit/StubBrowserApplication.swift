import AppKit
import Foundation
import Observation

/// An engine without a web engine: pages are placeholders. UI work runs on it without a Chromium build.
@MainActor
public final class StubBrowserApplication: BrowserApplication {
    private var contexts: [UUID: StubBrowserContext] = [:]

    public init() {}

    public func run(ready: @escaping @MainActor () -> Void) -> Int32 {
        let application = NSApplication.shared
        ready()
        application.run()
        return 0
    }

    public func terminate() {
        NSApplication.shared.reply(toApplicationShouldTerminate: true)
    }

    public func browserContext(id: UUID) -> any BrowserContext {
        if let context = contexts[id] { return context }
        let context = StubBrowserContext(id: id)
        contexts[id] = context
        return context
    }

    public func attachWindow(_ window: NSWindow, id: UUID) {}

    public func closeWindow(id: UUID) {}

    public func askToLeave(windowID: UUID) async -> Bool {
        await StubPage.askToLeave(windowID: windowID)
    }
}

@MainActor
final class StubBrowserContext: BrowserContext {
    let id: UUID
    private let stubDownloads = StubDownloads()
    var downloads: any Downloads { stubDownloads }
    let preferences: any BrowserContextPreferences = StubPreferences()
    private let stubExtensions = StubExtensions()
    var extensions: any Extensions { stubExtensions }
    private var browsers: [UUID: WeakBrowser] = [:]

    init(id: UUID) { self.id = id }

    func makePage(windowID: UUID, restoring sessionID: PageSessionID?) async -> (page: any Page, restored: Bool)? {
        if let sessionID,
            let page = StubPage.restore(
                sessionID, id: UUID(), windowID: windowID, downloads: stubDownloads, extensions: stubExtensions)
        {
            return (page, true)
        }
        return (StubPage(id: UUID(), windowID: windowID, downloads: stubDownloads, extensions: stubExtensions), false)
    }

    func browser(windowID: UUID) -> any Browser {
        if let browser = browsers[windowID]?.browser { return browser }
        let browser = StubBrowser(windowID: windowID, extensions: stubExtensions, downloads: stubDownloads)
        browsers = browsers.filter { $0.value.browser != nil }
        browsers[windowID] = WeakBrowser(browser: browser)
        return browser
    }

    func makeAutocomplete() -> any Autocomplete { StubAutocomplete(preferences: preferences) }

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
    let searchEngines = [
        SearchEngine(name: "Google", keyword: "google.com", url: "https://www.google.com/search?q={searchTerms}"),
        SearchEngine(name: "DuckDuckGo", keyword: "duckduckgo.com", url: "https://duckduckgo.com/?q={searchTerms}"),
        SearchEngine(name: "Microsoft Bing", keyword: "bing.com", url: "https://www.bing.com/search?q={searchTerms}"),
    ]
    private(set) var defaultSearchEngine: SearchEngine?
    var includesSearchSuggestions = true

    init() { defaultSearchEngine = searchEngines.first }

    func setDefaultSearchEngine(_ engine: SearchEngine) { defaultSearchEngine = engine }
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

    private static let history: [(title: String, url: String, visits: Int)] =
        [
            ("Apple", "https://www.apple.com/", 12),
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

    private func search(_ text: String) -> URL? {
        let template = preferences.defaultSearchEngine?.url ?? "https://www.google.com/search?q={searchTerms}"
        let terms = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        return URL(string: template.replacingOccurrences(of: "{searchTerms}", with: terms))
    }

    private static func url(from text: String) -> URL? {
        if let url = URL(string: text), url.scheme != nil, url.host() != nil || url.scheme == "file" { return url }
        guard !text.contains(" "), text.contains(".") else { return nil }
        return URL(string: "https://\(text)")
    }
}
