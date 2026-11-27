import AppKit
import DevKit
import Observation

@MainActor
final class RegionCapture {
    private var request: UUID?
    private weak var selection: RegionSelectionView?

    func cancel() {
        request = nil
        selection?.finish()
    }

    func begin(on page: any Page, in model: WindowModel) {
        cancel()
        let token = UUID()
        request = token
        let url = page.url
        page.snapshot { [weak self, weak model, weak page] snapshot in
            guard let self, request == token, let model, let page, let window = page.view.window,
                window.isKeyWindow, model.frontPage?.id == page.id, page.url == url
            else { return }
            guard let bitmap = snapshot?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                model.present(.capture("Couldn’t capture this page"), at: .windowContent(page.id))
                return
            }
            let view = RegionSelectionView(image: bitmap, frame: page.view.bounds) { [weak model, weak page] cropped in
                guard let page, let model, model.frontPage?.id == page.id, page.url == url, let cropped else { return }
                let png = NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:])
                model.copyCapture(png, for: page.id)
            }
            selection = view
            page.view.addSubview(view, positioned: .above, relativeTo: nil)
            view.takeFocus(in: window)
            withObservationTracking {
                _ = page.url
                _ = model.frontPage?.id
            } onChange: { [weak self] in
                Task { @MainActor in if self?.request == token { self?.cancel() } }
            }
        }
    }
}

@MainActor
final class RegionSelectionView: NSView {
    private weak var previousResponder: NSResponder?
    private let image: CGImage
    private var completion: ((CGImage?) -> Void)?
    private var start: NSPoint?
    private var selection = NSRect.zero

    init(image: CGImage, frame: NSRect, completion: @escaping (CGImage?) -> Void) {
        self.image = image
        self.completion = completion
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
        setAccessibilityLabel("Drag to capture a portion of this page. Press Escape to cancel.")
    }

    required init?(coder: NSCoder) { fatalError() }

    func takeFocus(in window: NSWindow) {
        previousResponder = window.firstResponder
        window.makeFirstResponder(self)
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSImage(cgImage: image, size: bounds.size).draw(
            in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        if !selection.isEmpty {
            let outside = NSBezierPath(rect: bounds)
            outside.append(NSBezierPath(rect: selection))
            outside.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(0.35).setFill()
            outside.fill()
            NSColor.white.setStroke()
            NSBezierPath(rect: selection).stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        selection = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = NSRect(
            x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x - start.x),
            height: abs(point.y - start.y)
        ).intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        guard !selection.isEmpty, !bounds.isEmpty else { finish(); return }
        let pixels = selection.applying(
            CGAffineTransform(scaleX: CGFloat(image.width) / bounds.width, y: CGFloat(image.height) / bounds.height)
        ).integral
        finish(image.cropping(to: pixels))
    }

    override func cancelOperation(_ sender: Any?) { finish() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { finish() } else { super.keyDown(with: event) }
    }

    func finish(_ cropped: CGImage? = nil) {
        guard let completion else { return }
        self.completion = nil
        let window = window
        let hadFocus = window?.firstResponder === self
        removeFromSuperview()
        if hadFocus { window?.makeFirstResponder(previousResponder) }
        completion(cropped)
    }
}

extension WindowModel {
    func startRegionCapture(on page: any Page) {
        portraitCapture.cancel()
        regionCapture.begin(on: page, in: self)
    }
}
