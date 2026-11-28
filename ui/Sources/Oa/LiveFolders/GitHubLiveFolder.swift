import DevKit
import Foundation

struct GitHubLiveFolder: Codable, Hashable {
    let profileID: UUID
    var hidden: Set<URL> = []
    var lastFetch: Date?
    var failedSince: Date?
    var error: GitHubFolderError?
    private var filters: Set<GitHubPullRequestFilter>?
    fileprivate var fetchedRequests: [GitHubPullRequest]?
    private var hiddenRepositories: Set<String>?

    init(profileID: UUID) { self.profileID = profileID }

    func includesRepository(_ name: String) -> Bool {
        hiddenRepositories?.contains(name.lowercased()) != true
    }

    fileprivate mutating func toggleRepository(_ name: String) {
        var hidden = hiddenRepositories ?? []
        hidden.formSymmetricDifference([name.lowercased()])
        hiddenRepositories = hidden
    }

    var enabledFilters: Set<GitHubPullRequestFilter> {
        get { filters ?? Set(GitHubPullRequestFilter.allCases) }
        set { filters = newValue }
    }

    var hasPersistentFailure: Bool {
        guard let failedSince, let lastFetch else { return false }
        return lastFetch.timeIntervalSince(failedSince) > 30
    }

    var warning: GitHubFolderError? {
        switch error {
        case .signedOut, .singleSignOn: error
        case .unavailable: hasPersistentFailure ? error : nil
        case nil: nil
        }
    }
}

extension SidebarState {
    func gitHubFolders(in spaceID: UUID) -> [SidebarFolder] {
        guard let root = space(spaceID)?.pinnedRootID else { return [] }
        return tree.descendants(of: root).compactMap { $0.folder }.filter { $0.gitHub != nil }
    }

    mutating func resetMovedLiveFolders() {
        for item in tree.items.values {
            guard var folder = item.folder, let live = folder.gitHub,
                let profileID = space(containingItem: item.id)?.profileID, profileID != live.profileID
            else { continue }
            for child in item.childIDs where tree.tab(child)?.liveURL != nil { tree.remove(child) }
            folder.gitHub = GitHubLiveFolder(profileID: profileID)
            folder.gitHub?.enabledFilters = live.enabledFilters
            tree.update(folder.id) { $0.kind = .folder(folder) }
        }
    }

    mutating func updateLiveFolder(_ id: UUID, _ change: (inout GitHubLiveFolder) -> Void) {
        tree.update(id) { item in
            guard var folder = item.folder, var live = folder.gitHub else { return }
            change(&live)
            folder.gitHub = live
            item.kind = .folder(folder)
        }
    }

    private func cachedPullRequests(in folderID: UUID) -> [GitHubPullRequest] {
        if let cached = tree.folder(folderID)?.gitHub?.fetchedRequests { return cached }
        // Older snapshots hold the last results only in the managed tabs.
        return tree.tabs(under: folderID).compactMap { tab in
            tab.liveURL.map { GitHubPullRequest(url: $0, title: tab.title) }
        }
    }

