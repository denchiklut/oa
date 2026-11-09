import AppKit
import DevKit
import Foundation
import Observation

/// A window's selection over the shared sidebar state, and the pages it holds. A page exists only once the
/// tab was shown here; one live page per tab across windows, and it moves to the window that shows the tab.
@MainActor
@Observable
final class WindowModel {
    let id: UUID
    private(set) var selectedSpaceID: UUID
    private(set) var selectedTabIDs: [UUID: UUID] = [:]
    private(set) var pages: [UUID: any Page] = [:]
    /// Last frames of pages that left for another window while their tab stayed selected here.
    private(set) var placeholders: [UUID: NSImage] = [:]
    /// Pages shown over the window as Arc's Peek: by the tab they were opened from, whose state they are, or by
    /// the Archive entry they show.
    private(set) var peeks: [UUID: any Page] = [:]
    private(set) var showingArchive = false {
        didSet { if !showingArchive { closeArchivePeek() } }
    }
    var focusAddressField = 0
    @ObservationIgnored var bringToFront: () -> Void = {}
    @ObservationIgnored private let engine: any BrowserApplication
    @ObservationIgnored private let store: SidebarStore
    @ObservationIgnored private var previousTabID: UUID?
    @ObservationIgnored private var pendingURLs: [UUID: URL] = [:]
    @ObservationIgnored private var creating: [UUID: UUID] = [:]
    private var archivePeekID: UUID?

    var state: SidebarState { store.state }
    var space: SidebarSpace? { state.space(selectedSpaceID) }
    var selectedTabID: UUID? { selectedTabIDs[selectedSpaceID] }
    var selectedTab: SidebarTab? { selectedTabID.flatMap { state.tree.tab($0) } }
    var page: (any Page)? { selectedTabID.flatMap { pages[$0] } }
    var placeholder: NSImage? { page == nil ? selectedTabID.flatMap { placeholders[$0] } : nil }
    var peek: (any Page)? { peekOwnerID.flatMap { peeks[$0] } }
    /// What the toolbar commands act on: the Peek while one is shown.
    var frontPage: (any Page)? { peek ?? page }
    private var peekOwnerID: UUID? { showingArchive ? archivePeekID : selectedTabID }
    /// What the address field shows: the live page's URL, else the tab's saved one while its page is pending.
    var address: URL? { page?.url ?? selectedTab?.url }
    var pinnedTabs: [SidebarTab] { state.tabs(in: selectedSpaceID, pinned: true) }
    var unpinnedTabs: [SidebarTab] { state.tabs(in: selectedSpaceID, pinned: false) }
    var selectableTabs: [SidebarTab] { state.selectableTabs(in: selectedSpaceID) }

    var record: WindowRecord { WindowRecord(id: id, selectedSpaceID: selectedSpaceID) }

    init(id: UUID, engine: any BrowserApplication, store: SidebarStore, spaceID: UUID) {
        self.id = id
        self.engine = engine
        self.store = store
        selectedSpaceID = spaceID
    }

    /// As Arc: a restored window comes back on its Space with nothing selected and no page.
    func restore(_ record: WindowRecord) {
        if state.space(record.selectedSpaceID) != nil { selectedSpaceID = record.selectedSpaceID }
        focusAddressField += 1
    }

    /// A pinned tab whose page has left its address reads "/ live title", as in Arc.
    func title(for tab: SidebarTab) -> String {
        guard state.isPinned(tab.id), let page = pages[tab.id], let url = page.url, !tab.isAt(url) else {
            return tab.displayTitle
        }
        return "/ " + (page.title.isEmpty ? url.host() ?? url.absoluteString : page.title)
    }

    func favicon(for tab: SidebarTab) -> NSImage? {
        (pages[tab.id] ?? store.windows.lazy.compactMap { $0.pages[tab.id] }.first)?.favicon
    }

    /// Only the only window picks a tab: first unpinned, else first pinned. Another window starts empty.
    func showFirst(isOnlyWindow: Bool) {
        if isOnlyWindow, let first = state.firstTabID(in: selectedSpaceID) {
            select(first)
        } else {
            focusAddressField += 1
        }
    }

    func newTab(_ url: URL? = nil) {
        let tab = SidebarTab(id: UUID(), url: url, viewedAt: .now)
        store.edit { $0.appendTab(tab, in: selectedSpaceID) }
        select(tab.id)
    }

