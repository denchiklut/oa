import DevKit
import Foundation
import Observation

/// Chromium's downloads for a profile, kept current by OaCore's events as ADK's download manager is by ArcCore's.
@MainActor
@Observable
final class ChromiumDownloads: Downloads {
    private(set) var items: [Download] = []
    var events: AsyncStream<DownloadEvent> { downloadEvents.stream(initial: isInitialized ? items : nil) }
    @ObservationIgnored private let downloadEvents = DownloadEvents()
    @ObservationIgnored private var isInitialized = false
    @ObservationIgnored private let core: CoreDownloads?
    @ObservationIgnored private let delegate = DownloadsDelegate()

    init(core: CoreDownloads?) {
        self.core = core
        delegate.downloads = self
        core?.delegate = delegate
    }

    func pause(_ id: Download.ID) { core?.pauseDownload(identifier: id) }
    func resume(_ id: Download.ID) { core?.resumeDownload(identifier: id) }
    func cancel(_ id: Download.ID) { core?.cancelDownload(identifier: id) }
    func remove(_ id: Download.ID) { core?.removeDownload(identifier: id) }

    fileprivate func initialized(_ downloads: [Download]) {
        items = downloads.sorted { $0.startedAt < $1.startedAt }
        isInitialized = true
        downloadEvents.send(.initialized(items))
    }

    /// An event for a download the list lacks adds it: Chromium creates some before its history has loaded.
    fileprivate func changed(_ download: Download, created: Bool) {
        if let index = items.firstIndex(where: { $0.id == download.id }) {
            if items[index] != download { items[index] = download }
        } else {
            items.append(download)
        }
        if created { downloadEvents.send(.create(download)) } else { downloadEvents.sendUpdate(download) }
    }

    fileprivate func removed(_ id: Download.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        downloadEvents.send(.cancel(items.remove(at: index), shouldRemove: true))
    }
}

@MainActor
private final class DownloadsDelegate: NSObject, CoreDownloadsDelegate {
    weak var downloads: ChromiumDownloads?

    func downloadsDidInitialize(_ downloads: [NSObject]) {
        self.downloads?.initialized(downloads.map { Download(core: unsafeBitCast($0, to: CoreDownload.self)) })
    }

    func downloadWasCreated(_ download: CoreDownload) { downloads?.changed(Download(core: download), created: true) }
    func downloadWasUpdated(_ download: CoreDownload) { downloads?.changed(Download(core: download), created: false) }
    func downloadWasRemoved(identifier: String) { downloads?.removed(identifier) }
}

extension Download {
    /// `OADownloadState` in `core/objc/OACore.h`.
    @MainActor fileprivate init(core: CoreDownload) {
        let status: Status =
            switch core.state {
            case 1: .finished
            case 2: .cancelled
            case 3: .failed
            default: core.targetFileURL == nil ? .notStarted : core.isPaused ? .paused : .inProgress
            }
        let page = (core.page?.delegate as? PageDelegate)?.content
        self.init(
            id: core.identifier, status: status, receivedBytes: core.receivedBytes,
            totalBytes: core.totalBytes > 0 ? core.totalBytes : nil, bytesPerSecond: core.bytesPerSecond,
            secondsRemaining: core.remainingSeconds < 0 ? nil : Int(core.remainingSeconds), file: core.targetFileURL,
            sourceURL: core.sourceURL, sourceDomain: core.sourceDomain, startedAt: core.startTime, pageID: page?.id,
            pageURL: page?.url,
            pageTitle: page?.title, pageSessionID: page?.tabSessionID)
    }
}
