import AppKit
import DevKit

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    /// Slice 1 uses one profile; the profile list and its UI come later.
    static let defaultContextID = UUID(uuidString: "6B0F3E1A-0A5C-4F7B-9C1D-0A0A0A0A0A01")!

    private let engine: any BrowserApplication
    private var windows: [BrowserWindowController] = []
    private var mainMenu: MainMenu?
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
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        openWindow()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows && windows.isEmpty { openWindow() }
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        for window in windows { window.closeAllTabs() }
        engine.terminate()
        return .terminateLater
    }

    @objc func newWindow(_ sender: Any?) { openWindow() }

    private func openWindow() {
        let context = engine.browserContext(id: Self.defaultContextID)
        let controller = BrowserWindowController(engine: engine, context: context) { [weak self] closed in
            self?.windows.removeAll { $0 === closed }
        }
        let previous = windows.last?.window
        windows.append(controller)
        controller.open(cascadingFrom: previous)
    }
}
