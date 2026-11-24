import AppKit
import DevKit
import SwiftUI

@MainActor
final class BrowserWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    let model: WindowModel
    private let layout: WindowLayoutController
    private let engine: any BrowserApplication
    private let store: SidebarStore
    private let didClose: (BrowserWindowController) -> Void
    private var asking = false
    private let downloadPreview = DownloadPreviewWindow()
    private let extensionPopup = ExtensionPopupWindow()
    private var modalItemSwitcher: (state: ModalItemSwitcher, controller: ModalItemSwitcherWindowController)?
    private var viewTimer: Task<Void, Never>?
    /// As Arc's `BrowserWindow.windowButtons`: the title bar's own, taken before the sidebar's header makes its set,
    /// which the window would hand out in their place. They show only in full screen.
    private let windowButtons: [NSButton]

    init(
        id: UUID, engine: any BrowserApplication, store: SidebarStore, downloads: DownloadsStore,
        pictureInPicture: PictureInPicture, spaceID: UUID, didClose: @escaping (BrowserWindowController) -> Void
    ) {
        self.engine = engine
        self.store = store
        self.didClose = didClose
        model = WindowModel(
            id: id, engine: engine, store: store, downloads: downloads, pictureInPicture: pictureInPicture,
            spaceID: spaceID)
        layout = WindowLayoutController(model: model)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentMinSize = NSSize(width: 640, height: 320)
        // As Arc's browser windows: AppKit keeps them across a quit and hands them back by the window's ID.
        window.identifier = NSUserInterfaceItemIdentifier(id.uuidString)
        window.restorationClass = ApplicationDelegate.self
        window.isRestorable = true
        windowButtons = [.closeButton, .miniaturizeButton, .zoomButton].compactMap(window.standardWindowButton)
        windowButtons.forEach { $0.isHidden = true }
        super.init(window: window)
        window.contentViewController = layout
        window.setContentSize(NSSize(width: 1100, height: 760))
        window.delegate = self
        model.bringToFront = { [weak window] in window?.makeKeyAndOrderFront(nil) }
        model.window = window
        model.undoManager = ArcUndoManager(window.undoManager) { [weak model] in model?.perform($0) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func open(cascadingFrom previous: NSWindow?) {
        guard let window else { return }
        engine.attachWindow(window, id: model.id)
        store.addWindow(model)
        model.ensureBrowsersCreated()
        if let previous {
            window.setFrameTopLeftPoint(
                window.cascadeTopLeft(from: NSPoint(x: previous.frame.minX, y: previous.frame.maxY)))
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        observeTitle()
        observeDownloadPreview()
        observeExtensionPopup()
        observeModalItemSwitcher()
        // As Arc's per-window timer: each minute the shown tab counts as viewed, unless the window is fully hidden.
        viewTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self, !Task.isCancelled else { return }
                if self.window?.occlusionState.contains(.visible) == true { model.markShownViewed() }
            }
        }
    }

    private func observeDownloadPreview() {
        let shown = withObservationTracking {
            model.previewedDownload != nil
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeDownloadPreview() }
        }
        guard let window else { return }
        if shown { downloadPreview.show(over: window, model: model) } else { downloadPreview.close() }
    }

    private func observeExtensionPopup() {
        let popup = withObservationTracking {
            _ = model.extensionPopup?.size
            return model.extensionPopup
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeExtensionPopup() }
        }
        guard let window, let popup else { return extensionPopup.close() }
        extensionPopup.show(popup, over: window) { [weak self] in self?.model.closeExtensionPopup() }
    }

    /// As Arc's `WindowViewController`: the switcher's window controller lives as long as the window's switcher.
    private func observeModalItemSwitcher() {
        let switcher = withObservationTracking {
            model.modalItemSwitcher
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeModalItemSwitcher() }
        }
        guard modalItemSwitcher?.state !== switcher else { return }
        modalItemSwitcher?.controller.close()
        modalItemSwitcher = nil
        guard let window, let switcher else { return }
        let controller = ModalItemSwitcherWindowController(model: model, switcher: switcher, parent: window)
        modalItemSwitcher = (switcher, controller)
        controller.beginObservingEvents()
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

    func windowDidEnterFullScreen(_ notification: Notification) { windowButtons.forEach { $0.isHidden = false } }
    func windowWillExitFullScreen(_ notification: Notification) { windowButtons.forEach { $0.isHidden = true } }

    func windowDidBecomeKey(_ notification: Notification) {
        model.showSelected()
        if model.dialog == nil { model.page?.activate() }
    }

    /// Only the last window asks, as Arc's does: another one takes the pages over.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard store.windows.count == 1 else { return true }
        guard !asking else { return false }
        asking = true
        Task {
            if await engine.askToLeave(windowID: model.id) { sender.close() }
            asking = false
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        viewTimer?.cancel()
        model.dismissModalItemSwitcher()
        modalItemSwitcher?.controller.close()
        downloadPreview.close()
        extensionPopup.close()
        model.dropAll()
        store.removeWindow(model)
        engine.closeWindow(id: model.id)
        didClose(self)
    }

    @objc func goBack(_ sender: Any?) { model.frontPage?.goBack() }
    @objc func goForward(_ sender: Any?) { model.frontPage?.goForward() }
    @objc func reload(_ sender: Any?) { model.frontPage?.reload() }
    @objc func forceReload(_ sender: Any?) { model.frontPage?.reloadBypassingCache() }
    @objc func stopLoading(_ sender: Any?) { model.frontPage?.stopLoading() }
    @objc func expandPeek(_ sender: Any?) { model.expandPeek() }
    @objc func openLocation(_ sender: Any?) { model.openCommandBar(.currentTab) }
    @objc func newTab(_ sender: Any?) { model.openCommandBar(.newTab) }
    @objc func addSplitView(_ sender: Any?) { model.addSplitViewPane() }
    /// As seen in Arc: the same as closing the focused pane's tab.
    @objc func closeFocusedSplitViewPanel(_ sender: Any?) { model.selectedTabID.map { model.close($0) } }
    @objc func separateTabFromSplitView(_ sender: Any?) { model.selectedTabID.map(model.separateFromSplitView) }
    @objc func switchToSplitViewPane(_ sender: NSMenuItem) { model.switchToSplitViewPane(at: sender.tag - 1) }
    @objc func switchToNextSplitViewPane(_ sender: Any?) { model.switchToAdjacentSplitViewPane(offset: 1) }
    @objc func switchToPreviousSplitViewPane(_ sender: Any?) { model.switchToAdjacentSplitViewPane(offset: -1) }
    @objc func selectNextTab(_ sender: Any?) { model.selectAdjacentTab(1) }
    @objc func selectPreviousTab(_ sender: Any?) { model.selectAdjacentTab(-1) }
    @objc func cycleToNextRecentTab(_ sender: Any?) { model.highlightAdjacentRecentTab(.next) }
    @objc func cycleToPreviousRecentTab(_ sender: Any?) { model.highlightAdjacentRecentTab(.previous) }
    @objc func togglePin(_ sender: Any?) { model.togglePin() }
    @objc func focusSidebar(_ sender: Any?) { layout.revealCurrentTab() }
    @objc func toggleFavorite(_ sender: Any?) { model.toggleFavorite() }

    /// As Arc's File ▸ New Profile: the create sheet with the window's Space ticked.
    @objc func newProfile(_ sender: Any?) {
        ProfileDialogUtils.createProfile(checking: [model.selectedSpaceID], in: model)
    }

    @objc func togglePinnedSection(_ sender: Any?) {
        if let space = model.space { model.togglePinnedSection(of: space.id) }
    }

    @objc func newSpace(_ sender: Any?) {
        model.beginSpaceCreation(after: model.selectedSpaceID)
    }

    @objc func renameSpace(_ sender: Any?) {
        guard let space = model.space, let name = NamePrompt.run("Rename Space", name: space.name) else { return }
        model.renameSpace(space.id, to: name)
    }

    @objc func editTheme(_ sender: Any?) {
        if let space = model.space { model.presentSpaceStyleEditor(for: space.id, from: .sidebar) }
    }

    @objc func changeProfile(_ sender: Any?) {
        if let space = model.space { ProfileDialogUtils.changeProfile(of: space, in: model) }
    }

    @objc func deleteSpace(_ sender: Any?) {
        if let space = model.space { SpaceDeletion.confirm(space, in: model) }
    }

    @objc func nextSpace(_ sender: Any?) { model.selectAdjacentSpace(1) }
    @objc func previousSpace(_ sender: Any?) { model.selectAdjacentSpace(-1) }
    @objc func focusSpace(_ sender: NSMenuItem) { model.selectSpace(at: sender.tag - 1) }

    @objc func toggleArchive(_ sender: Any?) {
        if model.showingArchive { model.exitLibrary() } else { model.viewLibrary(.archive) }
    }
    @objc func viewHistory(_ sender: Any?) { model.viewHistory() }

    @objc func toggleLibrary(_ sender: Any?) {
        if model.library != nil { model.exitLibrary() } else { model.viewLibrary() }
    }

    @objc func toggleDownloads(_ sender: Any?) {
        if model.showingDownloads { model.exitLibrary() } else { model.viewLibrary(.downloads) }
    }
    /// Not `toggleSidebar:`, which AppKit's own responders answer first, as Arc's `toggleArcSidebar:` isn't.
    @objc func toggleSidebarMode(_ sender: Any?) {
        // Oa's own: Spaces takes over the sidebar's spot, so dismiss it to reveal the result of the toggle.
        if model.library == .spaces { model.exitLibrary() }
        layout.toggleSidebar()
    }
    @objc func restoreLastClosed(_ sender: Any?) { model.restoreLastClosed() }
    @objc func clearTabs(_ sender: Any?) { model.clearTabs() }
    @objc func copyCurrentURL(_ sender: Any?) { model.copyCurrentURLs() }
    @objc func copyCurrentURLAsMarkdown(_ sender: Any?) { model.copyCurrentURLs(asMarkdown: true) }
    @objc func addExtension(_ sender: Any?) { model.addExtension() }
    @objc func manageExtensions(_ sender: Any?) { model.manageExtensions() }

    @objc func runExtension(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { model.runExtension(id) }
    }

    @objc func clearArchive(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Clear the Archive?"
        alert.informativeText = "Every archived tab is removed. This can't be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { model.clearArchive() }
    }

    /// The Peek when one is shown, else the multi-selection, else the selected tab, else the window.
    @objc func closeTab(_ sender: Any?) {
        let rows = model.multiSelectedTabIDs
        if model.peek != nil {
            model.closePeek()
        } else if !rows.isEmpty {
            // As seen in Arc: the rows go whatever is shown; a Favorite stays, and a split goes whole with them. Oa's
            // own: a pinned split is unloaded, as by ⌘W alone.
            let splitID = model.selectedTabID.flatMap {
                rows.contains($0) || model.state.isFavorite($0) ? nil : model.state.splitViewID(containing: $0)
            }
            let pinned = model.selectedTabID.map(model.state.isPinned) ?? false
            // The split first: a loaded row's close finishes later, and the split's would pick it to show.
            if let splitID { pinned ? model.closeSplitViewPages(splitID) : model.closeSplitView(splitID) }
            model.archiveTabs(rows)
        } else if let tabID = model.selectedTabID {
            if model.state.splitViewID(containing: tabID) != nil, model.state.isFavorite(tabID) {
                model.deselectSplitView()
            } else if model.state.isPinned(tabID), let splitID = model.state.splitViewID(containing: tabID) {
                // As seen in Arc: ⌘W on a pinned split's pane unloads the whole split.
                model.closeSplitViewPages(splitID)
            } else {
                model.close(tabID)
            }
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

    /// The window's commands wait while a dialog is up, as Arc swallows them; other windows and quit stay usable.
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        // Arc takes Archive Tab out of the menu while a download's preview shows.
        if item.action == #selector(expandPeek(_:)) {
            // As seen in Arc: the shown Space's name, wherever Air Traffic Control sends it.
            item.title = model.peek != nil ? "Open in \(model.space?.name ?? "")" : "Expand Peek"
            return model.peek != nil
        }
        if item.action == #selector(closeTab(_:)) {
            item.isHidden = model.previewedDownload != nil
            if item.isHidden { return false }
        }
        if model.dialog != nil || model.extensionRequest != nil { return false }
        // Oa's own, as Arc's isn't traced: ⌘← and ⌘→ stay with a text field that is editing.
        if (item as? KeyBindableMenuItem)?.arcKeyBindingID.hasSuffix("_Alternate") == true,
            window?.firstResponder is NSText
        {
            return false
        }
        // As Arc: the Create a Space panel holds back creating and editing a Space, not moving between them.
        let editsSpace = [
            #selector(newSpace(_:)), #selector(renameSpace(_:)), #selector(editTheme(_:)), #selector(changeProfile(_:)),
        ]
        if model.spaceCreation != nil, let action = item.action, editsSpace.contains(action) { return false }
        if item.action == #selector(runExtension(_:)) {
            return model.extensionActions.contains { $0.id == item.representedObject as? String }
        }
        if item.action == #selector(togglePin(_:)) {
            guard let tabID = model.selectedTabID, !model.state.isFavorite(tabID) else { return false }
            item.title = model.state.isPinned(tabID) ? "Unpin Tab" : "Pin Tab"
            return true
        }
        if item.action == #selector(toggleFavorite(_:)) {
            guard let tabID = model.selectedTabID else { return false }
            item.title = model.state.isFavorite(tabID) ? "Unfavorite Tab" : "Favorite Tab"
            return true
        }
        if item.action == #selector(togglePinnedSection(_:)) {
            let collapsed = model.space.map { model.collapsedPinnedSpaces.contains($0.id) } ?? false
            item.title = collapsed ? "Expand Pinned Tabs" : "Collapse Pinned Tabs"
            return model.space != nil && model.spaceCreation == nil
        }
        if item.action == #selector(toggleSidebarMode(_:)) {
            item.title = model.sidebarMode == .anchored ? "Hide Sidebar" : "Show Sidebar"
            return true
        }
        if item.action == #selector(focusSpace(_:)) {
            // As seen in Arc: the window's Space is ticked.
            let spaces = model.state.spaces
            item.state =
                spaces.indices.contains(item.tag - 1) && spaces[item.tag - 1].id == model.selectedSpaceID ? .on : .off
            return true
        }
        if item.action == #selector(toggleLibrary(_:)) {
            item.title = model.library != nil ? "Close Library" : "Open Library…"
            return true
        }
        if item.action == #selector(toggleDownloads(_:)) {
            item.title = model.showingDownloads ? "Hide Downloads" : "View Downloads…"
            return true
        }
        if item.action == #selector(toggleArchive(_:)) {
            item.title = model.showingArchive ? "Hide Archive" : "View Archive…"
            return true
        }
        if item.action == #selector(expandPeek(_:)) {
            // As seen in Arc: the shown Space's name, wherever Air Traffic Control sends it.
            item.title = model.peek != nil ? "Open in \(model.space?.name ?? "")" : "Expand Peek"
            return model.peek != nil
        }
        if item.action == #selector(closeTab(_:)) {
            let archives = model.selectedTabID.map { !model.state.keepsAddress($0) } ?? false
            item.title =
                model.peek != nil
                ? "Close Peek"
                : !model.multiSelectedTabIDs.isEmpty ? "Archive Tabs" : archives ? "Archive Tab" : "Close Tab"
            return true
        }
        return switch item.action {
        case #selector(goBack(_:)): model.frontPage?.canGoBack ?? false
        case #selector(goForward(_:)): model.frontPage?.canGoForward ?? false
        case #selector(stopLoading(_:)): model.frontPage?.isLoading ?? false
        case #selector(addSplitView(_:)): model.canAddSplitViewPane
        case #selector(closeFocusedSplitViewPanel(_:)), #selector(separateTabFromSplitView(_:)),
            #selector(switchToNextSplitViewPane(_:)), #selector(switchToPreviousSplitViewPane(_:)):
            model.presentedTabIDs.count > 1
        case #selector(switchToSplitViewPane(_:)):
            model.presentedTabIDs.count > 1 && item.tag <= model.presentedTabIDs.count
        case #selector(selectNextTab(_:)), #selector(selectPreviousTab(_:)): !model.selectableTabs.isEmpty
        case #selector(selectTab(_:)): tabIndex(for: item) != nil
        case #selector(deleteSpace(_:)): model.state.spaces.count > 1
        case #selector(restoreLastClosed(_:)): model.canRestoreLastClosed
        case #selector(clearTabs(_:)): model.canClearTabs
        // Oa's own: with no tab Arc's stays on and offers to share the Space.
        case #selector(copyCurrentURL(_:)), #selector(copyCurrentURLAsMarkdown(_:)): model.address != nil
        case #selector(clearArchive(_:)): !model.state.archive.isEmpty
        default: true
        }
    }
}
