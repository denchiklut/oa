import DevKit
import Foundation
import Observation

/// A profile's preferences, kept current by OaCore's reports as ADK's are by ArcCore's preferences observer.
@MainActor
@Observable
final class ChromiumPreferences: BrowserContextPreferences {
    private var directory: URL?
    private var asks = false
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

    fileprivate func changed(_ core: CorePreferences) {
        if core.downloadDirectory != directory { directory = core.downloadDirectory }
        if core.asksWhereToSaveDownloads != asks { asks = core.asksWhereToSaveDownloads }
    }
}

@MainActor
private final class PreferencesDelegate: NSObject, CorePreferencesDelegate {
    weak var preferences: ChromiumPreferences?

    func preferencesDidChange(_ preferences: CorePreferences) { self.preferences?.changed(preferences) }
}
