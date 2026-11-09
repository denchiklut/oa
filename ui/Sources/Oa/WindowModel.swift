import DevKit
import Foundation
import Observation

/// A window's selection over the shared sidebar state, and the pages it holds. A page exists only once the
/// tab was shown here; one live page per tab across windows.
@MainActor
@Observable
final class WindowModel {
    let id: UUID
    private(set) var selectedSpaceID: UUID
    private(set) var selectedTabIDs: [UUID: UUID] = [:]
    private(set) var pages: [UUID: any Page] = [:]
    var focusAddressField = 0
    @ObservationIgnored private let engine: any BrowserApplication
    @ObservationIgnored private let store: SidebarStore
    @ObservationIgnored private var previousTabID: UUID?
    @ObservationIgnored private var pendingURLs: [UUID: URL] = [:]
    @ObservationIgnored private var creating: [UUID: UUID] = [:]
    @ObservationIgnored private var events: [UUID: Task<Void, Never>] = [:]

    var state: SidebarState { store.state }
    var space: SidebarSpace? { state.space(selectedSpaceID) }
    var selectedTabID: UUID? { selectedTabIDs[selectedSpaceID] }
    var selectedTab: SidebarTab? { selectedTabID.flatMap { state.tree.tab($0) } }
    var page: (any Page)? { selectedTabID.flatMap { pages[$0] } }
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

    /// Only the only window picks a tab: first unpinned, else first pinned. Another window starts empty.
    func showFirst(isOnlyWindow: Bool) {
        if isOnlyWindow, let first = state.firstTabID(in: selectedSpaceID) {
            select(first)
        } else {
            focusAddressField += 1
        }
    }

    func newTab(_ url: URL? = nil) {
        let tab = SidebarTab(id: UUID(), url: url)
        store.edit { $0.appendTab(tab, in: selectedSpaceID) }
        select(tab.id)
    }

    func select(_ tabID: UUID) {
        guard state.space(containing: tabID)?.id == selectedSpaceID, selectedTabID != tabID else { return }
        if let current = selectedTabID, pages[current] != nil { previousTabID = current }
        selectedTabIDs[selectedSpaceID] = tabID
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

    /// ⌘W. An unpinned tab goes with its page closed as the user would; a pinned one keeps its entry and drops
    /// its page.
    func close(_ tabID: UUID) {
        end(tabID) { page, pinned in pinned ? page.drop() : page.close() }
    }

    /// Window close and quit: no unload handlers, the records stay.
    func dropAll() {
        for tabID in Array(pages.keys) { release(tabID)?.drop() }
        creating = [:]
    }

    /// Lets go of the page for `tabID` without ending it. Another window takes it over this way.
    @discardableResult
    func release(_ tabID: UUID) -> (any Page)? {
        events.removeValue(forKey: tabID)?.cancel()
        creating.removeValue(forKey: tabID)
        pendingURLs.removeValue(forKey: tabID)
        if previousTabID == tabID { previousTabID = nil }
        return pages.removeValue(forKey: tabID)
    }

    /// After a state edit: selections and pages of tabs or Spaces that are gone go too.
    func reconcile() {
        if space == nil, let first = state.spaces.first { selectedSpaceID = first.id }
        for (spaceID, tabID) in selectedTabIDs where state.space(containing: tabID)?.id != spaceID {
            selectedTabIDs.removeValue(forKey: spaceID)
        }
        for tabID in Array(pages.keys) where state.tree.tab(tabID) == nil { release(tabID)?.drop() }
        for tabID in Array(creating.keys) where state.tree.tab(tabID) == nil { release(tabID) }
        if let previousTabID, state.tree.tab(previousTabID) == nil { self.previousTabID = nil }
    }

    private func end(_ tabID: UUID, _ finish: (any Page, Bool) -> Void) {
        guard let spaceID = state.space(containing: tabID)?.id else { return }
        let pinned = state.isPinned(tabID)
        let wasSelected = selectedTabIDs[spaceID] == tabID
        let next = wasSelected ? nextSelection(closing: tabID, pinned: pinned, in: spaceID) : nil
        let page = release(tabID)
        if !pinned { store.edit { $0.removeTab(tabID) } }
        if let page { finish(page, pinned) }
        if wasSelected {
            selectedTabIDs[spaceID] = next
            if let next, spaceID == selectedSpaceID { ensurePage(next) }
        }
    }

    /// The tab shown before, if its page is still live. An unpinned close falls back to the tab above, else below.
    private func nextSelection(closing tabID: UUID, pinned: Bool, in spaceID: UUID) -> UUID? {
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

    /// Creates the page for a shown tab, taking it over from a window that holds it.
    private func ensurePage(_ tabID: UUID) {
        guard pages[tabID] == nil, creating[tabID] == nil else { return }
        for window in store.windows where window !== self { window.release(tabID)?.drop() }
        guard let space = state.space(containing: tabID), let profile = state.profile(space.profileID) else { return }
        let context = engine.browserContext(id: profile.id)
        let token = UUID()
        creating[tabID] = token
        Task { [weak self, id] in
            guard let page = await context.makePage(id: tabID, windowID: id), let self else { return }
            guard creating[tabID] == token, let tab = state.tree.tab(tabID) else { return page.drop() }
            creating.removeValue(forKey: tabID)
            pages[tabID] = page
            if let url = pendingURLs.removeValue(forKey: tabID) ?? tab.url { page.load(url) }
            observe(page, for: tabID)
            events[tabID] = Task { [weak self] in
                for await event in page.events where event == .closed { self?.pageEnded(tabID) }
            }
        }
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