    func select(_ tabID: UUID) {
        guard state.space(containing: tabID)?.id == selectedSpaceID, selectedTabID != tabID else { return }
        showingArchive = false
        if let current = selectedTabID {
            if pages[current] != nil { previousTabID = current }
            placeholders[current] = nil
            handOff(current)
        }
        selectedTabIDs[selectedSpaceID] = tabID
        store.markViewed(tabID)
        ensurePage(tabID)
    }

    /// Wraps at either end. With no selection, forward selects the first tab and backward the last.
    func selectAdjacentTab(_ offset: Int) {
        let tabs = selectableTabs
        guard let last = tabs.indices.last else { return }
        guard let selectedTabID, let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else {
            return select(tabs[offset > 0 ? 0 : last].id)
        }
        select(tabs[(index + offset + tabs.count) % tabs.count].id)
    }

    func selectTab(at index: Int) {
        let tabs = selectableTabs
        if tabs.indices.contains(index) { select(tabs[index].id) }
    }

    func selectSpace(_ spaceID: UUID) {
        guard state.space(spaceID) != nil, spaceID != selectedSpaceID else { return }
        selectedSpaceID = spaceID
        if let tabID = selectedTabID { ensurePage(tabID) } else { focusAddressField += 1 }
        store.windowStateChanged()
    }

    /// On becoming key, the selected tab takes its page back from the window that holds it.
    func showSelected() {
        guard let tabID = selectedTabID, pages[tabID] == nil,
            store.windows.contains(where: { $0 !== self && $0.pages[tabID] != nil })
        else { return }
        ensurePage(tabID)
    }

    func addSpace(named name: String) {
        guard let profileID = space?.profileID else { return }
        var created: SidebarSpace?
        store.edit { created = $0.addSpace(name: name, profileID: profileID) }
        if let created { selectSpace(created.id) }
    }

    func renameSpace(_ spaceID: UUID, to name: String) {
        store.edit { $0.renameSpace(spaceID, to: name) }
    }

    /// Pages of the Space's tabs are dropped in every window. This window moves to the neighbor above, else below.
    func deleteSpace(_ spaceID: UUID) {
        let spaces = state.spaces
        guard spaces.count > 1, let index = spaces.firstIndex(where: { $0.id == spaceID }) else { return }
        if selectedSpaceID == spaceID { selectSpace(spaces[index == 0 ? 1 : index - 1].id) }
        store.edit { $0.removeSpace(spaceID) }
    }

    func togglePin() {
        guard let tabID = selectedTabID else { return }
        store.edit { $0.togglePin(tabID) }
    }

    func viewArchive() {
        showingArchive = true
    }

    func exitArchive() {
        showingArchive = false
    }

    func restoreArchived(_ id: UUID) {
        store.edit { $0.restoreArchived(id, in: selectedSpaceID, toOldPosition: false) }
    }

    /// As Arc: the row's page in a Peek over the list, from the saved URL with no history; the entry stays.
    func peekArchived(_ entryID: UUID) {
        guard let entry = state.archive.first(where: { $0.id == entryID }), let url = entry.url,
            let profileID = (state.space(entry.spaceID) ?? space)?.profileID
        else { return }
        closeArchivePeek()
        archivePeekID = entryID
        let context = engine.browserContext(id: profileID)
        Task { [weak self, id] in
            guard let page = await context.makePage(id: entryID, windowID: id), let self else { return }
            guard showingArchive, archivePeekID == entryID else { return page.drop() }
            peeks[entryID] = page
            listen(to: page, for: entryID)
            page.load(url)
        }
    }

    /// Expand: an opened Peek becomes a selected tab after its opener's earlier children, as Arc does; an Archive
    /// Peek's entry leaves the Archive for the top of the shown Space.
    func expandPeek() {
        guard let ownerID = peekOwnerID, let page = peeks.removeValue(forKey: ownerID) else { return }
        var tab = SidebarTab(id: page.id, title: page.title, url: page.url, viewedAt: .now)
        if ownerID == archivePeekID {
            archivePeekID = nil
            store.edit {
                $0.removeArchived(ownerID)
                $0.insertTab(tab, atTopOf: selectedSpaceID)
            }
        } else {
            tab.openerID = ownerID
            store.edit { $0.openTab(tab, from: ownerID) }
        }
        install(page, for: tab.id)
        select(tab.id)
    }

