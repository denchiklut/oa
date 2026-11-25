import AppKit
import DevKit
import Observation

/// As Arc's `DevToolsWindowController`: a page's undocked DevTools, in a "Developer Tools" window of its own.
@MainActor
final class DevToolsWindowController: NSWindowController, NSWindowDelegate {
    /// As Arc's `DevToolsManager.devToolsWindows`: one window per page.
    private static var windows: [UUID: DevToolsWindowController] = [:]
    /// Arc's name; its own key reads `Optional(…)` around the bundle ID, a slip Oa doesn't copy.
    private static let frameName = "\(Bundle.main.bundleIdentifier ?? "Oa").devToolsWindowAutosaveFrame"

    private let page: any Page
    private var isClosedByParent = false

    /// Shows and closes the page's window as its DevTools' display changes, for the page's life. A Little window's
    /// page has them undocked because the engine doesn't dock a popup browser's, as ArcCore's.
    static func follow(_ page: any Page) {
        withObservationTracking {
            update(page)
        } onChange: { [followed = FollowedPage(page)] in
            Task { @MainActor in
                if let page = followed.page { follow(page) }
            }
        }
    }

    static func pageClosed(_ pageID: UUID) {
        windows[pageID]?.closeByParent()
    }

    private static func update(_ page: any Page) {
        guard page.devTools.display == .undocked, let view = page.devTools.view else { return pageClosed(page.id) }
        let controller = windows[page.id] ?? DevToolsWindowController(page: page)
        windows[page.id] = controller
        controller.show(view)
    }

    private init(page: any Page) {
        self.page = page
        // As Arc's: a 1 × 1 window, as its hosting view makes it, centred unless a frame was saved, then grown to
        // 512 × 544 from its top left, so a first window opens a little right of the screen's middle.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered,
            defer: false)
        window.isOpaque = false
        window.collectionBehavior = .fullScreenAuxiliary
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.title = "Developer Tools"
        window.isReleasedWhenClosed = false
        if !window.setFrameUsingName(Self.frameName) {
            window.center()
            let top = window.frame.maxY
            window.setFrame(NSRect(x: window.frame.minX, y: top - 544, width: 512, height: 544), display: false)
        }
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    private func show(_ view: NSView) {
        guard let window, let content = window.contentView else { return }
        if view.superview !== content {
            view.removeFromSuperview()
            view.translatesAutoresizingMaskIntoConstraints = true
            view.frame = content.convert(window.contentLayoutRect, from: nil)
            view.autoresizingMask = [.width, .height]
            content.addSubview(view)
        }
        guard !window.isVisible else { return }
        showWindow(nil)
        page.devTools.focus()
    }

    private func closeByParent() {
        isClosedByParent = true
        close()
    }

    /// As Arc's: ⌥⌘I and F12 close the window they're pressed in.
    @objc func toggleDevTools(_ sender: Any?) { page.devTools.setOpen(false) }

    func windowDidMove(_ notification: Notification) { window?.saveFrame(usingName: Self.frameName) }
    func windowDidResize(_ notification: Notification) { window?.saveFrame(usingName: Self.frameName) }

    func windowWillClose(_ notification: Notification) {
        Self.windows[page.id] = nil
        if !isClosedByParent { page.devTools.setOpen(false) }
    }
}

/// Read back on the main actor only.
private final class FollowedPage: @unchecked Sendable {
    weak var page: (any Page)?

    init(_ page: any Page) { self.page = page }
}
