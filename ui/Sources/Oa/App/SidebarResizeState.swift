import AppKit
import SwiftUI

/// Arc's state of a drag on the sidebar's edge, with its limits: 164 to 500 pt, hidden below 82 pt, and a snap to
/// the 228 pt a double-click resets to. The 14 pt band, the 50 pt/s and the 0.5 s are Arc's; that a slow drag inside
/// the band snaps, with a tap at most that often, is Oa's reading of them.
struct SidebarResizeState {
    static let widths: ClosedRange<CGFloat> = 164...500
    static let collapseWidth: CGFloat = 82
    static let resetWidth: CGFloat = 228

    let widthAtBegin: CGFloat
    let modeAtBegin: SidebarMode
    private var canSnap: Bool
    private var snapTime: TimeInterval?

    init(width: CGFloat, mode: SidebarMode) {
        widthAtBegin = width
        modeAtBegin = mode
        canSnap = abs(width - Self.resetWidth) > 14
    }

    /// The width a drag asks for, or nil for a docked sidebar dragged narrow enough to hide.
    mutating func width(for translation: CGFloat, velocity: CGFloat) -> CGFloat? {
        let width = (widthAtBegin + translation).rounded()
        if width < Self.collapseWidth, modeAtBegin == .anchored { return nil }
        guard abs(width - Self.resetWidth) <= 14 else {
            canSnap = true
            return min(max(width, Self.widths.lowerBound), Self.widths.upperBound)
        }
        guard canSnap, abs(velocity) < 50 || snapTime != nil else { return width }
        let now = ProcessInfo.processInfo.systemUptime
        if snapTime.map({ now - $0 > 0.5 }) ?? true {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        snapTime = now
        return Self.resetWidth
    }
}

/// Arc's resize region: 8 pt across the sidebar's trailing edge, 11 pt short of the window's top and bottom.
struct SidebarResizeRegion: NSViewRepresentable {
    let layout: WindowLayoutController

    func makeNSView(context: Context) -> Handle { Handle() }

    func updateNSView(_ view: Handle, context: Context) {
        view.layout = layout
    }

    final class Handle: NSView {
        weak var layout: WindowLayoutController?
        private var last: (x: CGFloat, time: TimeInterval, start: CGFloat)?

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .resizeLeftRight)
        }

        override func mouseDown(with event: NSEvent) {
            guard event.clickCount < 2 else { return layout?.resetSidebarWidth() ?? () }
            last = (event.locationInWindow.x, event.timestamp, event.locationInWindow.x)
        }

        override func mouseDragged(with event: NSEvent) {
            guard let last else { return }
            let x = event.locationInWindow.x
            let elapsed = event.timestamp - last.time
            layout?.resizeSidebar(by: x - last.start, velocity: elapsed > 0 ? (x - last.x) / elapsed : 0)
            self.last = (x, event.timestamp, last.start)
        }

        override func mouseUp(with event: NSEvent) {
            if last != nil { layout?.endSidebarResize() }
            last = nil
        }
    }
}
