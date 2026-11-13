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
    private(set) var selectedSpaceID: UUID {
        didSet { closeCommandBarIfSelectionChanged() }
    }
    private(set) var selectedTabIDs: [UUID: UUID] = [:] {
        didSet { closeCommandBarIfSelectionChanged() }
    }
    private(set) var pages: [UUID: any Page] = [:]
    /// Last frames of pages that left for another window while their tab stayed selected here.
    private(set) var placeholders: [UUID: NSImage] = [:]
    /// Pages shown over the window as Arc's Peek: by the tab they were opened from, whose state they are, or by
    /// the Archive entry they show.
    private(set) var peeks: [UUID: any Page] = [:]
    private(set) var showingArchive = false {
        didSet { if !showingArchive { closeArchivePeek() } }
    }
    private(set) var showingDownloads = false
    private var previewedDownloadID: Download.ID?
    private(set) var dialogs: [UUID: [PageDialog]] = [:]
    /// By page, as Arc's ADK keeps `pendingPermissionRequests`; the engine sends one at a time, while the page is front.
    private(set) var permissionRequests: [UUID: [PagePermissionRequest]] = [:]
    private var answeredPermissionRequest: (pageID: UUID, request: PagePermissionRequest)?
    /// By profile, as ADK keeps a browser per window and profile: from the window's first page in the profile on.
    private(set) var browsers: [UUID: any Browser] = [:]
    private(set) var commandBar: CommandBar?
    /// When this window last showed a tab and when a tab was made through it, as Arc's per-window
    /// `itemLastActiveDates` and `itemCreatedDates`, which order its empty command bar.
    private(set) var lastActiveDates: [UUID: Date] = [:]
    private(set) var createdDates: [UUID: Date] = [:]
    /// The selection the command bar was opened over, which its destination is for.
    @ObservationIgnored private var commandBarSelection: (spaceID: UUID, tabID: UUID?)?
    @ObservationIgnored var bringToFront: () -> Void = {}
    /// Opens another window on this one's Space with the tab selected; the tab's page follows it there.
    @ObservationIgnored var openWindow: (_ tabID: UUID) -> Void = { _ in }
    @ObservationIgnored let downloads: DownloadsStore
    @ObservationIgnored private let engine: any BrowserApplication
    @ObservationIgnored private let store: SidebarStore
    @ObservationIgnored private var previousTabID: UUID?
    @ObservationIgnored private var pendingURLs: [UUID: URL] = [:]
    @ObservationIgnored private var creating: [UUID: UUID] = [:]
    /// By profile: ArcCore keeps one omnibox per window.
    @ObservationIgnored private var autocompletes: [UUID: any Autocomplete] = [:]
    @ObservationIgnored private var browserListeners: [Task<Void, Never>] = []
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
    var permissionRequest: PagePermissionRequest? {
        guard let page = frontPage, answeredPermissionRequest?.pageID != page.id else { return nil }
        return permissionRequests[page.id]?.first
    }
    /// What the prompt draws: the answered request stays until its popover has closed.
    var promptedPermissionRequest: PagePermissionRequest? { permissionRequest ?? answeredPermissionRequest?.request }
    private var peekOwnerID: UUID? { showingArchive ? archivePeekID : selectedTabID }
    /// What the address field shows: the live page's URL, else the tab's saved one while its page is pending.
    var address: URL? { page?.url ?? selectedTab?.url }
    var favorites: [SidebarTab] { state.favorites(for: selectedSpaceID) }
    var pinnedTabs: [SidebarTab] { state.tabs(in: selectedSpaceID, pinned: true) }
    var unpinnedTabs: [SidebarTab] { state.tabs(in: selectedSpaceID, pinned: false) }
    var selectableTabs: [SidebarTab] { state.selectableTabs(in: selectedSpaceID) }

    var record: WindowRecord {
        WindowRecord(
            id: id, selectedSpaceID: selectedSpaceID, lastActiveDates: lastActiveDates, createdDates: createdDates)
    }

    init(id: UUID, engine: any BrowserApplication, store: SidebarStore, downloads: DownloadsStore, spaceID: UUID) {
        self.id = id
        self.engine = engine
        self.store = store
        self.downloads = downloads
        selectedSpaceID = spaceID
    }

    /// As Arc: a restored window comes back on its Space with nothing selected and no page. Its dates come back
    /// too, as Oa's own: Arc saves them with the window, and what its restore does with them is unknown.
    func restore(_ record: WindowRecord) {
        if state.space(record.selectedSpaceID) != nil { selectedSpaceID = record.selectedSpaceID }
        lastActiveDates = record.lastActiveDates
        createdDates = record.createdDates
        openCommandBar(.newTab)
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
        livePage(for: tab.id)?.favicon ?? store.savedFavicon(tab.id)
    }

    private func livePage(for tabID: UUID) -> (any Page)? {
        pages[tabID] ?? store.windows.lazy.compactMap { $0.pages[tabID] }.first
    }

    func savedFavicon(_ id: UUID) -> NSImage? { store.savedFavicon(id) }

    func isRecording(_ tab: SidebarTab) -> Bool {
        guard let page = livePage(for: tab.id) else { return false }
        return page.isCameraOn || page.isMicrophoneOn
    }

    /// Only the only window picks a tab: first unpinned, else first pinned. Another window starts empty.
    func showFirst(isOnlyWindow: Bool) {
        if isOnlyWindow, let first = state.firstTabID(in: selectedSpaceID) {
            select(first)
        } else {
            openCommandBar(.newTab)
        }
    }

    /// As Arc's Site Controls: read when it opens and after each change, for the page's site in its tab's profile;
    /// only a secure page lists its settings.
    func siteSettings() -> [SiteSetting] {
        guard let page, page.securityLevel == .secure, let url = page.url, let context = siteContext else { return [] }
        return context.changedSiteSettings(for: url) ?? []
    }

    /// As Arc: allowed becomes blocked and anything else allowed, with no reload.
    func toggle(_ setting: SiteSetting) {
        guard let url = page?.url, let context = siteContext else { return }
        context.setSiteSetting(setting.type, to: setting.value.isAllowed ? .block : .allow, for: url)
    }

    /// Arc shows the page in a panel in the window; a new tab is Oa's own.
    func openAllSiteSettings() {
        guard let url = page?.url, var components = URLComponents(string: "chrome://settings/content/siteDetails")
        else { return }
        components.queryItems = [URLQueryItem(name: "site", value: url.absoluteString)]
        if let settings = components.url { newTab(settings) }
    }

    private var siteContext: (any BrowserContext)? {
        selectedTabID.flatMap { state.profile(containing: $0) }.map { engine.browserContext(id: $0.id) }
    }

    private func ensureBrowser(for profileID: UUID) {
        guard browsers[profileID] == nil else { return }
        let browser = engine.browserContext(id: profileID).browser(windowID: id)
        browsers[profileID] = browser
        browserListeners.append(
            Task { [weak self] in
                for await event in browser.events {
                    guard let self, case .opened(let page, let isActive) = event else { continue }
                    place(page, isActive: isActive, in: profileID)
                }
            })
    }

    /// A page the engine made itself, as an extension's `chrome.tabs.create`. Oa's own: at the top of the shown Space
    /// when it is the profile's, else of the profile's first; where Arc puts one is unknown.
    private func place(_ page: any Page, isActive: Bool, in profileID: UUID) {
        let shown = space?.profileID == profileID ? selectedSpaceID : nil
        guard let spaceID = shown ?? state.spaces.first(where: { $0.profileID == profileID })?.id else {
            return page.drop()
        }
        let tab = SidebarTab(id: UUID(), url: page.url, viewedAt: .now)
        store.edit { $0.insertTab(tab, atTopOf: spaceID) }
        createdDates[tab.id] = .now
        install(page, for: tab.id)
        listen(to: page)
        if isActive { show(tab.id) }
    }

    /// As Arc: at the top of the Space's unpinned tabs.
    func newTab(_ url: URL) {
        let tab = SidebarTab(id: UUID(), url: url, viewedAt: .now)
        store.edit { $0.insertTab(tab, atTopOf: selectedSpaceID) }
        createdDates[tab.id] = .now
        select(tab.id)
    }

    /// As Arc: Chromium's History page in a new tab at the top of the Space, in the Space's profile.
    func viewHistory() {
        if let url = URL(string: "chrome://history/") { newTab(url) }
    }

    /// As Arc: ⌘L edits the front page, the Peek included, and does nothing over a dialog; with no tab selected it
    /// makes one as ⌘T does.
    func openCommandBar(_ destination: CommandBar.Destination) {
        if destination == .currentTab, dialog != nil { return }
        let editing = destination == .currentTab && selectedTabID != nil
        let profileID = editing ? selectedTabID.flatMap { state.profile(containing: $0)?.id } : space?.profileID
        guard let profileID else { return }
        commandBar?.autocomplete.stop()
        let autocomplete = autocompletes[profileID] ?? engine.browserContext(id: profileID).makeAutocomplete()
        autocompletes[profileID] = autocomplete
        let bar = CommandBar(
            destination: editing ? .currentTab : .newTab, autocomplete: autocomplete,
            currentURL: editing ? frontPage?.url ?? address : nil, profileID: profileID, picks: store.commandBarPicks
        ) { [weak self] in self?.commandBarTabs ?? [] }
        bar.perform = { [weak self, destination = bar.destination] in self?.perform($0, in: destination) }
        commandBar = bar
        commandBarSelection = (selectedSpaceID, selectedTabID)
    }

    func closeCommandBar() {
        guard let bar = commandBar else { return }
        bar.autocomplete.stop()
        commandBar = nil
        if dialog == nil { frontPage?.activate() }
    }

    /// Oa's own: ⌘W, ⌘Y or anything else that changes the selection under the bar closes it, rather than leaving
    /// it to act on a tab it wasn't opened for. Arc's behaviour here is untested.
    private func closeCommandBarIfSelectionChanged() {
        guard commandBar != nil, let opened = commandBarSelection,
            opened.spaceID != selectedSpaceID || opened.tabID != selectedTabID
        else { return }
        closeCommandBar()
    }

    /// As Arc's command bar: the profile's Favorites and the tabs of all its Spaces but the selected tab, each with
    /// an address.
    var commandBarTabs: [CommandBarRanking.Tab] {
        guard let space else { return [] }
        let others = state.spaces.filter { $0.profileID == space.profileID && $0.id != space.id }
        let tabs: [(SidebarTab, String?)] =
            selectableTabs.map { ($0, nil) }
            + others.flatMap { other in state.tabs(in: other.id).map { ($0, other.name) } }
        return tabs.compactMap { tab, spaceName in
            guard tab.id != selectedTabID, let url = livePage(for: tab.id)?.url ?? tab.url else { return nil }
            return CommandBarRanking.Tab(
                tab: tab, url: url, spaceName: spaceName, activeAt: lastActiveDates[tab.id] ?? createdDates[tab.id],
                isVisible: store.windows.contains { $0.selectedTabID == tab.id },
                saveLevel: state.keepsAddress(tab.id) ? folderDepth(of: tab.id) : nil)
        }
    }

    private func folderDepth(of id: UUID) -> Int {
        var depth = 0
        var parentID = state.tree[id]?.parentID
        while let id = parentID, let parent = state.tree[id], parent.parentID != nil {
            depth += 1
            parentID = parent.parentID
        }
        return depth
    }

    private func perform(_ action: CommandBar.Action, in destination: CommandBar.Destination) {
        closeCommandBar()
        switch action {
        case .switchTo(let tabID): show(tabID)
        case .open(let url, background: true):
            let tab = SidebarTab(id: UUID(), url: url, viewedAt: .now)
            store.edit { $0.insertTab(tab, atTopOf: selectedSpaceID) }
            createdDates[tab.id] = .now
            ensurePage(tab.id)
        case .open(let url, background: false):
            guard destination == .currentTab, let tabID = selectedTabID else { return newTab(url) }
            if let peek {
                peek.load(url)
                return peek.activate()
            }
            ensurePage(tabID)
            if let page = pages[tabID] {
                page.load(url)
                page.activate()
            } else {
                pendingURLs[tabID] = url
            }
        }
    }

    func select(_ tabID: UUID, restoring sessionID: PageSessionID? = nil) {
        guard state.isSelectable(tabID, in: selectedSpaceID), selectedTabID != tabID else { return }
        showingArchive = false
        if let current = selectedTabID {
            if pages[current] != nil { previousTabID = current }
            placeholders[current] = nil
            handOff(current)
        }
        selectedTabIDs[selectedSpaceID] = tabID
        markViewed(tabID)
        ensurePage(tabID, restoring: sessionID)
    }

    /// As Arc's `selectItem`: a tab the window shows by a selection is stamped for the window and for itself. The
    /// tab that takes a closed one's place isn't: Arc's code reads as if it were, and Arc's bar showed it wasn't.
    private func markViewed(_ tabID: UUID) {
        lastActiveDates[tabID] = .now
        store.markViewed(tabID)
    }

    /// Arc's pass each minute over what a window shows.
    func markShownViewed() {
        if !showingArchive, let tabID = selectedTabID { markViewed(tabID) }
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
        if let tabID = selectedTabID {
            ensurePage(tabID)
            markViewed(tabID)
        } else {
            openCommandBar(.newTab)
        }
        store.windowStateChanged()
    }

    /// On becoming key, the selected tab takes its page back from the window that holds or is making it.
    func showSelected() {
        guard let tabID = selectedTabID, pages[tabID] == nil,
            store.windows.contains(where: { $0 !== self && ($0.pages[tabID] != nil || $0.creating[tabID] != nil) })
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

    /// As Arc: every live page of the Space closes at once as the user would; the ones that ask come forward one
    /// after another, and any that stays keeps the Space. Its Peeks go without asking or an entry; Arc runs their
    /// handlers and unloads them, Oa drops them. Then this window moves to the neighbor above, else below.
    func deleteSpace(_ spaceID: UUID) {
        guard state.spaces.count > 1, state.space(spaceID) != nil, store.deletingSpace == nil else { return }
        let tabIDs = state.tabs(in: spaceID).map(\.id)
        for window in store.windows {
            for tabID in tabIDs {
                guard let peek = window.peeks.removeValue(forKey: tabID) else { continue }
                window.dialogs[peek.id] = nil
                window.permissionRequests[peek.id] = nil
                peek.drop()
            }
        }
        let live = store.windows.flatMap { window in tabIDs.compactMap { window.pages[$0] } }
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
        showingDownloads = false
        showingArchive = true
    }

    func viewDownloads() {
        showingArchive = false
        showingDownloads = true
    }

    func hideDownloads() {
        showingDownloads = false
    }

    var previewedDownload: DownloadsStore.Entry? {
        previewedDownloadID.flatMap { id in downloads.entries.first { $0.id == id } }
    }

    /// A click on a download, as Arc: a finished one is previewed over the window; one still running opens when it
    /// finishes.
    func activate(_ entry: DownloadsStore.Entry) {
        if entry.isRunning {
            downloads.toggleOpenWhenFinished(entry)
        } else if entry.download.status == .finished, entry.fileExists {
            previewedDownloadID = entry.id
        }
    }

    func closeDownloadPreview() {
        previewedDownloadID = nil
        frontPage?.activate()
    }

    /// Arc's ‹ and ›, over the finished downloads in the Library's order.
    func previewAdjacentDownload(_ offset: Int) {
        let files = downloads.entries.filter { $0.download.status == .finished && $0.fileExists }
        guard let index = files.firstIndex(where: { $0.id == previewedDownloadID }),
            files.indices.contains(index + offset)
        else { return }
        previewedDownloadID = files[index + offset].id
    }

    func exitArchive() {
        showingArchive = false
    }

    func restoreArchived(_ id: UUID) {
        store.edit { $0.restoreArchived(id, in: selectedSpaceID, toOldPosition: false) }
        createdDates[id] = .now
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
            guard let page = await context.makePage(windowID: id, restoring: nil)?.page, let self else { return }
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
                permissionRequests[page.id] = nil
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
        createdDates[tab.id] = .now
        install(page, for: tab.id)
        select(tab.id)
    }

    /// Closes as the user would, so a `beforeunload` handler can keep the Peek, as Arc does.
    func closePeek() {
        guard let page = peek else { return }
        if peekOwnerID != archivePeekID { store.closing[page.id] = .manual }
        page.close()
    }

    /// As Arc, with its history; Restore and the Archive Peek load fresh.
    func restoreLastClosed() {
        guard let entry = state.archive.last else { return }
        let sessionID = store.sessionIDs[entry.id]
        var spaceID: UUID?
        store.edit { spaceID = $0.restoreArchived(entry.id, in: selectedSpaceID, toOldPosition: true) }
        guard let spaceID else { return }
        createdDates[entry.id] = .now
        selectSpace(spaceID)
        select(entry.id, restoring: sessionID)
    }

    func deleteArchived(_ id: UUID) {
        store.edit { $0.removeArchived(id) }
    }

    func clearArchive() {
        store.edit { $0.clearArchive() }
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

    func respond(to request: PagePermissionRequest, with response: PermissionResponse) {
        guard let pageID = permissionRequests.first(where: { $0.value.contains { $0 === request } })?.key else {
            return
        }
        answeredPermissionRequest = (pageID, request)
        request.respond(response)
    }

    /// As Arc: the prompt's close dismisses the request its page holds by then, so one queued behind an answered
    /// request is never shown (arc-permissions.md §11 L7).
    func permissionPromptClosed() {
        guard let answered = answeredPermissionRequest else { return }
        answeredPermissionRequest = nil
        permissionRequests[answered.pageID]?.first { $0 !== answered.request }?.respond(.dismiss)
    }

    private func forget(_ request: PagePermissionRequest) {
        for (pageID, requests) in permissionRequests where requests.contains(where: { $0 === request }) {
            permissionRequests[pageID] = requests.filter { $0 !== request }
            if permissionRequests[pageID]?.isEmpty == true { permissionRequests[pageID] = nil }
        }
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
        permissionRequests = [:]
        browserListeners.forEach { $0.cancel() }
        browserListeners = []
        browsers = [:]
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
        // Oa's own: Arc's last-active dates were never seen to be removed.
        for tabID in Array(lastActiveDates.keys) where state.tree.tab(tabID) == nil { lastActiveDates[tabID] = nil }
        for tabID in Array(createdDates.keys) where state.tree.tab(tabID) == nil { createdDates[tabID] = nil }
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

    private func end(
        _ tabID: UUID, reason: SidebarArchivedTab.Reason, sessionID: PageSessionID? = nil,
        _ finish: (any Page, Bool) -> Void
    ) {
        guard let spaceID = state.space(containing: tabID)?.id else { return }
        let pinned = state.isPinned(tabID)
        let wasSelected = selectedTabIDs[spaceID] == tabID
        let next = wasSelected ? nextSelection(closing: tabID, pinned: pinned, in: spaceID) : nil
        let page = store.windows.compactMap { $0.release(tabID) }.first
        for window in store.windows {
            window.placeholders[tabID] = nil
            // As Arc's close: a pinned tab keeps when a window last showed it, not when one made it.
            window.createdDates[tabID] = nil
        }
        if !pinned {
            store.edit { $0.archiveTab(tabID, reason: reason) }
            store.sessionIDs[tabID] = sessionID
        }
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

    /// As Arc's ingest, in one step: the last window to select a tab takes its page from the window that holds it, or
    /// the page still being made from the window making it.
    private func ensurePage(_ tabID: UUID, restoring sessionID: PageSessionID? = nil) {
        guard pages[tabID] == nil, creating[tabID] == nil else { return }
        if let holder = store.windows.first(where: { $0 !== self && $0.pages[tabID] != nil }),
            let page = holder.release(tabID)
        {
            holder.keepFrame(of: page, for: tabID)
            return adopt(page, for: tabID, from: holder)
        }
        if let maker = store.windows.first(where: { $0 !== self && $0.creating[tabID] != nil }) {
            return takeCreation(of: tabID, from: maker)
        }
        guard let profile = state.profile(containing: tabID) else { return }
        let token = UUID()
        creating[tabID] = token
        let context = engine.browserContext(id: profile.id)
        ensureBrowser(for: profile.id)
        Task { [store, id] in
            let made = await context.makePage(windowID: id, restoring: sessionID)
            let owner = store.windows.first { $0.creating[tabID] == token }
            owner?.creating.removeValue(forKey: tabID)
            guard let page = made?.page else { return }
            guard let owner, let tab = store.state.tree.tab(tabID) else { return page.drop() }
            if owner.id != id { page.move(toWindow: owner.id) }
            owner.install(page, for: tabID)
            owner.listen(to: page)
            if let url = owner.pendingURLs.removeValue(forKey: tabID) ?? (made?.restored == true ? nil : tab.url) {
                page.load(url)
            }
            for window in store.windows where window !== owner { window.keepFrameLater(of: page, for: tabID) }
        }
    }

    /// As Arc's eject on deselection, a page still being made goes too.
    private func handOff(_ tabID: UUID) {
        guard let heir = store.windows.first(where: { $0 !== self && $0.shows(tabID) }) else { return }
        if creating[tabID] != nil { return heir.takeCreation(of: tabID, from: self) }
        if let page = release(tabID) { heir.adopt(page, for: tabID, from: self) }
    }

    private func takeCreation(of tabID: UUID, from maker: WindowModel) {
        creating[tabID] = maker.creating.removeValue(forKey: tabID)
        if let url = maker.pendingURLs.removeValue(forKey: tabID) { pendingURLs[tabID] = url }
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

    /// Asked before the page leaves, while it still draws here, and not waited for, as Arc's ingest does.
    private func keepFrame(of page: any Page, for tabID: UUID) {
        guard selectedTabID == tabID else { return }
        page.snapshot { [weak self] image in
            guard let self, selectedTabID == tabID, pages[tabID] == nil else { return }
            if let image { placeholders[tabID] = image } else { keepFrameLater(of: page, for: tabID) }
        }
    }

    private func keepFrameLater(of page: any Page, for tabID: UUID, attempts: Int = 2) {
        guard attempts > 0, placeholders[tabID] == nil, selectedTabID == tabID, pages[tabID] == nil else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, placeholders[tabID] == nil, selectedTabID == tabID, pages[tabID] == nil else { return }
            page.snapshot { [weak self] image in
                guard let self, selectedTabID == tabID, pages[tabID] == nil else { return }
                if let image {
                    placeholders[tabID] = image
                } else {
                    keepFrameLater(of: page, for: tabID, attempts: attempts - 1)
                }
            }
        }
    }

    /// As Arc, whose ADK observes a page with `.initial`: what the page already shows counts, since tracking only
    /// reports changes and a page opened by script may have its title before it arrives here.
    private func install(_ page: any Page, for tabID: UUID) {
        pages[tabID] = page
        if let profile = state.profile(containing: tabID) { ensureBrowser(for: profile.id) }
        page.keepsAddress = state.keepsAddress(tabID)
        save(page, for: tabID)
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
        case .permissionRequest(let request):
            permissionRequests[pageID, default: []].append(request)
            return
        case .permissionRequestClosed(let request):
            for window in store.windows { window.forget(request) }
            return
        case .closeCancelled:
            return closeCancelled(pageID)
        default:
            break
        }
        if let ownerID = peekOwner(of: pageID) {
            switch event {
            case .opened(let opened, let url, let disposition, let byPage):
                place(opened, url: url, disposition: disposition, byPage: byPage, from: ownerID, insidePeek: true)
            case .wantsActivation:
                if ownerID != archivePeekID { show(ownerID) } else { bringToFront() }
            case .closed(let sessionID):
                peekEnded(ownerID, sessionID: sessionID)
            default:
                break
            }
            return
        }
        guard let tabID = tabID(of: pageID) else { return }
        switch event {
        case .opened(let opened, let url, let disposition, let byPage):
            place(opened, url: url, disposition: disposition, byPage: byPage, from: tabID, insidePeek: false)
        case .wantsActivation:
            show(tabID)
        case .closed(let sessionID):
            pageEnded(tabID, sessionID: sessionID)
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
    private func peekEnded(_ ownerID: UUID, sessionID: PageSessionID?) {
        guard let page = peeks.removeValue(forKey: ownerID) else { return }
        dialogs[page.id] = nil
        permissionRequests[page.id] = nil
        if store.closing.removeValue(forKey: page.id) != nil, state.tree.tab(ownerID) != nil {
            let spaceID = state.space(containing: ownerID)?.id
            store.edit { $0.archivePage(id: page.id, title: page.title, url: page.url, in: spaceID) }
            // Oa's own: ⇧⌘T brings a Peek back with its history; what Arc's does is unknown.
            store.sessionIDs[page.id] = sessionID
        }
        if ownerID == archivePeekID { archivePeekID = nil }
        self.page?.activate()
        spaceDeletionEnded(page.id, kept: false)
    }

    /// As Arc; a Shift-click arrives as the page's own new window, and the engine's, as its page menu's Open Link in
    /// New Window, opens a window on this Space with the page as its selected tab. A page from an Archive Peek has no
    /// tab to join, and the top of the shown Space is Oa's own.
    private func place(
        _ page: any Page, url: URL?, disposition: OpenDisposition, byPage: Bool, from openerID: UUID,
        insidePeek: Bool
    ) {
        let inWindow = disposition == .newWindow && !byPage
        guard state.tree.tab(openerID) != nil else {
            guard insidePeek, openerID == archivePeekID else { return page.drop() }
            let tab = SidebarTab(id: UUID(), url: url, viewedAt: .now)
            store.edit { $0.insertTab(tab, atTopOf: selectedSpaceID) }
            createdDates[tab.id] = .now
            install(page, for: tab.id)
            listen(to: page)
            return inWindow ? openWindow(tab.id) : select(tab.id)
        }
        let background = disposition == .backgroundTab
        if !insidePeek, !inWindow, disposition == .newWindow || (!background && state.keepsAddress(openerID)) {
            return peek(page, from: openerID)
        }
        let tab = SidebarTab(id: UUID(), url: url, viewedAt: .now, openerID: openerID)
        store.edit { $0.openTab(tab, from: openerID, in: selectedSpaceID) }
        createdDates[tab.id] = .now
        install(page, for: tab.id)
        listen(to: page)
        guard state.isSelectable(tab.id, in: selectedSpaceID) else { return }
        if inWindow { openWindow(tab.id) } else if !background { select(tab.id) }
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

    /// Switches to the tab's Space and raises the window, as Arc does for a page asking to be shown and for another
    /// Space's tab picked in the command bar.
    private func show(_ tabID: UUID) {
        let spaceID = state.space(containing: tabID)?.id ?? selectedSpaceID
        guard state.isSelectable(tabID, in: spaceID) else { return }
        if spaceID != selectedSpaceID {
            showingArchive = false
            selectedTabIDs[spaceID] = tabID
            selectSpace(spaceID)
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
            _ = page.navigationResult
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let page = pages[tabID], ObjectIdentifier(page) == identity else { return }
                save(page, for: tabID)
                observe(page, for: tabID)
            }
        }
    }

    /// As Arc: a page that has loaded with no favicon clears an unpinned tab's, and a tab that keeps its address never
    /// loses its own.
    private func save(_ page: any Page, for tabID: UUID) {
        store.setSavedPage(tabID, title: page.title, url: page.url)
        let favicon = page.favicon
        let hasLoaded = page.navigationResult == .loaded
        guard favicon != nil || (hasLoaded && !state.keepsAddress(tabID)) else { return }
        let hasSaved = store.savedFavicon(tabID) != nil
        guard state.takesFavicon(tabID, at: page.url, canGoBack: page.canGoBack, hasSaved: hasSaved) else { return }
        store.setSavedFavicon(tabID, favicon)
    }

    /// A Favorite's page that ends leaves the tile, as a pinned tab's leaves its row, unless Remove Favorite asked
    /// for the close.
    private func pageEnded(_ tabID: UUID, sessionID: PageSessionID?) {
        guard let page = pages[tabID] else { return }
        dialogs[page.id] = nil
        permissionRequests[page.id] = nil
        let reason = store.closing.removeValue(forKey: page.id)
        if state.isFavorite(tabID) {
            release(tabID)
            for window in store.windows { window.placeholders[tabID] = nil }
            if reason != nil {
                store.edit { $0.archiveTab(tabID, reason: .manual) }
                store.sessionIDs[tabID] = sessionID
            }
            deselect(tabID)
        } else if store.deletingSpace?.closing.contains(page.id) == true {
            release(tabID)
        } else {
            end(tabID, reason: reason ?? .manual, sessionID: sessionID) { _, _ in }
        }
        spaceDeletionEnded(page.id, kept: false)
    }
}
