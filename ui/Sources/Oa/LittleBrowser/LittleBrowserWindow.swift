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
        collectionBehavior = .managed
        isMovableByWindowBackground = false
    }

    var onCancel: () -> Void = {}
    /// Arc's dismiss, run before the window closes: it calls back once the window may go.
    var dismiss: ((@escaping () -> Void) -> Void)?
    private var isDismissing = false

    override func close() {
        guard !isDismissing else { return }
        guard let dismiss else { return super.close() }
        isDismissing = true
        dismiss { [weak self] in
            self?.dismiss = nil
            self?.isDismissing = false
            self?.orderOut(nil)
            self?.close()
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// While the window covers its screen for a present or a dismiss, menu bar included as Arc's does.
    var coversScreen = false

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        coversScreen ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }

    /// Arc's show. Over a full-screen window on the session's screen the panel joins that Space and leaves the app
    /// as it is; anywhere else it is an ordinary window and the app comes forward on the next turn. Either way it
    /// comes to the active Space, which `makeKey` undoes.
    func show(on screen: NSScreen?, isNew: Bool) {
        let overFullScreen =
            (screen ?? .main)?.hasFullscreenWindow == true && (isNew || !styleMask.contains(.fullScreen))
        if overFullScreen, !isNew { orderOut(nil) }
        setActivates(!overFullScreen)
        collectionBehavior.insert(.moveToActiveSpace)
        if isNew, !overFullScreen { Task { NSApp.activate(ignoringOtherApps: true) } }
        makeKeyAndOrderFront(nil)
        if !isNew, !overFullScreen { Task { NSApp.activate(ignoringOtherApps: true) } }
    }

    private func setActivates(_ activates: Bool) {
        var (mask, behavior) = (styleMask, collectionBehavior)
        if activates {
            mask.remove(.nonactivatingPanel)
            behavior.remove(.fullScreenAuxiliary)
            behavior.insert(.fullScreenPrimary)
        } else {
            mask.insert(.nonactivatingPanel)
            behavior.remove(.fullScreenPrimary)
            behavior.insert(.fullScreenAuxiliary)
        }
        if mask != styleMask { styleMask = mask }
        collectionBehavior = behavior
    }

    /// As Arc's: over every app's windows as it becomes key, and back to the normal level on the next turn.
    override func makeKey() {
        level = .mainMenu
        super.makeKey()
        Task { [weak self] in
            self?.level = .normal
            self?.collectionBehavior.remove(.moveToActiveSpace)
        }
    }

    /// As Arc's: full screen is an ordinary window's, whatever the panel was shown as, and leaving it changes
    /// nothing back.
    override func toggleFullScreen(_ sender: Any?) {
        if !styleMask.contains(.fullScreen) { setActivates(true) }
        super.toggleFullScreen(sender)
    }

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

    let card = ModalV2HostView()

    override func loadView() {
        let content = NSHostingView(rootView: LittleWindowView(model: model))
        content.sizingOptions = []
        content.autoresizingMask = [.width, .height]
        content.wantsLayer = true
        content.layer?.masksToBounds = true
        card.wantsLayer = true
        card.autoresizingMask = [.width, .height]
        card.addSubview(content)
        view = KeyboardShortcutInterceptionView(keyBindings: model.keyBindings)
        view.addSubview(card)
    }
}
