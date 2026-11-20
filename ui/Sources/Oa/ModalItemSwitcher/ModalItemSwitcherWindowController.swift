import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Arc's `ModalItemSwitcherWindowController`. While the switcher is up a local monitor takes every key, so the
/// panel never needs the keyboard: a borderless child window centred on the browser window, shown 0.1 s after the
/// shortcut so that a quick tap switches with nothing on screen.
@MainActor
final class ModalItemSwitcherWindowController {
    private static let presentationDelay = 0.1
    /// Arc's second key for backward, which is no binding.
    private static let alternatePreviousShortcut = ARCKeyboardShortcut(key: "`", modifiers: .control)

    private let model: WindowModel
    private let switcher: ModalItemSwitcher
    /// As Arc's state holds them: the two bindings as they were when the switcher came up.
    private let nextShortcut: ARCKeyboardShortcut?
    private let previousShortcut: ARCKeyboardShortcut?
    private weak var parent: NSWindow?
    private var window: NSWindow?
    private var monitor: Any?
    private var presentationTimer: Timer?
    private var resignObservers: [NSObjectProtocol] = []
    private var pointerWhenShown = NSPoint.zero

    init(model: WindowModel, switcher: ModalItemSwitcher, parent: NSWindow) {
        self.model = model
        self.switcher = switcher
        self.parent = parent
        nextShortcut = model.keyBindings.state.shortcut(for: ModalItemSwitcher.cycleNextTabID)
        previousShortcut = model.keyBindings.state.shortcut(for: ModalItemSwitcher.cyclePreviousTabID)
    }

    private var shortcuts: [ARCKeyboardShortcut] {
        [nextShortcut, previousShortcut, Self.alternatePreviousShortcut].compactMap { $0 }
    }

    /// As Arc's, which tests the modifiers of its shortcuts together: with all of them up already, the tap commits
    /// at once, and with the default keys Shift alone still down keeps the switcher until it goes.
    func beginObservingEvents() {
        let held = shortcuts.reduce(into: NSEvent.ModifierFlags()) { $0.formUnion($1.modifiers) }
        guard !NSEvent.modifierFlags.isDisjoint(with: held) else { return complete(selecting: true) }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handle(event)
            return nil
        }
        // Arc's ends on the app resigning active. Oa's own, where Arc's is unknown: also on its window giving up the
        // keyboard, so that the monitor doesn't take another window's keys.
        var endings: [(NSNotification.Name, AnyObject?)] = [(NSApplication.didResignActiveNotification, nil)]
        if let parent { endings.append((NSWindow.didResignKeyNotification, parent)) }
        resignObservers = endings.map { name, object in
            NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.complete(selecting: false) }
            }
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
        resignObservers.forEach(NotificationCenter.default.removeObserver)
        resignObservers = []
        guard let window else { return }
        self.window = nil
        window.parent?.removeChildWindow(window)
        window.orderOut(nil)
    }

    private func complete(selecting: Bool) {
        presentationTimer?.invalidate()
        model.dismissModalItemSwitcher(selecting: selecting ? switcher.focusedItemID : nil)
    }

    /// As Arc's monitor: the modifiers of any of its shortcuts keep the switcher, any other change of modifiers
    /// commits, and a key it has no use for is swallowed.
    private func handle(_ event: NSEvent) {
        guard event.type == .keyDown else {
            let modifiers = event.modifierFlags.intersection(ARCKeyboardShortcut.modifierMask)
            if !shortcuts.contains(where: { $0.modifiers == modifiers }) { complete(selecting: true) }
            return
        }
        let shortcut = ARCKeyboardShortcut(event: event)
        if let shortcut, shortcut == nextShortcut { return switcher.focusAdjacentItem(1) }
        if let shortcut, shortcut == previousShortcut || shortcut == Self.alternatePreviousShortcut {
            return switcher.focusAdjacentItem(-1)
        }
        switch Int(event.keyCode) {
        case kVK_RightArrow: switcher.focusAdjacentItem(1)
        case kVK_LeftArrow: switcher.focusAdjacentItem(-1)
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

    /// As Arc's cards, which follow the pointer's moves and not its presence (ARCUI's `onMouseMove`): a card that
    /// comes up under a pointer at rest doesn't take the focus.
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
