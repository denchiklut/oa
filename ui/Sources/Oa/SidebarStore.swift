import Foundation
import Observation

/// Holds the sidebar state and the open windows. Every edit goes through it, so windows reconcile and a save
/// follows 2.8 s later. Title and URL write-backs ride on the next save.
@MainActor
@Observable
final class SidebarStore {
    private(set) var state: SidebarState
    @ObservationIgnored private(set) var windows: [WindowModel] = []
    @ObservationIgnored let savedWindows: [WindowRecord]
    @ObservationIgnored private let persistence: SidebarPersistence
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var sweep: Task<Void, Never>?
    @ObservationIgnored private var frozen = false

    init(directory: URL) {
        persistence = SidebarPersistence(directory: directory)
        state = persistence.loadSidebar() ?? .initial()
        savedWindows = persistence.loadWindows()
    }

    func edit(_ change: (inout SidebarState) -> Void) {
        change(&state)
        for window in windows { window.reconcile() }
        scheduleSave()
    }

    func setSavedPage(_ tabID: UUID, title: String, url: URL?) {
        state.setSavedPage(tabID, title: title, url: url)
    }

    func markViewed(_ tabID: UUID) {
        state.markViewed(tabID)
    }

    /// Sweeps now and every 15 minutes. A tab selected in a window counts as viewed.
    func startAutoArchive() {
        sweep = Task { [weak self] in
            while let self, !Task.isCancelled {
                autoArchive()
                try? await Task.sleep(for: .seconds(15 * 60))
            }
        }
    }

    private func autoArchive() {
        guard state.autoArchive(shown: Set(windows.compactMap(\.selectedTabID))) else { return }
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

    /// The last save before quitting; nothing is written after it.
    func saveAndFreeze() {
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
    }
}
