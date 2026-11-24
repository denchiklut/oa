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

    /// Shows and closes the page's window as its DevTools' display changes, for the page's life.
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
        guard page.devTools.display == .undocked, let view = page.devTools.view else {
            return pageClosed(page.id)
        }
        let controller = windows[page.id] ?? DevToolsWindowController(page: page)
        windows[page.id] = controller
        controller.show(view)
    }

    private init(page: any Page) {
        self.page = page
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 512, height: 544),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Developer Tools"
        window.isReleasedWhenClosed = false
        // As measured in Arc: 512 × 544 until moved or resized, then the last frame of any page's window.
        window.setFrame(NSRect(x: 0, y: 0, width: 512, height: 544), display: false)
        if !window.setFrameUsingName(Self.frameName) { window.center() }
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    private func show(_ view: NSView) {
        guard let window, let content = window.contentView else { return }
        if view.superview !== content {
            view.removeFromSuperview()
            view.translatesAutoresizingMaskIntoConstraints = true
            view.frame = content.bounds
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
