import AppKit
import DevKit
import SwiftUI

@MainActor
final class BrowserWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    let model: WindowModel
    private let engine: any BrowserApplication
    private let store: SidebarStore
    private let didClose: (BrowserWindowController) -> Void

    init(
        id: UUID, engine: any BrowserApplication, store: SidebarStore, spaceID: UUID,
        didClose: @escaping (BrowserWindowController) -> Void
    ) {
        self.engine = engine
        self.store = store
        self.didClose = didClose
        model = WindowModel(id: id, engine: engine, store: store, spaceID: spaceID)
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
        model.bringToFront = { [weak window] in window?.makeKeyAndOrderFront(nil) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func open(cascadingFrom previous: NSWindow?) {
        guard let window else { return }
        engine.attachWindow(window, id: model.id)
        store.addWindow(model)
        if let previous {
            window.setFrameTopLeftPoint(
                window.cascadeTopLeft(from: NSPoint(x: previous.frame.minX, y: previous.frame.maxY)))
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        observeTitle()
    }

    private func observeTitle() {
        let title = withObservationTracking {
            _ = model.peek
            return model.selectedTab.map(model.title(for:)) ?? ""
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeTitle() }
        }
        window?.title = model.peek != nil ? model.space?.name ?? "Oa" : title.isEmpty ? "Oa" : title
    }

    func windowDidBecomeKey(_ notification: Notification) {
        model.showSelected()
        model.page?.activate()
    }

    func windowWillClose(_ notification: Notification) {
        model.dropAll()
        store.removeWindow(model)
        engine.closeWindow(id: model.id)
        didClose(self)
    }

    @objc func goBack(_ sender: Any?) { model.frontPage?.goBack() }
    @objc func goForward(_ sender: Any?) { model.frontPage?.goForward() }
    @objc func reload(_ sender: Any?) { model.frontPage?.reload() }
    @objc func stopLoading(_ sender: Any?) { model.frontPage?.stopLoading() }
    @objc func expandPeek(_ sender: Any?) { model.expandPeek() }
    @objc func openLocation(_ sender: Any?) { model.focusAddressField += 1 }
    @objc func newTab(_ sender: Any?) { model.newTab() }
    @objc func selectNextTab(_ sender: Any?) { model.selectAdjacentTab(1) }
    @objc func selectPreviousTab(_ sender: Any?) { model.selectAdjacentTab(-1) }
    @objc func togglePin(_ sender: Any?) { model.togglePin() }

    @objc func newSpace(_ sender: Any?) {
        if let name = NamePrompt.run("New Space") { model.addSpace(named: name) }
    }

    @objc func renameSpace(_ sender: Any?) {
        guard let space = model.space, let name = NamePrompt.run("Rename Space", name: space.name) else { return }
        model.renameSpace(space.id, to: name)
    }

    @objc func deleteSpace(_ sender: Any?) {
        if let space = model.space { SpaceDeletion.confirm(space, in: model) }
    }

    @objc func viewArchive(_ sender: Any?) { model.viewArchive() }
    @objc func restoreLastClosed(_ sender: Any?) { model.restoreLastClosed() }

    @objc func clearArchive(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Clear the Archive?"
        alert.informativeText = "Every archived tab is removed. This can't be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { model.clearArchive() }
    }

    /// The Peek when one is shown, else the selected tab, else the window.
    @objc func closeTab(_ sender: Any?) {
        if model.peek != nil {
            model.closePeek()
        } else if let tabID = model.selectedTabID {
            model.close(tabID)
        } else {
            window?.performClose(sender)
        }
    }

    @objc func selectTab(_ sender: NSMenuItem) {
        if let index = tabIndex(for: sender) { model.selectTab(at: index) }
    }

    private func tabIndex(for item: NSMenuItem) -> Int? {
        let count = model.selectableTabs.count
        let index = item.tag == MainMenu.lastTabTag ? count - 1 : item.tag - 1
        return index >= 0 && index < count ? index : nil
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(togglePin(_:)) {
            guard let tabID = model.selectedTabID else { return false }
            item.title = model.state.isPinned(tabID) ? "Unpin Tab" : "Pin Tab"
            return true
        }
        if item.action == #selector(closeTab(_:)) {
            let archives = model.selectedTabID.map { !model.state.isPinned($0) } ?? false
            item.title = model.peek != nil ? "Close Peek" : archives ? "Archive Tab" : "Close Tab"
            return true
        }
        return switch item.action {
        case #selector(goBack(_:)): model.frontPage?.canGoBack ?? false
        case #selector(goForward(_:)): model.frontPage?.canGoForward ?? false
        case #selector(stopLoading(_:)): model.frontPage?.isLoading ?? false
        case #selector(expandPeek(_:)): model.peek != nil
        case #selector(selectNextTab(_:)), #selector(selectPreviousTab(_:)): !model.selectableTabs.isEmpty
        case #selector(selectTab(_:)): tabIndex(for: item) != nil
        case #selector(deleteSpace(_:)): model.state.spaces.count > 1
        case #selector(restoreLastClosed(_:)), #selector(clearArchive(_:)): !model.state.archive.isEmpty
        default: true
        }
    }
}
