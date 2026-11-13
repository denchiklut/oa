import AppKit
import DevKit

/// Arc's extension popup as measured (arc-extensions.md §8b): a titled window with no title, 50 pt in from the
/// browser window's right edge and 10 pt below its top whichever button opened it, sized to the popup's page, closed
/// when it stops being the key window. The page fills the content area under a standard title bar, which leaves the
/// window 4 pt shorter than Arc's for the same page.
@MainActor
final class ExtensionPopupWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var popup: ExtensionPopup?
    private var closePopup: () -> Void = {}

    func show(_ popup: ExtensionPopup, over parent: NSWindow, close: @escaping () -> Void) {
        closePopup = close
        if self.popup !== popup {
            self.close()
            self.popup = popup
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: popup.size), styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.delegate = self
            popup.view.frame = NSRect(origin: .zero, size: popup.size)
            popup.view.autoresizingMask = [.width, .height]
            window.contentView?.addSubview(popup.view)
            self.window = window
        }
        guard let window else { return }
        let size = window.frameRect(forContentRect: NSRect(origin: .zero, size: popup.size)).size
        let origin = NSPoint(x: parent.frame.maxX - 50 - size.width, y: parent.frame.maxY - 10 - size.height)
        window.setFrame(NSRect(origin: origin, size: size), display: true)
        if !window.isVisible {
            window.makeKeyAndOrderFront(nil)
            popup.focus()
        }
    }

    func close() {
        guard let window else { return }
        self.window = nil
        window.delegate = nil
        popup?.view.removeFromSuperview()
        popup = nil
        window.close()
    }

    func windowDidResignKey(_ notification: Notification) { closePopup() }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        closePopup()
        return false
    }
}
