import AppKit
import SwiftUI

/// Arc's `LittleBrowserWindow`, a panel as Arc's is.
final class LittleBrowserWindow: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: LittleBrowserFrame.barSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        hidesOnDeactivate = false
        isFloatingPanel = false
        becomesKeyOnlyIfNeeded = false
        isExcludedFromWindowsMenu = false
        collectionBehavior = [.managed, .fullScreenPrimary]
        isMovableByWindowBackground = false
    }

    var onCancel: () -> Void = {}

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// A panel's own Escape closes it. Arc's override calls that and then its Escape action; what the two do to a
    /// page's window wasn't seen there, so keeping the window is Oa's own.
    override func cancelOperation(_ sender: Any?) { onCancel() }
}

/// Arc's `LittleWindowViewController`.
final class LittleWindowViewController: NSViewController {
    private let model: WindowModel

    init(model: WindowModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let content = NSHostingView(rootView: LittleWindowView(model: model))
        content.sizingOptions = []
        content.autoresizingMask = [.width, .height]
        view = KeyboardShortcutInterceptionView(keyBindings: model.keyBindings)
        view.addSubview(content)
    }
}
