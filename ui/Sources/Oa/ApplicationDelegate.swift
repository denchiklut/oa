import AppKit
import DevKit

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    private let engine: any BrowserApplication
    private let store: SidebarStore
    private let downloads: DownloadsStore
    private var windows: [BrowserWindowController] = []
    private var mainMenu: MainMenu?
    private lazy var restoreData = RestoreDataController(store: store) { Self.relaunch() }
    private lazy var settings = SettingsWindowController()
    private var askingToQuit = false
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
        downloads = DownloadsStore(engine: engine, sidebar: store)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let saved = store.savedWindows
        if saved.isEmpty { openWindow() } else { saved.forEach { openWindow(restoring: $0) } }
        store.startAutoArchive()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows && windows.isEmpty { openWindow() }
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

    /// As Arc: ⌘Q and Quit ask first while the warning is on, before any page is asked; quitting from the Dock or
    /// at logout doesn't.
    @objc func quit(_ sender: Any?) {
        guard QuitWarning.isOn else { return NSApplication.shared.terminate(nil) }
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
            // After the sheet is gone, and from the run loop rather than the main queue: quitting waits on pages'
            // prompts, which run on the main queue.
            NSApplication.shared.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)
        }
        if let window = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow {
            alert.beginSheetModal(for: window) { response in MainActor.assumeIsolated { answer(response) } }
        } else {
            answer(alert.runModal())
        }
    }
    @objc func restoreData(_ sender: Any?) { restoreData.show() }

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

    /// A new window opens on the key window's Space. A restored one brings its own selection.
    private func openWindow(restoring record: WindowRecord? = nil) {
        let key = windows.first { $0.window?.isKeyWindow == true } ?? windows.last
        let spaceID = key?.model.selectedSpaceID ?? store.state.spaces[0].id
        let controller = BrowserWindowController(
            id: record?.id ?? UUID(), engine: engine, store: store, downloads: downloads, spaceID: spaceID
        ) { [weak self] closed in
            self?.windows.removeAll { $0 === closed }
        }
        let previous = windows.last?.window
        windows.append(controller)
        controller.open(cascadingFrom: previous)
        if let record {
            controller.model.restore(record)
        } else {
            controller.model.showFirst(isOnlyWindow: windows.count == 1)
        }
    }
}
