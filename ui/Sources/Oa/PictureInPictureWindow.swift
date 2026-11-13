import AppKit

/// Arc's video picture-in-picture window as read from its binary (arc-picture-in-picture-static.md §8): a
/// non-activating resizable panel with no title bar, floating on every Space and beside full-screen windows, with 6 pt
/// corners, at least 224×126, 320 pt wide at first, the video's aspect ratio kept, and dragged from its content. It
/// opens at the frame it last closed with. Arc's place for it with nothing saved is unknown; the main screen's top
/// right is Oa's own, at the 10 pt Arc keeps between the window and the screen's edges.
@MainActor
final class PictureInPictureWindow {
    private static let positionKey = "LastPiPPosition"
    private static let initialWidth: CGFloat = 320
    private static let minimumSize = NSSize(width: 224, height: 126)
    private static let screenMargin: CGFloat = 10

    /// Arc's `WindowPosition` in the JSON its Codable writes. Oa saves `absolute`; Arc's corner cases wait for
    /// snapping.
    private enum WindowPosition: Codable {
        case absolute(CGRect)
    }

    var videoSize = CGSize(width: 16, height: 9) {
        didSet { if videoSize != oldValue, panel.isVisible { fit(panel.frame) } }
    }

    private let panel: NSPanel
    private let content: PictureInPictureContentView
    private var videoView: NSView?

    init(onBackToTab: @escaping () -> Void, onClose: @escaping () -> Void) {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.minimumSize), styleMask: [.nonactivatingPanel, .resizable],
            backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.managed, .fullScreenAuxiliary, .canJoinAllSpaces]
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        content = PictureInPictureContentView(onBackToTab: onBackToTab, onClose: onClose)
        panel.contentView = content
    }

    func show(_ view: NSView, videoSize: CGSize?) {
        if videoView !== view {
            videoView?.removeFromSuperview()
            videoView = view
            content.host(view)
        }
        if let videoSize, videoSize.width > 0, videoSize.height > 0 { self.videoSize = videoSize }
        guard !panel.isVisible else { return }
        fit(savedFrame ?? .zero)
        panel.orderFrontRegardless()
    }

    func dismiss() {
        guard panel.isVisible else { return }
        if let data = try? JSONEncoder().encode(WindowPosition.absolute(panel.frame)) {
            UserDefaults.standard.set(String(decoding: data, as: UTF8.self), forKey: Self.positionKey)
        }
        panel.orderOut(nil)
        videoView?.removeFromSuperview()
        videoView = nil
    }

    private var savedFrame: NSRect? {
        guard let json = UserDefaults.standard.string(forKey: Self.positionKey),
            case .absolute(let frame)? = try? JSONDecoder().decode(WindowPosition.self, from: Data(json.utf8)),
            NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) })
        else { return nil }
        return frame
    }

    /// Keeps `frame`'s width and top left corner and takes the height from the video.
    private func fit(_ frame: NSRect) {
        let ratio = videoSize.height / videoSize.width
        let minimumWidth = max(Self.minimumSize.width, Self.minimumSize.height / ratio)
        panel.contentAspectRatio = videoSize
        panel.contentMinSize = NSSize(width: minimumWidth, height: minimumWidth * ratio)
        let width = max(frame.width > 0 ? frame.width : Self.initialWidth, minimumWidth)
        var fitted = NSRect(x: frame.minX, y: frame.maxY - width * ratio, width: width, height: width * ratio)
        if frame.isEmpty, let screen = NSScreen.main?.visibleFrame {
            fitted.origin = NSPoint(
                x: screen.maxX - Self.screenMargin - fitted.width, y: screen.maxY - Self.screenMargin - fitted.height)
        }
        panel.setFrame(fitted, display: true)
    }
}

/// The video under Arc's two corner buttons as measured live (arc-picture-in-picture-live-controls.md §3–§4): Back to
/// Tab top left and Close top right, 28 pt tall and 16 pt in, 12 pt under 280 pt of width, where Close loses its
/// label; from 400 pt Back to Tab has one. They show over a dimmed video when the pointer moves 3 pt or more over the
/// window and fade 3 s after its last move. How much Arc dims is read off its captures. Arc's Minimize and its
/// playback controls aren't here yet.
private final class PictureInPictureContentView: NSView {
    private let backToTab = PictureInPictureContentView.button(
        symbol: "arrow.up.left", label: "Back to Tab", hasToolTip: true)
    private let close = PictureInPictureContentView.button(symbol: "xmark", label: "Close", hasToolTip: false)
    private let scrim = NSView()
    private var controls: [NSView] { [scrim, backToTab, close] }
    private let onBackToTab: () -> Void
    private let onClose: () -> Void
    private var hidesControls: Task<Void, Never>?

    init(onBackToTab: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.onBackToTab = onBackToTab
        self.onClose = onClose
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.cgColor
        backToTab.target = self
        backToTab.action = #selector(pressBackToTab)
        close.target = self
        close.action = #selector(pressClose)
        scrim.wantsLayer = true
        scrim.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        for control in controls {
            control.isHidden = true
            addSubview(control)
        }
        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func host(_ view: NSView) {
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view, positioned: .below, relativeTo: scrim)
    }

    override func layout() {
        super.layout()
        scrim.frame = bounds
        let inset: CGFloat = bounds.width < 280 ? 12 : 16
        backToTab.title = bounds.width < 400 ? "" : "Back to Tab"
        close.title = bounds.width < 280 ? "" : "Close"
        let backWidth: CGFloat = bounds.width < 400 ? 28 : 109
        let closeWidth: CGFloat = bounds.width < 280 ? 29 : 72
        let y = bounds.maxY - inset - 28
        backToTab.frame = NSRect(x: inset, y: y, width: backWidth, height: 28)
        close.frame = NSRect(x: bounds.maxX - inset - closeWidth, y: y, width: closeWidth, height: 28)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit is NSButton ? hit : hit == nil ? nil : self
    }

    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    override func mouseEntered(with event: NSEvent) { revealControls() }
    override func mouseMoved(with event: NSEvent) {
        if hypot(event.deltaX, event.deltaY) >= 3 { revealControls() }
    }

    private func revealControls() {
        hidesControls?.cancel()
        for control in controls {
            control.alphaValue = 1
            control.isHidden = false
        }
        hidesControls = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { self?.fadeControls() }
        }
    }

    private func fadeControls() {
        let controls = controls
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            controls.forEach { $0.animator().alphaValue = 0 }
        } completionHandler: {
            MainActor.assumeIsolated { controls.forEach { $0.isHidden = $0.alphaValue == 0 } }
        }
    }

    @objc private func pressBackToTab() { onBackToTab() }
    @objc private func pressClose() { onClose() }

    /// Arc's buttons carry no accessibility labels; Oa's do.
    private static func button(symbol: String, label: String, hasToolTip: Bool) -> NSButton {
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        let button = NSButton(title: "", image: image ?? NSImage(), target: nil, action: nil)
        button.isBordered = false
        button.imagePosition = .imageLeading
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.contentTintColor = .white
        button.toolTip = hasToolTip ? label : nil
        button.setAccessibilityLabel(label)
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
        return button
    }
}
