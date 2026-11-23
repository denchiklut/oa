import AppKit
import Darwin
import DevKit
import Foundation

/// The live engine: Chromium through OaCore inside the app bundle's framework. Chromium's run loop drives AppKit.
@MainActor
public final class ChromiumBrowserApplication: BrowserApplication {
    private let main: CoreMain
    private let arguments: [String]
    private var engine: CoreEngine?
    private var contexts: [UUID: ChromiumBrowserContext] = [:]
    /// As ADK's `deletedProfiles`: Chromium still lists a profile until it has unloaded it.
    private var deletedProfiles: Set<UUID> = []
    private let dataDirectory: URL
    public lazy var adBlocker = AdBlocker(
        directory: dataDirectory,
        apply: { [weak self] texts in
            guard let engine = self?.engine else { return false }
            return await withCheckedContinuation { continuation in
                engine.setBlockLists(texts) { continuation.resume(returning: $0) }
            }
        },
        exclude: { [weak self] hosts in self?.engine?.setAdBlockExcludedHosts(hosts) }
    )

    /// Loads the framework from the app bundle, or nil when the bundle has none. Call it before the process starts a
    /// second thread: PartitionAlloc installs its allocator when the framework loads.
    public static func bundled(userDataDirectory: URL) -> ChromiumBrowserApplication? {
        guard
            let frameworks = Bundle.main.privateFrameworksURL,
            case let path = frameworks.appendingPathComponent("Chromium Framework.framework/Chromium Framework").path,
            FileManager.default.fileExists(atPath: path)
        else { return nil }
        guard let library = dlopen(path, RTLD_LAZY | RTLD_LOCAL | RTLD_FIRST) else {
            FileHandle.standardError.write(Data("oa: dlopen \(path): \(String(cString: dlerror()))\n".utf8))
            return nil
        }
        guard let symbol = dlsym(library, "OACoreMain") else {
            FileHandle.standardError.write(Data("oa: the framework has no OACoreMain\n".utf8))
            return nil
        }
        return ChromiumBrowserApplication(
            main: unsafeBitCast(symbol, to: CoreMain.self), userDataDirectory: userDataDirectory)
    }

    private init(main: CoreMain, userDataDirectory: URL) {
        self.main = main
        dataDirectory = userDataDirectory.deletingLastPathComponent()
        arguments = CommandLine.arguments + ["--user-data-dir=\(userDataDirectory.path)", "--use-mock-keychain"]
    }

    public func run(ready: @escaping @MainActor () -> Void) -> Int32 {
        let start = Start(application: self, ready: ready)
        let context = Unmanaged.passRetained(start).toOpaque()
        defer { Unmanaged<Start>.fromOpaque(context).release() }
        var argv: [UnsafePointer<CChar>?] = arguments.map { UnsafePointer(strdup($0)) } + [nil]
        let callback: CoreReadyCallback = { context, engine in
            let start = Unmanaged<Start>.fromOpaque(context!).takeUnretainedValue()
            let object = Unmanaged<AnyObject>.fromOpaque(engine).takeUnretainedValue()
            MainActor.assumeIsolated { start.engineDidStart(object) }
        }
        return argv.withUnsafeMutableBufferPointer { argv in
            main(Int32(arguments.count), argv.baseAddress!, callback, context)
        }
    }

    public func saveSessionsForQuit() { engine?.saveSessionsForQuit() }

    public func terminate() {
        NSApplication.shared.reply(toApplicationShouldTerminate: false)
        engine?.quit()
    }

    public func browserContext(id: UUID) -> any BrowserContext {
        if let context = contexts[id] { return context }
        let context = ChromiumBrowserContext(
            id: id, profile: { [weak self] in self?.engine?.profile(identifier: id.uuidString) })
        contexts[id] = context
        return context
    }

    public let listsEveryProfile = true

    public func allProfiles() -> [UUID] {
        attributes.compactMap { UUID(uuidString: $0.identifier) }.filter { !deletedProfiles.contains($0) }
    }

    public func userVisibleName(of profileID: UUID) -> String? {
        attributes.first { UUID(uuidString: $0.identifier) == profileID }?.name
    }

    private var attributes: [CoreProfileAttributes] {
        engine?.availableProfileAttributes().map { unsafeBitCast($0, to: CoreProfileAttributes.self) } ?? []
    }

    public func createBrowserContext(userVisibleName: String) async -> UUID? {
        guard let engine else { return nil }
        let identifier = await withCheckedContinuation { continuation in
            engine.createProfile(name: userVisibleName) { continuation.resume(returning: $0) }
        }
        return identifier.flatMap(UUID.init)
    }

    public func deleteBrowserContext(id: UUID) -> Bool {
        guard id != BrowserProfile.initialID, let engine else { return false }
        contexts[id] = nil
        guard engine.deleteProfile(identifier: id.uuidString) else { return false }
        deletedProfiles.insert(id)
        return true
    }

    public func attachWindow(_ window: NSWindow, id: UUID) {
        engine?.attach(window, identifier: id.uuidString)
    }

    public func closeWindow(id: UUID) {
        engine?.closeWindow(identifier: id.uuidString)
    }

