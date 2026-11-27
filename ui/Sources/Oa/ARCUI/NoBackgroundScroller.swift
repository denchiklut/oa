import AppKit
import SwiftUI

private final class NoBackgroundScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }
    override class var preferredScrollerStyle: NSScroller.Style { .overlay }

    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style)
        -> CGFloat
    {
        scrollerStyle == .legacy ? 8 : super.scrollerWidth(for: controlSize, scrollerStyle: scrollerStyle)
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
}

struct SpaceScroller: NSViewRepresentable {
    var axis: Axis = .vertical
    var insets: NSEdgeInsets?
    var hidesWhilePaging = false

    func makeNSView(context: Context) -> Installer { Installer(self) }

    func updateNSView(_ view: Installer, context: Context) {
        view.configuration = self
        view.apply()
    }

    final class Installer: NSView {
        var configuration: SpaceScroller

        init(_ configuration: SpaceScroller) {
            self.configuration = configuration
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        override func layout() {
            super.layout()
            apply()
        }

        func apply() {
            guard let scrollView = enclosingScrollView else { return }
            let vertical = configuration.axis == .vertical
            if vertical {
                // A legacy scroller reserves row width even while paging. Only an overlay can be removed.
                let enabled = !configuration.hidesWhilePaging || scrollView.scrollerStyle == .legacy
                if scrollView.hasVerticalScroller != enabled { scrollView.hasVerticalScroller = enabled }
                guard enabled else { return }
            }
            let slot: ReferenceWritableKeyPath<NSScrollView, NSScroller?> =
                vertical ? \.verticalScroller : \.horizontalScroller
            if !(scrollView[keyPath: slot] is NoBackgroundScroller) {
                let scroller = NoBackgroundScroller()
                scroller.controlSize = .small
                scrollView[keyPath: slot] = scroller
            }
            if !scrollView.autohidesScrollers { scrollView.autohidesScrollers = true }
            if let insets = configuration.insets, !NSEdgeInsetsEqual(scrollView.scrollerInsets, insets) {
                scrollView.scrollerInsets = insets
            }
            if vertical, scrollView.scrollerStyle == .legacy {
                scrollView.verticalScroller?.alphaValue = configuration.hidesWhilePaging ? 0 : 1
            }
        }
    }
}