    func liveFolderRepositories(in folderID: UUID) -> [String] {
        var seen = Set<String>()
        return cachedPullRequests(in: folderID).map { GitHubPullRequest.repository(of: $0.url) }
            .filter { seen.insert($0.lowercased()).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    mutating func toggleLiveFolderRepository(_ name: String, in folderID: UUID) {
        let requests = cachedPullRequests(in: folderID)
        updateLiveFolder(folderID) {
            $0.fetchedRequests = requests
            $0.toggleRepository(name)
        }
        reconcilePullRequests(requests, in: folderID, repository: name)
    }

    mutating func applyPullRequests(_ requests: [GitHubPullRequest], to folderID: UUID) {
        updateLiveFolder(folderID) { $0.fetchedRequests = requests }
        reconcilePullRequests(requests, in: folderID)
    }

    private mutating func reconcilePullRequests(
        _ requests: [GitHubPullRequest], in folderID: UUID, repository: String? = nil
    ) {
        guard let live = tree.folder(folderID)?.gitHub else { return }
        func inScope(_ url: URL) -> Bool {
            repository.map { GitHubPullRequest.repository(of: url).caseInsensitiveCompare($0) == .orderedSame } ?? true
        }
        let visible = requests.filter {
            inScope($0.url) && live.includesRepository(GitHubPullRequest.repository(of: $0.url))
                && !live.hidden.contains($0.url)
        }
        let urls = Set(visible.map(\.url))
        var existing: [URL: UUID] = [:]
        for id in tree[folderID]?.childIDs ?? [] {
            guard let url = tree.tab(id)?.liveURL, inScope(url) else { continue }
            if urls.contains(url), existing[url] == nil { existing[url] = id } else { tree.remove(id) }
        }
        for request in visible {
            if let id = existing[request.url] {
                tree.update(id) { item in
                    guard var tab = item.tab else { return }
                    tab.title = request.title
                    item.kind = .tab(tab)
                }
            } else {
                let tab = SidebarTab(id: UUID(), title: request.title, url: request.url, liveURL: request.url)
                tree.append(SidebarItem(id: tab.id, kind: .tab(tab)), to: folderID)
            }
        }
    }
}

@MainActor
final class LiveFolderRefreshes {
    private struct Job {
        let profileID: UUID
        let task: Task<Void, Never>
        var waitingToRetry = false
    }
    private var jobs: [UUID: Job] = [:]

    func cancelRemovedFolders(in state: SidebarState) {
        for (id, job) in jobs where state.tree.folder(id)?.gitHub?.profileID != job.profileID {
            job.task.cancel()
            jobs[id] = nil
        }
    }

    func refresh(_ folder: SidebarFolder, in store: SidebarStore, using engine: any BrowserApplication, manual: Bool) {
        guard let live = folder.gitHub else { return }
        let id = folder.id
        if let job = jobs[id] {
            guard manual || job.waitingToRetry || job.profileID != live.profileID else { return }
            job.task.cancel()
        }
        let task = Task { [weak store] in
            guard let store else { return }
            if !manual, let last = live.lastFetch {
                let delay = min(10, 10 + last.timeIntervalSinceNow)
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            }
            for attempt in 0...1 {
                guard !Task.isCancelled, !store.quitting,
                    store.state.tree.folder(id)?.gitHub?.profileID == live.profileID
                else { break }
                jobs[id]?.waitingToRetry = false
                let result: Result<[GitHubPullRequest], GitHubFolderError>
                do {
                    result = .success(
                        try await GitHubPullRequests.fetch(
                            live.enabledFilters, in: engine.browserContext(id: live.profileID)))
                } catch {
                    result = .failure(error as? GitHubFolderError ?? .unavailable)
                }
                guard !Task.isCancelled, !store.quitting,
                    let current = store.state.tree.folder(id)?.gitHub, current.profileID == live.profileID,
                    current.enabledFilters == live.enabledFilters
                else { break }
                let now = Date.now
                store.edit { state in
                    if case .success(let requests) = result { state.applyPullRequests(requests, to: id) }
                    state.updateLiveFolder(id) { data in
                        data.lastFetch = now
                        switch result {
                        case .success:
                            data.error = nil
                            data.failedSince = nil
                        case .failure(let error):
                            data.error = error
                            data.failedSince = data.failedSince ?? now
                        }
                    }
                }
                guard attempt == 0, case .failure(let error) = result,
                    store.state.tree.folder(id)?.gitHub?.hasPersistentFailure == false
                else {
                    break
                }
                if case .singleSignOn = error { break }
                jobs[id]?.waitingToRetry = true
                try? await Task.sleep(for: .seconds(60))
            }
            if !Task.isCancelled { jobs[id] = nil }
        }
        jobs[id] = Job(profileID: live.profileID, task: task)
    }
}
