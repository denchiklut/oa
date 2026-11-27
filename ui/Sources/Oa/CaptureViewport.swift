import SwiftUI

struct CaptureViewport {
    private(set) var zoom: CGFloat = 1
    // The top-left of the visible area in fractions of the original image, independent of window size.
    private var origin = CGPoint.zero

    // A pinch past fit briefly reveals the white canvas, as in Arc's editor.
    var pinchScale: CGFloat { 1 - max(0, 1 - zoom) * 0.2 }

    func transform(image: CGSize, in size: CGSize) -> CGAffineTransform {
        let width = size.width * max(1, zoom)
        let height = size.height * max(1, zoom)
        return CGAffineTransform(
            a: width / image.width, b: 0, c: 0, d: height / image.height, tx: -origin.x * width, ty: -origin.y * height)
    }

    mutating func magnify(to value: CGFloat, around point: CGPoint, in size: CGSize, pinching: Bool = false) {
        let next = min(8, max(pinching ? 0.5 : 1, value))
        let delta = 1 / max(1, zoom) - 1 / max(1, next)
        zoom = next
        moveOrigin(dx: point.x / size.width * delta, dy: point.y / size.height * delta)
    }

    mutating func pan(by distance: CGSize, in size: CGSize) {
        moveOrigin(dx: -distance.width / (zoom * size.width), dy: -distance.height / (zoom * size.height))
    }

    private mutating func moveOrigin(dx: CGFloat, dy: CGFloat) {
        let edge = 1 - 1 / max(1, zoom)
        origin.x = min(edge, max(0, origin.x + dx))
        origin.y = min(edge, max(0, origin.y + dy))
    }
}

struct CaptureViewportGestures: NSViewRepresentable {
    @Binding var viewport: CaptureViewport
    var enabled: Bool

    func makeNSView(context: Context) -> GestureView { GestureView() }
    func updateNSView(_ view: GestureView, context: Context) {
        view.handle = { event, point, size in
            guard enabled, size.width > 0, size.height > 0 else { return false }
            switch event.type {
            case .smartMagnify:
                viewport.magnify(to: viewport.zoom > 1 ? 1 : 2, around: point, in: size)
            case .magnify:
                viewport.magnify(to: viewport.zoom * (1 + event.magnification), around: point, in: size, pinching: true)
                if viewport.zoom < 1 && (event.phase.contains(.ended) || event.phase.contains(.cancelled)) {
                    withAnimation(.spring(duration: 0.28)) { viewport = CaptureViewport() }
                }
            case .scrollWheel:
                if !event.hasPreciseScrollingDeltas || event.modifierFlags.contains(.command) {
                    let rate: CGFloat = event.hasPreciseScrollingDeltas ? 0.012 : 0.15
                    viewport.magnify(to: viewport.zoom * exp(event.scrollingDeltaY * rate), around: point, in: size)
                } else {
                    viewport.pan(by: CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY), in: size)
                }
            default: return false
            }
            return true
        }
    }

    final class GestureView: NSView {
        var handle: ((NSEvent, CGPoint, CGSize) -> Bool)?
        private var monitor: Any?
        private var pinching = false
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            pinching = false
            guard window != nil else { return }
            // The canvas keeps mouse drags and the inline text field keeps focus while zooming.
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.magnify, .smartMagnify, .scrollWheel]) {
                [weak self] event in
                MainActor.assumeIsolated {
                    guard let self, let window = self.window, window.attachedSheet == nil else { return false }
                    var location = event.locationInWindow
                    if let target = event.window {
                        guard target === window else { return false }
                    } else {
                        // AppKit reports windowless scroll events in screen coordinates.
                        guard NSWindow.windowNumber(at: location, belowWindowWithWindowNumber: 0) == window.windowNumber
                        else { return false }
                        location = window.convertPoint(fromScreen: location)
                    }
                    let point = self.convert(location, from: nil)
                    let continuingPinch = event.type == .magnify && self.pinching
                    guard self.bounds.contains(point) || continuingPinch else { return false }
                    let handled = self.handle?(event, point, self.bounds.size) == true
                    if event.type == .magnify {
                        self.pinching = handled && !event.phase.intersection([.began, .changed]).isEmpty
                    }
                    return handled
                } ? nil : event
            }
        }
    }
}
