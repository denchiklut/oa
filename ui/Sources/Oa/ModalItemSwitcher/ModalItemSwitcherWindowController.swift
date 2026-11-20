import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Arc's `ModalItemSwitcherWindowController`. While the switcher is up a local monitor takes every key, so the
/// panel never needs the keyboard: a borderless child window centred on the browser window, shown 0.1 s after the
/// shortcut so that a quick tap switches with nothing on screen.
@MainActor
final class ModalItemSwitcherWindowController {
    private static let presentationDelay = 0.1

    private let model: WindowModel
    private let switcher: ModalItemSwitcher
    private weak var parent: NSWindow?
    private var window: NSWindow?
    private var monitor: Any?
    private var presentationTimer: Timer?
    private var resignObserver: NSObjectProtocol?
    private var pointerWhenShown = NSPoint.zero

    init(model: WindowModel, switcher: ModalItemSwitcher, parent: NSWindow) {
        self.model = model
        self.switcher = switcher
        self.parent = parent
    }

    /// As Arc's: with the shortcut's modifiers already up, the tap commits at once.
    func beginObservingEvents() {
        guard !NSEvent.modifierFlags.isDisjoint(with: [.control, .shift]) else { return complete(selecting: true) }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handle(event)
            return nil
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.complete(selecting: false) }
        }
        let delay = Self.presentationDelay - Date().timeIntervalSince(switcher.presentationRequestTime)
        guard delay > 0 else { return showWindow() }
        presentationTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.showWindow() }
        }
    }

    func close() {
        presentationTimer?.invalidate()
        monitor.map(NSEvent.removeMonitor)
        monitor = nil
        resignObserver.map(NotificationCenter.default.removeObserver)
        resignObserver = nil
        guard let window else { return }
        self.window = nil
        window.parent?.removeChildWindow(window)
        window.orderOut(nil)
    }

    private func complete(selecting: Bool) {
        presentationTimer?.invalidate()
        model.dismissModalItemSwitcher(selecting: selecting ? switcher.focusedItemID : nil)
    }

    /// As Arc's monitor: Control alone or with Shift keeps the switcher, any other change of modifiers commits, and
    /// a key it has no use for is swallowed.
    private func handle(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.control, .shift, .option, .command])
        guard event.type == .keyDown else {
            if modifiers != .control, modifiers != [.control, .shift] { complete(selecting: true) }
            return
        }
        switch Int(event.keyCode) {
        case kVK_Tab: switcher.focusAdjacentItem(modifiers.contains(.shift) ? -1 : 1)
        case kVK_RightArrow: switcher.focusAdjacentItem(1)
        case kVK_LeftArrow: switcher.focusAdjacentItem(-1)
        case kVK_ANSI_Grave where modifiers == .control: switcher.focusAdjacentItem(-1)
        case kVK_Escape: complete(selecting: false)
        case kVK_ANSI_W: model.close(switcher.focusedItemID)
        default: break
        }
    }

    private func showWindow() {
        guard window == nil, let parent else { return }
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.animationBehavior = .none
        window.appearance = parent.appearance
        window.contentView = NSHostingView(
            rootView: ModalItemSwitcherView(model: model, switcher: switcher) { [weak self] in self?.hover($0) })
        self.window = window
        pointerWhenShown = NSEvent.mouseLocation
        layOut()
        parent.addChildWindow(window, ordered: .above)
    }

    /// Oa's own: a card under a pointer at rest doesn't take the focus from the keys as the panel comes up under it.
    private func hover(_ id: UUID) {
        if NSEvent.mouseLocation != pointerWhenShown { switcher.focus(id) }
    }

    /// As Arc's `windowDidResize:`, which its own change of size reaches: the panel is centred on the browser
    /// window's frame and kept on its screen.
    private func layOut() {
        guard let window, let parent else { return }
        let count = withObservationTracking {
            switcher.visibleItemIDs.count
        } onChange: { [weak self] in
            Task { @MainActor in self?.layOut() }
        }
        let insets = ModalItemSwitcherView.shadowInsets
        var panel = NSRect(
            origin: .zero,
            size: NSSize(width: ModalItemSwitcherView.width(itemCount: count), height: ModalItemSwitcherView.height))
        panel.origin = NSPoint(x: parent.frame.midX - panel.width / 2, y: parent.frame.midY - panel.height / 2)
        if let screen = parent.screen?.frame {
            panel.origin.x = max(screen.minX, min(panel.minX, screen.maxX - panel.width))
            panel.origin.y = max(screen.minY, min(panel.minY, screen.maxY - panel.height))
        }
        let frame = NSRect(
            x: panel.minX - insets.leading, y: panel.minY - insets.bottom,
            width: panel.width + insets.leading + insets.trailing,
            height: panel.height + insets.top + insets.bottom)
        window.setFrame(frame, display: true)
    }
}
