import AppKit
import SwiftUI

/// Arc's window buttons in the sidebar's header: a set of its own from AppKit's factory, not the window's. Away from
/// the pointer a `DimmedWindowControls` disc covers each, 12 pt across as measured, and the group is at 10% over light
/// content, 33% over dark.
final class WindowStandardButtons: NSView {
    private let group = Group()
    private var covers: [NSView] = []
    /// What the green button does in place of AppKit's zoom: a Little window's moves its page out, as Arc's.
    private let zoomAction: (() -> Void)?

    init(zoomAction: (() -> Void)? = nil) {
        self.zoomAction = zoomAction
        super.init(frame: .zero)
        addSubview(group)
        addTrackingArea(
            NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private static let dimension: CGFloat = 14
    private static var spacing: CGFloat { if #available(macOS 26, *) { 9 } else { 6 } }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 3 * Self.dimension + 2 * Self.spacing, height: Self.dimension)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, group.subviews.isEmpty else { return }
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = NSWindow.standardWindowButton(kind, for: window.styleMask) else { continue }
            if kind == .zoomButton, zoomAction != nil {
                button.target = self
                button.action = #selector(performZoomAction)
            }
            group.addSubview(button)
            let cover = NSView()
            cover.wantsLayer = true
            cover.layer?.cornerRadius = Self.dimension / 2 - 1
            addSubview(cover)
            covers.append(cover)
        }
        update()
    }

    override func layout() {
        super.layout()
        group.frame = bounds
        for (index, button) in group.subviews.enumerated() {
            button.frame = NSRect(
                x: CGFloat(index) * (Self.dimension + Self.spacing), y: (bounds.height - Self.dimension) / 2,
                width: Self.dimension, height: Self.dimension)
            let cover = covers[index]
            cover.frame = button.frame.insetBy(dx: 1, dy: 1)
            // Fit AppKit's native disc (14 pt, or 12 pt in the older appearance) around the 12 pt cover.
            let nativeFrame = NSRect(origin: .zero, size: button.intrinsicContentSize)
            button.bounds.size =
                group.mouseInside ? button.frame.size : button.alignmentRect(forFrame: nativeFrame).size
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        update()
    }

    @objc private func performZoomAction() { zoomAction?() }

    override func mouseEntered(with event: NSEvent) {
        group.mouseInside = true
        update()
    }

    override func mouseExited(with event: NSEvent) {
        group.mouseInside = false
        update()
    }

    private func update() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        alphaValue = group.mouseInside ? 1 : dark ? 0.33 : 0.1
        for cover in covers {
            cover.isHidden = group.mouseInside
            cover.layer?.backgroundColor = dark ? CGColor(red: 0.953, green: 0.953, blue: 0.918, alpha: 1) : .black
        }
        // On macOS 26 the buttons redraw their state in layout, not on `needsDisplay`.
        needsLayout = true
        group.subviews.forEach { $0.needsLayout = true }
    }

    /// The buttons ask their superview this before they draw their glyphs, as they ask a title bar.
    private final class Group: NSView {
        var mouseInside = false

        @objc(_mouseInGroup:) func mouseInGroup(_ button: NSButton) -> Bool { mouseInside }
    }
}

struct WindowStandardButtonsView: NSViewRepresentable {
    var zoomAction: (() -> Void)?

    func makeNSView(context: Context) -> WindowStandardButtons { WindowStandardButtons(zoomAction: zoomAction) }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WindowStandardButtons, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }

    func updateNSView(_ view: WindowStandardButtons, context: Context) {
        view.appearance = NSAppearance(named: context.environment.colorScheme == .dark ? .darkAqua : .aqua)
    }
}
