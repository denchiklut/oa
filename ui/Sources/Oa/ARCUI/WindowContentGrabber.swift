import AppKit
import SwiftUI

/// Arc's `ARCUI.WindowContentGrabber`: an invisible strip over the top of a content. The page gets every press; a drag
/// that began on the arrow cursor moves the window instead. Chromium hit-tests the window's content view on every mouse
/// event, which is how the strip sees a drag the page owns.
final class WindowContentGrabber: NSView {
    /// Arc's key; on when absent, as Arc registers it.
    static let key = "contentWindowDraggingEnabled"

    private enum DragState: Equatable {
        case inactive
        case beganInValidState
        /// How far the pointer has gone since the window began to move.
        case committed(CGSize)
    }

    var hasContent = true
    var allowsDrag: () -> Bool = { true }
    private var monitor: Any?
    private var dragState = DragState.inactive {
        didSet { updateMonitor() }
    }

    /// Arc removes the monitor when the grabber goes away.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { dragState = .inactive }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent, event.type == .leftMouseDown || event.type == .leftMouseDragged,
            super.hitTest(point) === self
        else { return nil }
        if event.type == .leftMouseDown {
            dragState = canDrag(event) ? .beganInValidState : .inactive
            return hasContent ? nil : self
        }
        // As Arc: the cursor is checked again on every drag event.
        if !canDrag(event) { dragState = .inactive }
        switch dragState {
        case .inactive: return nil
        case .beganInValidState: window?.performDrag(with: event)
        case .committed: break
        }
        dragState = .committed(.zero)
        return self
    }

    /// Arc's grabber leaves the press to the views behind it, which zoom on a double-click; behind Oa's is SwiftUI, so
    /// it does the title bar's action itself.
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { window?.performTitleBarDoubleClickAction() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard canDrag(event) else { return }
        window?.performDrag(with: event)
        dragState = .committed(.zero)
    }

    /// As Arc: on the arrow cursor only, so text, links and fields keep their drags, and on the press also with no
    /// modifier or ⌥ alone. Oa compares only ⇧⌃⌥⌘.
    private func canDrag(_ event: NSEvent) -> Bool {
        guard NSCursor.current === NSCursor.arrow else { return false }
        guard event.type == .leftMouseDown else { return true }
        let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
        return (modifiers.isEmpty || modifiers == .option) && allowsDrag()
    }

    /// As Arc: while the window moves, the page gets none of the drag's later events, and its mouse-up only when the
    /// pointer went 1 pt or less.
    private func updateMonitor() {
        guard case .committed = dragState else {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            return
        }
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .leftMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated { self?.passesDuringDrag(event) ?? true } ? event : nil
        }
    }

    private func passesDuringDrag(_ event: NSEvent) -> Bool {
        guard event.window === window, !isHidden, case .committed(let distance) = dragState else { return true }
        if event.type == .leftMouseDragged {
            dragState = .committed(
                CGSize(width: distance.width + abs(event.deltaX), height: distance.height + abs(event.deltaY)))
            return false
        }
        dragState = .inactive
        return hypot(distance.width, distance.height) <= 1
    }
}

extension View {
    /// Arc's grabber frame: from the content's top edge to 60 pt below it, the bar of `barHeight` over the page left
    /// out, and short of the 14 pt the scroll bar takes. No window drag while a Peek is up, as Arc's.
    func windowContentGrabber(model: WindowModel, hasContent: Bool, enabled: Bool = true, barHeight: CGFloat)
        -> some View
    {
        overlay(alignment: .topLeading) {
            if enabled {
                WindowContentGrabberStrip(model: model, hasContent: hasContent)
                    .frame(height: max(0, 60 - barHeight))
                    .padding(.trailing, 14)
            }
        }
    }
}

private struct WindowContentGrabberStrip: View {
    let model: WindowModel
    let hasContent: Bool
    @AppStorage(WindowContentGrabber.key) private var isEnabled = true

    var body: some View {
        if isEnabled { Grabber(model: model, hasContent: hasContent) }
    }

    private struct Grabber: NSViewRepresentable {
        let model: WindowModel
        let hasContent: Bool

        func makeNSView(context: Context) -> WindowContentGrabber { WindowContentGrabber() }

        func updateNSView(_ view: WindowContentGrabber, context: Context) {
            view.hasContent = hasContent
            view.allowsDrag = { [weak model] in model?.peek == nil }
        }
    }
}
