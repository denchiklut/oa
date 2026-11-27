import AppKit
import DevKit
import Foundation
import Observation

/// Holds the sidebar state and the open windows. Every edit goes through it, so windows reconcile and a save
/// follows 2.8 s later. Title and URL write-backs ride on the next save.
@MainActor
@Observable
final class SidebarStore {
    private(set) var state: SidebarState
    private var removedFavicons = 0
    @ObservationIgnored private(set) var windows: [WindowModel] = []
    var peekOnShiftClick = !UserDefaults.standard.bool(forKey: "disableShiftClickToOpenLinksInModal") {
        didSet { UserDefaults.standard.set(!peekOnShiftClick, forKey: "disableShiftClickToOpenLinksInModal") }
    }
    var peekFromPinnedTabs = UserDefaults.standard.object(forKey: "modalEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(peekFromPinnedTabs, forKey: "modalEnabled")
            for window in windows { window.updateLinkRouting() }
        }
    }
    @ObservationIgnored let savedWindows: [WindowRecord]
    @ObservationIgnored var sidebarViewPreferences: SidebarViewPreferences {
        didSet { scheduleSave() }
    }
    @ObservationIgnored private let persistence: SidebarPersistence
    @ObservationIgnored private let favicons: FaviconCache
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var sweep: Task<Void, Never>?
    @ObservationIgnored private var littleSweep: Task<Void, Never>?
    @ObservationIgnored private var frozen = false
    /// Set once quitting is certain.
    @ObservationIgnored var quitting = false
    /// Pages asked to close, by page ID, until the page reports closed or kept.
    @ObservationIgnored var closing: [UUID: CloseRequest] = [:]
    @ObservationIgnored var archivingPins: Set<UUID> = []
    @ObservationIgnored var deletingSpace: ClosingSpace?
    @ObservationIgnored let commandBarPicks: CommandBarPicks
    /// One for the app, as Arc's.
    @ObservationIgnored let topBarColors = TopBarColorClient()
    @ObservationIgnored let contentSnapshots = ContentSnapshotClient()
    @ObservationIgnored let captureLibrary: CaptureLibrary
    @ObservationIgnored let home: StorableHome
    @ObservationIgnored let keyBindings: KeyBindingsClient
    @ObservationIgnored let developerMode: DeveloperModeClient
    @ObservationIgnored let linkRouting: LinkRoutingClient
    @ObservationIgnored let sessionRestoration: SessionRestorationClient
    @ObservationIgnored var didCreateProfile: (UUID) -> Void = { _ in }
    /// Settings ▸ Shortcuts on a binding.
    @ObservationIgnored var showShortcut: (String) -> Void = { _ in }

    init(directory: URL) {
        persistence = SidebarPersistence(directory: directory)
        favicons = FaviconCache(directory: directory)
        commandBarPicks = CommandBarPicks(directory: directory)
        captureLibrary = CaptureLibrary(directory: directory)
        home = StorableHome(directory: directory)
        keyBindings = KeyBindingsClient(directory: directory)
        developerMode = DeveloperModeClient(directory: directory)
        linkRouting = LinkRoutingClient(directory: directory)
        sessionRestoration = SessionRestorationClient(directory: directory)
        state = persistence.loadSidebar() ?? .initial()
        let windows = persistence.loadWindows()
        savedWindows = windows?.windows ?? []
        sidebarViewPreferences = windows?.sidebarViewPreferences ?? SidebarViewPreferences()
        commandBarPicks.prune(keeping: state.profiles.map(\.id))
    }

    func edit(_ change: (inout SidebarState) -> Void) {
        let profiles = state.profiles.map(\.id)
        change(&state)
        state.dissolveSplitViews()
        if state.profiles.map(\.id) != profiles { commandBarPicks.prune(keeping: state.profiles.map(\.id)) }
        for window in windows { window.reconcile() }
        scheduleSave()
    }

    /// Arc's launch check: a Space whose profile the engine no longer has goes to the default profile, and nothing
    /// else changes. The default profile is never missing, as Arc takes it for granted, nor is one whose name is
    /// still to be handed over: the engine lists that one only once it has loaded it. Returns the Spaces' names.
    func resetMissingProfiles(in engine: any BrowserApplication) -> [String] {
        guard engine.listsEveryProfile else { return [] }
        let known = Set(
            engine.allProfiles() + state.profiles.filter { $0.pendingName != nil }.map(\.id)
                + [SidebarProfile.defaultID])
        let missing = state.allSpaces.filter { !known.contains($0.profileID) }
        guard !missing.isEmpty else { return [] }
        edit { $0.setProfile(SidebarProfile.defaultID, forSpaces: missing.map(\.id)) }
        return missing.filter { state.isGlobal($0.id) }.map(\.name)
    }

    /// The engine owns profile names, as Arc's does. Once, it takes those an older sidebar.json kept and a new
    /// install's "Personal", as Arc names its default profile once.
    func handProfileNames(to engine: any BrowserApplication) {
        guard state.profiles.contains(where: { $0.pendingName != nil }) else { return }
        edit { state in
            for index in state.profiles.indices {
                guard let name = state.profiles[index].pendingName else { continue }
                engine.browserContext(id: state.profiles[index].id).setUserVisibleName(name)
                state.profiles[index].pendingName = nil
            }
        }
    }

    /// As Arc: never the default profile, and the UI offers it only for a profile without a Space. Every window lets
    /// go of the profile first, as ADK does, so the engine can delete its data at once.
    func deleteProfile(_ id: UUID, from engine: any BrowserApplication) -> Bool {
        guard id != SidebarProfile.defaultID, !state.allSpaces.contains(where: { $0.profileID == id }) else {
            return false
        }
        for window in windows { window.forgetProfile(id) }
        guard engine.deleteBrowserContext(id: id) else { return false }
        edit { $0.removeProfile(id) }
        return true
    }

    /// Where Air Traffic Control sends `url`: the first matching route's Space, else `unmatched` or the Default.
    /// As seen in Arc, a route or Default whose Space is gone goes to `recent`, the Most Recent Space.
    /// As seen in Arc: a route to Little Arc sends a link from another app there, and a link with no route goes
    /// there while "Links from other apps open in Little Arc" is on, else where the default says.
    func routesToLittleWindow(_ url: URL) -> Bool {
        let rule = linkRouting.state.rule(for: url)
        if rule == nil, LittleBrowserPreferences.opensExternalLinks { return true }
        if case .littleArc = rule?.destination ?? linkRouting.state.defaultDestination { return true }
        return false
    }

    func routedSpace(for url: URL?, recent: UUID, unmatched: UUID? = nil) -> UUID {
        let rule = linkRouting.state.rule(for: url)
        if rule == nil, let unmatched { return unmatched }
        guard case .space(let id) = (rule?.destination ?? linkRouting.state.defaultDestination).target,
            state.space(id) != nil
        else { return recent }
        return id
    }

    func setSavedPage(_ tabID: UUID, title: String?, url: URL?) {
        state.setSavedPage(tabID, title: title, url: url)
    }

    /// The last favicon a tab's page showed, for a tab or Archive entry without a page.
    func savedFavicon(_ id: UUID) -> NSImage? {
        _ = removedFavicons
        return favicons.image(for: id)
    }

    /// The cache isn't observed, and a row showing a removed favicon has nothing else to redraw for.
    func setSavedFavicon(_ tabID: UUID, _ favicon: NSImage?) {
        if let favicon {
            favicons.set(favicon, for: tabID)
        } else if favicons.remove(for: tabID) {
            removedFavicons += 1
        }
    }

    func markViewed(_ tabID: UUID) {
        state.markViewed(tabID)
    }

    /// From a reconcile or a window closing, where an edit can't be nested; the save rides on the enclosing one.
    func archivePage(_ page: any Page, in spaceID: UUID?) {
        state.archivePage(id: page.id, title: page.title, url: page.url, in: spaceID)
    }

    func startAutoArchive() {
        sweep = Task { [weak self] in
            while let self, !Task.isCancelled {
                autoArchive()
                try? await Task.sleep(for: .seconds(15 * 60))
            }
        }
    }

    /// As Arc's sweep of its Little windows, a second after launch and every 300 s.
    func startLittleAutoArchive() {
        littleSweep = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            while let self, !Task.isCancelled {
                archiveIdleLittlePages()
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    /// As Arc's, by container: one whose window didn't come back after the last quit is swept too, by the dates its
    /// record kept. Oa's own: its rows are filed under Little Arc, where Arc's source for them is unknown.
    private func archiveIdleLittlePages() {
        let before = Date.now.addingTimeInterval(-LittleBrowserPreferences.autoArchiveThreshold.seconds)
        for window in windows where window.isLittleIdle(since: before) { window.archiveLittlePages() }
        let open = Set(windows.map(\.id))
        for (container, space) in state.containers {
            guard case .littleBrowser(let windowID) = container, !open.contains(windowID) else { continue }
            let tabIDs = state.tabs(in: space.id).map(\.id)
            let dates = savedWindows.first { $0.id == windowID }?.lastActiveDates ?? [:]
            guard !tabIDs.isEmpty, tabIDs.allSatisfy({ dates[$0].map { $0 < before } ?? false }) else { continue }
            edit { state in tabIDs.forEach { state.archiveTab($0, reason: .auto) } }
        }
    }

    /// A tab with a live page is closed as the user would, so a `beforeunload` handler can keep it, as Arc's idle
    /// unload lets a page stay; the rest are archived outright.
    private func autoArchive() {
        let due = state.tabsDueForArchive(shown: Set(windows.flatMap(\.presentedTabIDs))) {
            AutoArchiveThresholds.threshold(for: $0).seconds
        }
        guard !due.isEmpty else { return }
        for tabID in due {
            if let holder = windows.first(where: { $0.pages[tabID] != nil }) {
                holder.close(tabID, reason: .auto)
            } else {
                state.archiveTab(tabID, reason: .auto)
            }
        }
        state.dissolveSplitViews()
        for window in windows { window.reconcile() }
        scheduleSave()
    }

    func addWindow(_ window: WindowModel) {
        windows.append(window)
        scheduleSave()
    }

    /// As seen in Arc: a Little window's pages are archived as it closes. Then, as Arc's `WindowsData.clean`, the
    /// containers with no window go, their tabs unarchived: this window's own, and one a window left at the last
    /// quit without coming back. Nothing is closed at a quit, so nothing goes then.
    func removeWindow(_ window: WindowModel) {
        windows.removeAll { $0 === window }
        guard !quitting else { return }
        let open = Set(windows.compactMap { $0.style.container(of: $0.id) })
        let littleTabIDs = window.isLittle ? state.tabs(in: window.selectedSpaceID).map(\.id) : []
        edit { state in
            for tabID in littleTabIDs { state.archiveTab(tabID, reason: .manual) }
            for container in state.containers.keys where !open.contains(container) { state.removeContainer(container) }
        }
        scheduleSave()
    }

    func windowStateChanged() {
        scheduleSave()
    }

    var backups: [SidebarBackup] { persistence.backups() }

    func read(_ backup: SidebarBackup) throws -> SidebarState { try persistence.read(backup) }

    /// The file as last saved is kept as a copy, as Arc's is, so edits still waiting for their save are not; then
    /// the backup's bytes replace the file and nothing is saved after, so the relaunch starts from them.
    func restore(_ backup: SidebarBackup) throws {
        try persistence.restore(backup)
        pendingSave?.cancel()
        frozen = true
    }

    /// The last save before quitting; nothing is written after it.
    func saveAndFreeze() {
        guard !frozen else { return }
        pendingSave?.cancel()
        save()
        frozen = true
    }

    private func scheduleSave() {
        guard !frozen else { return }
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.8))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    /// As Arc's, written before quitting unloads pages; nothing is written after it.
    func saveSessionRestorationAndFreeze() {
        sessionRestoration.saveAndFreeze(sessionRestorationMapping)
    }

    private var sessionRestorationMapping: [SessionRestorationClient.Key: Int32] {
        var mapping: [SessionRestorationClient.Key: Int32] = [:]
        for window in windows where window.sidebarContext != nil && window.sidebarContext != .incognito {
            for (tabID, page) in window.pages where page.tabSessionID >= 0 {
                guard let profile = state.profile(containing: tabID) else { continue }
                mapping[.init(itemId: tabID, browser: .init(windowID: window.id, contextID: profile.id))] =
                    page.tabSessionID
            }
        }
        return mapping
    }

    private func save() {
        persistence.save(
            state,
            windows: WindowsSnapshot(
                sidebarViewPreferences: sidebarViewPreferences,
                windows: windows.filter { $0.sidebarContext != .incognito }.map(\.record)))
        sessionRestoration.save(sessionRestorationMapping)
        favicons.prune(keeping: Set(state.tree.items.values.compactMap { $0.tab?.id } + state.archive.map(\.id)))
    }
}

/// Who asked a page to close: the user, from a window and maybe with other tabs at once, or the auto-archive sweep.
enum CloseRequest: Equatable {
    case window(UUID, group: ClosedGroup? = nil)
    case auto

    var windowID: UUID? {
        if case .window(let id, _) = self { id } else { nil }
    }

    var group: ClosedGroup? {
        if case .window(_, let group) = self { group } else { nil }
    }
}

/// The Space's pages still closing, by page ID; one that stayed keeps the Space.
struct ClosingSpace {
    let id: UUID
    let window: WindowModel
    var closing: Set<UUID>
    var kept = false
}
