import AppKit
import DevKit
import SwiftUI

/// As Arc's `WebContentViewControllerSplitView`: a page and its docked DevTools side by side, with AppKit's 10 pt pane
/// splitter between them. The page stays the same view whatever the side, so docking never moves it out of its window.
struct WebContentSplitView<Content: View>: View {
    static var splitterThickness: CGFloat { 10 }

    let page: any Page
    @ViewBuilder let content: Content

    var body: some View {
        let devTools = page.devTools
        let side = devTools.display.flatMap { $0 == .undocked ? nil : $0 }
        let view = side.flatMap { _ in devTools.view }
        GeometryReader { geometry in
            let bottom = side == .bottom
            let length = bottom ? geometry.size.height : geometry.size.width
            let layout = bottom ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
            layout {
                if side == .left, let view {
                    pane(view, side: .left, length: length)
                    splitter(side: .left, length: length)
                }
                content
                if let side, side != .left, let view {
                    splitter(side: side, length: length)
                    pane(view, side: side, length: length)
                }
            }
            .coordinateSpace(.named(DevToolsSplitter.space))
        }
        // As Arc: opening DevTools gives it the keyboard and closing gives it back to the page.
        .onChange(of: devTools.display == nil) { _, closed in
            if closed { return page.activate() }
            Task { @MainActor in devTools.focus() }
        }
    }

    private func pane(_ view: NSView, side: DevToolsDisplay, length: CGFloat) -> some View {
        let paneLength = max(0, (length * DevToolsState.shared.dimension(for: side)).rounded() - Self.splitterThickness)
        return PageHostView(view: view)
            .frame(width: side == .bottom ? nil : paneLength, height: side == .bottom ? paneLength : nil)
    }

    private func splitter(side: DevToolsDisplay, length: CGFloat) -> some View {
        DevToolsSplitter(horizontal: side == .bottom) { location in
            // As Arc's split view: either side can be dragged down to nothing.
            let devToolsLength =
                side == .left ? location + Self.splitterThickness / 2 : length - location + Self.splitterThickness / 2
            let clamped = min(max(devToolsLength, Self.splitterThickness), length)
            DevToolsState.shared.sizePreferences[side] = clamped / length
        }
    }
}

private struct DevToolsSplitter: View {
    static let space = "devToolsSplit"

    let horizontal: Bool
    let moved: (CGFloat) -> Void

    var body: some View {
        let thickness = WebContentSplitView<EmptyView>.splitterThickness
        Color.clear
            .frame(width: horizontal ? nil : thickness, height: horizontal ? thickness : nil)
            .overlay { PaneSplitterDivider(vertical: !horizontal).allowsHitTesting(false) }
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    (horizontal ? NSCursor.resizeUpDown : NSCursor.resizeLeftRight).push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space)).onChanged { value in
                    moved(horizontal ? value.location.y : value.location.x)
                }
            )
            .accessibilityElement()
            .accessibilityLabel("Splitter")
    }
}

/// Draws the divider as Arc's `NSSplitView` does, in its `.paneSplitter` style.
private struct PaneSplitterDivider: NSViewRepresentable {
    let vertical: Bool

    func makeNSView(context: Context) -> DividerView {
        let view = DividerView()
        view.dividerStyle = .paneSplitter
        return view
    }

    func updateNSView(_ view: DividerView, context: Context) {
        view.isVertical = vertical
        view.needsDisplay = true
    }

    final class DividerView: NSSplitView {
        override func draw(_ dirtyRect: NSRect) { drawDivider(in: bounds) }
    }
}
