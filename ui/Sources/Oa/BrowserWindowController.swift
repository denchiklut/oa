import AppKit
import DevKit
import SwiftUI

@MainActor
final class BrowserWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    let id = UUID()
    private let engine: any BrowserApplication
    private let model: WindowModel
    private let didClose: (BrowserWindowController) -> Void

    init(
        engine: any BrowserApplication, context: any BrowserContext,
        didClose: @escaping (BrowserWindowController) -> Void
    ) {
        self.engine = engine
        self.didClose = didClose
        model = WindowModel(windowID: id, context: context)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.contentMinSize = NSSize(width: 640, height: 320)
        super.init(window: window)
        let content = NSHostingController(rootView: BrowserWindowView(model: model))
        content.sizingOptions = []
        window.contentViewController = content
        window.setContentSize(NSSize(width: 1100, height: 760))
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func open(cascadingFrom previous: NSWindow?) {
        guard let window else { return }
        engine.attachWindow(window, id: id)
        model.newTab(URL(string: "https://www.wikipedia.org/")!)
        if let previous {
            window.setFrameTopLeftPoint(
                window.cascadeTopLeft(from: NSPoint(x: previous.frame.minX, y: previous.frame.maxY)))
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        observeTitle()
    }

    func closeAllTabs() {
        model.closeAll()
    }

    private func observeTitle() {
        let title = withObservationTracking {
            model.selectedTab?.title ?? ""
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeTitle() }
        }
        window?.title = title.isEmpty ? "Oa" : title
    }

    func windowDidBecomeKey(_ notification: Notification) {
        model.page?.activate()
    }

    func windowWillClose(_ notification: Notification) {
        model.dropAll()
        engine.closeWindow(id: id)
        didClose(self)
    }

    @objc func goBack(_ sender: Any?) { model.page?.goBack() }
    @objc func goForward(_ sender: Any?) { model.page?.goForward() }
    @objc func reload(_ sender: Any?) { model.page?.reload() }
    @objc func stopLoading(_ sender: Any?) { model.page?.stopLoading() }
    @objc func openLocation(_ sender: Any?) { model.focusAddressField += 1 }
    @objc func newTab(_ sender: Any?) { model.newTab() }
    @objc func selectNextTab(_ sender: Any?) { model.selectAdjacentTab(1) }
    @objc func selectPreviousTab(_ sender: Any?) { model.selectAdjacentTab(-1) }

    /// The selected tab, or the window when no tab is selected.
    @objc func closeTab(_ sender: Any?) {
        if let tab = model.selectedTab { model.close(tab) } else { window?.performClose(sender) }
    }

    @objc func selectTab(_ sender: NSMenuItem) {
        if let index = tabIndex(for: sender) { model.selectTab(at: index) }
    }

    private func tabIndex(for item: NSMenuItem) -> Int? {
        let index = item.tag == MainMenu.lastTabTag ? model.tabs.count - 1 : item.tag - 1
        return model.tabs.indices.contains(index) ? index : nil
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(goBack(_:)): model.page?.canGoBack ?? false
        case #selector(goForward(_:)): model.page?.canGoForward ?? false
        case #selector(stopLoading(_:)): model.page?.isLoading ?? false
        case #selector(selectNextTab(_:)), #selector(selectPreviousTab(_:)): !model.tabs.isEmpty
        case #selector(selectTab(_:)): tabIndex(for: item) != nil
        default: true
        }
    }
}
