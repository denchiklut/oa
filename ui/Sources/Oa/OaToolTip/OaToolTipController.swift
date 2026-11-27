import AppKit
import SwiftUI

@MainActor
final class OaToolTipController {
    private static let auxiliaryHosts = NSMapTable<NSWindow, OaToolTipController>.weakToWeakObjects()
    private static let fadeInDuration: TimeInterval = 0.05
    private static let cursorOffset = CGPoint(x: 8, y: 16)
    private static let screenMargin: CGFloat = 8
    /// Oa's own: ignore sub-half-point synthetic jitter while dismissing on any real pointer movement.
    private static let movementThreshold: CGFloat = 0.5

    private struct Entry {
        let id: UUID
        var configuration: OaToolTipConfiguration
        var palette: OaToolTipPalette
        var inSidebar: Bool
        let order: UInt64
    }

    weak var window: NSWindow?
    var canPresent: (Bool) -> Bool = { _ in true }
    private var monitor: Any?

    static func host(for window: NSWindow) -> OaToolTipController {
        if let layout = window.contentViewController as? WindowLayoutController { return layout.toolTipController }
        if let host = auxiliaryHosts.object(forKey: window) { return host }
        let host = OaToolTipController()
        host.window = window
        auxiliaryHosts.setObject(host, forKey: window)
        host.observeAuxiliaryWindow(window)
        return host
    }

