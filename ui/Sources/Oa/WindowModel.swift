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
    private(set) var dialogs: [UUID: [PageDialog]] = [:]
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
    /// Over the whole window as Arc draws it, so a tab's own page can ask while its Peek is up.
    var dialog: PageDialog? { [peek, page].lazy.compactMap { $0.flatMap { self.dialogs[$0.id]?.last } }.first }
    private var peekOwnerID: UUID? { showingArchive ? archivePeekID : selectedTabID }
    /// What the address field shows: the live page's URL, else the tab's saved one while its page is pending.
    var address: URL? { page?.url ?? selectedTab?.url }
    var favorites: [SidebarTab] { state.favorites(for: selectedSpaceID) }
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

    /// A pinned tab whose page has left its address reads "/ live title", as in Arc; a Favorite, whose tile has no
    /// text, gives the window the live title as Arc's does.
    func title(for tab: SidebarTab) -> String {
        guard state.keepsAddress(tab.id), let page = pages[tab.id], let url = page.url, !tab.isAt(url) else {
            return tab.displayTitle
        }
        let live = page.title.isEmpty ? url.host() ?? url.absoluteString : page.title
        return state.isFavorite(tab.id) ? live : "/ " + live
    }

    /// The live page's favicon, wherever the page lives, else the saved one, as Arc shows it.
    func favicon(for tab: SidebarTab) -> NSImage? {
        (pages[tab.id] ?? store.windows.lazy.compactMap { $0.pages[tab.id] }.first)?.favicon
            ?? store.savedFavicon(tab.id)
    }

    func savedFavicon(_ id: UUID) -> NSImage? { store.savedFavicon(id) }

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
        guard state.isSelectable(tabID, in: selectedSpaceID), selectedTabID != tabID else { return }
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

    /// As Arc: every live page of the Space, Peeks too, closes at once as the user would; the ones that ask come
    /// forward one after another, and any that stays keeps the Space. Then this window moves to the neighbor above,
    /// else below.
    func deleteSpace(_ spaceID: UUID) {
        guard state.spaces.count > 1, state.space(spaceID) != nil, store.deletingSpace == nil else { return }
        let tabIDs = state.tabs(in: spaceID).map(\.id)
        let live = store.windows.flatMap { window in
            tabIDs.flatMap { [window.pages[$0], window.peeks[$0]] }.compactMap { $0 }
        }
        guard !live.isEmpty else { return removeSpace(spaceID) }
        if selectedSpaceID != spaceID { selectSpace(spaceID) }
        store.deletingSpace = ClosingSpace(id: spaceID, window: self, closing: Set(live.map(\.id)))
        for page in live { page.close() }
    }

    private func removeSpace(_ spaceID: UUID) {
        let spaces = state.spaces
        let index = spaces.firstIndex { $0.id == spaceID }!
        if selectedSpaceID == spaceID { selectSpace(spaces[index == 0 ? 1 : index - 1].id) }
        store.edit { $0.removeSpace(spaceID) }
    }

    func togglePin() {
        guard let tabID = selectedTabID else { return }
        store.edit { $0.togglePin(tabID) }
    }

    func toggleFavorite() {
        guard let tabID = selectedTabID else { return }
        if state.isFavorite(tabID) { unfavorite(tabID) } else { favorite(tabID, at: nil) }
    }

    /// The tile's Unfavorite and a tile dropped on the tab list, Oa's own ways to Arc's command-bar Unfavorite Tab.
    func unfavorite(_ tabID: UUID) {
        store.edit { $0.unfavoriteTab(tabID, in: selectedSpaceID) }
    }

    /// A drop on the grid: a row joins it at the index, a tile moves there.
    func favorite(_ tabID: UUID, at index: Int?) {
        store.edit { $0.favoriteTab(tabID, at: index) }
    }

    /// Remove Favorite: archived under no Space once its page has closed, and nothing selected in its place, as
    /// Arc does.
    func removeFavorite(_ tabID: UUID) {
        guard state.isFavorite(tabID) else { return }
        guard let page = store.windows.lazy.compactMap({ $0.pages[tabID] }).first else {
            for window in store.windows { window.placeholders[tabID] = nil }
            return store.edit { $0.archiveTab(tabID, reason: .manual) }
        }
        store.closing[page.id] = .manual
        page.close()
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

    /// As Arc: no history, and the entry stays.
    func peekArchived(_ entryID: UUID) {
        guard let entry = state.archive.first(where: { $0.id == entryID }), let url = entry.url,
            let profileID = (entry.spaceID.flatMap { state.space($0) } ?? space)?.profileID
        else { return }
        closeArchivePeek()
        archivePeekID = entryID
        let context = engine.browserContext(id: profileID)
        Task { [weak self, id] in
            guard let page = await context.makePage(windowID: id), let self else { return }
            guard showingArchive, archivePeekID == entryID else { return page.drop() }
            peeks[entryID] = page
            listen(to: page)
            page.load(url)
        }
    }

    func expandPeek() {
        guard let ownerID = peekOwnerID, let page = peeks.removeValue(forKey: ownerID) else { return }
        let tabID = ownerID == archivePeekID ? ownerID : UUID()
        var tab = SidebarTab(id: tabID, title: page.title, url: page.url, viewedAt: .now)
        if ownerID == archivePeekID {
            archivePeekID = nil
            // Another window brought the entry back; selecting its tab is Oa's own, after Arc's ⇧⌘T.
            if let spaceID = state.space(containing: ownerID)?.id {
                dialogs[page.id] = nil
                page.drop()
                selectSpace(spaceID)
                return select(ownerID)
            }
            store.edit {
                $0.removeArchived(ownerID)
                $0.insertTab(tab, atTopOf: selectedSpaceID)
            }
        } else {
            tab.openerID = ownerID
            store.edit { $0.openTab(tab, from: ownerID, in: selectedSpaceID) }
        }
        install(page, for: tab.id)
        select(tab.id)
    }

    /// Closes as the user would, so a `beforeunload` handler can keep the Peek, as Arc does.
    func closePeek() {
        guard let page = peek else { return }
        if peekOwnerID != archivePeekID { store.closing[page.id] = .manual }
        page.close()
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

    /// ⌘W. An unpinned tab's page, wherever it lives, is closed as the user would and the tab archived once it is
    /// gone, so a `beforeunload` handler can keep both, as Arc does; a pinned one keeps its entry and drops its
    /// page; a Favorite is only deselected, its page reloading the saved URL in the background when it has left
    /// it, as Arc does.
    func close(_ tabID: UUID, reason: SidebarArchivedTab.Reason = .manual) {
        if state.isFavorite(tabID) {
            if let tab = state.tree.tab(tabID), let url = tab.url, let page = pages[tabID], !tab.isAt(page.url) {
                page.load(url)
            }
            return deselect(tabID)
        }
        let page = store.windows.lazy.compactMap { $0.pages[tabID] }.first
        guard let page, !state.isPinned(tabID) else {
            return end(tabID, reason: reason) { page, _ in page.drop() }
        }
        store.closing[page.id] = reason
        page.close()
    }

    func forget(_ dialog: PageDialog) {
        for (pageID, shown) in dialogs where shown.contains(where: { $0 === dialog }) {
            dialogs[pageID] = shown.filter { $0 !== dialog }
            if dialogs[pageID]?.isEmpty == true { dialogs[pageID] = nil }
        }
    }

    /// As Arc: a closing window hands every page to another window, preferring one that shows its tab; quitting
    /// hands nothing over.
    func dropAll(handingOff: Bool) {
        let others = store.windows.filter { $0 !== self }
        for tabID in Array(pages.keys) {
            guard let page = release(tabID) else { continue }
            if handingOff, let heir = others.first(where: { $0.shows(tabID) }) ?? others.first {
                heir.adopt(page, for: tabID, from: self)
            } else {
                page.drop()
            }
        }
        for (ownerID, page) in peeks {
            if ownerID != archivePeekID, state.tree.tab(ownerID) != nil {
                store.archivePage(page, in: spaceID(ofPeekOwner: ownerID))
            }
            page.drop()
        }
        peeks = [:]
        dialogs = [:]
        archivePeekID = nil
        creating = [:]
    }

    /// Stops at the first page a `beforeunload` handler keeps. A page that asks comes forward, as in Arc; the
    /// sidebar order is Oa's own.
    func askToLeave() async -> Bool {
        var seen = Set<ObjectIdentifier>()
        let tabIDs = state.spaces.flatMap { state.selectableTabs(in: $0.id) }.map(\.id)
        let ordered = tabIDs.flatMap { [pages[$0], peeks[$0]] }.compactMap { $0 } + pages.values + peeks.values
        for page in ordered where seen.insert(ObjectIdentifier(page)).inserted {
            guard await page.askToLeave() else { return false }
        }
        return true
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
        for (spaceID, tabID) in selectedTabIDs where !state.isSelectable(tabID, in: spaceID) {
            selectedTabIDs.removeValue(forKey: spaceID)
        }
        for tabID in Array(pages.keys) where state.tree.tab(tabID) == nil { release(tabID)?.drop() }
        for (tabID, page) in pages where page.keepsAddress != state.keepsAddress(tabID) {
            page.keepsAddress = state.keepsAddress(tabID)
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

    private func spaceID(ofPeekOwner ownerID: UUID) -> UUID? {
        if state.tree.tab(ownerID) != nil { return state.space(containing: ownerID)?.id }
        if let entry = state.archive.last(where: { $0.id == ownerID }) { return entry.spaceID }
        return selectedSpaceID
    }

    /// The page stays in `peeks`, unshown, until it reports closed.
    private func closeArchivePeek() {
        guard let entryID = archivePeekID, let page = peeks[entryID] else { return }
        archivePeekID = nil
        page.close()
    }

    private func end(_ tabID: UUID, reason: SidebarArchivedTab.Reason, _ finish: (any Page, Bool) -> Void) {
        guard let spaceID = state.space(containing: tabID)?.id else { return }
        let pinned = state.isPinned(tabID)
        let wasSelected = selectedTabIDs[spaceID] == tabID
        let next = wasSelected ? nextSelection(closing: tabID, pinned: pinned, in: spaceID) : nil
        let page = store.windows.compactMap { $0.release(tabID) }.first
        for window in store.windows { window.placeholders[tabID] = nil }
        if !pinned { store.edit { $0.archiveTab(tabID, reason: reason) } }
        if let page { finish(page, pinned) }
        if wasSelected {
            selectedTabIDs[spaceID] = next
            if let next, spaceID == selectedSpaceID { ensurePage(next) }
        }
    }

    /// A Favorite's page stays as it is, hidden, as Arc keeps it.
    private func deselect(_ tabID: UUID) {
        guard selectedTabID == tabID else { return }
        selectedTabIDs[selectedSpaceID] = nextSelection(closing: tabID, pinned: true, in: selectedSpaceID)
        if let next = selectedTabID { ensurePage(next) }
    }

    /// The opener's group first, as in Arc; else the tab shown before, if its page is still live; an unpinned close
    /// then falls back to the tab above, Favorites counted first, else below; Arc's choice for a Space with no
    /// earlier selection is unknown.
    private func nextSelection(closing tabID: UUID, pinned: Bool, in spaceID: UUID) -> UUID? {
        if let successor = state.openerSuccessor(of: tabID) { return successor }
        if let previousTabID, previousTabID != tabID, pages[previousTabID] != nil,
            state.isSelectable(previousTabID, in: spaceID)
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
        guard let profile = state.profile(containing: tabID) else {
            creating.removeValue(forKey: tabID)
            return
        }
        let context = engine.browserContext(id: profile.id)
        Task { [weak self, id] in
            guard let page = await context.makePage(windowID: id), let self else { return }
            guard creating[tabID] == token, let tab = state.tree.tab(tabID) else { return page.drop() }
            creating.removeValue(forKey: tabID)
            install(page, for: tabID)
            listen(to: page)
            if let url = pendingURLs.removeValue(forKey: tabID) ?? tab.url { page.load(url) }
        }
    }

    private func handOff(_ tabID: UUID) {
        guard let heir = store.windows.first(where: { $0 !== self && $0.shows(tabID) }), let page = release(tabID)
        else { return }
        heir.adopt(page, for: tabID, from: self)
    }

    /// The tab's Peek comes along, as Arc's does.
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
        page.keepsAddress = state.keepsAddress(tabID)
        observe(page, for: tabID)
    }

    /// The stream has one consumer, so a page gets one loop for its life, delivering to whichever window holds it.
    private func listen(to page: any Page) {
        let store = store
        let pageID = page.id
        Task {
            for await event in page.events {
                store.windows.first { $0.holds(pageID) }?.handle(event, for: pageID)
            }
        }
    }

    private func holds(_ pageID: UUID) -> Bool {
        tabID(of: pageID) != nil || peekOwner(of: pageID) != nil
    }

    private func tabID(of pageID: UUID) -> UUID? {
        pages.first { $0.value.id == pageID }?.key
    }

    private func peekOwner(of pageID: UUID) -> UUID? {
        peeks.first { $0.value.id == pageID }?.key
    }

    private func handle(_ event: PageEvent, for pageID: UUID) {
        switch event {
        case .dialog(let dialog):
            dialogs[pageID, default: []].append(dialog)
            if let ownerID = peekOwner(of: pageID), state.tree.tab(ownerID) == nil, archivePeekID != ownerID {
                showingArchive = true
                archivePeekID = ownerID
            }
            return
        case .dialogDismissed(let dialog):
            return forget(dialog)
        case .closeCancelled:
            return closeCancelled(pageID)
        default:
            break
        }
        if let ownerID = peekOwner(of: pageID) {
            switch event {
            case .opened(let opened, let url, let disposition):
                place(opened, url: url, disposition: disposition, from: ownerID, insidePeek: true)
            case .wantsActivation:
                if ownerID != archivePeekID { show(ownerID) } else { bringToFront() }
            case .closed:
                peekEnded(ownerID)
            default:
                break
            }
            return
        }
        guard let tabID = tabID(of: pageID) else { return }
        switch event {
        case .opened(let opened, let url, let disposition):
            place(opened, url: url, disposition: disposition, from: tabID, insidePeek: false)
        case .wantsActivation:
            show(tabID)
        case .closed:
            pageEnded(tabID)
        default:
            break
        }
    }

    /// A refused auto-archive counts as a view, so the next sweep doesn't ask again.
    private func closeCancelled(_ pageID: UUID) {
        if store.closing.removeValue(forKey: pageID) == .auto, let tabID = tabID(of: pageID) {
            store.markViewed(tabID)
        }
        spaceDeletionEnded(pageID, kept: true)
    }

    private func spaceDeletionEnded(_ pageID: UUID, kept: Bool) {
        guard var deletion = store.deletingSpace, deletion.closing.remove(pageID) != nil else { return }
        deletion.kept = deletion.kept || kept
        store.deletingSpace = deletion.closing.isEmpty ? nil : deletion
        if deletion.closing.isEmpty, !deletion.kept { deletion.window.removeSpace(deletion.id) }
    }

    /// A Peek the user closed leaves an entry under its tab's Space, as Arc does; one that closed itself, or showed
    /// an Archive entry, leaves none.
    private func peekEnded(_ ownerID: UUID) {
        guard let page = peeks.removeValue(forKey: ownerID) else { return }
        dialogs[page.id] = nil
        if store.closing.removeValue(forKey: page.id) != nil, state.tree.tab(ownerID) != nil {
            let spaceID = state.space(containing: ownerID)?.id
            store.edit { $0.archivePage(id: page.id, title: page.title, url: page.url, in: spaceID) }
        }
        if ownerID == archivePeekID { archivePeekID = nil }
        self.page?.activate()
        spaceDeletionEnded(page.id, kept: false)
    }

    /// As Arc; a Shift-click arrives as a new window. A page from an Archive Peek has no tab to join, and the top of
    /// the shown Space is Oa's own.
    private func place(
        _ page: any Page, url: URL?, disposition: OpenDisposition, from openerID: UUID, insidePeek: Bool
    ) {
        guard state.tree.tab(openerID) != nil else {
            guard insidePeek, openerID == archivePeekID else { return page.drop() }
            let tab = SidebarTab(id: UUID(), url: url, viewedAt: .now)
            store.edit { $0.insertTab(tab, atTopOf: selectedSpaceID) }
            install(page, for: tab.id)
            listen(to: page)
            return select(tab.id)
        }
        let background = disposition == .backgroundTab
        if !insidePeek, disposition == .newWindow || (!background && state.keepsAddress(openerID)) {
            return peek(page, from: openerID)
        }
        let tab = SidebarTab(id: UUID(), url: url, viewedAt: .now, openerID: openerID)
        store.edit { $0.openTab(tab, from: openerID, in: selectedSpaceID) }
        install(page, for: tab.id)
        listen(to: page)
        if !background, state.isSelectable(tab.id, in: selectedSpaceID) { select(tab.id) }
    }

    /// Oa's own: a new Peek replaces the tab's current one, archived at once.
    private func peek(_ page: any Page, from openerID: UUID) {
        if let current = peeks[openerID] {
            let spaceID = state.space(containing: openerID)?.id
            store.edit { $0.archivePage(id: current.id, title: current.title, url: current.url, in: spaceID) }
            current.close()
        }
        peeks[openerID] = page
        listen(to: page)
    }

    /// Switches to the tab's Space and raises the window, as Arc does for a page asking to be shown.
    private func show(_ tabID: UUID) {
        let spaceID = state.space(containing: tabID)?.id ?? selectedSpaceID
        guard state.isSelectable(tabID, in: spaceID) else { return }
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
            _ = page.favicon
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let page = pages[tabID], ObjectIdentifier(page) == identity else { return }
                store.setSavedPage(tabID, title: page.title, url: page.url)
                if let favicon = page.favicon { store.setSavedFavicon(tabID, favicon) }
                observe(page, for: tabID)
            }
        }
    }

    /// A Favorite's page that ends leaves the tile, as a pinned tab's leaves its row, unless Remove Favorite asked
    /// for the close.
    private func pageEnded(_ tabID: UUID) {
        guard let page = pages[tabID] else { return }
        dialogs[page.id] = nil
        let reason = store.closing.removeValue(forKey: page.id)
        if state.isFavorite(tabID) {
            release(tabID)
            for window in store.windows { window.placeholders[tabID] = nil }
            if reason != nil { store.edit { $0.archiveTab(tabID, reason: .manual) } }
            deselect(tabID)
        } else if store.deletingSpace?.closing.contains(page.id) == true {
            release(tabID)
        } else {
            end(tabID, reason: reason ?? .manual) { _, _ in }
        }
        spaceDeletionEnded(page.id, kept: false)
    }
}
