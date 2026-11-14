import AppKit
import SwiftUI

/// Arc keeps the system's window buttons and moves them into the sidebar's header: their centres are 24 pt below the
/// window's top, at x 20, 43 and 66.
@MainActor
final class WindowButtons {
    private static let centers: [CGFloat] = [20, 43, 66]
    private static let centerY: CGFloat = 24

    private weak var window: NSWindow?
    private let buttons: [NSButton]

    init(window: NSWindow) {
        self.window = window
        buttons = [.closeButton, .miniaturizeButton, .zoomButton].compactMap(window.standardWindowButton)
        // AppKit puts them back whenever it lays the title bar out (a resize, a new title, a return from full
        // screen) and tells no one. This runs after it in the same pass of the run loop, before the window draws.
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, 0) {
            [weak self] observer, _ in
            guard let self else { return CFRunLoopObserverInvalidate(observer) }
            MainActor.assumeIsolated { self.place() }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        place()
    }

    private func place() {
        guard let window, !window.styleMask.contains(.fullScreen),
            let container = buttons.first?.superview?.superview, container.window === window,
            let frame = container.superview
        else { return }
        // The title bar is shorter than the header and would clip them.
        let height = 2 * Self.centerY
        let bar = NSRect(x: 0, y: frame.bounds.height - height, width: frame.bounds.width, height: height)
        if container.frame != bar { container.frame = bar }
        for (button, x) in zip(buttons, Self.centers) {
            guard let parent = button.superview else { continue }
            let center = parent.convert(NSPoint(x: x, y: window.frame.height - Self.centerY), from: nil)
            let origin = NSPoint(x: center.x - button.frame.width / 2, y: center.y - button.frame.height / 2)
            if button.frame.origin != origin { button.setFrameOrigin(origin) }
        }
    }
}

/// Where the window's title bar would be. As on a title bar, a click makes the window key, a drag moves it, and a
/// double-click does what System Settings asks of a title bar's, zooming by default.
struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ view: NSView, context: Context) {}

    /// Handles the mouse itself: left to the window server (`mouseDownCanMoveWindow`), the click never reaches the
    /// app, so a background window doesn't become key and its page doesn't move to it.
    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return super.mouseDown(with: event) }
            if !window.isKeyWindow { window.makeKeyAndOrderFront(nil) }
            guard event.clickCount == 2 else { return window.performDrag(with: event) }
            // System Settings ▸ Desktop & Dock. Fill has no public API, so it zooms.
            let defaults = UserDefaults.standard
            switch defaults.string(forKey: "AppleActionOnDoubleClick") {
            case "Minimize": window.performMiniaturize(nil)
            case "None": break
            case nil where defaults.bool(forKey: "AppleMiniaturizeOnDoubleClick"): window.performMiniaturize(nil)
            default: window.performZoom(nil)
            }
        }
    }
}