    // Popovers and floating panels have their own event window, outside the browser layout controller.
    private func observeAuxiliaryWindow(_ window: NSWindow) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [
            .mouseMoved, .leftMouseDragged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown,
        ]) { [weak self] event in
            if event.type == .mouseMoved { self?.handlePointerMoved() } else { self?.dismiss() }
            return event
        }
        let center = NotificationCenter.default
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification, NSWindow.willMoveNotification] {
            center.addObserver(self, selector: #selector(dismissOnNotification(_:)), name: name, object: window)
        }
        center.addObserver(
            self, selector: #selector(dismissOnNotification(_:)), name: NSApplication.didResignActiveNotification,
            object: nil)
        center.addObserver(
            self, selector: #selector(dismissOnNotification(_:)), name: NSMenu.didBeginTrackingNotification, object: nil
        )
    }

    @objc private func dismissOnNotification(_ notification: Notification) { dismiss() }

    isolated deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    private var entries: [Entry] = []
    private var nextOrder: UInt64 = 0
    private var presentedID: UUID?
    private var timer: Timer?
    private var lastPointerLocation = NSEvent.mouseLocation
    private var panel: NSWindow?

    func register(_ id: UUID, configuration: OaToolTipConfiguration, palette: OaToolTipPalette, inSidebar: Bool = false)
    {
        if let index = entries.firstIndex(where: { $0.id == id }) {
            guard
                entries[index].configuration != configuration || entries[index].palette != palette
                    || entries[index].inSidebar != inSidebar
            else { return }
            entries[index].configuration = configuration
            entries[index].palette = palette
            entries[index].inSidebar = inSidebar
            if presentedID == id { dismiss() }
        } else {
            nextOrder += 1
            entries.append(
                Entry(id: id, configuration: configuration, palette: palette, inSidebar: inSidebar, order: nextOrder))
        }
        lastPointerLocation = NSEvent.mouseLocation
        if presentedID != activeEntry?.id { hidePanel() }
        reschedule()
    }

    func unregister(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries.remove(at: index)
        if presentedID == id { hidePanel() }
        reschedule()
    }

    /// Oa's own: any pointer movement dismisses a visible tooltip at once and restarts the idle wait.
    func handlePointerMoved() {
        let location = NSEvent.mouseLocation
        guard hypot(location.x - lastPointerLocation.x, location.y - lastPointerLocation.y) > Self.movementThreshold
        else { return }
        lastPointerLocation = location
        hidePanel()
        reschedule()
    }

    /// Dismisses any visible tooltip and cancels pending timers, without dropping hovered registrations so idling
    /// again after a transition still works once the pointer settles.
    func dismiss() {
        timer?.invalidate()
        timer = nil
        hidePanel()
    }

    func tearDown() {
        entries.removeAll()
        dismiss()
        panel = nil
    }

    private var activeEntry: Entry? {
        entries.max { lhs, rhs in
            if lhs.configuration.priority != rhs.configuration.priority {
                return lhs.configuration.priority < rhs.configuration.priority
            }
            return lhs.order < rhs.order
        }
    }

    private func reschedule() {
        timer?.invalidate()
        timer = nil
        guard presentedID == nil, let entry = activeEntry, canPresent(entry.inSidebar) else { return }
        let targetID = entry.id
        timer = Timer.scheduledTimer(withTimeInterval: entry.configuration.delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.presentIfEligible(targetID) }
        }
    }

    private func presentIfEligible(_ targetID: UUID) {
        timer = nil
        guard let parent = window, parent.isVisible,
            parent.isKeyWindow || monitor != nil, NSApp.isActive || parent.styleMask.contains(.nonactivatingPanel),
            NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0) == parent.windowNumber,
            NSEvent.pressedMouseButtons == 0, let entry = activeEntry, entry.id == targetID, canPresent(entry.inSidebar)
        else { return }
        let pointer = NSEvent.mouseLocation
        guard hypot(pointer.x - lastPointerLocation.x, pointer.y - lastPointerLocation.y) <= Self.movementThreshold
        else {
            lastPointerLocation = pointer
            return reschedule()
        }
        show(entry, at: pointer, over: parent)
    }

    private func show(_ entry: Entry, at pointer: NSPoint, over parent: NSWindow) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.appearance = parent.effectiveAppearance

        let insets = OaToolTipView.shadowInsets
        let hosting = NSHostingController(
            rootView: OaToolTipView(
                configuration: entry.configuration, pinchedCorner: .topLeading, palette: entry.palette))
        let maxProposal = CGSize(
            width: OaToolTipView.maxWidth + insets.left + insets.right,
            height: CGFloat.greatestFiniteMagnitude
        )
        let fullSize = hosting.sizeThatFits(in: maxProposal)
        let bubbleSize = CGSize(
            width: max(fullSize.width - insets.left - insets.right, 1),
            height: max(fullSize.height - insets.top - insets.bottom, 1)
        )

        let screenFrame = (parent.screen ?? NSScreen.main)?.visibleFrame ?? parent.frame
        let placement = place(bubbleSize: bubbleSize, pointer: pointer, in: screenFrame)
        if placement.corner != .topLeading {
            hosting.rootView = OaToolTipView(
                configuration: entry.configuration, pinchedCorner: placement.corner, palette: entry.palette)
        }

        let windowOrigin = NSPoint(
            x: placement.bubbleFrame.minX - insets.left,
            y: placement.bubbleFrame.minY - insets.bottom
        )
        hosting.sizingOptions = []
        panel.contentViewController = hosting
        panel.setFrame(NSRect(origin: windowOrigin, size: fullSize), display: true)
        panel.alphaValue = 0
        if panel.parent !== parent {
            panel.parent?.removeChildWindow(panel)
            parent.addChildWindow(panel, ordered: .above)
        } else {
            panel.orderFront(nil)
        }
        presentedID = entry.id

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeInDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func hidePanel() {
        presentedID = nil
        guard let panel else { return }
        panel.alphaValue = 0
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    private func makePanel() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.animationBehavior = .none
        return window
    }

    /// Places the bubble below-right of the pointer, flipping horizontally or vertically near the screen's edge and
    /// pinching whichever corner sits closest to the pointer.
    private func place(
        bubbleSize: CGSize, pointer: NSPoint, in bounds: NSRect
    ) -> (bubbleFrame: NSRect, corner: OaToolTipCorner) {
        let margin = Self.screenMargin
        let offset = Self.cursorOffset
        var x = pointer.x + offset.x
        var flippedX = false
        if x + bubbleSize.width > bounds.maxX - margin {
            x = pointer.x - offset.x - bubbleSize.width
            flippedX = true
        }
        x = min(max(x, bounds.minX + margin), max(bounds.minX + margin, bounds.maxX - margin - bubbleSize.width))

        var y = pointer.y - offset.y - bubbleSize.height
        var flippedY = false
        if y < bounds.minY + margin {
            y = pointer.y + offset.x
            flippedY = true
        }
        y = min(max(y, bounds.minY + margin), max(bounds.minY + margin, bounds.maxY - margin - bubbleSize.height))

        let corner: OaToolTipCorner =
            switch (flippedX, flippedY) {
            case (false, false): .topLeading
            case (true, false): .topTrailing
            case (false, true): .bottomLeading
            case (true, true): .bottomTrailing
            }
        return (NSRect(origin: NSPoint(x: x, y: y), size: bubbleSize), corner)
    }
}
