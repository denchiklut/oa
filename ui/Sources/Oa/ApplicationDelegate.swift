import AppKit
import DevKit

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSWindowRestoration {
    private let engine: any BrowserApplication
    private let store: SidebarStore
    private let downloads: DownloadsStore
    private let pictureInPicture: PictureInPicture
    private var windows: [BrowserWindowController] = []
    private var mainMenu: MainMenu?
    private lazy var restoreData = RestoreDataController(store: store) { Self.relaunch() }
    private lazy var settings = SettingsWindowController(
        engine: engine, store: store, openSettings: { [weak self] in self?.openSettings($0, in: $1) },
        openHelp: { [weak self] in self?.openHelp($0) }, createProfile: { [weak self] in self?.createProfile() },
        frontProfile: { [weak self] in self?.frontWindows.first?.space?.profileID })
    private let spaceNamesWithMissingProfiles: [String]
    private var askingToQuit = false
    private var isLaunching = true
    private var pendingLinks: [URL] = []
    /// The windows AppKit asked back before the app was ready for them.
    private var pendingRestorations: [(id: UUID, completion: (NSWindow?, (any Error)?) -> Void)] = []
    private static var current: ApplicationDelegate?
    /// Oa's own: the first launch with AppKit's restoration has no saved state yet, so `windows.json`'s windows open
    /// once the way they did before.
    private static let restoresWindowsThroughAppKitKey = "restoresWindowsThroughAppKit"

    static func start(engine: any BrowserApplication) {
        let delegate = ApplicationDelegate(engine: engine)
        current = delegate
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        application.delegate = delegate
        let menu = MainMenu()
        delegate.mainMenu = menu
        menu.install(in: application, store: delegate.store)
    }

    private init(engine: any BrowserApplication) {
        self.engine = engine
        store = SidebarStore(directory: AppEngine.dataDirectory)
        spaceNamesWithMissingProfiles = store.resetMissingProfiles(in: engine)
        store.handProfileNames(to: engine)
        downloads = DownloadsStore(engine: engine, sidebar: store)
        pictureInPicture = PictureInPicture(store: store)
        super.init()
        store.didCreateProfile = { [weak self] in self?.settings.profileCreated($0) }
        store.showShortcut = { [weak self] in self?.settings.showShortcuts(selecting: $0) }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        AppAppearance.restore()
        RestoreWindowsPreference.registerAtLaunch()
        engine.setRestoresLastSession(RestoreWindowsPreference.restoresLastSession)
    }

    /// As Arc's `AppDelegate`: AppKit hands back each window it kept, and the window comes back from its record in
    /// `windows.json` once the app is ready. A window with no record isn't restored.
    static func restoreWindow(
        withIdentifier identifier: NSUserInterfaceItemIdentifier, state: NSCoder,
        completionHandler: @escaping (NSWindow?, (any Error)?) -> Void
    ) {
        guard let current, let id = UUID(uuidString: identifier.rawValue) else { return completionHandler(nil, nil) }
        NSApplication.shared.extendStateRestoration()
        current.pendingRestorations.append((id, completionHandler))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            await engine.adBlocker.start()
            finishLaunching()
        }
    }

    private func finishLaunching() {
        isLaunching = false
        SiteSearchMigrations.seedOnce(in: engine)
        let saved = store.savedWindows
        let restoring = pendingRestorations
        pendingRestorations.removeAll()
        for (id, completion) in restoring {
            let window = saved.first { $0.id == id }.flatMap { openWindow(restoring: $0).window }
            completion(window, nil)
            NSApplication.shared.completeStateRestoration()
        }
        let defaults = UserDefaults.standard
        if windows.isEmpty {
            if defaults.bool(forKey: Self.restoresWindowsThroughAppKitKey) || saved.isEmpty {
                openWindow()
            } else {
                saved.forEach { openWindow(restoring: $0) }
            }
        }
        defaults.set(true, forKey: Self.restoresWindowsThroughAppKitKey)
        store.removeContainersWithoutWindows()
        engine.finishedRestoringWindows()
        openExternalLinks(pendingLinks)
        pendingLinks.removeAll()
        store.startAutoArchive()
        NSApplication.shared.activate(ignoringOtherApps: true)
        // From the run loop, so the pages go on working under the alert: they run on the main queue.
        if !spaceNamesWithMissingProfiles.isEmpty {
            perform(#selector(warnAboutMissingProfiles), with: nil, afterDelay: 1)
        }
    }

    /// Arc's alert, with its words and its second's wait after the windows are back.
    @objc private func warnAboutMissingProfiles() {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Oa"
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Missing Profile!"
        alert.informativeText = """
            Looks like one or more of your Profiles is missing from this computer. \(name) has reverted to using \
            your Default profile for space(s):

            \(spaceNamesWithMissingProfiles.joined(separator: ", "))
            """
        alert.runModal()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let links = urls.filter { ["http", "https"].contains($0.scheme?.lowercased()) && $0.host != nil }
        if isLaunching { pendingLinks.append(contentsOf: links) } else { openExternalLinks(links) }
    }

    /// As seen in Arc: in the last key window, switched to the routed Space, Most Recent being the one it shows.
    private func openExternalLinks(_ links: [URL]) {
        guard !links.isEmpty else { return }
        // As seen in Arc: never a Blank or incognito window, even a key one.
        let front = frontWindows.first { $0.sidebarContext == .global } ?? openWindow()
        for url in links {
            front.openRoutedLink(url, in: store.routedSpace(for: url, recent: front.selectedSpaceID))
        }
        front.bringToFront()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !isLaunching && !hasVisibleWindows && windows.isEmpty { openWindow() }
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    /// As Arc: running downloads are asked about first, then the pages; a page whose `beforeunload` handler stays
    /// cancels the quit.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            guard await confirmsCancellingDownloads() else { return sender.reply(toApplicationShouldTerminate: false) }
            for window in windows {
                guard await engine.askToLeave(windowID: window.model.id) else {
                    return sender.reply(toApplicationShouldTerminate: false)
                }
            }
            store.quitting = true
            engine.saveSessionsForQuit()
            store.saveSessionRestorationAndFreeze()
            for window in windows { window.model.archivePeeks() }
            store.saveAndFreeze()
            engine.terminate()
        }
        return .terminateLater
    }

    /// Arc's words and keys: Return closes, Esc keeps browsing. Arc draws its own panel over the key window; a
    /// sheet there is Oa's, as for its quit warning. Closing lets the engine cancel them and delete their partial
    /// files, Oa's own: Arc's stay behind.
    private func confirmsCancellingDownloads() async -> Bool {
        guard !downloads.running.isEmpty else { return true }
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Oa"
        let alert = NSAlert()
        alert.messageText = "Downloads in progress"
        alert.informativeText = "There are downloads in progress. Closing the application will cancel them."
        alert.addButton(withTitle: "Close \(name)")
        alert.addButton(withTitle: "Keep browsing").keyEquivalent = "\u{1b}"
        guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow else {
            return alert.runModal() == .alertFirstButtonReturn
        }
        return await alert.beginSheetModal(for: window) == .alertFirstButtonReturn
    }

    @objc func newWindow(_ sender: Any?) { openWindow() }

    /// As Arc's `onCreateNewBlankWindow`: a window on a sidebar of its own, one Space on the last focused profile;
    /// the command bar opens, as for any new window.
    @objc func blankWindow(_ sender: Any?) {
        openWindow(context: .standalone, profileID: lastFocusedProfileID)
    }

    /// As Arc's `WindowsData.lastFocusedProfile`: the Space's profile of the frontmost window that isn't incognito,
    /// else the default one.
    private var lastFocusedProfileID: UUID {
        frontWindows.first { $0.sidebarContext != .incognito }?.space?.profileID ?? SidebarProfile.defaultID
    }

    /// As Arc's `newIncognitoWindow:`: a window on the incognito context of the last focused profile, as Arc's
    /// `createWindow` takes it for the incognito style, with its own sidebar kept in memory; the command bar opens,
    /// as for any new window.
    @objc func newIncognitoWindow(_ sender: Any?) {
        guard !engine.incognitoDisabled else {
            return NSLog("Oa: attempted to create an incognito window but incognito is disabled.")
        }
        openWindow(context: .incognito, profileID: lastFocusedProfileID)
    }

    /// As Arc's `onOpenLinkInIncognitoWindow`: a new tab at the top of the newest incognito window, whatever its
    /// profile, which comes forward, else of a new one with no command bar.
    private func openLinkInIncognitoWindow(_ url: URL, profileID: UUID) {
        guard !engine.incognitoDisabled else { return }
        let model =
            windows.last { $0.model.sidebarContext == .incognito }?.model
            ?? openWindow(context: .incognito, profileID: profileID, empty: true)
        model.bringToFront()
        model.newTab(url)
    }

    /// As Arc's `createTabInNewWindow(url:isIncognito:)` from a window with a sidebar of its own, as seen in Arc:
    /// an incognito window's link opens a new incognito window, and a Blank Window's a global one on the last key
    /// global window's Space, at the top of its tabs. Either way selected, with no command bar, cascaded from the
    /// source. With no global window open, the first Space is Oa's own.
    private func openURLInNewWindow(_ url: URL, from source: WindowModel) {
        if source.sidebarContext == .incognito {
            openWindow(from: source, context: .incognito, profileID: source.space?.profileID, empty: true).newTab(url)
        } else {
            let spaceID = frontWindows.first { $0.sidebarContext == .global }?.selectedSpaceID
            openWindow(from: source, on: spaceID ?? store.state.spaces[0].id, empty: true).newTab(url)
        }
    }

    @objc func showSettings(_ sender: Any?) { settings.showWindow(nil) }
    @objc func toggleToolbar(_ sender: Any?) { PageToolbar.isShown.toggle() }
    @objc func setAutomaticAppearance(_ sender: Any?) { AppAppearance.set(nil) }
    @objc func setLightAppearance(_ sender: Any?) { AppAppearance.set(.aqua) }
    @objc func setDarkAppearance(_ sender: Any?) { AppAppearance.set(.darkAqua) }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let appearances: [Selector: NSAppearance.Name?] = [
            #selector(setAutomaticAppearance(_:)): nil, #selector(setLightAppearance(_:)): .aqua,
            #selector(setDarkAppearance(_:)): .darkAqua,
        ]
        if let action = item.action, let name = appearances[action] {
            item.state = AppAppearance.current == name ? .on : .off
            // As Arc: not while Settings is key.
            return !(NSApplication.shared.keyWindow?.windowController is SettingsWindowController)
        }
        if item.action == #selector(blankWindow(_:)) || item.action == #selector(newIncognitoWindow(_:)) {
            // As Arc: not while Settings is key, and incognito not while it is disabled.
            guard !(NSApplication.shared.keyWindow?.windowController is SettingsWindowController) else { return false }
            return item.action == #selector(blankWindow(_:))
                || !engine.incognitoDisabled
        }
        if item.action == #selector(toggleToolbar(_:)) {
            item.title = PageToolbar.isShown ? "Hide Toolbar" : "Show Toolbar"
            // As seen in Arc: not while the window shows a split, which has no window toolbar.
            let controller = NSApplication.shared.keyWindow?.windowController as? BrowserWindowController
            return (controller?.model.presentedTabIDs.count ?? 0) < 2
        }
        return true
    }

    /// As Arc: ⌘Q and Quit ask first while the warning is on, before any page is asked; quitting from the Dock or
    /// at logout doesn't.
    @objc func quit(_ sender: Any?) {
        guard QuitWarning.isOn else { return terminateFromRunLoop() }
        guard !askingToQuit else { return }
        askingToQuit = true
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Oa"
        let alert = NSAlert()
        alert.messageText = "Quit \(name)?"
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit, and don't ask again")
        let answer: @MainActor (NSApplication.ModalResponse) -> Void = { [weak self] response in
            self?.askingToQuit = false
            guard response != .alertSecondButtonReturn else { return }
            if response == .alertThirdButtonReturn { QuitWarning.isOn = false }
            self?.terminateFromRunLoop()
        }
        if let window = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow {
            alert.beginSheetModal(for: window) { response in MainActor.assumeIsolated { answer(response) } }
        } else {
            answer(alert.runModal())
        }
    }
    /// Quitting waits on pages' prompts, which run on the main queue, so it starts from the run loop: never inside
    /// the engine's task that delivered ⌘Q from a focused page, nor under a sheet that is still closing.
    private func terminateFromRunLoop() {
        NSApplication.shared.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)
    }

    @objc func restoreData(_ sender: Any?) { restoreData.show() }

    /// As Arc's help links in Settings: a new tab in the frontmost window's Space, which comes forward while
    /// Settings stays open. A new window when none is open, and passing over a window with a sidebar of its own, are
    /// Oa's own.
    private func openHelp(_ url: URL) {
        let model = frontWindows.first { $0.sidebarContext == .global } ?? openWindow()
        model.bringToFront()
        model.newTab(url)
    }

    /// As Arc: Settings closes, except for Advanced's More Settings…, then the page opens as a new tab at the top of a Space of the profile, in a window
    /// showing one, else in the frontmost window, which moves to one. A profile without a Space gets no page. Which
    /// of its Spaces, and a new window when none is open, are Oa's own.
    private func openSettings(_ page: ChromiumSettings, in profileID: UUID) {
        if page != .settings { settings.close() }
        guard let space = store.state.spaces.first(where: { $0.profileID == profileID }) else { return }
        let windows = frontWindows.filter { $0.sidebarContext == .global }
        let model = windows.first { $0.space?.profileID == profileID } ?? windows.first ?? openWindow(on: space.id)
        if model.space?.profileID != profileID { model.selectSpace(space.id) }
        model.bringToFront()
        model.newTab(page.url)
    }

    /// As Arc's + in Settings: the create sheet goes on the last key browser window, which comes forward. With no
    /// browser window there is none. Oa's own: a window with a sidebar of its own is passed over.
    private func createProfile() {
        guard let model = frontWindows.first(where: { $0.sidebarContext == .global }) else { return }
        model.bringToFront()
        ProfileDialogUtils.createProfile(in: model)
    }

    /// As Arc's `moveItemsToGlobalDestination`, in the windows' front-to-back order: the first global window on the
    /// Space, else the first global one, else a new one on the Space with nothing selected and no command bar.
    private func globalWindow(for spaceID: UUID) -> WindowModel {
        let global = frontWindows.filter { $0.sidebarContext == .global }
        return global.first { $0.selectedSpaceID == spaceID } ?? global.first ?? openWindow(on: spaceID, empty: true)
    }

    private var frontWindows: [WindowModel] {
        NSApplication.shared.orderedWindows.compactMap { window in windows.first { $0.window === window }?.model }
    }

    /// Quits and opens the bundle again once this process is gone, with the engine and data directory it was
    /// given, as Arc does after a restore.
    private static func relaunch() {
        let environment = ProcessInfo.processInfo.environment
        var open = ["open", "-n", Bundle.main.bundlePath]
        for key in ["OA_DATA_DIRECTORY", "OA_ENGINE"] {
            if let value = environment[key] { open += ["--env", "\(key)=\(value)"] }
        }
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments =
            [
                "-c",
                "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.1; done; exec \"$@\"",
                "sh",
            ]
            + open
        try? shell.run()
        NSApplication.shared.terminate(nil)
    }

    /// A new window opens on the key window's Space, or on the one asked for. A restored one brings its own
    /// selection. One opened for a tab of `source` opens beside it on its Space and selects the tab, as Arc's Open
    /// Link in New Window does. A window with a sidebar of its own opens on its container's Space, made here unless a
    /// restored record finds it; one whose container is gone comes back global.
    @discardableResult
    private func openWindow(
        restoring record: WindowRecord? = nil, selecting tabID: UUID? = nil, from source: WindowModel? = nil,
        on spaceID: UUID? = nil, context: SidebarContext = .global, profileID: UUID? = nil, empty: Bool = false
    ) -> WindowModel {
        let key = windows.first { $0.window?.isKeyWindow == true } ?? windows.last
        let id = record?.id ?? UUID()
        var context = record?.sidebarContext ?? context
        var spaceID = spaceID
        if let container = context.container(of: id) {
            if let space = store.state.containers[container] {
                spaceID = space.id
            } else if record == nil {
                var space: SidebarSpace?
                store.edit { space = $0.addContainer(container, profileID: profileID ?? SidebarProfile.defaultID) }
                spaceID = space?.id
            } else {
                context = .global
            }
        }
        let openerSpaceID = (source ?? key?.model).flatMap {
            $0.sidebarContext == .global ? $0.selectedSpaceID : nil
        }
        let controller = BrowserWindowController(
            id: id, sidebarContext: context, engine: engine, store: store, downloads: downloads,
            pictureInPicture: pictureInPicture, spaceID: spaceID ?? openerSpaceID ?? store.state.spaces[0].id
        ) { [weak self] closed in
            self?.windows.removeAll { $0 === closed }
        }
        controller.model.openWindow = { [weak self, weak model = controller.model] tabID in
            self?.openWindow(selecting: tabID, from: model)
        }
        controller.model.globalWindow = { [weak self] spaceID in self?.globalWindow(for: spaceID) }
        controller.model.openLinkInIncognitoWindow = { [weak self] url, profileID in
            self?.openLinkInIncognitoWindow(url, profileID: profileID)
        }
        // As seen in Arc: from the key window.
        controller.model.openURLInNewWindow = { [weak self, weak model = controller.model] url in
            if let model { self?.openURLInNewWindow(url, from: model) }
        }
        let previous = (windows.first { $0.model === source } ?? key)?.window
        windows.append(controller)
        controller.open(cascadingFrom: previous)
        if let record {
            controller.model.restore(record)
        } else {
            if let opener = source ?? key?.model { controller.model.inheritCollapsedPinnedSpaces(from: opener) }
            if context != .global {
                if !empty { controller.model.openCommandBar(.newTab) }
            } else if let tabID {
                controller.model.select(tabID)
            } else if !empty {
                controller.model.showFirst(isOnlyWindow: windows.count == 1)
            }
        }
        return controller.model
    }
}
