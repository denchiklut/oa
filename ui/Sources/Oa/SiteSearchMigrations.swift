import DevKit
import Foundation

/// As Arc's `SiteSearchMigrations`: its popular site searches go to every profile once per installation, and to each
/// profile made after.
@MainActor
enum SiteSearchMigrations {
    private static let seededKey = "seededPopularSiteSearches"

    /// The stub lists only the profiles made through it, so the flag waits for an engine that lists them all.
    static func seedOnce(in engine: any BrowserApplication) {
        guard engine.listsEveryProfile, !UserDefaults.standard.bool(forKey: seededKey) else { return }
        for profileID in engine.allProfiles() { seed(engine.browserContext(id: profileID)) }
        UserDefaults.standard.set(true, forKey: seededKey)
    }

    static func seed(_ context: any BrowserContext) {
        for site in SearchEngine.enginesToAutoActivate { context.preferences.addSearchEngine(site.engine) }
    }
}
