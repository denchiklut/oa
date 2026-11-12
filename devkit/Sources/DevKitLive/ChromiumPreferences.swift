import DevKit
import Foundation
import Observation

/// A profile's preferences, kept current by OaCore's reports as ADK's are by ArcCore's preferences observer.
@MainActor
@Observable
final class ChromiumPreferences: BrowserContextPreferences {
    private var directory: URL?
    private var asks = false
    private(set) var searchEngines: [SearchEngine] = []
    private(set) var defaultSearchEngine: SearchEngine?
    private var suggests = true
    @ObservationIgnored private let core: CorePreferences?
    @ObservationIgnored private let delegate = PreferencesDelegate()

    init(core: CorePreferences?) {
        self.core = core
        delegate.preferences = self
        core?.delegate = delegate
    }

    var downloadDirectory: URL? {
        get { directory }
        set { core?.downloadDirectory = newValue }
    }

    var asksWhereToSaveDownloads: Bool {
        get { asks }
        set { core?.asksWhereToSaveDownloads = newValue }
    }

    var includesSearchSuggestions: Bool {
        get { suggests }
        set { core?.searchSuggestEnabled = newValue }
    }

    func setDefaultSearchEngine(_ engine: SearchEngine) {
        core?.setDefaultSearchEngine(keyword: engine.keyword)
    }

    fileprivate func changed(_ core: CorePreferences) {
        if core.downloadDirectory != directory { directory = core.downloadDirectory }
        if core.asksWhereToSaveDownloads != asks { asks = core.asksWhereToSaveDownloads }
        if core.searchSuggestEnabled != suggests { suggests = core.searchSuggestEnabled }
        let engines = (core.searchEngines ?? []).map { SearchEngine(unsafeBitCast($0, to: CoreSearchEngine.self)) }
        if engines != searchEngines { searchEngines = engines }
        let current = core.defaultSearchEngine.map(SearchEngine.init)
        if current != defaultSearchEngine { defaultSearchEngine = current }
    }
}

@MainActor
private final class PreferencesDelegate: NSObject, CorePreferencesDelegate {
    weak var preferences: ChromiumPreferences?

    func preferencesDidChange(_ preferences: CorePreferences) { self.preferences?.changed(preferences) }
}

extension SearchEngine {
    @MainActor
    fileprivate init(_ core: CoreSearchEngine) {
        self.init(
            name: core.name, keyword: core.keyword, url: core.url, faviconURL: core.faviconURL,
            isPrepopulated: core.isPrepopulated)
    }
}
