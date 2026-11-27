import AppKit
import DevKit
import Observation
import SwiftUI

@MainActor
final class RegionCapture {
    private var request: UUID?
    private weak var selection: RegionSelectionView?

    var hasResult: Bool { selection?.hasResult == true }

    func cancel() {
        request = nil
        selection?.finish()
    }

    func windowResignedKey() {
        if selection?.hasResult != true { cancel() }
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
            let view = RegionSelectionView(image: bitmap, frame: page.view.bounds) {
                [weak self, weak model, weak page] result, view in
                guard let model, let page, model.frontPage?.id == page.id, page.url == url else {
                    view.finish()
                    return
                }
                let menu = CaptureActionMenu(result: result, model: model, pageID: page.id) {
                    [weak self, weak model, weak page] in
                    if let self, let model, let page { self.begin(on: page, in: model) }
                } edited: { [weak view] in
                    view?.needsDisplay = true
                }
                view.show(menu)
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

private struct CaptureDragHint: View {
    var body: some View {
        Text("Drag to capture a portion of this page")
            .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.indigo)
            .padding(.horizontal, 28).frame(height: 46)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
    }
}

@MainActor
final class RegionSelectionView: NSView {
    private weak var previousResponder: NSResponder?
    private let image: CGImage
    private let onSelect: (CapturedRegion, RegionSelectionView) -> Void
    private var start: NSPoint?
    private var selection = NSRect.zero
    private var result: CapturedRegion?
    private var actionScroll: NSScrollView?
    private var escapeMonitor: Any?
    var hasResult: Bool { result != nil }

    private let hint = NSHostingView(rootView: CaptureDragHint())

    private static let cameraCursor: NSCursor = {
        let cross = NSCursor.crosshair
        let size = NSSize(width: 32, height: 32)
        let image = NSImage(size: size, flipped: false) { _ in
            cross.image.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
            let badge = NSRect(x: 14, y: 15, width: 17, height: 13)
            NSColor.black.withAlphaComponent(0.8).setFill()
            NSBezierPath(roundedRect: badge, xRadius: 3, yRadius: 3).fill()
            let camera = NSImage(systemSymbolName: "camera", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(paletteColors: [.white]))
            camera?.draw(in: badge.insetBy(dx: 1, dy: 1))
            return true
        }
        return NSCursor(
            image: image,
            hotSpot: NSPoint(x: cross.hotSpot.x, y: size.height - cross.image.size.height + cross.hotSpot.y))
    }()

    init(image: CGImage, frame: NSRect, onSelect: @escaping (CapturedRegion, RegionSelectionView) -> Void) {
        self.image = image
        self.onSelect = onSelect
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
        addSubview(hint)
        setAccessibilityLabel("Drag to capture a portion of this page. Press Escape to cancel.")
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() {
        if !hasResult { addCursorRect(bounds, cursor: Self.cameraCursor) }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func takeFocus(in window: NSWindow) {
        previousResponder = window.firstResponder
        window.makeFirstResponder(self)
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let window = self.window, event.window === window, window.attachedSheet == nil,
                    event.keyCode == 53
                else { return false }
                self.finish()
                return true
            } ? nil : event
        }
    }

    override func layout() {
        super.layout()
        let size = hint.fittingSize
        hint.frame = NSRect(
            x: (bounds.width - size.width) / 2, y: max(0, bounds.height - size.height - 24), width: size.width,
            height: size.height)
        if let scroll = actionScroll, let menu = scroll.documentView {
            let size = NSSize(
                width: min(270, max(1, bounds.width - 16)), height: min(menu.fittingSize.height, bounds.height))
            menu.setFrameSize(NSSize(width: size.width, height: menu.fittingSize.height))
            let left = selection.minX - size.width - 6
            let right = selection.maxX + 6
            let x = left < 8 && right + size.width <= bounds.width - 8 ? right : left
            scroll.frame = NSRect(
                x: min(max(8, x), max(8, bounds.width - size.width - 8)),
                y: min(selection.minY, max(0, bounds.height - size.height - 8)), width: size.width, height: size.height)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSImage(cgImage: image, size: bounds.size).draw(
            in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        let outside = NSBezierPath(rect: bounds)
        outside.append(NSBezierPath(rect: selection))
        outside.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.40).setFill()
        outside.fill()
        if !selection.isEmpty {
            if let result {
                NSImage(cgImage: result.image, size: selection.size).draw(
                    in: selection, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
            }
            NSColor.systemBlue.setStroke()
            let outline = NSBezierPath(roundedRect: selection, xRadius: 3, yRadius: 3)
            outline.lineWidth = 1.5
            outline.stroke()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit.isDescendant(of: hint) ? self : hit
    }

    override func mouseDown(with event: NSEvent) {
        guard !hasResult else { finish(); return }
        start = convert(event.locationInWindow, from: nil)
        hint.isHidden = true
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
        guard start != nil else { return }
        mouseDragged(with: event)
        start = nil
        guard !selection.isEmpty, !bounds.isEmpty else {
            hint.isHidden = false
            return
        }
        let pixels = selection.applying(
            CGAffineTransform(scaleX: CGFloat(image.width) / bounds.width, y: CGFloat(image.height) / bounds.height)
        ).integral
        guard let cropped = image.cropping(to: pixels) else { finish(); return }
        let result = CapturedRegion(image: cropped)
        self.result = result
        window?.invalidateCursorRects(for: self)
        onSelect(result, self)
    }

    func show(_ actions: CaptureActionMenu) {
        let menu = NSHostingView(rootView: actions)
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = menu
        actionScroll = scroll
        addSubview(scroll)
        needsLayout = true
        needsDisplay = true
    }

    override func cancelOperation(_ sender: Any?) { finish() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil, let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
    }

    func finish() {
        let window = window
        let focus = window?.firstResponder as? NSView
        let hadFocus =
            focus?.isDescendant(of: self) == true || (window?.firstResponder as? NSTextView)?.isFieldEditor == true
        removeFromSuperview()
        if hadFocus { window?.makeFirstResponder(previousResponder) }
    }
}

extension WindowModel {
    func startRegionCapture(on page: any Page) {
        portraitCapture.cancel()
        regionCapture.begin(on: page, in: self)
    }
}