    public func askToLeave(windowID: UUID) async -> Bool {
        guard let engine else { return true }
        return await withCheckedContinuation { continuation in
            engine.askToLeaveWindow(identifier: windowID.uuidString) { continuation.resume(returning: $0) }
        }
    }

    @MainActor
    private final class Start {
        let application: ChromiumBrowserApplication
        let ready: @MainActor () -> Void

        init(application: ChromiumBrowserApplication, ready: @escaping @MainActor () -> Void) {
            self.application = application
            self.ready = ready
        }

        func engineDidStart(_ engine: AnyObject) {
            application.engine = unsafeBitCast(engine, to: CoreEngine.self)
            ready()
        }
    }
}

@MainActor
final class ChromiumBrowserContext: BrowserContext {
    let id: UUID
    private let profile: @MainActor () -> CoreProfile?
    private lazy var chromiumDownloads = ChromiumDownloads(core: profile()?.downloads)
    var downloads: any Downloads { chromiumDownloads }
    private lazy var chromiumPreferences = ChromiumPreferences(core: profile()?.preferences)
    var preferences: any BrowserContextPreferences { chromiumPreferences }
    private lazy var chromiumExtensions = ChromiumExtensions(core: profile()?.extensions)
    var extensions: any Extensions { chromiumExtensions }
    /// Weakly, as ADK's `browsers`: the window that asked holds its browser.
    private var browsers: [UUID: WeakBrowser] = [:]

    init(id: UUID, profile: @escaping @MainActor () -> CoreProfile?) {
        self.id = id
        self.profile = profile
    }

    func makePage(windowID: UUID, restoring sessionID: PageSessionID?) async -> (page: any Page, restored: Bool)? {
        guard let profile = profile() else { return nil }
        let delegate = PageDelegate()
        let created = CreatedPage()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            profile.createPage(
                inWindow: windowID.uuidString, restoringSessionID: sessionID?.rawValue ?? -1, delegate: delegate
            ) { page, restored in
                MainActor.assumeIsolated {
                    created.page = page
                    created.restored = restored
                }
                continuation.resume()
            }
        }
        guard let page = created.page else { return nil }
        return (ChromiumPage(id: UUID(), page: page, delegate: delegate), created.restored)
    }

    func restoreLastSession() async -> [RestoredPage] {
        guard let profile = profile() else { return [] }
        let restored = RestoredPages()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            profile.restoreLastSession { ids, pages in
                MainActor.assumeIsolated {
                    restored.pages = zip(ids, pages).map { id, page in
                        RestoredPage(
                            lastSessionID: id.int32Value,
                            page: ChromiumPage(
                                id: UUID(), page: unsafeBitCast(page, to: CorePage.self), delegate: PageDelegate()))
                    }
                }
                continuation.resume()
            }
        }
        return restored.pages
    }

    func makeAutocomplete() -> any Autocomplete {
        ChromiumAutocomplete(core: profile()?.makeAutocomplete())
    }

    func setUserVisibleName(_ name: String) { profile()?.setUserVisibleName(name) }

    func browser(windowID: UUID) -> any Browser {
        if let browser = browsers[windowID]?.browser { return browser }
        let browser = ChromiumBrowser(profile: profile(), windowID: windowID)
        browsers = browsers.filter { $0.value.browser != nil }
        browsers[windowID] = WeakBrowser(browser: browser)
        return browser
    }

    func changedSiteSettings(for url: URL) -> [SiteSetting]? {
        profile()?.changedSiteSettings(for: url)?.compactMap { object in
            let setting = unsafeBitCast(object, to: CoreSiteSetting.self)
            guard let type = SiteSettingType(rawValue: setting.type) else { return nil }
            return SiteSetting(type: type, value: SiteSettingValue(rawValue: setting.value) ?? .default)
        }
    }

    func setSiteSetting(_ type: SiteSettingType, to value: SiteSettingValue, for url: URL) {
        profile()?.setSiteSetting(type.rawValue, to: value.rawValue, for: url)
    }

    func history(matching text: String, maxResults: Int) async -> [HistoryEntry] {
        guard let profile = profile() else { return [] }
        return await withCheckedContinuation { continuation in
            profile.queryHistory(searchText: text, maxResults: maxResults) { entries in
                let entries = MainActor.assumeIsolated {
                    entries.compactMap { object -> HistoryEntry? in
                        let entry = unsafeBitCast(object, to: CoreHistoryEntry.self)
                        return URL(string: entry.url).map { HistoryEntry(url: $0, title: entry.title) }
                    }
                }
                continuation.resume(returning: entries)
            }
        }
    }

    func favicon(forPageAt url: URL) async -> NSImage? {
        guard let profile = profile() else { return nil }
        let icon = FoundIcon()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            profile.favicon(forPageURL: url.absoluteString) { image in
                MainActor.assumeIsolated { icon.image = image }
                continuation.resume()
            }
        }
        return icon.image
    }
}

private struct WeakBrowser {
    weak var browser: ChromiumBrowser?
}

@MainActor
private final class FoundIcon {
    var image: NSImage?
}

@MainActor
private final class CreatedPage {
    var page: CorePage?
    var restored = false
}

@MainActor
private final class RestoredPages {
    var pages: [RestoredPage] = []
}
