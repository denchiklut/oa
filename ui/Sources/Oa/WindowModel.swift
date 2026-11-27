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
    /// Arc's `WindowStyle`; a Little window's carries its state.
    private(set) var style: WindowStyle {
        didSet { store.windowStateChanged() }
    }
    var sidebarContext: SidebarContext? { style.sidebarContext }
    var isLittle: Bool { little != nil }
    var little: LittleBrowserState? {
        get {
            if case .little(let state) = style { state } else { nil }
        }
        set {
            if let newValue, isLittle { style = .little(newValue) }
        }
    }
    private(set) var selectedSpaceID: UUID {
        didSet {
            dismissSpaceStyleEditor()
            updateCommandBarForSelection()
            loadExtensions()
            presentationChanged()
            dismissModalItemSwitcher()
        }
    }
    private(set) var selectedTabIDs: [UUID: UUID] = [:] {
        didSet {
            selectionCount += 1
            if little?.isPresented == false, selectedTabID != nil { little?.modalState = .presented }
            // A close's replacement in a split is the pane the window comes back to, as one clicked is.
            for tabID in selectedTabIDs.values {
                if let splitID = state.splitViewID(containing: tabID) { focusedPaneIDs[splitID] = tabID }
            }
            updateCommandBarForSelection()
            presentationChanged()
        }
    }
    private(set) var pages: [UUID: any Page] = [:] {
        didSet { presentationChanged() }
    }
    /// Last settled live title for a pinned tab whose page has left its address, held steady while loading.
    private var settledLiveTitles: [UUID: String] = [:]
    /// Last frames of pages that left for another window while their tab stayed selected here.
    private(set) var placeholders: [UUID: NSImage] = [:]
    /// Pages shown over the window as Arc's Peek: by the tab they were opened from, whose state they are, or by
    /// the Archive entry they show.
    private(set) var peeks: [UUID: any Page] = [:]
    /// As Arc's `WindowState.spaceCreationState`: while it is open the window shows nothing selected.
    private(set) var spaceCreation: SpaceCreationState? {
        didSet {
            updateCommandBarForSelection()
            presentationChanged()
        }
    }
    /// As Arc's `WindowState.spaceStyleEditorPresentation`.
    private(set) var spaceStyleEditor: WindowSpaceStyleEditorPresentation?
    /// As Arc: the window keeps the editor's preset page, for every editor it opens.
    var spaceStyleEditorPresetPage = 0
    /// As Arc's per-window `spacesWithCollapsedPinnedSections`: the Spaces whose pinned tabs this window folds away.
    private(set) var collapsedPinnedSpaces: Set<UUID> = []
    /// As Arc's per-window `expandedItems`: the folders expanded in this window.
    private(set) var expandedFolderIDs: Set<UUID> = []
    /// Folder currently in inline rename (set when created inline so it focuses and scrolls into view).
    var editingFolderID: UUID?
    /// Tabs kept peeked under collapsed folders for 100 ms after selection leaves them, as Arc's
    /// `reparentPeekingIfNecessary(for:requiresDelay:)`.
    private var departingPeekTargets: [UUID: Set<UUID>] = [:]
    @ObservationIgnored private var departingPeekTasks: [UUID: Task<Void, Never>] = [:]
    private(set) var multiSelection = SidebarMultiSelection()
    private(set) var library: LibrarySection? {
        didSet {
            if let library { store.home.lastSelectedHomePage = library }
            if library != .archive { closeArchivePeek() }
        }
    }
    var lastLibrarySection: LibrarySection {
        librarySections.contains(store.home.lastSelectedHomePage) ? store.home.lastSelectedHomePage : librarySections[0]
    }
    /// As seen in Arc: an incognito window's Library has only Media, Downloads and Easels, of which Oa has Downloads.
    var librarySections: [LibrarySection] { sidebarContext == .incognito ? [.downloads] : LibrarySection.allCases }
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
    /// The engine's dialog shown over this window, as Arc's `currentWebDialog`: one that comes while another is shown
    /// is never shown, and its page waits until it closes some other way.
    private(set) var webDialog: WebDialog?
    /// By profile, as ADK keeps a browser per window and profile: from the window's first page in the profile on.
    private(set) var browsers: [UUID: any Browser] = [:]
    /// Where a Little window's Open in button is, for the list that opens over it.
    var littleMoveButtonFrame = CGRect.zero
    /// Run by the window's controller once the window has closed.
    @ObservationIgnored var afterClose: (() -> Void)?
    private(set) var commandBar: CommandBar?
    /// When this window last showed a tab and when a tab was made through it, as Arc's per-window
    /// `itemLastActiveDates` and `itemCreatedDates`, which order its empty command bar.
    private(set) var lastActiveDates: [UUID: Date] = [:]
    private(set) var createdDates: [UUID: Date] = [:]
    /// As Arc's `WindowState.modalItemSwitcherPresentation`: the ⌃⇥ switcher while it is up.
    private(set) var modalItemSwitcher: ModalItemSwitcher?
    private(set) var toast: WindowToast?
    /// By page: the find bars this window has open.
    var findInPage: [UUID: FindInPage.State] = [:]
    /// Arc's `WindowState.findInPageQuery`: what was last put in this window's find field. In memory only, as seen in
    /// Arc, where a window back from a relaunch opened its find field empty.
    @ObservationIgnored var findInPageQuery: String?
    /// Arc's `WindowState.queuedHotkey`: the menu item a consumed shortcut asked about, while its toast is up.
    @ObservationIgnored private weak var queuedHotkey: NSMenuItem?
    @ObservationIgnored private var toastRemoval: Task<Void, Never>?
    @ObservationIgnored private var commandBarSelection: (spaceID: UUID, tabID: UUID?)?
    @ObservationIgnored var bringToFront: () -> Void = {}
    @ObservationIgnored weak var window: NSWindow?
    /// A restored window's wait for the engine's restored pages in its Space's profile, with the tab it showed.
    @ObservationIgnored private var awaitedRestoration: (profileID: UUID, tabID: UUID?)?
    /// Opens another window on this one's Space with the tab selected; the tab's page follows it there.
    @ObservationIgnored var openWindow: (_ tabID: UUID) -> Void = { _ in }
    /// The global window a Blank Window's tabs go to for a Space, opened when there is none.
    @ObservationIgnored var globalWindow: (_ spaceID: UUID) -> WindowModel? = { _ in nil }
    @ObservationIgnored var openLinkInIncognitoWindow: (_ url: URL, _ profileID: UUID) -> Void = { _, _ in }
    /// A link's new window from a window with a sidebar of its own, which holds none of another window's tabs.
    @ObservationIgnored var openURLInNewWindow: (_ url: URL) -> Void = { _ in }
    /// As Arc's `createOrFocusLittleBrowserWindow`, on the profile given or the last used one.
    /// A page the engine already made for the link goes there live.
    @ObservationIgnored var openLittleWindow:
        (_ entryPoint: LittleBrowserEntryPoint, _ profileID: UUID?, _ page: (page: any Page, url: URL)?) -> Void = {
            _, _, _ in
        }
    /// The Space a Little window of the profile would move its page to.
    @ObservationIgnored var littleDestination: (_ profileID: UUID) -> UUID? = { _ in nil }
    @ObservationIgnored let downloads: DownloadsStore
    @ObservationIgnored private let pictureInPicture: PictureInPicture
    @ObservationIgnored private var presentedPage: (any Page)?
    @ObservationIgnored private let engine: any BrowserApplication
    @ObservationIgnored private let store: SidebarStore
    /// Arc's `previouslySelectedItem`, which its `recentTabDidExpire` clears five minutes after it was last set.
    @ObservationIgnored private var previousTabID: UUID? {
        didSet {
            guard previousTabID != oldValue else { return }
            previousExpiry?.cancel()
            guard previousTabID != nil else { return }
            previousExpiry = Task { [weak self] in
                try? await Task.sleep(for: .seconds(300))
                if !Task.isCancelled { self?.previousTabID = nil }
            }
        }
    }
    @ObservationIgnored private var previousExpiry: Task<Void, Never>?
    /// Arc's `deselectedItemIDs`: pinned tabs closed and Favorites deselected here, until selected again.
    @ObservationIgnored private var deselectedTabIDs: Set<UUID> = []
    /// Arc's `referrerPool`: the tabs of the opener group being worked through here.
    @ObservationIgnored private var openerPool: Set<UUID> = []
    @ObservationIgnored private var focusedPaneIDs: [UUID: UUID] = [:]
    @ObservationIgnored private var selectionCount = 0
    /// Arc's `interactionState.proposedWindowContentDropTarget`, while a tab is dragged over the page.
    var proposedSplitViewDropTarget: SplitViewDropTarget?
    /// As Arc's empty pane, which isn't stored: where Add Split View's command bar puts what it opens.
    private(set) var emptySplitViewPaneIndex: Int?
    /// As Arc's `addPanel(…, orientation:)`: the toolbar's Add Top and Add Bottom Split stack a lone page with it.
    private var emptySplitViewPaneOrientation: SidebarSplitViewData.LayoutOrientation = .horizontal
    /// Arc's `SplitViewLayoutCache` entry for the window, as seen: its own pane sizes for the split it shows, given
    /// by a resize here; another window, and this one once it has shown something else, start from the stored ones.
    private var splitViewLayout: WindowSplitViewLayout?
    @ObservationIgnored private var pendingURLs: [UUID: URL] = [:]
    @ObservationIgnored private var creating: [UUID: UUID] = [:]
    /// By profile: ArcCore keeps one omnibox per window.
    @ObservationIgnored private var autocompletes: [UUID: any Autocomplete] = [:]
    @ObservationIgnored private var browserListeners: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var littleDownloads: (downloads: any Downloads, listener: Task<Void, Never>)?
    /// As Arc's `ClosedSidebarItemsCache`: what the user closed from this window, a group for each close with a step
    /// for each tab, the last ten, in memory and gone with the window.
    @ObservationIgnored private var closedGroups: [ClosedGroup] = []
    @ObservationIgnored var undoManager: ArcUndoManager?
    private var archivePeekID: UUID?

    var state: SidebarState { store.state }
    var developerMode: DeveloperModeClient { store.developerMode }

    var developerModeURL: URL? {
        guard !isLittle, peek == nil, placeholder == nil, let url = page?.url, let host = url.host(), !host.isEmpty
        else {
            return nil
        }
        return url
    }
    /// The Spaces the window pages through: the global sidebar's, or the one of its own container.
    var spaces: [SidebarSpace] {
        guard let container = style.container(of: id) else { return state.spaces }
        return state.containers[container].map { [$0] } ?? []
    }
    var adBlocker: AdBlocker { engine.adBlocker }
    var space: SidebarSpace? { state.space(selectedSpaceID) }
    var selectedTabID: UUID? { spaceCreation == nil ? selectedTabIDs[selectedSpaceID] : nil }
    var selectedTab: SidebarTab? { selectedTabID.flatMap { state.tree.tab($0) } }
    /// As Arc's `SplitViewState.windowContentIDs`, its focused one the selected tab: the selected tab's split in
    /// pane order, or the tab alone.
    var presentedTabIDs: [UUID] { selectedTabID.map(state.presentedTabIDs(with:)) ?? [] }
    var page: (any Page)? { selectedTabID.flatMap { pages[$0] } }
    var placeholder: NSImage? { selectedTabID.flatMap(placeholder(for:)) }
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
        selectedTabID.flatMap { profile(containing: $0)?.id } ?? shownProfileID
    }
    /// As Arc's `focusedProfile`: a Little window's own profile, whatever its hidden Space's is, else the shown
    /// Space's.
    var shownProfileID: UUID? { little?.profile ?? space?.profileID }

    /// As Arc reads a Little window's pages: all of the window's own profile, also one a profile switch left
    /// running in the profile before.
    private func profile(containing tabID: UUID) -> SidebarProfile? {
        little.flatMap { state.profile($0.profile) } ?? state.profile(containing: tabID)
    }
    var browser: (any Browser)? { profileID.flatMap { browsers[$0] } }
    func profileName(_ id: UUID) -> String { engine.userVisibleName(of: id) ?? "" }
    /// The engine's profiles in its order, read when asked, as Arc's menus list them.
    var profiles: [ProfileState] { engine.allProfiles().map { ProfileState(id: $0, name: profileName($0)) } }
    var extensions: [BrowserExtension] { profileID.map { engine.browserContext(id: $0).extensions.items } ?? [] }
    var extensionActions: [ExtensionAction] { browser?.extensionActions ?? [] }
    var pinnedExtensionActions: [ExtensionAction] { pinnedExtensionActions(for: profileID) }

    func pinnedExtensionActions(for profileID: UUID?) -> [ExtensionAction] {
        guard let profileID, let actions = browsers[profileID]?.extensionActions else { return [] }
        return actions.filter { $0.pinnedPosition != nil }.sorted { $0.pinnedPosition! < $1.pinnedPosition! }
    }
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
    /// As Arc's `selectableItemInfo`, whose root for a split's tab is the split: a split counts once, as the pane
    /// this window focuses in it.
    var selectableTabs: [SidebarTab] {
        let entries =
            state.favoriteEntries(for: selectedSpaceID)
            + visiblePinnedRows(in: selectedSpaceID).map(\.entry)
            + state.entries(in: selectedSpaceID, pinned: false)
        return entries.compactMap { entry in
            switch entry {
            case .folder: nil
            case .tab(let tab): tab
            case .splitView(let id, _): focusedTabID(of: id).flatMap(state.tree.tab)
            }
        }
    }
    var canRestoreLastClosed: Bool { closedGroups.contains { !$0.steps.isEmpty } }
    /// As Arc's sweep reads a Little window: every page was last active before `date`, and none plays or records.
    func isLittleIdle(since date: Date) -> Bool {
        let tabs = state.tabs(in: selectedSpaceID)
        guard isLittle, !tabs.isEmpty else { return false }
        return tabs.allSatisfy { tab in
            guard let active = lastActiveDates[tab.id], active < date else { return false }
            guard let page = pages[tab.id] else { return true }
            return !page.isAudible && !page.isCameraOn && !page.isMicrophoneOn
        }
    }

    var record: WindowRecord {
        WindowRecord(
            id: id, style: style, selectedSpaceID: selectedSpaceID, sidebarMode: sidebarMode,
            sidebarWidth: sidebarWidth, lastActiveDates: lastActiveDates, createdDates: createdDates,
            collapsedPinnedSpaces: collapsedPinnedSpaces, expandedItems: expandedFolderIDs,
            selectedTabID: selectedTabIDs[selectedSpaceID])
    }

    init(
        id: UUID, style: WindowStyle, engine: any BrowserApplication, store: SidebarStore,
        downloads: DownloadsStore, pictureInPicture: PictureInPicture, spaceID: UUID
    ) {
        self.id = id
        self.style = style
        self.engine = engine
        self.store = store
        self.downloads = downloads
        self.pictureInPicture = pictureInPicture
        selectedSpaceID = spaceID
        sidebarMode = store.sidebarViewPreferences.sidebarMode
        sidebarWidth = store.sidebarViewPreferences.sidebarWidth
        loadExtensions()
    }

    /// As Arc: a restored window comes back on its Space with nothing selected and no page, and doesn't build its
    /// contents itself: they come with the engine's restored pages. Its dates come back too, as Oa's own: Arc saves
    /// them with the window, and what its restore does with them is unknown.
    func restore(_ record: WindowRecord) {
        if state.space(record.selectedSpaceID) != nil { selectedSpaceID = record.selectedSpaceID }
        sidebarMode = record.sidebarMode
        sidebarWidth = record.sidebarWidth
        lastActiveDates = record.lastActiveDates
        createdDates = record.createdDates
        collapsedPinnedSpaces = record.collapsedPinnedSpaces
        expandedFolderIDs = record.expandedItems.filter { state.tree.folder($0) != nil }
        guard let profileID = space?.profileID else { return openCommandBar(.newTab) }
        awaitedRestoration = (profileID, record.selectedTabID)
    }

    /// A pinned tab whose page has left its address reads "/ live title", as in Arc; a Favorite, whose tile has no
    /// text, gives the window the live title as Arc's does. Oa's own: the live title is the last one a finished load
    /// gave, and the address's host until one has.
    func title(for tab: SidebarTab) -> String {
        guard let url = leftAddress(tab), let page = pages[tab.id] else { return tab.displayTitle }
        let settled = settledLiveTitles[tab.id] ?? settledTitle(of: page)
        let live = tab.customTitle ?? settled ?? url.host() ?? url.absoluteString
        // As seen in Arc: a split's pane shows no "/".
        return state.isFavorite(tab.id) || state.splitViewID(containing: tab.id) != nil ? live : "/ " + live
    }

    func leftAddress(_ tab: SidebarTab) -> URL? { leftAddress(tab, page: pages[tab.id]) }

    func liveLeftAddress(_ tab: SidebarTab) -> URL? { leftAddress(tab, page: livePage(for: tab.id)) }

    private func leftAddress(_ tab: SidebarTab, page: (any Page)?) -> URL? {
        guard state.keepsAddress(tab.id), let url = page?.url, !tab.isAt(url) else { return nil }
        return url
    }

    /// The live page's favicon, wherever the page lives, else the saved one, as Arc shows it.
    func favicon(for tab: SidebarTab) -> NSImage? {
        livePage(for: tab.id)?.favicon ?? store.savedFavicon(tab.id)
    }

    /// Where the tab's page is now, wherever it lives, else its saved address.
    func liveURL(of tabID: UUID) -> URL? {
        livePage(for: tabID)?.url ?? state.tree.tab(tabID)?.url
    }

    func liveTitle(of tabID: UUID) -> String {
        livePage(for: tabID)?.title ?? state.tree.tab(tabID)?.title ?? ""
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
        guard let tabID = selectedTabID, let url = page?.url, let profile = profile(containing: tabID),
            var components = URLComponents(string: "chrome://settings/content/siteDetails")
        else { return }
        components.queryItems = [URLQueryItem(name: "site", value: url.absoluteString)]
        guard let settings = components.url else { return }
        let context = context(for: profile.id)
        Task { [weak self, id] in
            guard let page = await context.makePage(windowID: id, restoring: nil)?.page, let self else { return }
            guard pages[tabID] != nil else { return page.drop() }
            peek(page, from: tabID)
            page.load(settings)
        }
    }

    func siteSetting(_ type: SiteSettingType, ofPage pageID: UUID) -> SiteSettingValue? {
        guard let tabID = tabID(of: pageID), let url = pages[tabID]?.url,
            let profile = profile(containing: tabID)
        else { return nil }
        return context(for: profile.id).changedSiteSettings(for: url)?.first { $0.type == type }?.value
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
        selectedTabID.flatMap { profile(containing: $0) }.map { context(for: $0.id) }
    }

    /// As ADK's `browserContextID(for:)`: an incognito window's pages are its profile's incognito context's.
    private func context(for profileID: UUID) -> any BrowserContext {
        engine.browserContext(id: profileID, type: sidebarContext == .incognito ? .incognito : .normal)
    }

    /// Read as a Space is shown, so the engine has reported its profile's by the time the Extensions menu opens.
    private func loadExtensions() {
        if let profileID = shownProfileID { _ = engine.browserContext(id: profileID).extensions.items }
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

    /// As Arc's `ensureBrowsersCreated`, as the window appears: its browser in every profile it has a Space of.
    func ensureBrowsersCreated() {
        // As Arc's `ensureBrowsersCreated`: a Little window adds its one profile.
        for profileID in little.map({ [$0.profile] }) ?? Array(Set(spaces.map(\.profileID))) {
            ensureBrowser(for: profileID)
        }
        subscribeToLittleDownloads()
    }

    /// As Arc's `setupSubscriptions`: a Little window hears of every download of its profile from then on,
    /// whichever window starts it, and of none of an incognito context. As seen in Arc, a profile switch doesn't
    /// move it: the tray goes on with the profile the window was made in.
    private func subscribeToLittleDownloads() {
        guard littleDownloads == nil, let profileID = little?.profile else { return }
        let downloads = engine.browserContext(id: profileID, type: .normal).downloads
        let events = downloads.events
        littleDownloads = (
            downloads,
            Task { [weak self] in
                for await event in events { self?.receiveLittleDownload(event) }
            }
        )
    }

    func cancelLittleDownload(_ id: Download.ID) {
        littleDownloads?.downloads.cancel(id)
    }

    private func ensureBrowser(for profileID: UUID) {
        guard browsers[profileID] == nil else { return }
        let browser = context(for: profileID).browser(windowID: id, type: isLittle ? .popup : .normal)
        browsers[profileID] = browser
        browserListeners[profileID] = Task { [weak self] in
            for await event in browser.events {
                guard let self else { continue }
                switch event {
                case .opened(let page, let isActive): place(page, isActive: isActive, in: profileID)
                case .restoredPages(let pages): receive(pages, in: profileID)
                }
            }
        }
    }

    /// As Arc's `restoreTab`: each restored page takes the sidebar item that had its tab in the last session, and one
    /// with no item, or whose item has a page, goes. Oa's own: the tab the window showed then comes back shown; with
    /// no page for it the window is as Arc's with its switch off.
    private func receive(_ restored: [RestoredPage], in profileID: UUID) {
        for entry in restored {
            guard
                let owner = store.sessionRestoration.owner(
                    ofTab: entry.lastSessionID, contextID: profileID, windowID: id),
                state.tree.tab(owner.itemId) != nil,
                !store.windows.contains(where: { $0.pages[owner.itemId] != nil || $0.creating[owner.itemId] != nil })
            else {
                entry.page.drop()
                continue
            }
            install(entry.page, for: owner.itemId)
            listen(to: entry.page)
        }
        guard let awaited = awaitedRestoration, awaited.profileID == profileID else { return }
        awaitedRestoration = nil
        guard selectedTabID == nil, commandBar == nil else { return }
        if let tabID = awaited.tabID, pages[tabID] != nil { select(tabID) } else { openCommandBar(.newTab) }
    }

    /// A page the engine made itself, as an extension's `chrome.tabs.create`. Oa's own: at the top of the shown Space
    /// when it is the profile's, else of the profile's first; where Arc puts one is unknown.
    private func place(_ page: any Page, isActive: Bool, in profileID: UUID) {
        let shown = isLittle || space?.profileID == profileID ? selectedSpaceID : nil
        guard let spaceID = shown ?? spaces.first(where: { $0.profileID == profileID })?.id else {
            return page.drop()
        }
        let tab = makeTab(url: page.url)
        store.edit { $0.insertTab(tab, atTopOf: spaceID) }
        createdDates[tab.id] = .now
        install(page, for: tab.id)
        listen(to: page)
        if isActive { show(tab.id) }
    }

    /// As Arc: at the top of the Space's unpinned tabs.
    func newTab(_ url: URL) {
        let tab = makeTab(url: url)
        store.edit { $0.insertTab(tab, atTopOf: selectedSpaceID) }
        createdDates[tab.id] = .now
        select(tab.id)
    }

    /// As Arc's reuse of a Little window: it was opened on this very address, shows a page of its host, and that
    /// page can't go back, by its history or to the page that opened it.
    func reusesLittleWindow(for url: URL) -> Bool {
        guard let page, let tab = selectedTab, little?.session.entryPoint.url == url, page.url?.host() == url.host(),
            !page.canGoBack
        else { return false }
        return tab.openerID.flatMap { state.tree.tab($0) } == nil
    }

    /// The page the engine made for a ⌘⌥-click, moved here live.
    func adoptLittlePage(_ page: any Page, url: URL) {
        let tab = makeTab(url: url)
        store.edit { $0.insertTab(tab, atTopOf: selectedSpaceID) }
        createdDates[tab.id] = .now
        page.move(toWindow: id)
        install(page, for: tab.id)
        listen(to: page)
        select(tab.id)
    }

    /// As Arc's, on a match: a new page in front, opened from the one shown.
    func openLittleLink(_ url: URL) {
        let tab = makeTab(url: url, opener: selectedTabID)
        store.edit { $0.insertTab(tab, atTopOf: selectedSpaceID) }
        createdDates[tab.id] = .now
        select(tab.id)
    }

    /// As seen in Arc: a new tab every time, even where one is at that URL.
    func openRoutedLink(_ url: URL, in spaceID: UUID) {
        exitLibrary()
        if spaceID != selectedSpaceID { selectSpace(spaceID) }
        newTab(url)
    }

    /// As Arc's ⌥⌘U: a new tab at the top of the Space, not the engine's view source, which opens after the page.
    func viewSource() {
        if let url = frontPage?.url, let source = URL(string: "view-source:" + url.absoluteString) { newTab(source) }
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
        let profileID = editing ? selectedTabID.flatMap { profile(containing: $0)?.id } : shownProfileID
        guard let profileID else { return }
        commandBar?.autocomplete.stop()
        let context = context(for: profileID)
        let bar = CommandBar(
            destination: editing ? .currentTab : .newTab, autocomplete: autocomplete(for: context),
            currentURL: editing ? frontPage?.url ?? address : nil, context: context, picks: store.commandBarPicks,
            usesPicks: sidebarContext != .incognito, commands: CommandBarActions.snapshot(for: self)
        ) { [weak self] in self?.commandBarTabs ?? [] }
        bar.perform = { [weak self, destination = bar.destination] in self?.perform($0, in: destination) }
        commandBar = bar
        commandBarSelection = (selectedSpaceID, selectedTabID)
    }

    private func autocomplete(for context: any BrowserContext) -> any Autocomplete {
        if let cached = autocompletes[context.id] { return cached }
        let autocomplete = context.makeAutocomplete()
        autocompletes[context.id] = autocomplete
        return autocomplete
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

    func trackPaneToolbarPage(_ tabID: UUID, shown: Bool) {
        store.topBarColors.setTrackedPage(shown ? pages[tabID] : nil, for: ToolbarOwner.pane(id, tabID))
    }

    private enum ToolbarOwner: Hashable {
        case window(UUID)
        case peek(UUID)
        case pane(UUID, UUID)
    }

    /// As seen in Arc: a Little window that is its bar alone goes with it.
    func closeCommandBar() {
        endCommandBar()
        if little?.isPresented == false { window?.close() }
    }

    private func endCommandBar() {
        guard let bar = commandBar else { return }
        bar.autocomplete.stop()
        commandBar = nil
        emptySplitViewPaneIndex = nil
        emptySplitViewPaneOrientation = .horizontal
        if dialog == nil { frontPage?.activate() }
    }

    private func updateCommandBarForSelection() {
        guard let bar = commandBar, let opened = commandBarSelection,
            opened.spaceID != selectedSpaceID || opened.tabID != selectedTabID
        else { return }
        // As seen in Arc: the open bar follows a swipe between Spaces with no selected tab.
        guard opened.tabID == nil, selectedTabID == nil, let profileID = shownProfileID else {
            return closeCommandBar()
        }
        commandBarSelection = (selectedSpaceID, nil)
        let context = context(for: profileID)
        bar.changeSpace(
            to: context, autocomplete: autocomplete(for: context), commands: CommandBarActions.snapshot(for: self))
    }

    /// As Arc's command bar: the profile's Favorites and the tabs of all its Spaces but the selected tab, each with
    /// an address.
    var commandBarTabs: [CommandBarRanking.Tab] {
        // As seen in Arc: a Little window's bar offers no tab.
        guard let space, !isLittle else { return [] }
        // As seen in Arc: a Blank Window offers only its own tabs.
        let others = spaces.filter { $0.profileID == space.profileID && $0.id != space.id }
        let tabs: [(SidebarTab, String?)] =
            state.selectableTabs(in: space.id).map { ($0, nil) }
            + others.flatMap { other in state.tabs(in: other.id).map { ($0, other.name) } }
        return tabs.compactMap { tab, spaceName in
            if let splitID = state.splitViewID(containing: tab.id), focusedTabID(of: splitID) != tab.id { return nil }
            guard !presentedTabIDs.contains(tab.id), let url = livePage(for: tab.id)?.url ?? tab.url else {
                return nil
            }
            // As seen in Arc: a split is one row, Switch to Split View. Its title here is its focused pane's, Oa's own.
            var row = CommandBarRanking.Tab(
                tab: tab, url: url, spaceName: spaceName, activeAt: lastActiveDates[tab.id] ?? createdDates[tab.id],
                isVisible: store.windows.contains { $0.presentedTabIDs.contains(tab.id) },
                saveLevel: state.keepsAddress(tab.id) ? folderDepth(of: tab.id) : nil)
            row.isSplitView = state.splitViewID(containing: tab.id) != nil
            return row
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
        let paneIndex = emptySplitViewPaneIndex
        let orientation = emptySplitViewPaneOrientation
        endCommandBar()
        switch action {
        case .switchTo(let tabID):
            // As seen in Arc: Switch to Tab from the empty pane moves that tab into it. Oa's own: a split's row
            // switches to it, where Arc's rule from the empty pane wasn't made out.
            guard let anchorID = selectedTabID, paneIndex != nil,
                state.canOpenInSplitView(tabID, beside: anchorID, in: selectedSpaceID)
            else { return show(tabID) }
            editSplitView(taking: [anchorID, tabID]) {
                $0.openInSplitView(
                    tabID, beside: anchorID, in: self.selectedSpaceID, at: paneIndex, orientation: orientation)
            }
            select(tabID)
        case .open(let url, background: false) where paneIndex != nil, .openInSplitView(let url):
            // Oa's own where the tab can't take a pane, as a full split: a new tab.
            guard !isLittle, let anchorID = selectedTabID,
                state.canAddSplitViewPane(beside: anchorID, in: selectedSpaceID)
            else { return newTab(url) }
            let tab = makeTab(url: url)
            let spaceID = selectedSpaceID
            editSplitView(taking: [anchorID]) {
                $0.insertTab(tab, atTopOf: spaceID)
                $0.openInSplitView(tab.id, beside: anchorID, in: spaceID, at: paneIndex, orientation: orientation)
            }
            createdDates[tab.id] = .now
            select(tab.id)
        case .open(let url, background: true) where !isLittle:
            let tab = makeTab(url: url)
            store.edit { $0.insertTab(tab, atTopOf: selectedSpaceID) }
            createdDates[tab.id] = .now
            ensurePage(tab.id)
        case .runCommand(let command):
            execute(command)
        case .open(let url, _):
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

    var allLivePages: [any Page] { store.windows.flatMap { $0.pages.values } }

    private func execute(_ command: CommandAction) {
        let dismissBarWindow = little?.isPresented == false
        switch command.kind {
        case .menuItem(let id):
            if let item = CommandBarActions.menuItem(withTypeTravelID: id), let action = item.action {
                NSApp.sendAction(action, to: item.target, from: item)
            }
        case .openPreferencePane(let pane):
            (NSApp.delegate as? ApplicationDelegate)?.showSettingsPane(pane)
        case .openChromiumSettings(let page):
            (NSApp.delegate as? ApplicationDelegate)?.openChromiumSettings(
                page, in: shownProfileID ?? SidebarProfile.defaultID)
        case .openAirTrafficControl:
            (NSApp.delegate as? ApplicationDelegate)?.showSettingsPane(.links, showAirTrafficControl: true)
        case .focusSpace(let spaceID):
            selectSpace(spaceID)
        case .moveToSpace(let spaceID):
            if let tabID = selectedTabID { moveItems([tabID], toSpace: spaceID) }
        case .browserExtension(let extID):
            runExtension(extID)
        case .addExtension:
            addExtension()
        case .manageExtensions:
            manageExtensions()
        case .renameCurrentTab:
            guard let tabID = selectedTabID, let tab = state.tree.tab(tabID), let window else { break }
            DialogSheet.present(on: window) { [weak self] dismiss in
                TextInputDialog(
                    title: "Rename Tab…", text: tab.displayTitle, placeholder: "Keep it short and sweet!",
                    confirmTitle: "Rename"
                ) { title in
                    self?.renameTab(tabID, to: title)
                    dismiss()
                } onCancel: {
                    dismiss()
                }
            }
        case .duplicateCurrentTab:
            if let tabID = selectedTabID { duplicate(tabID) }
        case .resetCurrentTab:
            if let tabID = selectedTabID, let url = state.tree.tab(tabID)?.url { livePage(for: tabID)?.load(url) }
        case .moveToFavorites, .removeFromFavorites:
            toggleFavorite()
        case .muteAllTabs:
            setAllTabsMuted(true)
        case .unmuteAllTabs:
            setAllTabsMuted(false)
        case .convertToHorizontalSplitView, .convertToVerticalSplitView:
            if let tabID = selectedTabID, let splitID = state.splitViewID(containing: tabID) {
                flipSplitViewLayoutOrientation(splitID)
            }
        case .undoAction:
            window?.undoManager?.undo()
        case .redoAction:
            window?.undoManager?.redo()
        }
        if dismissBarWindow { window?.close() }
    }

    private func setAllTabsMuted(_ muted: Bool) {
        var changed: [UUID] = []
        for model in store.windows {
            for (tabID, page) in model.pages where muted ? (page.isAudible && !page.isMuted) : page.isMuted {
                page.isMuted = muted
                changed.append(tabID)
            }
        }
        guard !changed.isEmpty else { return }
        let status: SidebarTab.MuteStatus = muted ? .mute : .allowAudio
        store.edit { state in for tabID in changed { state.setMuteStatus(tabID, to: status) } }
    }

    func select(_ tabID: UUID, restoring sessionID: PageSessionID? = nil, keepingMultiSelection: Bool = false) {
        guard state.isSelectable(tabID, in: selectedSpaceID) else { return }
        // As Arc's `selectItem(params:)`: any selection ends the multi-selection, even of a row already in it.
        if !keepingMultiSelection { multiSelection = SidebarMultiSelection() }
        // Oa's own, as for a Space: a tab chosen with the Create a Space panel open closes it. Arc keeps the panel
        // under the ⌘T bar; what it does once a tab is chosen wasn't seen.
        cancelSpaceCreation()
        guard selectedTabID != tabID else { return }
        library = nil
        let presented = state.presentedTabIDs(with: tabID)
        noteSelection(of: tabID, after: selectedTabID)
        if let current = selectedTabID, !presented.contains(current) {
            scheduleDepartingPeek(leaving: current, goingTo: tabID, in: selectedSpaceID)
            splitViewLayout = nil
            for leaving in presentedTabIDs {
                placeholders[leaving] = nil
                handOff(leaving)
            }
        }
        selectedTabIDs[selectedSpaceID] = tabID
        for shown in presented {
            markViewed(shown)
            ensurePage(shown, restoring: shown == tabID ? sessionID : nil)
        }
    }

    /// As Arc's `reparentPeekingIfNecessary(for:requiresDelay:)`: leaving a tab inside a collapsed folder keeps it
    /// peeked for 100 ms before the collapsed folder closes over it.
    private func scheduleDepartingPeek(leaving oldTabID: UUID, goingTo newTabID: UUID, in spaceID: UUID) {
        let collapsedOld = Set(state.folderAncestors(of: oldTabID).filter { !expandedFolderIDs.contains($0) })
        guard !collapsedOld.isEmpty else { return }
        let collapsedNew = Set(state.folderAncestors(of: newTabID).filter { !expandedFolderIDs.contains($0) })
        guard !collapsedOld.subtracting(collapsedNew).isEmpty else { return }
        var held = Set(state.presentedTabIDs(with: oldTabID))
        if let splitID = state.splitViewID(containing: oldTabID) { held.insert(splitID) }
        departingPeekTargets[spaceID, default: []].formUnion(held)
        departingPeekTasks[spaceID]?.cancel()
        departingPeekTasks[spaceID] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self?.departingPeekTargets[spaceID] = nil
            self?.departingPeekTasks[spaceID] = nil
        }
    }

    /// As Arc's `selectItem(params:)`, whatever made the selection: the item shown before becomes the previous one,
    /// or none when nothing was; the new one is no longer deselected; the opener pool lets go of the group when the
    /// selection leaves it, and narrows to a pinned tab or Favorite of it.
    private func noteSelection(of tabID: UUID, after current: UUID?) {
        let presented = state.presentedTabIDs(with: tabID)
        deselectedTabIDs.subtract(presented)
        if !openerPool.contains(tabID) {
            openerPool = []
        } else if state.isPinned(tabID) || state.isFavorite(tabID) {
            openerPool = [tabID]
        }
        if current.map({ !presented.contains($0) }) ?? true { previousTabID = current }
    }

    /// As Arc's `createTab`: the opener's group gains the tab, a tab with no opener starts one with the tab shown,
    /// and a Peek's page starts one with the Peek's owner.
    private func makeTab(url: URL?, title: String = "", opener openerID: UUID? = nil, peekOwner: UUID? = nil)
        -> SidebarTab
    {
        let before = peekOwner ?? openerID ?? selectedTabID
        let tab = SidebarTab(
            id: UUID(), title: title, url: url, viewedAt: .now, openerID: openerID, activeTabBeforeCreationID: before)
        if let peekOwner {
            openerPool = [peekOwner, tab.id]
        } else if let openerID {
            openerPool.formUnion([openerID, tab.id])
        } else {
            openerPool = Set([before, tab.id].compactMap { $0 })
        }
        return tab
    }

    /// As Arc's selection after a close, an ordinary one: recorded and stamped.
    /// Arc's close clears a closed item as the previous one; a deselected item stays it.
    private func show(_ next: UUID?, after previous: UUID?, in spaceID: UUID) {
        selectedTabIDs[spaceID] = next
        guard spaceID == selectedSpaceID else { return }
        if let next {
            noteSelection(of: next, after: previous)
            state.presentedTabIDs(with: next).forEach(markViewed)
        }
        ensurePresentedPages()
    }

    /// Visible rows in the shown Space that are multi-selected (tabs and folders), in display order; none until there
    /// are two.
    var multiSelectedItemIDs: [UUID] {
        guard multiSelection != SidebarMultiSelection() else { return [] }
        let visible =
            visiblePinnedRows(in: selectedSpaceID).map(\.id) + state.unpinnedRows(in: selectedSpaceID).map(\.id)
        let ids = visible.filter {
            state.splitView($0) == nil && state.splitViewID(containing: $0) == nil
                && ($0 == selectedTabID || multiSelection.contains($0))
        }
        return ids.count > 1 ? ids : []
    }

    /// Arc's multi-selection as tab-only actions (Copy Links, ⌘W) take it: the selected tab rows in row order; none
    /// until there are two. Oa's own: a split and its panes don't join.
    var multiSelectedTabIDs: [UUID] {
        let ids = multiSelectedItemIDs.filter { state.tree.tab($0) != nil }
        return ids.count > 1 ? ids : []
    }

    func clearMultiSelection() {
        multiSelection = SidebarMultiSelection()
    }

    private func isMultiSelectable(_ itemID: UUID) -> Bool {
        guard state.space(containingItem: itemID)?.id == selectedSpaceID else { return false }
        if state.tree.folder(itemID) != nil { return true }
        return state.tree.tab(itemID) != nil && state.splitViewID(containing: itemID) == nil
    }

    /// As seen in Arc's ⌘-click: a row joins the selection or leaves it, and the page stays. The selected tab leaves
    /// for another member, which is shown; alone, it stays. Oa's own: the first member in row order is shown.
    func toggleMultiSelection(_ itemID: UUID) {
        guard isMultiSelectable(itemID) else { return }
        guard itemID == selectedTabID else { return multiSelection.toggle(itemID) }
        guard let next = multiSelectedTabIDs.first(where: { $0 != itemID }) else { return }
        multiSelection.remove(itemID)
        multiSelection.remove(next)
        select(next, keepingMultiSelection: true)
    }

    /// As seen in Arc's ⇧-click: the visible rows from the anchor to this one in its section, in place of the last
    /// range. Oa's own: a range across the pinned and Today lists does nothing, as Arc's first click across does.
    func extendMultiSelection(to itemID: UUID) {
        let anchor = multiSelection.anchorID.flatMap { isMultiSelectable($0) ? $0 : nil } ?? selectedTabID
        guard let anchor, isMultiSelectable(anchor), isMultiSelectable(itemID),
            state.isPinnedItem(anchor) == state.isPinnedItem(itemID)
        else { return }
        let pinned = state.isPinnedItem(anchor)
        let rows =
            (pinned ? visiblePinnedRows(in: selectedSpaceID) : state.unpinnedRows(in: selectedSpaceID))
            .map(\.id).filter(isMultiSelectable)
        guard let from = rows.firstIndex(of: anchor), let to = rows.firstIndex(of: itemID) else { return }
        multiSelection.select(range: Array(rows[min(from, to)...max(from, to)]))
    }

    /// As seen in Arc: ⌘W or Archive Tabs takes every tab at once, pins too, in one step, and ⇧⌘T brings the selected
    /// tab back first, then the rest from the bottom.
    func archiveTabs(_ tabIDs: [UUID]) {
        multiSelection = SidebarMultiSelection()
        let selected = selectedTabID.flatMap { tabIDs.contains($0) ? $0 : nil }
        closeTogether(
            tabIDs.filter { $0 != selected } + (selected.map { [$0] } ?? []),
            undoPrompt: tabIDs.count == 1 ? UndoStrings.archiveTab : UndoStrings.archiveTabs, completionToast: nil)
    }

    /// As seen in Arc: a window comes back to the pane it focused in a split, and to the last pane of a split it
    /// hasn't shown. Arc's stored `focusItemID` isn't kept up to date and isn't read here.
    func focusedTabID(of splitID: UUID) -> UUID? {
        let tabIDs = state.tree[splitID]?.childIDs ?? []
        return focusedPaneIDs[splitID].flatMap { tabIDs.contains($0) ? $0 : nil } ?? tabIDs.last
    }

    func placeholder(for tabID: UUID) -> NSImage? { pages[tabID] == nil ? placeholders[tabID] : nil }

    func activatePresented(_ page: any Page) {
        if page.id == self.page?.id, peek == nil, commandBar == nil, dialog == nil, extensionRequest == nil {
            page.activate()
        }
    }

    private func ensurePresentedPages() {
        for tabID in presentedTabIDs { ensurePage(tabID) }
    }

    func canOpenInSplitView(_ tabID: UUID) -> Bool {
        selectedTabID.map { state.canOpenInSplitView(tabID, beside: $0, in: selectedSpaceID) } ?? false
    }

    /// As Arc's Open in Split View: the tab joins the selected one on its right and takes the focus.
    func openInSplitView(_ tabID: UUID) {
        guard let anchorID = selectedTabID, canOpenInSplitView(tabID) else { return }
        editSplitView(taking: [anchorID, tabID]) {
            $0.openInSplitView(tabID, beside: anchorID, in: self.selectedSpaceID)
        }
        select(tabID)
    }

    func canOpenInSplitView(_ tabIDs: [UUID]) -> Bool {
        guard let anchorID = tabIDs.first, tabIDs.count <= SidebarSplitViewData.maxNumberSplit else { return false }
        return tabIDs.dropFirst().allSatisfy { state.canJoinSplitView($0, of: anchorID, in: selectedSpaceID) }
    }

    /// As seen in Arc: several tabs make one split in row order where the first was, the last one focused.
    func openInSplitView(_ tabIDs: [UUID]) {
        guard let anchorID = tabIDs.first, let last = tabIDs.last, canOpenInSplitView(tabIDs) else { return }
        let spaceID = selectedSpaceID
        editSplitView(taking: tabIDs) { state in
            for tabID in tabIDs.dropFirst() { state.openInSplitView(tabID, beside: anchorID, in: spaceID) }
        }
        select(last)
    }

    /// A row's tab, or the first of a split's.
    private func combineAnchor(_ rowID: UUID) -> UUID? {
        state.splitView(rowID) != nil ? state.tree[rowID]?.childIDs.first : rowID
    }

    /// As seen in Arc: a full split still lights up under a held tab, and the drop does nothing.
    func canCombineIntoSplitView(_ tabID: UUID, onto rowID: UUID) -> Bool {
        combineAnchor(rowID).map { state.canJoinSplitView(tabID, of: $0, in: selectedSpaceID) } ?? false
    }

    /// As seen in Arc: a tab dropped on a row's middle makes a split with that row's tab where it is, a pinned one's
    /// in the pinned section, or joins the row's split, before the row's tabs from its left half and after them from
    /// its right half; it takes the focus. Both tabs move as they are, with no copy left behind.
    func combineIntoSplitView(_ tabID: UUID, onto rowID: UUID, last: Bool) {
        guard let anchorID = combineAnchor(rowID),
            state.canOpenInSplitView(tabID, beside: anchorID, in: selectedSpaceID)
        else { return }
        let spaceID = selectedSpaceID
        store.edit { $0.openInSplitView(tabID, beside: anchorID, in: spaceID, at: last ? nil : 0) }
        select(tabID)
    }

    func combinedTabIDs(_ tabIDs: [UUID], onto rowID: UUID) -> [UUID] {
        guard !tabIDs.contains(rowID), let anchorID = combineAnchor(rowID) else { return [] }
        let panes = state.splitViewID(containing: anchorID).map { state.tree[$0]?.childIDs.count ?? 0 } ?? 1
        return Array(
            tabIDs.filter { state.canJoinSplitView($0, of: anchorID, in: selectedSpaceID) }
                .prefix(max(SidebarSplitViewData.maxNumberSplit - panes, 0)))
    }

    /// As seen in Arc: dragged rows dropped on a row's middle make one split with it, and the leftmost pane is shown.
    /// The rows go on the side of the row's half they are held on, LIKELY as a single tab's: Arc's were only seen
    /// from the left half, before the row. Oa's own: the rows in the sidebar's order, where Arc reverses them, and those past four panes
    /// stay rows, where Arc leaves out one it picks.
    func combineIntoSplitView(_ tabIDs: [UUID], onto rowID: UUID, last: Bool) {
        let tabIDs = combinedTabIDs(tabIDs, onto: rowID)
        guard let anchorID = combineAnchor(rowID), let first = tabIDs.first else { return }
        let spaceID = selectedSpaceID
        store.edit { state in
            for (index, tabID) in tabIDs.enumerated() {
                state.openInSplitView(tabID, beside: anchorID, in: spaceID, at: last ? nil : index)
            }
        }
        select(first)
    }

    /// As seen in Arc: a link dropped in the list is a tab at the line, its page loaded in the background.
    func openDroppedLink(_ url: URL, into parentID: UUID, at index: Int?) {
        guard let spaceID = state.space(containingItem: parentID)?.id else { return }
        let tab = makeTab(url: url)
        store.edit {
            $0.appendTab(tab, in: spaceID)
            $0.moveItem(tab.id, into: parentID, at: index)
        }
        createdDates[tab.id] = .now
        ensurePage(tab.id)
    }

    func canDropLink(inSplitView splitID: UUID) -> Bool {
        guard state.splitView(splitID) != nil, let anchorID = state.tree[splitID]?.childIDs.first else { return false }
        return state.canAddSplitViewPane(beside: anchorID, in: selectedSpaceID)
    }

    /// As seen in Arc: a link dropped on a split's cell is its first pane, loaded in the background, and the split
    /// isn't selected. From the cell's right half it is the last, LIKELY as a dropped tab.
    func openDroppedLink(_ url: URL, inSplitView splitID: UUID, last: Bool) {
        guard canDropLink(inSplitView: splitID), let anchorID = state.tree[splitID]?.childIDs.first else { return }
        let tab = makeTab(url: url)
        let spaceID = selectedSpaceID
        store.edit {
            $0.appendTab(tab, in: spaceID)
            $0.openInSplitView(tab.id, beside: anchorID, in: spaceID, at: last ? nil : 0)
        }
        createdDates[tab.id] = .now
        ensurePage(tab.id)
    }

    /// As seen in Arc: a lone pinned tab or Favorite among `tabIDs` goes into the split as its own item and page, and
    /// a copy keeps its place, its page loaded at once at the address the page was at.
    private func editSplitView(taking tabIDs: [UUID], _ change: (inout SidebarState) -> Void) {
        let spaceID = selectedSpaceID
        var copies: [(original: UUID, copy: UUID)] = []
        store.edit { state in
            for tabID in tabIDs {
                if let copy = state.takeIntoSplitView(tabID, in: spaceID) { copies.append((tabID, copy)) }
            }
            change(&state)
        }
        for (original, copy) in copies {
            createdDates[copy] = .now
            if let url = livePage(for: original)?.url { pendingURLs[copy] = url }
            ensurePage(copy)
        }
    }

    func setSplitViewIcon(_ splitID: UUID, to icon: String?) {
        store.edit { $0.updateSplitView(splitID) { $0.icon = icon } }
    }

    func resetSplitViewNameAndIcon(_ splitID: UUID) {
        store.edit { $0.resetSplitViewNameAndIcon(splitID) }
    }

    /// As seen in Arc: the copy isn't selected, and its pages load at once in the background.
    func duplicateSplitView(_ splitID: UUID) {
        var tabIDs: [UUID] = []
        store.edit { tabIDs = $0.duplicateSplitView(splitID) }
        for tabID in tabIDs {
            createdDates[tabID] = .now
            ensurePage(tabID)
        }
    }

    /// As seen in Arc: Move to ▸ takes a tab or a split whole to the top of that Space's list, a pinned one staying
    /// pinned. A shown one takes the window to that Space with it; one that isn't leaves the window where it is and its
    /// page running. A Space of another profile asks first, and as a page can't change profile, the item's pages close
    /// and load again in that profile, at once when the window follows and once selected otherwise, with nothing of
    /// the old profile's.
    func moveItem(_ itemID: UUID, toSpace spaceID: UUID) {
        moveItems([itemID], toSpace: spaceID)
    }

    /// As seen in Arc: several items land at the top of the list in their order, and without the shown tab among
    /// them the window stays and says where they went.
    ///
    /// From a Blank Window, as Arc's `moveItemsToGlobalDestination`: the items keep their IDs and live pages and go
    /// into the window `globalWindow` picks, which comes forward. It shows the Space and the tab only when the tab
    /// was the one shown here. As seen in Arc, no toast, and this window stays, empty or not, unless `closingWindow`
    /// (Arc's `hasCloseWindowIntent`, the header's Move to…). As Arc's `beginMoveItems`, a Space of another profile
    /// asks first, and as seen in Arc on that window, which comes forward for it; a sheet there is Oa's own.
    func moveItems(_ itemIDs: [UUID], toSpace spaceID: UUID, closingWindow: Bool = false) {
        let standalone = sidebarContext == .standalone || isLittle
        let itemIDs = itemIDs.filter { canMoveItem($0, toSpace: spaceID) }
        guard !itemIDs.isEmpty, let space = state.space(spaceID), !standalone || state.isGlobal(spaceID) else { return }
        let tabIDs = itemIDs.flatMap { state.splitView($0) != nil ? state.tree[$0]?.childIDs ?? [] : [$0] }
        let focused = presentedTabIDs.contains(where: tabIDs.contains) ? selectedTabID : nil
        let crossesProfile = profile(containing: tabIDs[0])?.id != space.profileID
        let sourceSpaceID = selectedSpaceID
        guard let destination = standalone ? globalWindow(spaceID) : self else { return }
        let move = { [weak self, weak destination] in
            guard let self, let destination else { return }
            let itemIDs = itemIDs.filter { canMoveItem($0, toSpace: spaceID) }
            guard !itemIDs.isEmpty else { return }
            multiSelection = SidebarMultiSelection()
            // As seen in Arc: a page a profile switch left in the Little window's old profile doesn't outlive the
            // window in a Space of its new one.
            let lost = tabIDs.filter {
                isLittle && !crossesProfile && pages[$0]?.profileID ?? space.profileID != space.profileID
            }
            // As seen in Arc: Open in closes the DevTools window of the page it moves.
            if isLittle {
                for case let devTools? in tabIDs.map({ pages[$0]?.devTools }) where devTools.display == .undocked {
                    devTools.setOpen(false)
                }
            }
            if crossesProfile {
                for window in store.windows { window.dropPages(of: tabIDs) }
            } else if standalone {
                for tabID in tabIDs { destination.takePage(of: tabID, from: self) }
            }
            store.edit { state in for itemID in itemIDs.reversed() { state.move(itemID, toSpace: spaceID) } }
            if let focused {
                selectedTabIDs[sourceSpaceID] = nil
                destination.selectSpace(spaceID)
                destination.select(focused)
            } else if !standalone, itemIDs.count > 1, let first = tabIDs.first {
                present(.itemsMoved(first), at: .window)
            }
            guard standalone else { return }
            destination.bringToFront()
            if closingWindow { Task { [weak window] in window?.close() } }
            if isLittle { littlePageMoved(losing: lost, in: destination) }
        }
        if crossesProfile {
            if standalone { destination.bringToFront() }
            ProfileDialogUtils.confirmMove(tabCount: tabIDs.count, to: space.name, in: destination, proceed: move)
        } else {
            move()
        }
    }

    func moveAllItemsToGlobalWindow(toSpace spaceID: UUID) {
        moveItems(state.entries(in: selectedSpaceID, pinned: false).map(\.id), toSpace: spaceID, closingWindow: true)
    }

    /// As seen in Arc: a Favorite moved to another profile keeps its ID, last in that profile's grid. Its page closes
    /// and loads again there from its saved address, at once when shown, the window following, else once selected.
    /// Oa's own: the sheet names the profile, and the window follows to the profile's first Space.
    func moveFavorite(_ tabID: UUID, toProfile profileID: UUID) {
        guard state.isFavorite(tabID), profile(containing: tabID)?.id != profileID,
            let spaceID = state.spaces.first(where: { $0.profileID == profileID })?.id
        else { return }
        let shown = presentedTabIDs.contains(tabID)
        ProfileDialogUtils.confirmMove(tabCount: 1, to: profileName(profileID), in: self) { [weak self] in
            guard let self, state.isFavorite(tabID) else { return }
            for window in store.windows { window.dropPages(of: [tabID]) }
            store.edit { $0.moveFavorite(tabID, toProfile: profileID) }
            for (otherSpaceID, selected) in selectedTabIDs where selected == tabID {
                selectedTabIDs[otherSpaceID] = nil
            }
            guard shown else { return }
            selectSpace(spaceID)
            select(tabID)
        }
    }

    func canMoveItem(_ itemID: UUID, toSpace spaceID: UUID) -> Bool {
        let tabID = state.splitView(itemID) != nil ? state.tree[itemID]?.childIDs.first : itemID
        guard let tabID, state.tree.tab(tabID) != nil, state.space(spaceID) != nil
        else { return false }
        return state.space(containing: tabID)?.id != spaceID
    }

    /// As seen in Arc: the tab is selected, alone, right after the split it left.
    func separateFromSplitView(_ tabID: UUID) {
        store.edit { $0.removeFromSplitView([tabID]) }
        select(tabID)
    }

    /// As seen in Arc: the focused tab stays selected.
    func separateAllSplitViewChildren(_ splitID: UUID) {
        store.edit { $0.separateAllSplitViewChildren(splitID) }
    }

    var splitViewPanes: [SplitViewPane] {
        var panes = presentedTabIDs.map(SplitViewPane.tab)
        if let index = emptySplitViewPaneIndex { panes.insert(.empty, at: min(index, panes.count)) }
        if case .insertContent(let index) = proposedSplitViewDropTarget?.target {
            panes.insert(.dropTarget, at: min(index, panes.count))
        }
        return panes
    }

    /// The shown split's, or the one a drop on a lone page proposes.
    var splitViewLayoutOrientation: SidebarSplitViewData.LayoutOrientation {
        selectedTabID.flatMap(state.splitViewID(containing:)).flatMap(state.splitView)?.layoutOrientation
            ?? proposedSplitViewDropTarget?.layoutOrientation ?? emptySplitViewPaneOrientation
    }

    /// Arc's `handleSidebarItemDroppedOnSplitView`, as seen: at an edge the tab becomes a pane there, in a split made
    /// with the lone page in the edge's orientation; on a pane of a split it replaces that pane's tab; on a lone
    /// page it is only selected. The tab takes the focus.
    func acceptSplitViewDrop(of tabID: UUID) {
        guard let proposed = proposedSplitViewDropTarget, let anchorID = selectedTabID else { return }
        proposedSplitViewDropTarget = nil
        let presented = presentedTabIDs
        let spaceID = selectedSpaceID
        switch proposed.target {
        case .insertContent(let index):
            editSplitView(taking: [anchorID, tabID]) {
                $0.openInSplitView(tabID, beside: anchorID, in: spaceID, at: index)
                if presented.count == 1, let splitID = $0.splitViewID(containing: tabID) {
                    $0.updateSplitView(splitID) { $0.layoutOrientation = proposed.layoutOrientation }
                }
            }
        case .replaceContent(let index):
            if presented.count > 1 {
                editSplitView(taking: [tabID]) { $0.replaceSplitViewPane(presented[index], with: tabID, in: spaceID) }
            }
        }
        select(tabID)
    }

    var canAddSplitViewPane: Bool {
        emptySplitViewPaneIndex == nil && !isLittle
            && selectedTabID.map { state.canAddSplitViewPane(beside: $0, in: selectedSpaceID) } ?? false
    }

    /// Arc's `addPanel`: an empty pane, the last one unless a pane's menu placed it, and the command bar to fill it.
    func addSplitViewPane(
        at index: Int? = nil, orientation: SidebarSplitViewData.LayoutOrientation = .horizontal
    ) {
        guard canAddSplitViewPane else { return }
        emptySplitViewPaneIndex = index ?? presentedTabIDs.count
        emptySplitViewPaneOrientation = orientation
        openCommandBar(.newTab)
    }

    /// Arc's `switchToSplitViewPane(at:)`.
    func switchToSplitViewPane(at index: Int) {
        let tabIDs = presentedTabIDs
        if tabIDs.count > 1, tabIDs.indices.contains(index) { select(tabIDs[index]) }
    }

    /// Arc's `switchToAdjacentSplitViewPane(offset:)`, with wraparound.
    func switchToAdjacentSplitViewPane(offset: Int) {
        let tabIDs = presentedTabIDs
        guard tabIDs.count > 1, let index = selectedTabID.flatMap(tabIDs.firstIndex(of:)) else { return }
        select(tabIDs[(index + offset + tabIDs.count) % tabIDs.count])
    }

    func moveSplitViewPane(_ tabID: UUID, by offset: Int) {
        store.edit { $0.moveSplitViewPane(tabID, by: offset) }
    }

    /// As seen in Arc: every pane turns, and the factors stay.
    func flipSplitViewLayoutOrientation(_ splitID: UUID) {
        store.edit {
            $0.updateSplitView(splitID) {
                $0.layoutOrientation = $0.layoutOrientation == .horizontal ? .vertical : .horizontal
            }
        }
    }

    /// The window's own shares for the split it shows, else the stored ones.
    func paneShares(of splitID: UUID) -> [CGFloat] {
        var data = state.splitView(splitID) ?? SidebarSplitViewData()
        if let layout = splitViewLayout, layout.splitID == splitID { data.itemWidthFactors = layout.itemWidthFactors }
        return data.shares(of: state.tree[splitID]?.childIDs ?? [])
    }

    /// As Arc's `handleSplitViewPanesResized`: the window keeps the layout, and the split's factors take it once
    /// the resize ends.
    func resizeSplitViewPanes(_ splitID: UUID, to factors: [UUID: CGFloat], ended: Bool) {
        splitViewLayout = WindowSplitViewLayout(splitID: splitID, itemWidthFactors: factors)
        if ended { store.edit { $0.updateSplitView(splitID) { $0.itemWidthFactors = factors } } }
    }

    func selectSplitView(_ splitID: UUID) {
        if let tabID = focusedTabID(of: splitID) { select(tabID) }
    }

    /// As Arc's `selectItem`: a tab the window shows by a selection is stamped for the window and for itself.
    private func markViewed(_ tabID: UUID) {
        lastActiveDates[tabID] = .now
        store.markViewed(tabID)
    }

    /// Arc's pass each minute over what a window shows.
    func markShownViewed() {
        if !showingArchive { presentedTabIDs.forEach(markViewed) }
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
        // As Arc's filter, which keeps the items that are their own selectable root: a split is one card, here the
        // pane this window focuses in it.
        var cards = Set<UUID>()
        return tabIDs.filter { state.tree.tab($0) != nil && profile(containing: $0)?.id == shownProfileID }
            .compactMap { tabID in
                let card = state.splitViewID(containing: tabID).flatMap(focusedTabID(of:)) ?? tabID
                return cards.insert(card).inserted ? card : nil
            }
    }

    /// As Arc's `onHighlightAdjacentRecentTab`: the command bar closes and the switcher comes up over the recent
    /// tabs, or not at all with none. The shown page and its Peek's are asked for a fresh thumbnail, the others have
    /// their last.
    func highlightAdjacentRecentTab(_ target: ModalItemSwitcher.Target) {
        closeCommandBar()
        guard modalItemSwitcher == nil,
            let switcher = ModalItemSwitcher(itemIDs: recentTabIDs, currentID: selectedTabID, target: target)
        else { return }
        presentedTabIDs.forEach { pages[$0]?.requestThumbnail() }
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

    /// As Arc's `onWebContentsDidConsumeShortcut`. A shortcut whose binding prompts shows its toast and waits, and
    /// the same one consumed again while the toast is up runs its menu item, which the page has had first both
    /// times. Another shortcut takes the toast and the wait, and a key with no modifier is nobody's shortcut here.
    private func webContentDidConsume(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, pageID: UUID) {
        guard page?.id == pageID || peek?.id == pageID,
            !modifierFlags.isDisjoint(with: ARCKeyboardShortcut.modifierMask),
            let shortcut = ARCKeyboardShortcut(keyCode: keyCode, modifiers: modifierFlags),
            let binding = keyBindings.state.shortcutToBinding[shortcut],
            binding.priority == .promptAfterConsumedByWebView,
            let item = NSApplication.shared.mainMenu?.firstItem(with: shortcut)
        else { return }
        item.menu?.update()
        guard item.isEnabled else { return }
        if queuedHotkey === item {
            queuedHotkey = nil
            if let action = item.action { NSApplication.shared.sendAction(action, to: item.target, from: item) }
            return
        }
        present(
            .webContentConsumedHotkey(binding.id, shortcut: shortcut, title: item.title), at: .windowContent(pageID))
        queuedHotkey = item
    }

    /// One toast at a time, for Arc's five seconds; a new one takes the place of the one that is up.
    func present(_ type: ToastType, at location: WindowToast.Location) {
        dismissToast()
        let toast = WindowToast(type: type, location: location)
        self.toast = toast
        toastRemoval = Task { [weak self] in
            try? await Task.sleep(for: .seconds(ToastConstants.toastVisibilityDuration), tolerance: .zero)
            if !Task.isCancelled, self?.toast?.id == toast.id { self?.dismissToast() }
        }
    }

    /// The wait ends with the toast, as Arc's does.
    private func dismissToast() {
        toastRemoval?.cancel()
        toast = nil
        queuedHotkey = nil
    }

    /// As Arc's "Edit the shortcut": the toast goes, and Settings opens on the binding.
    func editShortcut(of toast: WindowToast) {
        guard case .webContentConsumedHotkey(let identifier?, _, _) = toast.type else { return }
        dismissToast()
        store.showShortcut(identifier)
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

    /// As seen in Arc: wraps at either end, and never into the Library.
    func selectAdjacentSpace(_ offset: Int) {
        let spaces = spaces
        guard let index = spaces.firstIndex(where: { $0.id == selectedSpaceID }) else { return }
        selectSpace(at: (index + offset + spaces.count) % spaces.count)
    }

    /// Oa's own: out of the Library, as a swipe to the Space goes.
    func selectSpace(at index: Int) {
        guard spaces.indices.contains(index) else { return }
        exitLibrary()
        selectSpace(spaces[index].id)
    }

    /// As seen in Arc: switching to an empty Space doesn't open the command bar.
    func selectSpace(_ spaceID: UUID) {
        guard spaces.contains(where: { $0.id == spaceID }) else { return }
        cancelSpaceCreation()
        guard spaceID != selectedSpaceID else { return }
        // As seen in Arc: a Space switch ends the multi-selection.
        multiSelection = SidebarMultiSelection()
        let current = selectedTabID
        selectedSpaceID = spaceID
        if let shown = selectedTabID { noteSelection(of: shown, after: current) }
        ensurePresentedPages()
        presentedTabIDs.forEach(markViewed)
        store.windowStateChanged()
    }

    /// On becoming key, the selected tab takes its page back from the window that holds or is making it.
    func showSelected() {
        for tabID in presentedTabIDs
        where pages[tabID] == nil
            && store.windows.contains(where: { $0 !== self && ($0.pages[tabID] != nil || $0.creating[tabID] != nil) })
        {
            ensurePage(tabID)
        }
    }

    /// Arc's Create a Space panel, on the window's Space's profile, after `spaceID` or, as Arc's `.absolute(-1)`, at
    /// the end. As Arc, it leaves the Library and changes neither the Space nor the selection. As seen in Arc, the
    /// Library's + of a window with a sidebar of its own does nothing.
    func beginSpaceCreation(after spaceID: UUID? = nil, moving itemIDs: [UUID] = []) {
        guard spaceCreation == nil, sidebarContext == .global, let space else { return }
        closeCommandBar()
        library = nil
        spaceCreation = SpaceCreationState(insertAfter: spaceID, profileID: space.profileID, moving: itemIDs)
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
            created = $0.addSpace(
                name: name, profileID: profileID, icon: creation.icon, theme: creation.spaceStyleEditor.theme,
                after: creation.insertAfter)
        }
        if let created { moveItems(creation.moving, toSpace: created.id) }
        if selecting, let created { selectSpace(created.id) }
    }

    /// As Arc: a new window starts with the collapsed sections and expanded folders of the window it came from.
    func inheritCollapsedPinnedSpaces(from source: WindowModel) {
        collapsedPinnedSpaces = source.collapsedPinnedSpaces
        expandedFolderIDs = source.expandedFolderIDs
    }

    func togglePinnedSection(of spaceID: UUID) {
        if collapsedPinnedSpaces.remove(spaceID) == nil { collapsedPinnedSpaces.insert(spaceID) }
        store.windowStateChanged()
    }

    // MARK: - Folders

    func peekedTargets(in spaceID: UUID, includeDeparting: Bool = true) -> Set<UUID> {
        var targets = includeDeparting ? (departingPeekTargets[spaceID] ?? []) : []
        if let selected = selectedTabIDs[spaceID] {
            targets.formUnion(state.presentedTabIDs(with: selected))
            if let splitID = state.splitViewID(containing: selected) { targets.insert(splitID) }
        }
        return targets
    }

    func visiblePinnedRows(in spaceID: UUID, sectionCollapsed: Bool? = nil) -> [SidebarRow] {
        let collapsed = sectionCollapsed ?? collapsedPinnedSpaces.contains(spaceID)
        return state.visiblePinnedRows(
            in: spaceID, expanded: expandedFolderIDs,
            peekedTargets: peekedTargets(in: spaceID, includeDeparting: !collapsed),
            sectionCollapsed: collapsed)
    }

    func isFolderExpanded(_ id: UUID) -> Bool { expandedFolderIDs.contains(id) }

    func toggleFolderExpanded(_ id: UUID) {
        setFolderExpanded(id, !expandedFolderIDs.contains(id))
    }

    func setFolderExpanded(_ id: UUID, _ expanded: Bool) {
        let changed = expanded ? expandedFolderIDs.insert(id).inserted : expandedFolderIDs.remove(id) != nil
        if changed { store.windowStateChanged() }
    }

    /// As Arc's `WindowData.recursivelyExpandParents(for:)`: expands every enclosing folder (and uncollapses the
    /// Space's pinned section) so `id` is directly visible.
    func expandAncestors(of id: UUID) {
        guard state.isPinnedItem(id) else { return }
        let ancestors = state.folderAncestors(of: id)
        var changed = false
        for folderID in ancestors where expandedFolderIDs.insert(folderID).inserted { changed = true }
        if let spaceID = state.space(containingItem: id)?.id, collapsedPinnedSpaces.remove(spaceID) != nil {
            changed = true
        }
        if changed { store.windowStateChanged() }
    }

    @discardableResult
    func createFolder(in spaceID: UUID, title: String = "", startEditing: Bool = false) -> UUID? {
        guard state.isGlobal(spaceID), let pinnedRootID = state.space(spaceID)?.pinnedRootID else { return nil }
        if spaceID != selectedSpaceID { selectSpace(spaceID) }
        var created: SidebarFolder?
        store.edit { created = $0.createFolder(title: title, in: pinnedRootID) }
        return revealCreatedFolder(created, startEditing: startEditing)
    }

    @discardableResult
    func createNestedFolder(in parentID: UUID) -> UUID? {
        guard state.canCreateFolder(in: parentID), let spaceID = state.space(containingItem: parentID)?.id else {
            return nil
        }
        exitLibrary()
        if spaceID != selectedSpaceID { selectSpace(spaceID) }
        var created: SidebarFolder?
        store.edit { created = $0.createFolder(in: parentID) }
        return revealCreatedFolder(created, startEditing: true)
    }

    @discardableResult
    func createFolder(wrapping itemIDs: [UUID], title: String = "", startEditing: Bool = true) -> UUID? {
        guard sidebarContext == .global else { return nil }
        let spaceID = selectedSpaceID
        var created: SidebarFolder?
        store.edit { created = $0.createFolder(wrapping: itemIDs, in: spaceID, title: title) }
        return revealCreatedFolder(created, startEditing: startEditing)
    }

    private func revealCreatedFolder(_ folder: SidebarFolder?, startEditing: Bool) -> UUID? {
        guard let folder else { return nil }
        clearMultiSelection()
        expandAncestors(of: folder.id)
        setFolderExpanded(folder.id, true)
        if startEditing { editingFolderID = folder.id }
        return folder.id
    }

    func renameFolder(_ id: UUID, to title: String) {
        store.edit { $0.renameFolder(id, to: title) }
    }

    func setFolderIcon(_ id: UUID, to icon: String?) {
        store.edit { $0.setFolderIcon(id, to: icon) }
    }

    func moveItem(_ itemID: UUID, into parentID: UUID, at index: Int? = nil) {
        store.edit { $0.moveItem(itemID, into: parentID, at: index) }
    }

    func moveItems(_ itemIDs: [UUID], into parentID: UUID, after anchorID: UUID?) {
        store.edit { $0.moveItems(itemIDs, into: parentID, after: anchorID) }
    }

    /// As Arc: empty folders delete immediately; non-empty folders archive all descendant tabs in one undoable group
    /// and remove the folder once its tabs have closed.
    func deleteFolder(_ id: UUID) {
        guard let closed = state.closedFolder(id) else { return }
        multiSelection = SidebarMultiSelection()
        let tabIDs = state.tree.tabs(under: id).map(\.id)
        if tabIDs.isEmpty {
            store.edit { $0.removeFolder(id) }
            undoManager?.registerUndos([.restoreFolder(closed)], UndoStrings.deleteFolder)
            present(.undo("Folder deleted"), at: .window)
            return
        }
        closeTogether(tabIDs.reversed(), undoPrompt: UndoStrings.deleteFolder, completionToast: nil, folder: closed)
    }

    func moveSpace(_ spaceID: UUID, to index: Int) {
        guard let current = state.spaces.firstIndex(where: { $0.id == spaceID }), current != index else { return }
        store.edit { $0.moveSpace(spaceID, to: index) }
    }

    func renameSpace(_ spaceID: UUID, to name: String) {
        store.edit { $0.renameSpace(spaceID, to: name) }
    }

    func setSpaceIcon(_ icon: String?, for spaceID: UUID) {
        guard let space = state.space(spaceID), space.icon != icon else { return }
        store.edit { $0.setSpaceIcon(icon, for: spaceID) }
    }

    /// The theme the window draws a Space in: while its editor is open, the one the editor makes.
    func theme(of space: SidebarSpace) -> WindowTheme { customTheme(of: space) ?? .default }

    func customTheme(of space: SidebarSpace) -> WindowTheme? {
        guard let presentation = spaceStyleEditor, presentation.spaceID == space.id else {
            return space.customInfo?.windowTheme
        }
        return presentation.editor.theme
    }

    /// As Arc's `presentStyleEditor`: from the editor's state built from the Space's theme. Oa's own: the window
    /// shows the Space first, as it does for the icon picker.
    func presentSpaceStyleEditor(for spaceID: UUID, from origin: WindowSpaceStyleEditorPresentation.Origin) {
        guard let space = state.space(spaceID) else { return }
        dismissSpaceStyleEditor()
        if origin == .sidebar { selectSpace(spaceID) }
        spaceStyleEditor = WindowSpaceStyleEditorPresentation(
            spaceID: spaceID, origin: origin, editor: SpaceStyleEditor(theme: space.customInfo?.windowTheme))
    }

    /// A change in the open editor. What it returns is the state Arc files an "Update Theme" undo step for.
    func updateSpaceStyleEditor(_ change: (inout SpaceStyleEditor) -> SpaceStyleEditor.State?) {
        guard var presentation = spaceStyleEditor else { return }
        let old = change(&presentation.editor)
        spaceStyleEditor = presentation
        if let old { registerThemeUndo(SpaceStyleEditor(state: old).theme, for: presentation.spaceID) }
    }

    /// As Arc: the theme is written as the editor closes, however it closes, and there is no Cancel.
    func dismissSpaceStyleEditor() {
        guard let presentation = spaceStyleEditor else { return }
        spaceStyleEditor = nil
        setSpaceTheme(presentation.editor.theme, for: presentation.spaceID)
    }

    private func setSpaceTheme(_ theme: WindowTheme?, for spaceID: UUID) {
        guard state.space(spaceID) != nil else { return }
        store.edit { $0.setSpaceTheme(theme, for: spaceID) }
    }

    private func registerThemeUndo(_ theme: WindowTheme?, for spaceID: UUID) {
        undoManager?.registerUndos([.updateSpaceTheme(spaceID: spaceID, theme: theme)], UndoStrings.updateTheme)
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

    /// As Arc's `changeProfileInLittleBrowser`: the window's own profile changes, and its hidden Space's with it,
    /// as seen in Arc's file. The shown page is made again in the profile on its tab, and the others go on in the
    /// profile and Browser they have. A window opened on a link teaches the link's host its profile.
    func setLittleProfile(_ profileID: UUID) {
        guard let little, let space, little.profile != profileID, state.profile(profileID) != nil else { return }
        endCommandBar()
        self.little?.profile = profileID
        store.edit { $0.setProfile(profileID, forSpaces: [space.id]) }
        ensureBrowser(for: profileID)
        if let tabID = selectedTabID { dropPages(of: [tabID]) }
        loadExtensions()
        ensurePresentedPages()
        if let url = little.session.entryPoint.url { LittleBrowserPreferences.setPreferredProfile(profileID, for: url) }
    }

    /// As seen in Arc: the window closes at once, a page at a time into the Archive, with no stack and no toast.
    func archiveLittlePages() {
        guard isLittle else { return }
        for tab in state.tabs(in: selectedSpaceID) {
            end(tab.id, reason: .auto, closedBy: .auto) { page, _ in page.drop() }
        }
    }

    /// As seen in Arc: a Little window whose page moved out closes, its other pages into the Archive, and after
    /// them a moved page that is lost with it, from the Space it reached.
    private func littlePageMoved(losing lost: [UUID], in destination: WindowModel) {
        afterClose = { [weak destination] in destination?.endLittlePages(lost) }
        window?.close()
    }

    private func endLittlePages(_ tabIDs: [UUID]) {
        for tabID in tabIDs { end(tabID, reason: .manual, closedBy: nil) { page, _ in page.drop() } }
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

    /// A tile dropped on the tab list, Oa's own way to Arc's command-bar Unfavorite Tab.
    func unfavorite(_ tabID: UUID) {
        store.edit { $0.unfavoriteTab(tabID, in: selectedSpaceID) }
    }

    /// As seen in Arc: dragged rows all become Favorites from the slot. Oa's own: in the sidebar's order.
    func favorite(_ tabIDs: [UUID], at index: Int) {
        store.edit { state in
            for (offset, tabID) in tabIDs.enumerated() { state.favoriteTab(tabID, at: index + offset) }
        }
    }

    /// A drop on the grid: a row joins it at the index, a tile moves there.
    func favorite(_ tabID: UUID, at index: Int?) {
        store.edit { $0.favoriteTab(tabID, at: index) }
    }

    /// Remove Favorite: archived under no Space once its page has closed, and nothing selected in its place, as
    /// Arc does.
    func removeFavorite(_ tabID: UUID, group: ClosedGroup? = nil) {
        guard state.isFavorite(tabID) else { return }
        guard let page = store.windows.lazy.compactMap({ $0.pages[tabID] }).first else {
            for window in store.windows { window.placeholders[tabID] = nil }
            return archive(tabID, reason: .manual, closedBy: .window(id, group: group), sessionID: nil)
        }
        store.closing[page.id] = .window(id, group: group)
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
        library = section.flatMap { librarySections.contains($0) ? $0 : nil } ?? lastLibrarySection
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

    /// As seen in Arc: a matching route wins; else back to the Space it came from (1.19.1), else the shown one. The
    /// Default doesn't apply, and the tab isn't selected.
    func restoreArchived(_ id: UUID) {
        guard let entry = state.archive.first(where: { $0.id == id }) else { return }
        let origin = entry.spaceID.flatMap { state.isGlobal($0) || $0 == selectedSpaceID ? $0 : nil } ?? selectedSpaceID
        let spaceID = store.routedSpace(for: entry.url, recent: selectedSpaceID, unmatched: origin)
        store.edit { $0.restoreArchived(id, in: spaceID) }
        guard let space = state.space(containing: id) else { return }
        createdDates[id] = .now
        present(.tabUnarchived(id, location: space.name), at: .window)
    }

    func viewRestored(_ id: UUID) {
        guard let spaceID = state.space(containing: id)?.id else { return }
        dismissToast()
        exitLibrary()
        selectSpace(spaceID)
        select(id)
    }

    /// As Arc: no history, and the entry stays.
    func peekArchived(_ entryID: UUID) {
        guard let entry = state.archive.first(where: { $0.id == entryID }), let url = entry.url,
            let profileID = (entry.spaceID.flatMap { state.space($0) } ?? space)?.profileID
        else { return }
        closeArchivePeek()
        archivePeekID = entryID
        let context = context(for: profileID)
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
        guard ownerID != archivePeekID else { return expandArchivePeek(page, entryID: ownerID) }
        // As seen in Arc: Expand follows Air Traffic Control and moves the live page, with a new tab even where one is
        // at that URL. Across profiles Arc opens no Peek; a page that got there since loads afresh, Oa's own.
        let spaceID = store.routedSpace(for: page.url, recent: selectedSpaceID)
        guard state.space(spaceID)?.profileID == profile(containing: ownerID)?.id else {
            discardPeekPage(page)
            if let url = page.url { openRoutedLink(url, in: spaceID) }
            return
        }
        let besideOpener = spaceID == selectedSpaceID
        let tab = makeTab(url: page.url, title: page.title, opener: besideOpener ? ownerID : nil, peekOwner: ownerID)
        store.edit {
            if besideOpener { $0.openTab(tab, from: ownerID, in: spaceID) } else { $0.insertTab(tab, atTopOf: spaceID) }
        }
        createdDates[tab.id] = .now
        install(page, for: tab.id)
        if !besideOpener { selectSpace(spaceID) }
        select(tab.id)
    }

    /// As seen in Arc: into the shown Space, not through Air Traffic Control.
    private func expandArchivePeek(_ page: any Page, entryID: UUID) {
        archivePeekID = nil
        // Another window brought the entry back; selecting its tab is Oa's own, after Arc's ⇧⌘T.
        if let spaceID = state.space(containing: entryID)?.id {
            discardPeekPage(page)
            selectSpace(spaceID)
            return select(entryID)
        }
        let tab = SidebarTab(id: entryID, title: page.title, url: page.url, viewedAt: .now)
        store.edit {
            $0.removeArchived(entryID)
            $0.insertTab(tab, atTopOf: selectedSpaceID)
        }
        createdDates[tab.id] = .now
        install(page, for: tab.id)
        select(tab.id)
    }

    private func discardPeekPage(_ page: any Page) {
        dialogs[page.id] = nil
        permissionRequests[page.id] = nil
        extensionRequests[page.id] = nil
        page.drop()
    }

    var canAddPeekToSplitView: Bool {
        peek != nil && !showingArchive
            && selectedTabID.map { state.canAddSplitViewPane(beside: $0, in: selectedSpaceID) } ?? false
    }

    /// Arc's `addModalToSplit`: the Peek's page becomes a tab on the right of the one it was opened from, focused.
    func addPeekToSplitView() {
        guard canAddPeekToSplitView, let ownerID = peekOwnerID, let page = peeks.removeValue(forKey: ownerID) else {
            return
        }
        let tab = makeTab(url: page.url, title: page.title, opener: ownerID, peekOwner: ownerID)
        let spaceID = selectedSpaceID
        editSplitView(taking: [ownerID]) {
            $0.openTab(tab, from: ownerID, in: spaceID)
            let index = $0.presentedTabIDs(with: ownerID).firstIndex(of: ownerID).map { $0 + 1 }
            $0.openInSplitView(tab.id, beside: ownerID, in: spaceID, at: index)
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
        guard let index = closedGroups.lastIndex(where: { !$0.steps.isEmpty }) else { return }
        let closed = closedGroups[index].steps.removeLast()
        let group = closedGroups[index]
        // As Arc's `removeUndos` after the last step: ⌘Z has nothing left of this close to bring back.
        if group.steps.isEmpty {
            closedGroups.remove(at: index)
            undoManager?.removeUndos(group.id.uuidString)
        }
        reopen(closed, of: group, selecting: true)
    }

    /// One step back where it was. Selected, a tab comes with its history; unselected, it is a row without a page.
    private func reopen(_ closed: ClosedPage, of group: ClosedGroup, selecting: Bool) {
        guard case .tab(let parentID, let index) = closed.place else { return reopenPeek(closed) }
        var sessionID: PageSessionID?
        if state.tree.tab(closed.id) == nil {
            let present = state.tree[parentID]?.childIDs ?? []
            let index = group.index(of: closed.id, among: present) ?? index
            store.edit { $0.reopenTab(closed.reopenedTab, in: parentID, at: index, else: selectedSpaceID) }
            createdDates[closed.id] = .now
            sessionID = closed.sessionID
        }
        guard selecting else { return }
        if let spaceID = state.space(containing: closed.id)?.id { selectSpace(spaceID) }
        library = nil
        select(closed.id, restoring: sessionID)
    }

    /// As Arc replays what its undo manager sends back. An undone close returns whole, the tab the window was
    /// showing shown again; a group that ⇧⌘T emptied or that fell off the ten kept brings nothing, as Arc's.
    /// The redone close leaves nothing selected in its place, as Arc's does.
    func perform(_ action: UndoAction) {
        switch action {
        // As Arc: an undo with the editor open on the Space sets the theme and starts the editor over from it.
        case .updateSpaceTheme(let spaceID, let theme):
            guard let space = state.space(spaceID) else { return }
            let editing = spaceStyleEditor?.spaceID == spaceID
            registerThemeUndo(
                editing ? spaceStyleEditor?.editor.theme : space.customInfo?.windowTheme, for: spaceID)
            setSpaceTheme(theme, for: spaceID)
            if editing { spaceStyleEditor?.editor = SpaceStyleEditor(theme: theme) }
        case .restoreFolder(let closed):
            store.edit { $0.restoreFolder(closed, tabs: [], fallbackSpaceID: selectedSpaceID) }
            undoManager?.registerUndos([.deleteFolder(closed.id)], UndoStrings.deleteFolder)
        case .deleteFolder(let folderID):
            deleteFolder(folderID)
        case .undoCloseItems(let groupID):
            guard let index = closedGroups.firstIndex(where: { $0.id == groupID }) else { return }
            let group = closedGroups.remove(at: index)
            if let folder = group.folder, state.tree[folder.id] == nil {
                let steps = Dictionary(group.steps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                let tabs = group.steps.reversed().map(\.reopenedTab)
                store.edit { $0.restoreFolder(folder, tabs: tabs, fallbackSpaceID: selectedSpaceID) }
                for tab in tabs { createdDates[tab.id] = .now }
                expandedFolderIDs.insert(folder.id)
                if let focused = group.focusedTabID, let spaceID = state.space(containing: focused)?.id {
                    selectSpace(spaceID)
                    expandAncestors(of: focused)
                    select(focused, restoring: steps[focused]?.sessionID)
                }
                undoManager?.registerUndos([.deleteFolder(folder.id)], group.undoPrompt)
                return
            } else if let split = group.splitView, state.tree[split.id] == nil {
                // As seen in Arc: the split comes back whole, with its ID, where it was.
                let steps = Dictionary(group.steps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                let tabs = split.tabIDs.compactMap { steps[$0]?.reopenedTab }
                store.edit { $0.restoreSplitView(split, tabs: tabs) }
                for tab in tabs { createdDates[tab.id] = .now }
                if let focused = group.focusedTabID, state.tree.tab(focused) != nil {
                    select(focused, restoring: steps[focused]?.sessionID)
                }
            } else {
                for closed in group.steps.reversed() {
                    reopen(closed, of: group, selecting: closed.id == group.focusedTabID)
                }
            }
            if case .peek(let ownerID)? = group.steps.first?.place {
                undoManager?.registerUndos([.closePeek(ownerID: ownerID)], group.undoPrompt)
            } else {
                undoManager?.registerUndos(
                    [.closeItems(group.steps.map(\.id), undoPrompt: group.undoPrompt)], group.undoPrompt)
            }
        case .closeItems(let tabIDs, let undoPrompt):
            let tabIDs = tabIDs.filter { state.tree.tab($0) != nil }
            guard let first = tabIDs.first, let parentID = state.tree.location(of: first)?.parentID else { return }
            // Oa's own: on the stack before its pages have closed, so the step is filed while the redo runs and
            // the other redos stay. Arc files it when they have, and a redone close of a loaded tab leaves a
            // second step that does nothing.
            var group = ClosedGroup(
                undoPrompt: undoPrompt, order: tabIDs, siblings: state.tree[parentID]?.childIDs ?? [])
            // A split's close again closes it whole, so its undo brings it back again.
            if Set(state.tree[parentID]?.childIDs ?? []) == Set(tabIDs) { group.splitView = closedSplitView(parentID) }
            push(group)
            // A Favorite and a pinned tab are archived one at a time, by their own closes.
            if state.isFavorite(first) {
                removeFavorite(first, group: group)
            } else if state.isPinned(first) {
                archivePinned(first, group: group)
            } else {
                for tabID in tabIDs { close(tabID, group: group) }
            }
        case .closePeek(let ownerID):
            guard let page = peeks[ownerID] else { return }
            let group = ClosedGroup(undoPrompt: UndoStrings.closePeek)
            push(group)
            store.closing[page.id] = .window(id, group: group)
            page.close()
        }
    }

    /// As Arc: the Peek's tab is selected and the Peek returns over it with its history, its Archive entry gone.
    /// Nothing shows when the tab already has a Peek, or when the tab is gone, which also keeps the entry.
    private func reopenPeek(_ closed: ClosedPage) {
        guard case .peek(let ownerID) = closed.place, let profile = profile(containing: ownerID) else { return }
        store.edit { $0.removeArchived(closed.id) }
        guard !store.windows.contains(where: { $0.peeks[ownerID] != nil }) else { return }
        if let spaceID = state.space(containing: ownerID)?.id { selectSpace(spaceID) }
        library = nil
        select(ownerID)
        let context = context(for: profile.id)
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
    func archivePinned(_ tabID: UUID, group: ClosedGroup? = nil) {
        guard state.isPinned(tabID) else { return close(tabID, group: group) }
        store.archivingPins.insert(tabID)
        guard let page = store.windows.lazy.compactMap({ $0.pages[tabID] }).first else {
            return end(tabID, reason: .manual, closedBy: .window(id, group: group)) { page, _ in page.drop() }
        }
        store.closing[page.id] = .window(id, group: group)
        page.close()
    }

    var canClearTabs: Bool { !unpinnedTabs.isEmpty }

    /// As Arc's Clear: the Space's unpinned tabs but the selected one, which goes too when it is the last.
    /// ⇧⌘T brings the last selected back first, as Arc's did.
    /// A Library card's takes them all, as Arc's builds the card with no selection.
    func clearTabs(in spaceID: UUID? = nil, all: Bool = false) {
        let spaceID = spaceID ?? selectedSpaceID
        var tabIDs = state.tabs(in: spaceID, pinned: false).map(\.id)
        if !all, !clearsAllTabs(in: spaceID) { tabIDs.removeAll(where: presentedTabIDs.contains) }
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

    /// As Arc's `archiveItemsAbove`: the unpinned tabs above this one, which stays and is shown in place of the
    /// selected one when that goes.
    func archiveTabs(above tabID: UUID) {
        guard let space = state.space(containing: tabID) else { return }
        let tabIDs = state.tabs(in: space.id, pinned: false).map(\.id)
        guard let index = tabIDs.firstIndex(of: tabID) else { return }
        closeTogether(tabIDs[..<index].reversed(), selectingInstead: tabID)
    }

    /// As Arc's `archiveUnpinnedTabs(in:excluding:)`: the Space's unpinned tabs but these, as Clear does; pinned
    /// tabs and Favorites stay, and so does the multi-selection.
    func archiveOtherTabs(keeping tabIDs: [UUID]) {
        guard let first = tabIDs.first, let space = state.space(containing: first) else { return }
        let others = state.tabs(in: space.id, pinned: false).map(\.id).filter { !tabIDs.contains($0) }
        closeTogether(others.reversed(), selectingInstead: first)
    }

    func hasOtherTabs(than tabIDs: [UUID]) -> Bool {
        guard let first = tabIDs.first, let space = state.space(containing: first) else { return false }
        return state.tabs(in: space.id, pinned: false).contains { !tabIDs.contains($0.id) }
    }

    /// As seen in Arc: the copy isn't selected, and its page loads at once in the background, a clone of the tab's
    /// live page with its history.
    func duplicate(_ tabID: UUID) {
        multiSelection = SidebarMultiSelection()
        let page = livePage(for: tabID)
        let left = state.tree.tab(tabID).flatMap { leftAddress($0, page: page) }.map { ($0, page?.title ?? "") }
        let spaceID = selectedSpaceID
        var copyID: UUID?
        store.edit { copyID = $0.duplicateTab(tabID, in: spaceID, leftAddress: left) }
        guard let copyID else { return }
        createdDates[copyID] = .now
        guard let clone = page?.duplicate() else { return ensurePage(copyID) }
        clone.move(toWindow: id)
        install(clone, for: copyID)
        listen(to: clone)
    }

    /// As Arc's Replace Pinned URL with Current: the page's address, title and favicon become the tab's, with no
    /// reload.
    func replacePinnedURLWithCurrent(_ tabID: UUID) {
        guard let page = livePage(for: tabID), let url = page.url else { return }
        store.edit { $0.setPinnedURL(tabID, to: url, title: page.title) }
        if let favicon = page.favicon { store.setSavedFavicon(tabID, favicon) }
    }

    /// As Arc's Edit Pinned URL: the tab opens at the new address, its title waits for the page's, and a live page goes
    /// there at once.
    func editPinnedURL(_ tabID: UUID, to url: URL) {
        store.edit { $0.setPinnedURL(tabID, to: url, title: "") }
        livePage(for: tabID)?.load(url)
    }

    /// Whether the tab's page plays sound and is muted; nil while it has no page.
    func audio(of tabID: UUID) -> (isAudible: Bool, isMuted: Bool)? {
        livePage(for: tabID).map { ($0.isAudible, $0.isMuted) }
    }

    /// As Arc's `toggleMuted`: the live page's sound, and the tab's saved status for its next page.
    func toggleMuted(_ tabID: UUID) {
        guard let page = livePage(for: tabID) else { return }
        page.isMuted.toggle()
        let status: SidebarTab.MuteStatus = page.isMuted ? .mute : .allowAudio
        store.edit { $0.setMuteStatus(tabID, to: status) }
    }

    /// As Arc's `toggleMuted` for several: all muted when any page isn't, else all unmuted, each saved.
    func toggleMuted(_ tabIDs: [UUID]) {
        let pages = tabIDs.compactMap(livePage(for:))
        let muted = pages.isEmpty || pages.contains { !$0.isMuted }
        for page in pages { page.isMuted = muted }
        store.edit { state in for tabID in tabIDs { state.setMuteStatus(tabID, to: muted ? .mute : .allowAudio) } }
    }

    func setTabIcon(_ tabID: UUID, to icon: String?) {
        store.edit { $0.setTabIcon(tabID, to: icon) }
    }

    func renameTab(_ tabID: UUID, to title: String) {
        store.edit { $0.renameTab(tabID, to: title) }
    }

    func renameSplitView(_ splitID: UUID, to title: String) {
        store.edit { $0.renameSplitView(splitID, to: title) }
    }

    /// As seen in Arc: ⌘W on a Favorite split leaves nothing selected, its pages hidden, not unloaded.
    func deselectSplitView() {
        selectedTabIDs[selectedSpaceID] = nil
    }

    /// As seen in Arc: ⌘W and the "—" of a pinned split unload all its pages and leave nothing selected, and the
    /// split stays pinned.
    func closeSplitViewPages(_ splitID: UUID) {
        let tabIDs = state.tree[splitID]?.childIDs ?? []
        guard let first = tabIDs.first, let spaceID = state.space(containing: first)?.id else { return }
        if tabIDs.contains(where: { selectedTabIDs[spaceID] == $0 }) { selectedTabIDs[spaceID] = nil }
        for tabID in tabIDs where store.windows.contains(where: { $0.pages[tabID] != nil }) { close(tabID) }
    }

    /// As seen in Arc: a split's ✕ archives its tabs in one step, "Archive Tabs" to undo.
    func closeSplitView(_ splitID: UUID) {
        guard let closed = closedSplitView(splitID) else { return }
        closeTogether(closed.tabIDs.reversed(), splitView: closed)
    }

    private func closedSplitView(_ splitID: UUID) -> ClosedSplitView? {
        guard let data = state.splitView(splitID), let place = state.tree.location(of: splitID) else { return nil }
        return ClosedSplitView(
            id: splitID, data: data, parentID: place.parentID, index: place.index,
            tabIDs: state.tree[splitID]?.childIDs ?? [])
    }

    /// One close of several tabs from this window, one entry on its stack, the steps going back from the last.
    private func closeTogether(
        _ tabIDs: [UUID], undoPrompt: String? = nil, completionToast: CloseItemsCompletionToast? = .clearedTabs,
        splitView: ClosedSplitView? = nil, folder: ClosedFolder? = nil, selectingInstead keptID: UUID? = nil
    ) {
        guard !tabIDs.isEmpty else { return }
        let asSplitView = splitView != nil
        let closing = Set(tabIDs)
        var group = ClosedGroup(
            undoPrompt: undoPrompt ?? (asSplitView ? UndoStrings.archiveTabs : UndoStrings.clearTabs(tabIDs.count)),
            focusedTabID: selectedTabID.flatMap { closing.contains($0) ? $0 : nil },
            completionToast: asSplitView ? nil : completionToast, order: tabIDs,
            siblings: state.tabs(in: selectedSpaceID).map(\.id))
        group.splitView = splitView
        group.folder = folder
        // AppKit needs the inverse during redo, even when live pages report their closes later.
        if window?.undoManager?.isRedoing == true { push(group) }
        if let selected = selectedTabID, closing.contains(selected) {
            let next =
                keptID.flatMap { state.isSelectable($0, in: selectedSpaceID) ? $0 : nil }
                ?? nextSelection(closing: selected, deselecting: false, in: selectedSpaceID, alsoClosing: closing)
            show(next, after: nil, in: selectedSpaceID)
        }
        for tabID in tabIDs {
            if state.isPinned(tabID) { archivePinned(tabID, group: group) } else { close(tabID, group: group) }
        }
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

    /// As Arc's `tryToEjectWindowContentsForClosing`: a closing global window hands every page to another global
    /// window, preferring one that shows its tab. A window with a sidebar of its own neither gives nor takes: as seen
    /// in Arc, its pages end with it, a Peek's with no Archive entry.
    func dropAll() {
        let global = sidebarContext == .global
        let others = global ? store.windows.filter { $0 !== self && $0.sidebarContext == .global } : []
        for tabID in Array(pages.keys) {
            guard let page = release(tabID) else { continue }
            if let heir = others.first(where: { $0.shows(tabID) }) ?? others.first {
                heir.adopt(page, for: tabID, from: self)
            } else {
                page.drop()
            }
        }
        if global { archivePeeks() }
        peeks.values.forEach { $0.drop() }
        peeks = [:]
        dialogs = [:]
        permissionRequests = [:]
        extensionRequests = [:]
        closeExtensionPopup()
        browserListeners.values.forEach { $0.cancel() }
        browserListeners = [:]
        littleDownloads?.listener.cancel()
        browsers = [:]
        archivePeekID = nil
        creating = [:]
    }

    /// As Arc: closing the window or quitting archives each Peek's page.
    func archivePeeks() {
        for (ownerID, page) in peeks where ownerID != archivePeekID && state.tree.tab(ownerID) != nil {
            archivePeek(page, of: ownerID)
        }
    }

    /// As Arc's `beginCloseWindowContent`, which archives nothing of an incognito window: its Peek leaves no entry.
    /// `saving` is for a caller outside an edit and a reconcile, where the entry needs its own save.
    private func archivePeek(_ page: any Page, of ownerID: UUID, saving: Bool = false) {
        guard sidebarContext != .incognito else { return }
        let spaceID = spaceID(ofPeekOwner: ownerID)
        if saving {
            store.edit { $0.archivePage(id: page.id, title: page.title, url: page.url, in: spaceID) }
        } else {
            store.archivePage(page, in: spaceID)
        }
    }

    /// Lets go of the page for `tabID` without ending it. Another window takes it over this way.
    @discardableResult
    func release(_ tabID: UUID) -> (any Page)? {
        creating.removeValue(forKey: tabID)
        pendingURLs.removeValue(forKey: tabID)
        settledLiveTitles.removeValue(forKey: tabID)
        return pages.removeValue(forKey: tabID)
    }

    func releasePeek(_ tabID: UUID) -> (any Page)? {
        peeks.removeValue(forKey: tabID)
    }

    /// After a state edit: selections, placeholders and pages of tabs or Spaces that are gone go too.
    func reconcile() {
        if space == nil, let first = spaces.first { selectedSpaceID = first.id }
        for (spaceID, tabID) in selectedTabIDs where !state.isSelectable(tabID, in: spaceID) {
            selectedTabIDs.removeValue(forKey: spaceID)
        }
        for tabID in Array(pages.keys) where state.tree.tab(tabID) == nil { release(tabID)?.drop() }
        updateLinkRouting()
        for (ownerID, page) in peeks where ownerID != archivePeekID && state.tree.tab(ownerID) == nil {
            peeks[ownerID] = nil
            archivePeek(page, of: ownerID)
            page.close()
        }
        for tabID in Array(creating.keys) where state.tree.tab(tabID) == nil { release(tabID) }
        for tabID in Array(placeholders.keys) where state.tree.tab(tabID) == nil { placeholders[tabID] = nil }
        // Oa's own: Arc's last-active dates were never seen to be removed.
        for tabID in Array(lastActiveDates.keys) where state.tree.tab(tabID) == nil { lastActiveDates[tabID] = nil }
        for tabID in Array(createdDates.keys) where state.tree.tab(tabID) == nil { createdDates[tabID] = nil }
        if let previousTabID, state.tree.tab(previousTabID) == nil { self.previousTabID = nil }
        for splitID in Array(focusedPaneIDs.keys) where state.splitView(splitID) == nil {
            focusedPaneIDs[splitID] = nil
        }
        expandedFolderIDs = expandedFolderIDs.filter { state.tree.folder($0) != nil }
        if let editingFolderID, state.tree.folder(editingFolderID) == nil { self.editingFolderID = nil }
        // Arc's `restorableSplitViewLayout` is for the panes it was made with.
        if let layout = splitViewLayout,
            Set(layout.itemWidthFactors.keys) != Set(state.tree[layout.splitID]?.childIDs ?? [])
        {
            splitViewLayout = nil
        }
    }

    func updateLinkRouting() {
        for (tabID, page) in pages {
            let enabled = peeksFromLinks(in: tabID)
            if page.keepsAddress != enabled { page.keepsAddress = enabled }
        }
    }

    private func peeksFromLinks(in tabID: UUID) -> Bool {
        store.peekFromPinnedTabs && state.keepsAddress(tabID)
    }

    private func shows(_ tabID: UUID) -> Bool {
        presentedTabIDs.contains(tabID) && pages[tabID] == nil
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
        let deselecting = pinned && !store.archivingPins.contains(tabID)
        let next =
            wasSelected && request?.group == nil
            ? nextSelection(closing: tabID, deselecting: deselecting, in: spaceID) : nil
        let page = store.windows.compactMap { $0.release(tabID) }.first
        for window in store.windows {
            window.placeholders[tabID] = nil
            // As Arc's close: a pinned tab keeps when a window last showed it, not when one made it.
            window.createdDates[tabID] = nil
        }
        // As seen in Arc: a Blank Window's last tab goes unarchived, and the window closes with it; a Little window's
        // last page is archived as its others are, and the window closes too.
        let closesWindow =
            (sidebarContext == .standalone || isLittle)
            && state.tabs(in: spaceID).map(\.id) == [tabID]
        if closesWindow, sidebarContext == .standalone {
            store.edit { $0.removeTab(tabID) }
        } else if !pinned || store.archivingPins.remove(tabID) != nil {
            archive(tabID, reason: reason, closedBy: request, sessionID: sessionID)
        }
        if let page { finish(page, pinned) }
        if closesWindow { Task { [weak window] in window?.close() } }
        if deselecting { deselectedTabIDs.insert(tabID) }
        if wasSelected { show(next, after: deselecting ? tabID : nil, in: spaceID) }
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
                    sessionID: sessionID, tab: tab)
            }
        }
        let requester = store.windows.first { $0.id == request?.windowID }
        let focused = requester?.selectedTabID == tabID
        // As seen in Arc: an incognito tab closes without an Archive entry, and ⇧⌘T still brings it back.
        if sidebarContext == .incognito {
            store.edit { $0.removeTab(tabID) }
        } else {
            store.edit { $0.archiveTab(tabID, reason: reason) }
        }
        // As Arc's: a Little window has no stack of closed pages.
        if let closed, requester?.isLittle != true {
            requester?.remember(
                closed,
                in: request?.group
                    ?? ClosedGroup(undoPrompt: UndoStrings.archiveTab, focusedTabID: focused ? tabID : nil))
        }
        if let folder = request?.group?.folder, state.tree.folder(folder.id) != nil,
            state.tree.tabs(under: folder.id).isEmpty,
            Set(state.tree.descendants(of: folder.id).map(\.id)).isSubset(
                of: Set(folder.descendants.compactMap { $0.folder?.id }))
        {
            store.edit { $0.removeFolder(folder.id) }
            requester?.present(.undo("Folder deleted"), at: .window)
        }
    }

    private func remember(_ closed: ClosedPage, in group: ClosedGroup) {
        if let index = closedGroups.firstIndex(of: group) { return closedGroups[index].add(closed) }
        var group = group
        group.add(closed)
        push(group)
    }

    /// As Arc's close: the group goes on the window's ten and its undo step, under the group's ID, on the window's
    /// undo manager. A group that falls off the ten leaves its step behind, as Arc's does.
    private func push(_ group: ClosedGroup) {
        closedGroups.append(group)
        if closedGroups.count > 10 { closedGroups.removeFirst() }
        undoManager?.registerUndos([.undoCloseItems(groupID: group.id)], group.undoPrompt, group.id.uuidString)
        if group.completionToast == .clearedTabs { present(.undo("Cleared Tabs"), at: .window) }
    }

    /// A Favorite's page stays as it is, hidden, as Arc keeps it.
    private func deselect(_ tabID: UUID) {
        guard selectedTabID == tabID else { return }
        deselectedTabIDs.insert(tabID)
        show(nextSelection(closing: tabID, deselecting: true, in: selectedSpaceID), after: tabID, in: selectedSpaceID)
    }

    /// As Arc: the opener's group first; else the tab shown before, where a deselect stops; else a Today tab's row
    /// above, else below, never crossing into pinned; else the window's most recently active tab that still has its
    /// page here.
    private func nextSelection(
        closing tabID: UUID, deselecting: Bool, in spaceID: UUID, alsoClosing others: Set<UUID> = []
    ) -> UUID? {
        // As seen in Arc: closing a pane focuses the next one, or the one before the last.
        let panes = state.presentedTabIDs(with: tabID).filter { $0 == tabID || !others.contains($0) }
        if panes.count > 1, let index = panes.firstIndex(of: tabID) {
            return panes[index + 1 < panes.count ? index + 1 : index - 1]
        }
        // As Arc: a deselected item is passed over, and a deselect only looks back.
        let excluded = others.union(deselectedTabIDs)
        if !deselecting, let opened = openerSelection(closing: tabID, in: spaceID, excluding: excluded) {
            return opened
        }
        if let previousTabID, previousTabID != tabID, !excluded.contains(previousTabID),
            state.isSelectable(previousTabID, in: spaceID)
        {
            return previousTabID
        }
        guard !deselecting else { return nil }
        let staying = { (tab: SidebarTab) in tab.id != tabID && !excluded.contains(tab.id) }
        let today = state.tabs(in: spaceID, pinned: false)
        if let index = today.firstIndex(where: { $0.id == tabID }),
            let neighbour = today[..<index].last(where: staying) ?? today[(index + 1)...].first(where: staying)
        {
            return neighbour.id
        }
        let active = state.selectableTabs(in: spaceID).compactMap { tab in
            lastActiveDates[tab.id].flatMap { staying(tab) && pages[tab.id] != nil ? (tab.id, $0) : nil }
        }
        return active.max { $0.1 < $1.1 }?.0
    }

    /// As Arc's: a tab it opened right above or below it in Today; then, while the window's opener pool holds it, the
    /// next tab below from the same opener; then the tab shown when it was made, if still in the pool.
    private func openerSelection(closing tabID: UUID, in spaceID: UUID, excluding excluded: Set<UUID>) -> UUID? {
        guard let tab = state.tree.tab(tabID) else { return nil }
        let today = state.tabs(in: spaceID, pinned: false).filter { $0.id == tabID || !excluded.contains($0.id) }
        let index = today.firstIndex { $0.id == tabID }
        if let index {
            let neighbours = [index - 1, index + 1].filter(today.indices.contains).map { today[$0] }
            if let child = neighbours.first(where: { $0.openerID == tabID }) { return child.id }
        }
        if openerPool.contains(tabID), let index, let openerID = tab.openerID,
            let sibling = today[(index + 1)...].first(where: { $0.openerID == openerID && openerPool.contains($0.id) })
        {
            return sibling.id
        }
        guard let before = tab.activeTabBeforeCreationID, !excluded.contains(before), openerPool.contains(before),
            state.isSelectable(before, in: spaceID),
            state.isFavorite(before) || state.space(containing: before)?.id == selectedSpaceID
        else { return nil }
        return before
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
        guard let profile = profile(containing: tabID) else { return }
        let token = UUID()
        creating[tabID] = token
        let context = context(for: profile.id)
        ensureBrowser(for: profile.id)
        Task { [store, id] in
            let made = await context.makePage(windowID: id, restoring: sessionID)
            let owner = store.windows.first { $0.creating[tabID] == token }
            owner?.creating.removeValue(forKey: tabID)
            guard let page = made?.page else { return }
            guard let owner, let tab = store.state.tree.tab(tabID) else { return page.drop() }
            if owner.id != id { page.move(toWindow: owner.id) }
            if tab.muteStatus == .mute { page.isMuted = true }
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
        heir.takePage(of: tabID, from: self)
    }

    private func takePage(of tabID: UUID, from holder: WindowModel) {
        if holder.creating[tabID] != nil { return takeCreation(of: tabID, from: holder) }
        if let page = holder.release(tabID) { adopt(page, for: tabID, from: holder) }
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
        guard presentedTabIDs.contains(tabID) else { return }
        page.snapshot { [weak self] image in
            guard let self, shows(tabID) else { return }
            if let image { placeholders[tabID] = image } else { keepFrameLater(of: page, for: tabID) }
        }
    }

    private func keepFrameLater(of page: any Page, for tabID: UUID, attempts: Int = 2) {
        guard attempts > 0, placeholders[tabID] == nil, shows(tabID) else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, placeholders[tabID] == nil, shows(tabID) else { return }
            page.snapshot { [weak self] image in
                guard let self, shows(tabID) else { return }
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
        if let profile = profile(containing: tabID) { ensureBrowser(for: profile.id) }
        page.keepsAddress = peeksFromLinks(in: tabID)
        save(page, for: tabID)
        observe(page, for: tabID)
    }

    /// The stream has one consumer, so a page gets one loop for its life, delivering to whichever window holds it.
    private func listen(to page: any Page) {
        let store = store
        let pictureInPicture = pictureInPicture
        let pageID = page.id
        DevToolsWindowController.follow(page)
        Task {
            for await event in page.events {
                // The app's one window for it, whichever window holds the page, or none any more.
                if case .pictureInPicture(let event) = event {
                    pictureInPicture.handle(event, for: pageID)
                } else if case .webDialogClosed(let dialog) = event {
                    // The engine closes a page's dialog after the page, when no window holds it any more.
                    for window in store.windows where window.webDialog === dialog { window.webDialog = nil }
                } else if let window = store.windows.first(where: { $0.holds(pageID) }) {
                    window.handle(event, for: pageID)
                } else if case .dialog(let dialog) = event, case .beforeUnload = dialog.kind {
                    dialog.accept()
                }
            }
            DevToolsWindowController.pageClosed(pageID)
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
        // As Arc's quit recording: pages that unload on quit leave the sidebar as it is.
        if case .closed = event, store.quitting { return }
        if case .closed = event { findInPage[pageID] = nil }
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
        case .webDialog(let dialog):
            if webDialog == nil { webDialog = dialog }
            return
        case .consumedKey(let keyCode, let modifierFlags):
            return webContentDidConsume(keyCode: keyCode, modifierFlags: modifierFlags, pageID: pageID)
        case .findResult(let result):
            return found(result, on: pageID)
        case .thumbnail(let thumbnail):
            // As Arc's thumbnail listener: every thumbnail is kept as its page's snapshot, then goes to the toolbar's
            // colours, which sample a shown page's. An incognito page's too: as seen in Arc's defaults, its host's hash
            // and colour are cached like any other's.
            let page = page(id: pageID)
            if let page { store.contentSnapshots.storeSnapshot(thumbnail, of: page) }
            return store.topBarColors.process(thumbnail: thumbnail, ofPage: pageID, at: page?.url)
        case .closeCancelled:
            return closeCancelled(pageID)
        case .wantsActivation:
            return showPage(pageID)
        case .openLinkInIncognitoWindow(let url):
            if let ownerID = tabID(of: pageID) ?? peekOwner(of: pageID), let profile = profile(containing: ownerID) {
                openLinkInIncognitoWindow(url, profile.id)
            }
            return
        case .openLinkInLittleWindow(let url):
            // As Arc's `littleWindow(profile: nil)`.
            return openLittleWindow(.internalLink(url), nil, nil)
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
        if case .window(let ownerID, let group?) = request, group.folder != nil,
            !store.closing.values.contains(where: { $0.group == group }),
            let owner = store.windows.first(where: { $0.id == ownerID }),
            let index = owner.closedGroups.firstIndex(where: { $0 == group && $0.steps.isEmpty })
        {
            owner.closedGroups.remove(at: index)
            owner.undoManager?.removeUndos(group.id.uuidString)
        }
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
            archivePeek(page, of: ownerID, saving: true)
            store.windows.first { $0.id == request.windowID }?.remember(
                ClosedPage(
                    id: page.id, title: page.title, url: page.url, place: .peek(ownerID: ownerID),
                    sessionID: sessionID), in: request.group ?? ClosedGroup(undoPrompt: UndoStrings.closePeek))
        }
        if ownerID == archivePeekID { archivePeekID = nil }
        self.page?.activate()
        spaceDeletionEnded(page.id, kept: false)
    }

    private var allowsShiftClickToPeek: Bool { store.peekOnShiftClick && !isLittle }

    func canShiftClickToPeek(_ url: URL, from pageID: UUID) -> Bool {
        guard allowsShiftClickToPeek, let tabID = tabID(of: pageID),
            ["http", "https", "file"].contains(url.scheme)
        else { return false }
        return otherProfileSpace(for: url, from: tabID) == nil
    }

    private func otherProfileSpace(for url: URL, from openerID: UUID) -> UUID? {
        let spaceID = store.routedSpace(for: url, recent: selectedSpaceID)
        return state.space(spaceID)?.profileID == profile(containing: openerID)?.id ? nil : spaceID
    }

    /// As Arc; a Shift-click arrives as the page's own new window, and the engine's, as its page menu's Open Link in
    /// New Window, opens a window on this Space with the page as its selected tab. A page from an Archive Peek has no
    /// tab to join, and the top of the shown Space is Oa's own.
    private func place(
        _ page: any Page, url: URL?, disposition: OpenDisposition, byPage: Bool, from openerID: UUID,
        insidePeek: Bool
    ) {
        // As Arc's policy for a background page: with ⌘⌥ held and its switch on, a Little window; with ⌥ held
        // otherwise, as an ⌥-clicked link, a split. The engine's page goes to the Little window, on the opener's
        // profile, Oa's own: who makes its page in Arc is unknown.
        let held = NSEvent.modifierFlags.intersection([.option, .command, .shift, .control])
        if disposition == .backgroundTab, held == [.command, .option], sidebarContext != .incognito,
            LittleBrowserPreferences.opensOnOptionCommandClick, let url,
            let profile = profile(containing: openerID)
        {
            return openLittleWindow(.browserPopup, profile.id, (page, url))
        }
        // As seen in Arc: a ⌘-click or middle click in a Little window loads in the page it shows.
        if isLittle, disposition == .backgroundTab || disposition == .splitView {
            page.drop()
            if let url { frontPage?.load(url) }
            return
        }
        let splits = held == .option || held == [.command, .option]
        let disposition = disposition == .backgroundTab && splits ? .splitView : disposition
        // As seen in Arc, in any window: a Shift-click inside a Peek opens no second Peek but a window.
        // A Little window has no Peek, as Arc's: its Shift-click is a window too.
        let inWindow =
            disposition == .newWindow
            && (!byPage || insidePeek || !allowsShiftClickToPeek)
        // As Arc's `createTabInNewWindow(url:isIncognito:)`: only the address goes, and loads afresh there.
        if inWindow, insidePeek || sidebarContext != .global {
            page.drop()
            if let url { openURLInNewWindow(url) }
            return
        }
        guard state.tree.tab(openerID) != nil else {
            guard insidePeek, openerID == archivePeekID else { return page.drop() }
            let tab = makeTab(url: url)
            store.edit { $0.insertTab(tab, atTopOf: selectedSpaceID) }
            createdDates[tab.id] = .now
            install(page, for: tab.id)
            listen(to: page)
            return inWindow ? openWindow(tab.id) : select(tab.id)
        }
        let background = disposition == .backgroundTab
        let split = disposition == .splitView
        if !insidePeek, !inWindow, disposition == .newWindow || (!background && !split && peeksFromLinks(in: openerID))
        {
            // As seen in Arc: no Peek for a link routed to another profile's Space; it loads there afresh.
            guard let url, let spaceID = otherProfileSpace(for: url, from: openerID) else {
                return peek(page, from: openerID)
            }
            page.drop()
            return openRoutedLink(url, in: spaceID)
        }
        let tab = makeTab(url: url, opener: openerID)
        let spaceID = selectedSpaceID
        // As seen in Arc: the link's page on the right of the one it came from, focused, a pinned tab or Favorite
        // going in as itself. Oa's own where that one can't take a pane: a tab.
        editSplitView(taking: split ? [openerID] : []) {
            $0.openTab(tab, from: openerID, in: spaceID)
            if split {
                let index = $0.presentedTabIDs(with: openerID).firstIndex(of: openerID).map { $0 + 1 }
                $0.openInSplitView(tab.id, beside: openerID, in: spaceID, at: index)
            }
        }
        createdDates[tab.id] = .now
        install(page, for: tab.id)
        listen(to: page)
        guard state.isSelectable(tab.id, in: selectedSpaceID) else { return }
        if inWindow { openWindow(tab.id) } else if !background { select(tab.id) }
    }

    /// Oa's own: a new Peek replaces the tab's current one, archived at once.
    private func peek(_ page: any Page, from openerID: UUID) {
        if let current = peeks[openerID] {
            archivePeek(current, of: openerID, saving: true)
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
        guard let spaceID = spaceToShow(tabID), spaces.contains(where: { $0.id == spaceID }),
            state.isSelectable(tabID, in: spaceID)
        else { return }
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
        guard let profile = profile(containing: tabID) else { return nil }
        if space?.profileID == profile.id { return selectedSpaceID }
        return state.spaces.first { $0.profileID == profile.id }?.id
    }

    private func observe(_ page: any Page, for tabID: UUID) {
        let identity = ObjectIdentifier(page)
        withObservationTracking {
            _ = page.title
            _ = page.url
            _ = page.favicon
            _ = page.isLoading
            _ = page.navigationResult
            _ = page.hasFocus
        } onChange: { [weak self] in
            let selections = MainActor.assumeIsolated { self?.selectionCount }
            Task { @MainActor [weak self] in
                guard let self, let page = pages[tabID], ObjectIdentifier(page) == identity else { return }
                save(page, for: tabID)
                // As Arc's `onDidFocus`: the pane whose page takes the keyboard is the focused one. A page the window
                // gave the keyboard itself, before it selected another, isn't followed.
                if page.hasFocus, presentedTabIDs.contains(tabID), selections == selectionCount {
                    select(tabID, keepingMultiSelection: true)
                }
                observe(page, for: tabID)
            }
        }
    }

    /// As Arc: a tab's title stays untouched while a page loads or fails. Oa's own, where Arc gives a tab with no
    /// saved title one at once: such a tab waits too, so it shows its host steadily instead of flashing URL titles.
    private func settledTitle(of page: any Page) -> String? {
        guard page.url != nil, !page.isLoading, page.navigationResult == .loaded, !page.title.isEmpty else {
            return nil
        }
        return page.title
    }

    /// As Arc: a page that has loaded with no favicon clears an unpinned tab's, and a tab that keeps its address never
    /// loses its own.
    private func save(_ page: any Page, for tabID: UUID) {
        let title = settledTitle(of: page)
        store.setSavedPage(tabID, title: title, url: page.url)
        if let tab = state.tree.tab(tabID), leftAddress(tab, page: page) != nil {
            if let title { settledLiveTitles[tabID] = title }
        } else {
            settledLiveTitles[tabID] = nil
        }
        // As seen in Arc, which keeps no favicon of an incognito page.
        guard sidebarContext != .incognito else { return }
        let favicon = page.favicon
        guard favicon != nil || (page.navigationResult == .loaded && !state.keepsAddress(tabID)) else { return }
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
