import DevKit
import Foundation
import Observation

/// Chromium's downloads for a profile, kept current by OaCore's events as ADK's download manager is by ArcCore's.
@MainActor
@Observable
final class ChromiumDownloads: Downloads {
    private(set) var items: [Download] = []
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
    }

    /// An event for a download the list lacks adds it: Chromium creates some before its history has loaded.
    fileprivate func changed(_ download: Download) {
        if let index = items.firstIndex(where: { $0.id == download.id }) {
            if items[index] != download { items[index] = download }
        } else {
            items.append(download)
        }
    }

    fileprivate func removed(_ id: Download.ID) {
        items.removeAll { $0.id == id }
    }
}

@MainActor
private final class DownloadsDelegate: NSObject, CoreDownloadsDelegate {
    weak var downloads: ChromiumDownloads?

    func downloadsDidInitialize(_ downloads: [NSObject]) {
        self.downloads?.initialized(downloads.map { Download(core: unsafeBitCast($0, to: CoreDownload.self)) })
    }

    func downloadWasCreated(_ download: CoreDownload) { downloads?.changed(Download(core: download)) }
    func downloadWasUpdated(_ download: CoreDownload) { downloads?.changed(Download(core: download)) }
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
        self.init(
            id: core.identifier, status: status, receivedBytes: core.receivedBytes,
            totalBytes: core.totalBytes > 0 ? core.totalBytes : nil, bytesPerSecond: core.bytesPerSecond,
            secondsRemaining: core.remainingSeconds < 0 ? nil : Int(core.remainingSeconds), file: core.targetFileURL,
            sourceURL: core.sourceURL, startedAt: core.startTime,
            pageID: (core.page?.delegate as? PageDelegate)?.content?.id)
    }
}
