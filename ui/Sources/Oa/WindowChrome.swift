import AppKit
import SwiftUI

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
            window.performTitleBarDoubleClickAction()
        }
    }
}

extension NSWindow {
    /// System Settings ▸ Desktop & Dock. Fill has no public API, so it zooms.
    func performTitleBarDoubleClickAction() {
        let defaults = UserDefaults.standard
        switch defaults.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize": performMiniaturize(nil)
        case "None": break
        case nil where defaults.bool(forKey: "AppleMiniaturizeOnDoubleClick"): performMiniaturize(nil)
        default: performZoom(nil)
        }
    }
}