    /// ✕, the backdrop and ⌘W: an opened Peek's page is archived under its tab's Space, as Arc does; an Archive
    /// Peek keeps its entry.
    func closePeek() {
        guard let ownerID = peekOwnerID, let page = peeks.removeValue(forKey: ownerID) else { return }
        if ownerID == archivePeekID {
            archivePeekID = nil
        } else if let spaceID = state.space(containing: ownerID)?.id {
            store.edit { $0.archivePage(id: page.id, title: page.title, url: page.url, in: spaceID) }
        }
        page.close()
        self.page?.activate()
    }

    func restoreLastClosed() {
        guard let entry = state.archive.last else { return }
        var spaceID: UUID?
        store.edit { spaceID = $0.restoreArchived(entry.id, in: selectedSpaceID, toOldPosition: true) }
        guard let spaceID else { return }
        selectSpace(spaceID)
        select(entry.id)
    }

    func deleteArchived(_ id: UUID) {
        store.edit { $0.removeArchived(id) }
    }

    func clearArchive() {
        store.edit { $0.clearArchive() }
    }

    /// Typed input: a URL as typed, a host, or a search. Search fallback is a product decision for slice 1.
    func navigate(to input: String) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let url: URL
        if let typed = URL(string: text), typed.scheme != nil, typed.host() != nil || typed.scheme == "file" {
            url = typed
        } else if !text.contains(" "), text.contains("."), let host = URL(string: "https://\(text)") {
            url = host
        } else {
            var components = URLComponents(string: "https://www.google.com/search")!
            components.queryItems = [URLQueryItem(name: "q", value: text)]
            url = components.url!
        }
        guard let tabID = selectedTabID else { return newTab(url) }
        if let page = pages[tabID] {
            page.load(url)
            page.activate()
        } else {
            pendingURLs[tabID] = url
            ensurePage(tabID)
        }
    }

    /// ⌘W. An unpinned tab is archived and its page, wherever it lives, closed as the user would; a pinned one
    /// keeps its entry and drops its page.
    func close(_ tabID: UUID) {
        end(tabID) { page, pinned in pinned ? page.drop() : page.close() }
    }

    /// Window close and quit: a page whose tab another window shows moves there; the rest are dropped without
    /// unload handlers. The records stay.
    func dropAll() {
        for tabID in Array(pages.keys) {
            guard let page = release(tabID) else { continue }
            if let heir = store.windows.first(where: { $0 !== self && $0.shows(tabID) }) {
                heir.adopt(page, for: tabID, from: self)
            } else {
                page.drop()
            }
        }
        for (ownerID, page) in peeks {
            if ownerID != archivePeekID { store.archivePage(page, in: spaceID(ofPeekOwner: ownerID)) }
            page.drop()
        }
        peeks = [:]
        archivePeekID = nil
        creating = [:]
    }

    /// Lets go of the page for `tabID` without ending it. Another window takes it over this way.
    @discardableResult
    func release(_ tabID: UUID) -> (any Page)? {
        creating.removeValue(forKey: tabID)
        pendingURLs.removeValue(forKey: tabID)
        if previousTabID == tabID { previousTabID = nil }
        return pages.removeValue(forKey: tabID)
    }

    func releasePeek(_ tabID: UUID) -> (any Page)? {
        peeks.removeValue(forKey: tabID)
    }

    /// After a state edit: selections, placeholders and pages of tabs or Spaces that are gone go too.
    func reconcile() {
        if space == nil, let first = state.spaces.first { selectedSpaceID = first.id }
        for (spaceID, tabID) in selectedTabIDs where state.space(containing: tabID)?.id != spaceID {
            selectedTabIDs.removeValue(forKey: spaceID)
        }
        for tabID in Array(pages.keys) where state.tree.tab(tabID) == nil { release(tabID)?.drop() }
        for (tabID, page) in pages where page.keepsAddress != state.isPinned(tabID) {
            page.keepsAddress = state.isPinned(tabID)
        }
        for (ownerID, page) in peeks where ownerID != archivePeekID && state.tree.tab(ownerID) == nil {
            peeks[ownerID] = nil
            store.archivePage(page, in: spaceID(ofPeekOwner: ownerID))
            page.close()
        }
        for tabID in Array(creating.keys) where state.tree.tab(tabID) == nil { release(tabID) }
        for tabID in Array(placeholders.keys) where state.tree.tab(tabID) == nil { placeholders[tabID] = nil }
        if let previousTabID, state.tree.tab(previousTabID) == nil { self.previousTabID = nil }
    }

    private func shows(_ tabID: UUID) -> Bool {
        selectedTabID == tabID && pages[tabID] == nil
    }

    private func spaceID(ofPeekOwner ownerID: UUID) -> UUID {
        state.space(containing: ownerID)?.id ?? state.archive.last { $0.id == ownerID }?.spaceID ?? selectedSpaceID
    }

    private func closeArchivePeek() {
        guard let entryID = archivePeekID else { return }
        archivePeekID = nil
        peeks.removeValue(forKey: entryID)?.close()
    }

    private func end(_ tabID: UUID, _ finish: (any Page, Bool) -> Void) {
        guard let spaceID = state.space(containing: tabID)?.id else { return }
        let pinned = state.isPinned(tabID)
        let wasSelected = selectedTabIDs[spaceID] == tabID
        let next = wasSelected ? nextSelection(closing: tabID, pinned: pinned, in: spaceID) : nil
        let page = store.windows.compactMap { $0.release(tabID) }.first
        for window in store.windows { window.placeholders[tabID] = nil }
        if !pinned { store.edit { $0.archiveTab(tabID, reason: .manual) } }
        if let page { finish(page, pinned) }
        if wasSelected {
            selectedTabIDs[spaceID] = next
            if let next, spaceID == selectedSpaceID { ensurePage(next) }
        }
    }

    /// The opener's group first, as in Arc; else the tab shown before, if its page is still live; an unpinned close
    /// then falls back to the tab above, else below.
    private func nextSelection(closing tabID: UUID, pinned: Bool, in spaceID: UUID) -> UUID? {
        if let successor = state.openerSuccessor(of: tabID) { return successor }
        if let previousTabID, previousTabID != tabID, pages[previousTabID] != nil,
            state.space(containing: previousTabID)?.id == spaceID
        {
            return previousTabID
        }
        guard !pinned else { return nil }
        let tabs = state.selectableTabs(in: spaceID)
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return nil }
        return index > 0 ? tabs[index - 1].id : tabs.count > 1 ? tabs[1].id : nil
    }

    /// Takes the page over from the window that holds it, else creates it.
    private func ensurePage(_ tabID: UUID) {
        guard pages[tabID] == nil, creating[tabID] == nil else { return }
        let token = UUID()
        creating[tabID] = token
        if let holder = store.windows.first(where: { $0 !== self && $0.pages[tabID] != nil }) {
            Task { [weak self] in
                await holder.keepFrame(tabID)
                guard let self, creating[tabID] == token else { return }
                creating.removeValue(forKey: tabID)
                guard let page = holder.release(tabID) else { return }
                adopt(page, for: tabID, from: holder)
                holder.keepFrameLater(of: page, for: tabID)
            }
            return
        }
        guard let space = state.space(containing: tabID), let profile = state.profile(space.profileID) else {
            creating.removeValue(forKey: tabID)
            return
        }
        let context = engine.browserContext(id: profile.id)
        Task { [weak self, id] in
            guard let page = await context.makePage(id: tabID, windowID: id), let self else { return }
            guard creating[tabID] == token, let tab = state.tree.tab(tabID) else { return page.drop() }
            creating.removeValue(forKey: tabID)
            install(page, for: tabID)
            listen(to: page, for: tabID)
            if let url = pendingURLs.removeValue(forKey: tabID) ?? tab.url { page.load(url) }
        }
    }

    private func handOff(_ tabID: UUID) {
        guard let heir = store.windows.first(where: { $0 !== self && $0.shows(tabID) }), let page = release(tabID)
        else { return }
        heir.adopt(page, for: tabID, from: self)
    }

    /// The tab's Peek, its state, comes along.
    private func adopt(_ page: any Page, for tabID: UUID, from holder: WindowModel) {
        page.move(toWindow: id)
        if let peek = holder.releasePeek(tabID) {
            peek.move(toWindow: id)
            peeks[tabID] = peek
        }
        placeholders[tabID] = nil
        install(page, for: tabID)
    }

    /// Before the page leaves: the frame can only be copied while the page still draws here.
    private func keepFrame(_ tabID: UUID) async {
        guard selectedTabID == tabID, let page = pages[tabID], let image = await page.snapshot() else { return }
        placeholders[tabID] = image
    }

    private func keepFrameLater(of page: any Page, for tabID: UUID) {
        guard placeholders[tabID] == nil else { return }
        Task { [weak self] in
            for _ in 0..<2 {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, placeholders[tabID] == nil, selectedTabID == tabID, pages[tabID] == nil else { return }
                if let image = await page.snapshot() { placeholders[tabID] = image }
            }
        }
    }

    private func install(_ page: any Page, for tabID: UUID) {
        pages[tabID] = page
        page.keepsAddress = state.isPinned(tabID)
        observe(page, for: tabID)
    }

    /// The stream has one consumer, so a page gets one loop for its life, delivering to whichever window holds it.
    private func listen(to page: any Page, for tabID: UUID) {
        let store = store
        Task {
            for await event in page.events {
                store.windows.first { $0.holds(tabID) }?.handle(event, for: tabID)
            }
        }
    }

    private func holds(_ pageID: UUID) -> Bool {
        pages[pageID] != nil || peekOwner(of: pageID) != nil
    }

    private func peekOwner(of pageID: UUID) -> UUID? {
        peeks.first { $0.value.id == pageID }?.key
    }

    private func handle(_ event: PageEvent, for pageID: UUID) {
        if let ownerID = peekOwner(of: pageID) {
            switch event {
            case .opened(let opened, let url, let disposition):
                place(opened, url: url, disposition: disposition, from: ownerID, insidePeek: true)
            case .wantsActivation:
                if ownerID != archivePeekID { show(ownerID) } else { bringToFront() }
            case .closed:
                peeks[ownerID] = nil
                if ownerID == archivePeekID { archivePeekID = nil }
                page?.activate()
            }
            return
        }
        switch event {
        case .opened(let opened, let url, let disposition):
            place(opened, url: url, disposition: disposition, from: pageID, insidePeek: false)
        case .wantsActivation:
            show(pageID)
        case .closed:
            pageEnded(pageID)
        }
    }

    /// As Arc: a Shift-click from any tab, which the engine reports as a new window, and a pinned tab's foreground
    /// opens show a Peek; a Peek's own opens become tabs of its tab; the rest go below the opener. A page from an
    /// Archive Peek has no tab to join, so it goes to the top of the shown Space.
    private func place(
        _ page: any Page, url: URL?, disposition: OpenDisposition, from openerID: UUID, insidePeek: Bool
    ) {
        guard let space = state.space(containing: openerID) else {
            guard insidePeek, openerID == archivePeekID else { return page.drop() }
            let tab = SidebarTab(id: page.id, url: url, viewedAt: .now)
            store.edit { $0.insertTab(tab, atTopOf: selectedSpaceID) }
            install(page, for: tab.id)
            listen(to: page, for: tab.id)
            return select(tab.id)
        }
        let background = disposition == .backgroundTab
        if !insidePeek, disposition == .newWindow || (!background && state.isPinned(openerID)) {
            return peek(page, from: openerID)
        }
        let tab = SidebarTab(id: page.id, url: url, viewedAt: .now, openerID: openerID)
        store.edit { $0.openTab(tab, from: openerID) }
        install(page, for: tab.id)
        listen(to: page, for: tab.id)
        if !background, space.id == selectedSpaceID { select(tab.id) }
    }

    /// A tab has one Peek: a new one takes the place of the current one, which closes as with ✕.
    private func peek(_ page: any Page, from openerID: UUID) {
        if let current = peeks[openerID], let spaceID = state.space(containing: openerID)?.id {
            store.edit { $0.archivePage(id: current.id, title: current.title, url: current.url, in: spaceID) }
            current.close()
        }
        peeks[openerID] = page
        listen(to: page, for: page.id)
    }

    /// Switches to the tab's Space and raises the window, as Arc does for a page asking to be shown.
    private func show(_ tabID: UUID) {
        guard let spaceID = state.space(containing: tabID)?.id else { return }
        if spaceID != selectedSpaceID {
            showingArchive = false
            selectedTabIDs[spaceID] = tabID
            selectSpace(spaceID)
            store.markViewed(tabID)
        } else {
            select(tabID)
        }
        bringToFront()
    }

    private func observe(_ page: any Page, for tabID: UUID) {
        let identity = ObjectIdentifier(page)
        withObservationTracking {
            _ = page.title
            _ = page.url
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let page = pages[tabID], ObjectIdentifier(page) == identity else { return }
                store.setSavedPage(tabID, title: page.title, url: page.url)
                observe(page, for: tabID)
            }
        }
    }

    private func pageEnded(_ tabID: UUID) {
        guard pages[tabID] != nil else { return }
        end(tabID) { _, _ in }
    }
}
