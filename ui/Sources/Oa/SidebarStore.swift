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
    @ObservationIgnored let savedWindows: [WindowRecord]
    @ObservationIgnored private let persistence: SidebarPersistence
    @ObservationIgnored private let favicons: FaviconCache
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var sweep: Task<Void, Never>?
    @ObservationIgnored private var frozen = false
    /// Pages the user asked to close, by page ID, until the page reports closed or kept.
    @ObservationIgnored var closing: [UUID: SidebarArchivedTab.Reason] = [:]
    @ObservationIgnored var deletingSpace: ClosingSpace?
    /// Archive entries' closed pages, for ⇧⌘T. In memory only, as Arc's ⇧⌘T list is gone after a relaunch.
    @ObservationIgnored var sessionIDs: [UUID: PageSessionID] = [:]

    init(directory: URL) {
        persistence = SidebarPersistence(directory: directory)
        favicons = FaviconCache(directory: directory)
        state = persistence.loadSidebar() ?? .initial()
        savedWindows = persistence.loadWindows()
    }

    func edit(_ change: (inout SidebarState) -> Void) {
        change(&state)
        if !sessionIDs.isEmpty {
            let archived = Set(state.archive.map(\.id))
            sessionIDs = sessionIDs.filter { archived.contains($0.key) }
        }
        for window in windows { window.reconcile() }
        scheduleSave()
    }

    func setSavedPage(_ tabID: UUID, title: String, url: URL?) {
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

    /// A tab with a live page is closed as the user would, so a `beforeunload` handler can keep it, as Arc's idle
    /// unload lets a page stay; the rest are archived outright.
    private func autoArchive() {
        let due = state.tabsDueForArchive(shown: Set(windows.compactMap(\.selectedTabID)))
        guard !due.isEmpty else { return }
        for tabID in due {
            if let holder = windows.first(where: { $0.pages[tabID] != nil }) {
                holder.close(tabID, reason: .auto)
            } else {
                state.archiveTab(tabID, reason: .auto)
            }
        }
        for window in windows { window.reconcile() }
        scheduleSave()
    }

    func addWindow(_ window: WindowModel) {
        windows.append(window)
        scheduleSave()
    }

    func removeWindow(_ window: WindowModel) {
        windows.removeAll { $0 === window }
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

    private func save() {
        persistence.save(state, windows: windows.map(\.record))
        favicons.prune(keeping: Set(state.tree.items.values.compactMap { $0.tab?.id } + state.archive.map(\.id)))
    }
}

/// The Space's pages still closing, by page ID; one that stayed keeps the Space.
struct ClosingSpace {
    let id: UUID
    let window: WindowModel
    var closing: Set<UUID>
    var kept = false
}
