import AppKit
import SwiftUI

/// Arc's window layout controller, the window's content: it lays the sidebar and the page out for the sidebar's mode.
@MainActor
final class WindowLayoutController: NSViewController {
    /// Arc's lock and unlock: the sidebar and the page change frames together, over 0.08 s on this curve.
    private static let lockAnimation = Animation.timingCurve(0.25, 0.46, 0.45, 0.94, duration: 0.08)

    let model: WindowModel

    init(model: WindowModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let content = NSHostingView(rootView: BrowserWindowView(model: model, layout: self))
        content.sizingOptions = []
        view = content
    }

    func setSidebarMode(_ mode: SidebarMode) {
        withAnimation(Self.lockAnimation) { model.setSidebarMode(mode) }
    }

    func toggleSidebar() {
        setSidebarMode(model.sidebarMode == .anchored ? .noChrome : .anchored)
    }
}
