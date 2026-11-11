import AppKit
import Foundation

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

    init(id: UUID) { self.id = id }

    func makePage(windowID: UUID, restoring sessionID: PageSessionID?) async -> (page: any Page, restored: Bool)? {
        if let sessionID, let page = StubPage.restore(sessionID, id: UUID(), windowID: windowID) { return (page, true) }
        return (StubPage(id: UUID(), windowID: windowID), false)
    }

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
