import AppKit
import DevKit

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
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
    private static var current: ApplicationDelegate?

    static func start(engine: any BrowserApplication) {
        let delegate = ApplicationDelegate(engine: engine)
        current = delegate
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        application.delegate = delegate
        let menu = MainMenu()
        delegate.mainMenu = menu
        menu.install(in: application)
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
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            await engine.adBlocker.start()
            finishLaunching()
        }
    }

    private func finishLaunching() {
        isLaunching = false
        let saved = store.savedWindows
        if windows.isEmpty {
            if saved.isEmpty { openWindow() } else { saved.forEach { openWindow(restoring: $0) } }
        }
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
            for window in windows { window.model.dropAll(handingOff: false) }
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
    @objc func showSettings(_ sender: Any?) { settings.showWindow(nil) }
    @objc func toggleToolbar(_ sender: Any?) { PageToolbar.isShown.toggle() }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleToolbar(_:)) {
            item.title = PageToolbar.isShown ? "Hide Toolbar" : "Show Toolbar"
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
    /// Settings stays open. A new window when none is open is Oa's own.
    private func openHelp(_ url: URL) {
        let model = frontWindows.first ?? openWindow()
        model.bringToFront()
        model.newTab(url)
    }

    /// As Arc: Settings closes, then the page opens as a new tab at the top of a Space of the profile, in a window
    /// showing one, else in the frontmost window, which moves to one. A profile without a Space gets no page. Which
    /// of its Spaces, and a new window when none is open, are Oa's own.
    private func openSettings(_ page: ChromiumSettings, in profileID: UUID) {
        settings.close()
        guard let space = store.state.spaces.first(where: { $0.profileID == profileID }) else { return }
        let model =
            frontWindows.first { $0.space?.profileID == profileID } ?? frontWindows.first ?? openWindow(on: space.id)
        if model.space?.profileID != profileID { model.selectSpace(space.id) }
        model.bringToFront()
        model.newTab(page.url)
    }

    /// As Arc's + in Settings: the create sheet goes on the last key browser window, which comes forward. With no
    /// browser window there is none.
    private func createProfile() {
        guard let model = frontWindows.first else { return }
        model.bringToFront()
        ProfileDialogUtils.createProfile(in: model)
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
    /// Link in New Window does.
    @discardableResult
    private func openWindow(
        restoring record: WindowRecord? = nil, selecting tabID: UUID? = nil, from source: WindowModel? = nil,
        on spaceID: UUID? = nil
    ) -> WindowModel {
        let key = windows.first { $0.window?.isKeyWindow == true } ?? windows.last
        let spaceID = spaceID ?? (source ?? key?.model)?.selectedSpaceID ?? store.state.spaces[0].id
        let controller = BrowserWindowController(
            id: record?.id ?? UUID(), engine: engine, store: store, downloads: downloads,
            pictureInPicture: pictureInPicture, spaceID: spaceID
        ) { [weak self] closed in
            self?.windows.removeAll { $0 === closed }
        }
        controller.model.openWindow = { [weak self, weak model = controller.model] tabID in
            self?.openWindow(selecting: tabID, from: model)
        }
        let previous = (windows.first { $0.model === source } ?? windows.last)?.window
        windows.append(controller)
        controller.open(cascadingFrom: previous)
        if let record {
            controller.model.restore(record)
        } else {
            if let opener = source ?? key?.model { controller.model.inheritCollapsedPinnedSpaces(from: opener) }
            if let tabID {
                controller.model.select(tabID)
            } else {
                controller.model.showFirst(isOnlyWindow: windows.count == 1)
            }
        }
        return controller.model
    }
}
