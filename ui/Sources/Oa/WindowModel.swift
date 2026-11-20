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
        didSet {
            closeCommandBarIfSelectionChanged()
            loadExtensions()
            presentationChanged()
            dismissModalItemSwitcher()
        }
    }
    private(set) var selectedTabIDs: [UUID: UUID] = [:] {
        didSet {
            closeCommandBarIfSelectionChanged()
            presentationChanged()
        }
    }
    private(set) var pages: [UUID: any Page] = [:] {
        didSet { presentationChanged() }
    }
    /// Last frames of pages that left for another window while their tab stayed selected here.
    private(set) var placeholders: [UUID: NSImage] = [:]
    /// Pages shown over the window as Arc's Peek: by the tab they were opened from, whose state they are, or by
    /// the Archive entry they show.
    private(set) var peeks: [UUID: any Page] = [:]
    /// As Arc's `WindowState.spaceCreationState`: while it is open the window shows nothing selected.
    private(set) var spaceCreation: SpaceCreationState? {
        didSet {
            closeCommandBarIfSelectionChanged()
            presentationChanged()
        }
    }
    /// As Arc's per-window `spacesWithCollapsedPinnedSections`: the Spaces whose pinned tabs this window folds away.
    private(set) var collapsedPinnedSpaces: Set<UUID> = []
    private(set) var library: LibrarySection? {
        didSet {
            if let library { store.home.lastSelectedHomePage = library }
            if library != .archive { closeArchivePeek() }
        }
    }
    var lastLibrarySection: LibrarySection { store.home.lastSelectedHomePage }
    /// As Arc's `WindowState.sidebarMode` and width: the window's own, saved with it.
    private(set) var sidebarMode: SidebarMode
    private(set) var sidebarWidth: CGFloat
    private var previewedDownloadID: Download.ID?
    private(set) var dialogs: [UUID: [PageDialog]] = [:]
    /// By page, as Arc's ADK keeps `pendingPermissionRequests`; the engine sends one at a time, while the page is front.
    private(set) var permissionRequests: [UUID: [PagePermissionRequest]] = [:]
    private var answeredPermissionRequest: (pageID: UUID, request: PagePermissionRequest)?
    /// By page, as Arc's ADK queues an install consent on its page.
    private(set) var extensionRequests: [UUID: [PageExtensionRequest]] = [:]
    /// By profile, as ADK keeps a browser per window and profile: from the window's first page in the profile on.
    private(set) var browsers: [UUID: any Browser] = [:]
    private(set) var commandBar: CommandBar?
    /// When this window last showed a tab and when a tab was made through it, as Arc's per-window
    /// `itemLastActiveDates` and `itemCreatedDates`, which order its empty command bar.
    private(set) var lastActiveDates: [UUID: Date] = [:]
    private(set) var createdDates: [UUID: Date] = [:]
    /// As Arc's `WindowState.modalItemSwitcherPresentation`: the ⌃⇥ switcher while it is up.
    private(set) var modalItemSwitcher: ModalItemSwitcher?
    /// The selection the command bar was opened over, which its destination is for.
    @ObservationIgnored private var commandBarSelection: (spaceID: UUID, tabID: UUID?)?
    @ObservationIgnored var bringToFront: () -> Void = {}
    @ObservationIgnored weak var window: NSWindow?
    /// Opens another window on this one's Space with the tab selected; the tab's page follows it there.
    @ObservationIgnored var openWindow: (_ tabID: UUID) -> Void = { _ in }
    @ObservationIgnored let downloads: DownloadsStore
    @ObservationIgnored private let pictureInPicture: PictureInPicture
    @ObservationIgnored private var presentedPage: (any Page)?
    @ObservationIgnored private let engine: any BrowserApplication
    @ObservationIgnored private let store: SidebarStore
    @ObservationIgnored private var previousTabID: UUID?
    @ObservationIgnored private var pendingURLs: [UUID: URL] = [:]
    @ObservationIgnored private var creating: [UUID: UUID] = [:]
    /// By profile: ArcCore keeps one omnibox per window.
    @ObservationIgnored private var autocompletes: [UUID: any Autocomplete] = [:]
    @ObservationIgnored private var browserListeners: [UUID: Task<Void, Never>] = [:]
    /// As Arc's `ClosedSidebarItemsCache`: what the user closed from this window, a group for each close with a step
    /// for each tab, the last ten, in memory and gone with the window.
    @ObservationIgnored private var closedGroups: [ClosedGroup] = []
    private var archivePeekID: UUID?

    var state: SidebarState { store.state }
    var adBlocker: AdBlocker { engine.adBlocker }
    var space: SidebarSpace? { state.space(selectedSpaceID) }
    var selectedTabID: UUID? { spaceCreation == nil ? selectedTabIDs[selectedSpaceID] : nil }
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
    /// Over the whole window, as a dialog is. Oa's own: it waits with its page while another tab is shown; what Arc
    /// does with it on a tab switch is unknown.
    var extensionRequest: PageExtensionRequest? {
        [peek, page].lazy.compactMap { $0.flatMap { self.extensionRequests[$0.id]?.first } }.first
    }
    /// Something over the whole window that takes its clicks.
    var coversWindow: Bool {
        dialog != nil || extensionRequest != nil || commandBar != nil || (peek != nil && showingArchive)
    }
    /// The selected tab's profile, else the Space's: whose extensions the window shows.
    private var profileID: UUID? {
        selectedTabID.flatMap { state.profile(containing: $0)?.id } ?? space?.profileID
    }
    var browser: (any Browser)? { profileID.flatMap { browsers[$0] } }
    func profileName(_ id: UUID) -> String { engine.userVisibleName(of: id) ?? "" }
    /// The engine's profiles in its order, read when asked, as Arc's menus list them.
    var profiles: [ProfileState] { engine.allProfiles().map { ProfileState(id: $0, name: profileName($0)) } }
    var extensions: [BrowserExtension] { profileID.map { engine.browserContext(id: $0).extensions.items } ?? [] }
    var extensionActions: [ExtensionAction] { browser?.extensionActions ?? [] }
    var extensionPopup: ExtensionPopup? { browsers.values.lazy.compactMap(\.extensionPopup).first }
    /// What the prompt draws: the answered request stays until its popover has closed.
    var promptedPermissionRequest: PagePermissionRequest? { permissionRequest ?? answeredPermissionRequest?.request }
    private var peekOwnerID: UUID? { showingArchive ? archivePeekID : selectedTabID }
    /// What the address field shows: the live page's URL, else the tab's saved one while its page is pending. As Arc:
    /// a Peek's while one is up.
    var address: URL? { frontPage?.url ?? selectedTab?.url }
    var favorites: [SidebarTab] { state.favorites(for: selectedSpaceID) }
    var pinnedTabs: [SidebarTab] { state.tabs(in: selectedSpaceID, pinned: true) }
    var unpinnedTabs: [SidebarTab] { state.tabs(in: selectedSpaceID, pinned: false) }
    var selectableTabs: [SidebarTab] { state.selectableTabs(in: selectedSpaceID) }
    var canRestoreLastClosed: Bool { !closedGroups.isEmpty }

    var record: WindowRecord {
        WindowRecord(
            id: id, selectedSpaceID: selectedSpaceID, sidebarMode: sidebarMode, sidebarWidth: sidebarWidth,
            lastActiveDates: lastActiveDates, createdDates: createdDates, collapsedPinnedSpaces: collapsedPinnedSpaces)
    }

    init(
        id: UUID, engine: any BrowserApplication, store: SidebarStore, downloads: DownloadsStore,
        pictureInPicture: PictureInPicture, spaceID: UUID
    ) {
        self.id = id
        self.engine = engine
        self.store = store
        self.downloads = downloads
        self.pictureInPicture = pictureInPicture
        selectedSpaceID = spaceID
        sidebarMode = store.sidebarViewPreferences.sidebarMode
        sidebarWidth = store.sidebarViewPreferences.sidebarWidth
        loadExtensions()
    }

    /// As Arc: a restored window comes back on its Space with nothing selected and no page. Its dates come back
    /// too, as Oa's own: Arc saves them with the window, and what its restore does with them is unknown.
    func restore(_ record: WindowRecord) {
        if state.space(record.selectedSpaceID) != nil { selectedSpaceID = record.selectedSpaceID }
        sidebarMode = record.sidebarMode
        sidebarWidth = record.sidebarWidth
        lastActiveDates = record.lastActiveDates
        createdDates = record.createdDates
        collapsedPinnedSpaces = record.collapsedPinnedSpaces
        openCommandBar(.newTab)
    }

    /// A pinned tab whose page has left its address reads "/ live title", as in Arc; a Favorite, whose tile has no
    /// text, gives the window the live title as Arc's does.
    func title(for tab: SidebarTab) -> String {
        guard let url = leftAddress(tab), let page = pages[tab.id] else { return tab.displayTitle }
        let live = page.title.isEmpty ? url.host() ?? url.absoluteString : page.title
        return state.isFavorite(tab.id) ? live : "/ " + live
    }

    func leftAddress(_ tab: SidebarTab) -> URL? {
        guard state.keepsAddress(tab.id), let url = pages[tab.id]?.url, !tab.isAt(url) else { return nil }
        return url
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
    /// only a secure page lists its settings. Automatic picture-in-picture is always among them and allowed unless
    /// blocked, Chrome's Ask included.
    func siteSettings() -> [SiteSetting] {
        guard let page, page.securityLevel == .secure, let url = page.url, let context = siteContext else { return [] }
        let changed = context.changedSiteSettings(for: url) ?? []
        let pictureInPicture = changed.first { $0.type == .automaticPictureInPicture }?.value
        return changed.filter { $0.type != .automaticPictureInPicture }
            + [SiteSetting(type: .automaticPictureInPicture, value: pictureInPicture == .block ? .block : .allow)]
    }

    /// As Arc: allowed becomes blocked and anything else allowed, with no reload.
    func toggle(_ setting: SiteSetting) {
        guard let url = page?.url, let context = siteContext else { return }
        context.setSiteSetting(setting.type, to: setting.value.isAllowed ? .block : .allow, for: url)
    }

    /// As Arc: in a Peek over the tab (arc-site-controls.md §1).
    func openAllSiteSettings() {
        guard let tabID = selectedTabID, let url = page?.url, let profile = state.profile(containing: tabID),
            var components = URLComponents(string: "chrome://settings/content/siteDetails")
        else { return }
        components.queryItems = [URLQueryItem(name: "site", value: url.absoluteString)]
        guard let settings = components.url else { return }
        let context = engine.browserContext(id: profile.id)
        Task { [weak self, id] in
            guard let page = await context.makePage(windowID: id, restoring: nil)?.page, let self else { return }
            guard pages[tabID] != nil else { return page.drop() }
            peek(page, from: tabID)
            page.load(settings)
        }
    }

    func siteSetting(_ type: SiteSettingType, ofPage pageID: UUID) -> SiteSettingValue? {
        guard let tabID = tabID(of: pageID), let url = pages[tabID]?.url,
            let profile = state.profile(containing: tabID)
        else { return nil }
        return engine.browserContext(id: profile.id).changedSiteSettings(for: url)?.first { $0.type == type }?.value
    }

    /// As Arc's presentation updates, which its picture-in-picture rule answers: the page the window shows changed.
    /// A page's thumbnails are observed from the first time a window shows it, as Arc starts when its view loads.
    private func presentationChanged() {
        let page = page
        guard presentedPage?.id != page?.id else { return }
        for changed in [presentedPage, page] { changed.map(pictureInPicture.presentationChanged) }
        page?.startObservingThumbnails()
        presentedPage = page
    }

    private var siteContext: (any BrowserContext)? {
        selectedTabID.flatMap { state.profile(containing: $0) }.map { engine.browserContext(id: $0.id) }
    }

    /// Read as a Space is shown, so the engine has reported its profile's by the time the Extensions menu opens.
    private func loadExtensions() {
        if let profileID = space?.profileID { _ = engine.browserContext(id: profileID).extensions.items }
    }

    /// As Arc: the Chrome Web Store's extensions page in a new tab.
    func addExtension() {
        if let url = URL(string: "https://chromewebstore.google.com/category/extensions") { newTab(url) }
    }

    /// As Arc's Manage Extensions…: Chrome's page in a new tab.
    func manageExtensions() {
        if let url = URL(string: "chrome://extensions/") { newTab(url) }
    }

    func runExtension(_ id: ExtensionAction.ID) { browser?.runExtensionAction(id) }

    func togglePin(of action: ExtensionAction) {
        browser?.setExtensionPinned(action.pinnedPosition == nil, id: action.id)
    }

    func showExtensionMenu(for id: ExtensionAction.ID) { browser?.showExtensionMenu(for: id) }

    func closeExtensionPopup() {
        for browser in browsers.values { browser.closeExtensionPopup() }
    }

    func respond(to request: PageExtensionRequest, accepted: Bool) {
        forget(request)
        request.respond(accepted)
    }

    private func forget(_ request: PageExtensionRequest) {
        for (pageID, requests) in extensionRequests where requests.contains(where: { $0 === request }) {
            extensionRequests[pageID] = requests.filter { $0 !== request }
            if extensionRequests[pageID]?.isEmpty == true { extensionRequests[pageID] = nil }
        }
    }

    private func ensureBrowser(for profileID: UUID) {
        guard browsers[profileID] == nil else { return }
        let browser = engine.browserContext(id: profileID).browser(windowID: id)
        browsers[profileID] = browser
        browserListeners[profileID] = Task { [weak self] in
            for await event in browser.events {
                guard let self, case .opened(let page, let isActive) = event else { continue }
                place(page, isActive: isActive, in: profileID)
            }
        }
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
        let context = engine.browserContext(id: profileID)
        let autocomplete = autocompletes[profileID] ?? context.makeAutocomplete()
        autocompletes[profileID] = autocomplete
        let preferences = context.preferences
        let bar = CommandBar(
            destination: editing ? .currentTab : .newTab, autocomplete: autocomplete,
            currentURL: editing ? frontPage?.url ?? address : nil, profileID: profileID, picks: store.commandBarPicks,
            searchEngines: { preferences.activeSearchEngines },
            dominantColor: { await context.siteSearchDominantColor(host: $0) }
        ) { [weak self] in self?.commandBarTabs ?? [] }
        bar.perform = { [weak self, destination = bar.destination] in self?.perform($0, in: destination) }
        commandBar = bar
        commandBarSelection = (selectedSpaceID, selectedTabID)
    }

    var topBarColors: TopBarColorClient { store.topBarColors }
    var keyBindings: KeyBindingsClient { store.keyBindings }

    /// As Arc's `updateTopBarTrackedContent`: the window's visible pages, its Peek's among them, while their
    /// toolbar is shown.
    func trackToolbarPage(_ shown: Bool) {
        store.topBarColors.setTrackedPage(shown ? page : nil, for: ToolbarOwner.window(id))
    }

    func trackPeekToolbarPage(_ page: (any Page)?) {
        store.topBarColors.setTrackedPage(page, for: ToolbarOwner.peek(id))
    }

    private enum ToolbarOwner: Hashable {
        case window(UUID)
        case peek(UUID)
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
        guard state.isSelectable(tabID, in: selectedSpaceID) else { return }
        // Oa's own, as for a Space: a tab chosen with the Create a Space panel open closes it. Arc keeps the panel
        // under the ⌘T bar; what it does once a tab is chosen wasn't seen.
        cancelSpaceCreation()
        guard selectedTabID != tabID else { return }
        library = nil
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

    /// As Arc's `sortedLastActiveOrNewestItemIDs` under its switcher's filter: the tabs this window showed or made,
    /// newest first behind the one it shows, in the window's profile and whatever their Space.
    private var recentTabIDs: [UUID] {
        let dates = createdDates.merging(lastActiveDates) { $1 }
        var tabIDs = dates.keys.sorted { dates[$0]! > dates[$1]! }
        if let selectedTabID {
            tabIDs.removeAll { $0 == selectedTabID }
            tabIDs.insert(selectedTabID, at: 0)
        }
        return tabIDs.filter { state.tree.tab($0) != nil && state.profile(containing: $0)?.id == space?.profileID }
    }

    /// As Arc's `onHighlightAdjacentRecentTab`: the command bar closes and the switcher comes up over the recent
    /// tabs, or not at all with none. The shown page and its Peek's are asked for a fresh thumbnail, the others have
    /// their last.
    func highlightAdjacentRecentTab(_ target: ModalItemSwitcher.Target) {
        closeCommandBar()
        guard modalItemSwitcher == nil,
            let switcher = ModalItemSwitcher(itemIDs: recentTabIDs, currentID: selectedTabID, target: target)
        else { return }
        page?.requestThumbnail()
        peek?.requestThumbnail()
        modalItemSwitcher = switcher
    }

    /// As Arc's `dismissModalItemSwitcher(itemToSelect:)`: a commit selects as a click on the tab would, its Space
    /// first when it is in another.
    func dismissModalItemSwitcher(selecting tabID: UUID? = nil) {
        guard modalItemSwitcher != nil else { return }
        modalItemSwitcher = nil
        if let tabID { show(tabID) }
    }

    /// As Arc's `updateModalItemSwitcher(confirmedItemIDsToClose:)`: once a tab has closed, the list is built again
    /// without it, and the switcher goes with its last card.
    private func updateModalItemSwitcher(closing tabID: UUID) {
        guard let switcher = modalItemSwitcher else { return }
        switcher.closedItemIDs.insert(tabID)
        let tabIDs = recentTabIDs.filter { !switcher.closedItemIDs.contains($0) }
        if tabIDs.isEmpty { dismissModalItemSwitcher() } else { switcher.update(itemIDs: tabIDs) }
    }

    /// Nothing for a tab without a page, as Arc's card for an unloaded tab is blank.
    func snapshot(for tab: SidebarTab) -> NSImage? {
        livePage(for: tab.id).flatMap(store.contentSnapshots.snapshot(of:))
    }

    func peekSnapshot(for tab: SidebarTab) -> NSImage? {
        peeks[tab.id].flatMap(store.contentSnapshots.snapshot(of:))
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

    /// As Arc: a Space with nothing to show is shown empty, with no command bar.
    func selectSpace(_ spaceID: UUID) {
        guard state.space(spaceID) != nil else { return }
        cancelSpaceCreation()
        guard spaceID != selectedSpaceID else { return }
        selectedSpaceID = spaceID
        if let tabID = selectedTabID {
            ensurePage(tabID)
            markViewed(tabID)
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

    /// Arc's Create a Space panel, on the window's Space's profile, after `spaceID` or, as Arc's `.absolute(-1)`, at
    /// the end. As Arc, it leaves the Library and changes neither the Space nor the selection.
    func beginSpaceCreation(after spaceID: UUID? = nil) {
        guard spaceCreation == nil, let space else { return }
        closeCommandBar()
        library = nil
        spaceCreation = SpaceCreationState(insertAfter: spaceID, profileID: space.profileID)
    }

    /// Where the panel's page and dock item sit among the Spaces: where the Space will go.
    var spaceCreationIndex: Int? {
        guard let creation = spaceCreation else { return nil }
        let spaces = state.spaces
        return creation.insertAfter.flatMap { id in spaces.firstIndex { $0.id == id } }.map { $0 + 1 } ?? spaces.count
    }

    func updateSpaceCreation(_ change: (inout SpaceCreationState) -> Void) {
        guard var creation = spaceCreation else { return }
        change(&creation)
        spaceCreation = creation
    }

    /// As Arc: a cancel during the splash still makes the Space, without showing it.
    func cancelSpaceCreation() {
        guard let creation = spaceCreation else { return }
        if creation.phase == .animating { return completeSpaceCreation(selecting: false) }
        spaceCreation = nil
    }

    /// As Arc's `didTriggerCreateSpace`: the panel plays its splash, then `completeSpaceCreation` makes the Space, at
    /// once with Reduce Motion.
    func triggerSpaceCreation() {
        guard spaceCreation?.canCreate == true, spaceCreation?.phase == .editing else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return completeSpaceCreation() }
        updateSpaceCreation { $0.phase = .animating }
    }

    func completeSpaceCreation(selecting: Bool = true) {
        guard let creation = spaceCreation, creation.canCreate else { return }
        spaceCreation = nil
        let name = creation.title.trimmingCharacters(in: .whitespacesAndNewlines)
        // Oa's own: a profile deleted while the panel was open gives way to the window's Space's.
        guard let profileID = state.profile(creation.profileID)?.id ?? space?.profileID else { return }
        var created: SidebarSpace?
        store.edit {
            created = $0.addSpace(name: name, profileID: profileID, icon: creation.icon, after: creation.insertAfter)
        }
        if selecting, let created { selectSpace(created.id) }
    }

    /// As Arc: a new window starts with the collapsed sections of the window it came from.
    func inheritCollapsedPinnedSpaces(from source: WindowModel) {
        collapsedPinnedSpaces = source.collapsedPinnedSpaces
    }

    func togglePinnedSection(of spaceID: UUID) {
        if collapsedPinnedSpaces.remove(spaceID) == nil { collapsedPinnedSpaces.insert(spaceID) }
        store.windowStateChanged()
    }

    func moveSpace(_ spaceID: UUID, to index: Int) {
        guard state.spaces.firstIndex(where: { $0.id == spaceID }) != index else { return }
        store.edit { $0.moveSpace(spaceID, to: index) }
    }

    func renameSpace(_ spaceID: UUID, to name: String) {
        store.edit { $0.renameSpace(spaceID, to: name) }
    }

    func setSpaceIcon(_ icon: String?, for spaceID: UUID) {
        guard let space = state.space(spaceID), space.icon != icon else { return }
        store.edit { $0.setSpaceIcon(icon, for: spaceID) }
    }

    /// As Arc: the new profile has its Favorites and site searches from the start, and Settings selects it.
    func createProfile(named name: String) async -> UUID? {
        guard let profileID = await engine.createBrowserContext(userVisibleName: name) else { return nil }
        SiteSearchMigrations.seed(engine.browserContext(id: profileID))
        store.edit { $0.addProfile(profileID) }
        store.didCreateProfile(profileID)
        return profileID
    }

    /// As Arc's `didSetProfileForSpaceIDs`. A page can't change profile, so the Spaces' pages go with nothing kept
    /// and each tab loads again in the new profile once selected, at its saved address. A window showing a moved
    /// Space selects its bottom-most unpinned tab. Arc leaves the pages another window holds alive in the old
    /// profile and blank; in Oa a tab has one page, which goes wherever it is. Oa's own: an open command bar, which
    /// searches the old profile, closes.
    func setProfile(_ profileID: UUID, forSpaces spaceIDs: [UUID]) {
        let spaceIDs = spaceIDs.filter { state.space($0).map { $0.profileID != profileID } ?? false }
        let tabIDs = spaceIDs.flatMap { state.tabs(in: $0).map(\.id) }
        for window in store.windows { window.dropPages(of: tabIDs) }
        store.edit { $0.setProfile(profileID, forSpaces: spaceIDs) }
        for window in store.windows.filter({ $0 !== self }) + [self] where spaceIDs.contains(window.selectedSpaceID) {
            window.closeCommandBar()
            window.selectedTabIDs[window.selectedSpaceID] = nil
            if let bottom = state.tabs(in: window.selectedSpaceID, pinned: false).last { window.select(bottom.id) }
        }
    }

    /// Before a profile is deleted: its Favorites' pages and the window's browser and omnibox for it.
    func forgetProfile(_ id: UUID) {
        if let profile = state.profile(id) { dropPages(of: state.tree.tabs(under: profile.favoritesRootID).map(\.id)) }
        browserListeners.removeValue(forKey: id)?.cancel()
        browsers[id] = nil
        autocompletes[id] = nil
    }

    private func dropPages(of tabIDs: [UUID]) {
        for tabID in tabIDs {
            if let peek = peeks.removeValue(forKey: tabID) {
                dialogs[peek.id] = nil
                permissionRequests[peek.id] = nil
                peek.drop()
            }
            placeholders[tabID] = nil
            release(tabID)?.drop()
        }
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

    func move(_ tabID: UUID, pinned: Bool, at index: Int) {
        store.edit { $0.moveTab(tabID, in: selectedSpaceID, pinned: pinned, at: index) }
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
            return archive(tabID, reason: .manual, closedBy: .window(id), sessionID: nil)
        }
        store.closing[page.id] = .window(id)
        page.close()
    }

    /// As seen in Arc: the window's mode changes, and with it the one a new window takes.
    func setSidebarMode(_ mode: SidebarMode) {
        guard mode != sidebarMode else { return }
        sidebarMode = mode
        store.sidebarViewPreferences.sidebarMode = mode
    }

    func setSidebarWidth(_ width: CGFloat) {
        guard width != sidebarWidth else { return }
        sidebarWidth = width
        store.sidebarViewPreferences.sidebarWidth = width
    }

    var showingArchive: Bool { library == .archive }
    var showingDownloads: Bool { library == .downloads }

    func viewLibrary(_ section: LibrarySection? = nil) {
        library = section ?? lastLibrarySection
    }

    func exitLibrary() {
        library = nil
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

    func restoreArchived(_ id: UUID) {
        store.edit { $0.restoreArchived(id, in: selectedSpaceID) }
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
            page.startObservingThumbnails()
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
        if peekOwnerID != archivePeekID { store.closing[page.id] = .window(id) }
        page.close()
    }

    /// As Arc's `reopenLastClosedTab`: the newest step of this window's newest close. A tab that is open again is
    /// selected; one that is gone returns where it was with its history. Restore and the Archive Peek load fresh.
    func restoreLastClosed() {
        guard var group = closedGroups.popLast(), let closed = group.steps.popLast() else { return }
        if !group.steps.isEmpty { closedGroups.append(group) }
        guard case .tab(let parentID, let index) = closed.place else { return reopenPeek(closed) }
        var sessionID: PageSessionID?
        if state.tree.tab(closed.id) == nil {
            let present = state.tree[parentID]?.childIDs ?? []
            let index = group.index(of: closed.id, among: present) ?? index
            let tab = SidebarTab(id: closed.id, title: closed.title, url: closed.url, viewedAt: .now)
            store.edit { $0.reopenTab(tab, in: parentID, at: index, else: selectedSpaceID) }
            createdDates[closed.id] = .now
            sessionID = closed.sessionID
        }
        if let spaceID = state.space(containing: closed.id)?.id { selectSpace(spaceID) }
        library = nil
        select(closed.id, restoring: sessionID)
    }

    /// As Arc: the Peek's tab is selected and the Peek returns over it with its history, its Archive entry gone.
    /// Nothing shows when the tab already has a Peek, or when the tab is gone, which also keeps the entry.
    private func reopenPeek(_ closed: ClosedPage) {
        guard case .peek(let ownerID) = closed.place, let profile = state.profile(containing: ownerID) else { return }
        store.edit { $0.removeArchived(closed.id) }
        guard !store.windows.contains(where: { $0.peeks[ownerID] != nil }) else { return }
        if let spaceID = state.space(containing: ownerID)?.id { selectSpace(spaceID) }
        library = nil
        select(ownerID)
        let context = engine.browserContext(id: profile.id)
        ensureBrowser(for: profile.id)
        Task { [weak self, id] in
            guard let made = await context.makePage(windowID: id, restoring: closed.sessionID), let self else { return }
            guard state.tree.tab(ownerID) != nil, peeks[ownerID] == nil else { return made.page.drop() }
            peek(made.page, from: ownerID)
            if !made.restored, let url = closed.url { made.page.load(url) }
        }
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
    func close(_ tabID: UUID, reason: SidebarArchivedTab.Reason = .manual, group: ClosedGroup? = nil) {
        if state.isFavorite(tabID) {
            if let tab = state.tree.tab(tabID), let url = tab.url, let page = pages[tabID], !tab.isAt(page.url) {
                page.load(url)
            }
            deselect(tabID)
            return updateModalItemSwitcher(closing: tabID)
        }
        let page = store.windows.lazy.compactMap { $0.pages[tabID] }.first
        let request: CloseRequest = reason == .auto ? .auto : .window(id, group: group)
        guard let page, !state.isPinned(tabID) else {
            return end(tabID, reason: reason, closedBy: request) { page, _ in page.drop() }
        }
        store.closing[page.id] = request
        page.close()
    }

    /// A pinned row's ✕, which archives it as a Today row's does, as Arc's close button does.
    func archivePinned(_ tabID: UUID) {
        guard state.isPinned(tabID) else { return close(tabID) }
        store.archivingPins.insert(tabID)
        guard let page = store.windows.lazy.compactMap({ $0.pages[tabID] }).first else {
            return end(tabID, reason: .manual, closedBy: .window(id)) { page, _ in page.drop() }
        }
        store.closing[page.id] = .window(id)
        page.close()
    }

    var canClearTabs: Bool { !unpinnedTabs.isEmpty }

    /// As Arc's Clear: the Space's unpinned tabs but the selected one, which goes too when it is the last.
    /// ⇧⌘T brings the last selected back first, as Arc's did.
    /// A Library card's takes them all, as Arc's builds the card with no selection.
    func clearTabs(in spaceID: UUID? = nil, all: Bool = false) {
        let spaceID = spaceID ?? selectedSpaceID
        var tabIDs = state.tabs(in: spaceID, pinned: false).map(\.id)
        if !all, !clearsAllTabs(in: spaceID), let selectedTabID { tabIDs.removeAll { $0 == selectedTabID } }
        closeTogether(tabIDs.sorted { lastActiveDates[$0] ?? .distantPast < lastActiveDates[$1] ?? .distantPast })
    }

    /// Arc's `clearTabAction`: Clear keeps the window's selected tab only when it is one of several Today tabs.
    func clearsAllTabs(in spaceID: UUID) -> Bool {
        let tabIDs = state.tabs(in: spaceID, pinned: false).map(\.id)
        return tabIDs.count == 1 || !(selectedTabID.map(tabIDs.contains) ?? false)
    }

    /// As Arc's: the unpinned tabs below this one, the selected one included; ⇧⌘T brings them back from the top.
    func archiveTabs(below tabID: UUID) {
        guard let space = state.space(containing: tabID) else { return }
        let tabIDs = state.tabs(in: space.id, pinned: false).map(\.id)
        guard let index = tabIDs.firstIndex(of: tabID) else { return }
        closeTogether(tabIDs[(index + 1)...].reversed())
    }

    /// One close of several tabs from this window, one entry on its stack, the steps going back from the last.
    private func closeTogether(_ tabIDs: [UUID]) {
        guard !tabIDs.isEmpty else { return }
        let group = ClosedGroup(order: tabIDs, siblings: unpinnedTabs.map(\.id))
        let closing = Set(tabIDs)
        if let selected = selectedTabID, closing.contains(selected) {
            let next = nextSelection(closing: selected, pinned: false, in: selectedSpaceID, alsoClosing: closing)
            selectedTabIDs[selectedSpaceID] = next
            if let next { ensurePage(next) }
        }
        for tabID in tabIDs { close(tabID, group: group) }
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
        extensionRequests = [:]
        closeExtensionPopup()
        browserListeners.values.forEach { $0.cancel() }
        browserListeners = [:]
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
        _ tabID: UUID, reason: SidebarArchivedTab.Reason, closedBy request: CloseRequest?,
        sessionID: PageSessionID? = nil, _ finish: (any Page, Bool) -> Void
    ) {
        guard let spaceID = state.space(containing: tabID)?.id else { return }
        let pinned = state.isPinned(tabID)
        let wasSelected = selectedTabIDs[spaceID] == tabID
        // As Arc: a close of several picks the next selection up front, so a tab of it shown later by its "Leave
        // site?" leaves none.
        let next =
            wasSelected && request?.group == nil ? nextSelection(closing: tabID, pinned: pinned, in: spaceID) : nil
        let page = store.windows.compactMap { $0.release(tabID) }.first
        for window in store.windows {
            window.placeholders[tabID] = nil
            // As Arc's close: a pinned tab keeps when a window last showed it, not when one made it.
            window.createdDates[tabID] = nil
        }
        if !pinned || store.archivingPins.remove(tabID) != nil {
            archive(tabID, reason: reason, closedBy: request, sessionID: sessionID)
        }
        if let page { finish(page, pinned) }
        if wasSelected {
            selectedTabIDs[spaceID] = next
            if let next, spaceID == selectedSpaceID { ensurePage(next) }
        }
        for window in store.windows { window.updateModalItemSwitcher(closing: tabID) }
    }

    /// A close the user asked for goes on the stack of the window they asked in, as Arc's does. The session ID
    /// goes with it, Oa's own: Arc keeps it in the window that held the page, so a close from another window comes
    /// back with a fresh load there.
    private func archive(
        _ tabID: UUID, reason: SidebarArchivedTab.Reason, closedBy request: CloseRequest?, sessionID: PageSessionID?
    ) {
        let closed = state.tree.tab(tabID).flatMap { tab in
            state.tree.location(of: tabID).map {
                ClosedPage(
                    id: tabID, title: tab.title, url: tab.url, place: .tab(parentID: $0.parentID, index: $0.index),
                    sessionID: sessionID)
            }
        }
        store.edit { $0.archiveTab(tabID, reason: reason) }
        if let closed { store.windows.first { $0.id == request?.windowID }?.remember(closed, in: request?.group) }
    }

    private func remember(_ closed: ClosedPage, in group: ClosedGroup? = nil) {
        if let group, let index = closedGroups.firstIndex(of: group) { return closedGroups[index].add(closed) }
        var group = group ?? ClosedGroup()
        group.add(closed)
        push(group)
    }

    private func push(_ group: ClosedGroup) {
        closedGroups.append(group)
        if closedGroups.count > 10 { closedGroups.removeFirst() }
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
    private func nextSelection(
        closing tabID: UUID, pinned: Bool, in spaceID: UUID, alsoClosing others: Set<UUID> = []
    ) -> UUID? {
        if let successor = state.openerSuccessor(of: tabID), !others.contains(successor) { return successor }
        if let previousTabID, previousTabID != tabID, !others.contains(previousTabID), pages[previousTabID] != nil,
            state.isSelectable(previousTabID, in: spaceID)
        {
            return previousTabID
        }
        guard !pinned else { return nil }
        let tabs = state.selectableTabs(in: spaceID)
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return nil }
        let staying = { (tab: SidebarTab) in !others.contains(tab.id) }
        return (tabs[..<index].last(where: staying) ?? tabs[(index + 1)...].first(where: staying))?.id
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
        takeExtensionRequests(of: page, from: holder)
        if let peek = holder.releasePeek(tabID) {
            peek.move(toWindow: id)
            peeks[tabID] = peek
            takeExtensionRequests(of: peek, from: holder)
        }
        placeholders[tabID] = nil
        install(page, for: tabID)
    }

    /// The engine's question isn't tied to the window that showed it, so it goes where its page goes.
    private func takeExtensionRequests(of page: any Page, from holder: WindowModel) {
        if let requests = holder.extensionRequests.removeValue(forKey: page.id) {
            extensionRequests[page.id] = requests
        }
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
        let pictureInPicture = pictureInPicture
        let pageID = page.id
        Task {
            for await event in page.events {
                // The app's one window for it, whichever window holds the page, or none any more.
                if case .pictureInPicture(let event) = event {
                    pictureInPicture.handle(event, for: pageID)
                } else if let window = store.windows.first(where: { $0.holds(pageID) }) {
                    window.handle(event, for: pageID)
                } else if case .dialog(let dialog) = event, case .beforeUnload = dialog.kind {
                    dialog.accept()
                }
            }
        }
    }

    private func holds(_ pageID: UUID) -> Bool {
        tabID(of: pageID) != nil || peekOwner(of: pageID) != nil
    }

    private func tabID(of pageID: UUID) -> UUID? {
        pages.first { $0.value.id == pageID }?.key
    }

    /// A tab's page or a Peek's.
    func page(id pageID: UUID) -> (any Page)? {
        pages.values.first { $0.id == pageID } ?? peeks.values.first { $0.id == pageID }
    }

    /// As for a page that asks to be shown: its tab, or the tab its Peek is over.
    func showPage(_ pageID: UUID) {
        if let ownerID = peekOwner(of: pageID) {
            if ownerID != archivePeekID { show(ownerID) } else { bringToFront() }
        } else if let tabID = tabID(of: pageID) {
            show(tabID)
        }
    }

    private func peekOwner(of pageID: UUID) -> UUID? {
        peeks.first { $0.value.id == pageID }?.key
    }

    private func handle(_ event: PageEvent, for pageID: UUID) {
        switch event {
        case .dialog(let dialog):
            // As Arc: a page asks to be shown first, and a "Leave site?" its window still can't show leaves unasked.
            if case .beforeUnload = dialog.kind, page?.id != pageID, peek?.id != pageID {
                return dialog.accept()
            }
            dialogs[pageID, default: []].append(dialog)
            if let ownerID = peekOwner(of: pageID), state.tree.tab(ownerID) == nil, archivePeekID != ownerID {
                library = .archive
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
        case .extensionRequest(let request):
            extensionRequests[pageID, default: []].append(request)
            return
        case .extensionRequestClosed(let request):
            return forget(request)
        case .thumbnail(let thumbnail):
            // As Arc's thumbnail listener: every thumbnail is kept as its page's snapshot, then goes to the toolbar's
            // colours, which sample a shown page's.
            let page = page(id: pageID)
            if let page { store.contentSnapshots.storeSnapshot(thumbnail, of: page) }
            return store.topBarColors.process(thumbnail: thumbnail, ofPage: pageID, at: page?.url)
        case .closeCancelled:
            return closeCancelled(pageID)
        case .wantsActivation:
            return showPage(pageID)
        default:
            break
        }
        if let ownerID = peekOwner(of: pageID) {
            switch event {
            case .opened(let opened, let url, let disposition, let byPage):
                place(opened, url: url, disposition: disposition, byPage: byPage, from: ownerID, insidePeek: true)
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
        case .closed(let sessionID):
            pageEnded(tabID, sessionID: sessionID)
        default:
            break
        }
    }

    /// A refused auto-archive counts as a view, so the next sweep doesn't ask again.
    private func closeCancelled(_ pageID: UUID) {
        let request = store.closing.removeValue(forKey: pageID)
        if let tabID = tabID(of: pageID) {
            store.archivingPins.remove(tabID)
            if request == .auto { store.markViewed(tabID) }
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
        extensionRequests[page.id] = nil
        if let request = store.closing.removeValue(forKey: page.id), state.tree.tab(ownerID) != nil {
            let spaceID = state.space(containing: ownerID)?.id
            store.edit { $0.archivePage(id: page.id, title: page.title, url: page.url, in: spaceID) }
            store.windows.first { $0.id == request.windowID }?.remember(
                ClosedPage(
                    id: page.id, title: page.title, url: page.url, place: .peek(ownerID: ownerID),
                    sessionID: sessionID))
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
        // As Arc, whose card for a tab left with a Peek on it has the Peek's picture from its page's load.
        page.startObservingThumbnails()
    }

    /// Switches to the tab's Space and raises the window, as Arc does for a page asking to be shown and for another
    /// Space's tab picked in the command bar.
    func show(_ tabID: UUID) {
        guard let spaceID = spaceToShow(tabID), state.isSelectable(tabID, in: spaceID) else { return }
        if spaceID != selectedSpaceID {
            library = nil
            selectedTabIDs[spaceID] = tabID
            selectSpace(spaceID)
        } else {
            select(tabID)
        }
        bringToFront()
    }

    /// As Arc's `spaceToSwitchTo(whenSelecting:)`: a tab's own Space; a Favorite stays when the Space shares its
    /// profile, else goes to the first Space of its profile in the sidebar's order.
    private func spaceToShow(_ tabID: UUID) -> UUID? {
        if let space = state.space(containing: tabID) { return space.id }
        guard let profile = state.profile(containing: tabID) else { return nil }
        if space?.profileID == profile.id { return selectedSpaceID }
        return state.spaces.first { $0.profileID == profile.id }?.id
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
        extensionRequests[page.id] = nil
        let request = store.closing.removeValue(forKey: page.id)
        if state.isFavorite(tabID) {
            release(tabID)
            for window in store.windows { window.placeholders[tabID] = nil }
            if let request { archive(tabID, reason: .manual, closedBy: request, sessionID: sessionID) }
            deselect(tabID)
        } else if store.deletingSpace?.closing.contains(page.id) == true {
            release(tabID)
        } else {
            let reason: SidebarArchivedTab.Reason = request == .auto ? .auto : .manual
            end(tabID, reason: reason, closedBy: request, sessionID: sessionID) { _, _ in }
        }
        spaceDeletionEnded(page.id, kept: false)
    }
}
