import AppKit
import DevKit

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    private let engine: any BrowserApplication
    private let store: SidebarStore
    private var windows: [BrowserWindowController] = []
    private var mainMenu: MainMenu?
    private lazy var restoreData = RestoreDataController(store: store) { Self.relaunch() }
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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        store.saveAndFreeze()
        for window in windows { window.model.dropAll() }
        engine.terminate()
        return .terminateLater
    }

    @objc func newWindow(_ sender: Any?) { openWindow() }
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
            id: record?.id ?? UUID(), engine: engine, store: store, spaceID: spaceID
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
