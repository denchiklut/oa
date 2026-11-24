import AppKit
import DevKit

/// As Arc's `WebDialogFeature.WebDialogWindowController`: the engine's dialog in a window of its own, begun as a sheet
/// on the page's window at the dialog's size.
@MainActor
final class WebDialogWindowController: NSWindowController {
    let dialog: WebDialog

    init(dialog: WebDialog) {
        self.dialog = dialog
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: dialog.preferredSize),
            styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = dialog.title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.setAccessibilityTitle(dialog.accessibleTitle)
        window.contentMinSize = dialog.minimumSize
        let content = NSView(frame: NSRect(origin: .zero, size: dialog.preferredSize))
        dialog.view.removeFromSuperview()
        dialog.view.translatesAutoresizingMaskIntoConstraints = true
        dialog.view.frame = content.bounds
        dialog.view.autoresizingMask = [.width, .height]
        content.addSubview(dialog.view)
        window.contentView = content
        super.init(window: window)
        // As Arc's: the frame is saved under this name, and each showing takes the dialog's size again.
        windowFrameAutosaveName = "webDialogWindowAutosaveFrame"
        window.setContentSize(dialog.preferredSize)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func begin(on parent: NSWindow) {
        guard let window else { return }
        parent.beginSheet(window)
    }

    func end() {
        guard let window else { return }
        window.sheetParent?.endSheet(window)
        window.orderOut(nil)
        if dialog.view.superview === window.contentView { dialog.view.removeFromSuperview() }
    }
}
