import AppKit
import DevKit
import SwiftUI

/// Arc's Settings, with the panes Oa has so far: General and Profiles. As Arc's: toolbar tabs, one fixed size for
/// every pane, and the title is the pane's name.
@MainActor
final class SettingsWindowController: NSWindowController {
    private let tabs = NSTabViewController()

    /// `openWindow` opens a browser window on a Space and gives its model.
    init(engine: any BrowserApplication, store: SidebarStore, openWindow: @escaping (UUID) -> WindowModel?) {
        super.init(window: nil)
        tabs.tabStyle = .toolbar
        add("General", symbol: "gearshape") {
            GeneralPreferencePane(adBlocker: engine.adBlocker) { [weak tabs] in tabs?.selectedTabViewItemIndex = 1 }
        }
        add("Profiles", symbol: "person") {
            ProfilePreferencePane(engine: engine, store: store, openWindow: openWindow)
        }
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.center()
        self.window = window
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Arc's opens on its first pane each time; Oa's first is General.
    override func showWindow(_ sender: Any?) {
        if window?.isVisible != true { tabs.selectedTabViewItemIndex = 0 }
        super.showWindow(sender)
    }

    private func add(_ title: String, symbol: String, @ViewBuilder pane: () -> some View) {
        let controller = NSHostingController(rootView: pane())
        controller.preferredContentSize = NSSize(width: 684, height: 562)
        controller.title = title
        let item = NSTabViewItem(viewController: controller)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        tabs.addTabViewItem(item)
    }
}
