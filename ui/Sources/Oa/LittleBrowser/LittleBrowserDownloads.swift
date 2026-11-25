import AppKit
import DevKit
import Foundation

/// Arc's `DownloadsState`, as a Little window's record keeps it.
struct LittleBrowserDownloads: Codable {
    var downloads: [DownloadData] = []
}

/// Arc's `DownloadData`: a download as a Little window last heard of it, saved under Arc's keys.
struct DownloadData: Codable, Equatable, Identifiable {
    enum Status: Equatable {
        case inProgress(Double), paused(Double), notStarted, completed, failed, cancelled
    }

    enum TimeRemaining: Codable, Equatable {
        case seconds(Int)
        case undetermined
    }

    var downloadableID: String
    var localURL: URL
    var sourceURL: URL?
    var webContentsURL: URL?
    var webContentsSessionID: Int?
    var webContentsTitle: String?
    var status: Status
    var openOnDownloadFinished: Bool
    var bytesDownloaded: Int
    var totalBytes: Int?
    var currentSpeed: Int
    var timeRemaining: TimeRemaining
    var createdAt: Date?
    var isOpening = false
    /// Not Arc's, and not saved: Arc works the site out from `sourceURL` where it shows it.
    var sourceDomain: String?

    var id: String { downloadableID }

    private enum CodingKeys: String, CodingKey {
        case downloadableID, localURL, sourceURL, webContentsURL, webContentsSessionID, webContentsTitle, status
        case openOnDownloadFinished, bytesDownloaded, totalBytes, currentSpeed, timeRemaining, createdAt, isOpening
    }

    /// Nil until the engine has chosen the file.
    init?(_ download: Download, opensWhenFinished: Bool) {
        guard let file = download.file else { return nil }
        let fraction = download.totalBytes.map { $0 > 0 ? min(1, Double(download.receivedBytes) / Double($0)) : 0 } ?? 0
        downloadableID = download.id
        localURL = file
        sourceURL = download.sourceURL
        webContentsURL = download.pageURL
        webContentsSessionID = download.pageSessionID.map(Int.init)
        webContentsTitle = download.pageTitle
        status =
            switch download.status {
            case .notStarted: .notStarted
            case .inProgress: .inProgress(fraction)
            case .paused: .paused(fraction)
            case .finished: .completed
            case .failed: .failed
            case .cancelled: .cancelled
            }
        openOnDownloadFinished = opensWhenFinished
        bytesDownloaded = Int(download.receivedBytes)
        totalBytes = download.totalBytes.map(Int.init)
        currentSpeed = Int(download.bytesPerSecond)
        timeRemaining = download.secondsRemaining.map(TimeRemaining.seconds) ?? .undetermined
        createdAt = download.startedAt
        sourceDomain = download.sourceDomain
    }

    /// For the words the Library has for it.
    var download: Download {
        let status: Download.Status =
            switch status {
            case .inProgress: .inProgress
            case .paused: .paused
            case .notStarted: .notStarted
            case .completed: .finished
            case .failed: .failed
            case .cancelled: .cancelled
            }
        var seconds: Int?
        if case .seconds(let left) = timeRemaining { seconds = left }
        return Download(
            id: downloadableID, status: status, receivedBytes: Int64(bytesDownloaded),
            totalBytes: totalBytes.map(Int64.init), bytesPerSecond: Int64(currentSpeed), secondsRemaining: seconds,
            file: localURL, sourceURL: sourceURL, sourceDomain: sourceDomain, startedAt: createdAt ?? .now)
    }
}

/// Arc's coding: the case's name over its fraction, or over `true`. A paused one is written without its fraction and
/// has no arm to read it back, so its window's style reads as a standard one, as Arc's.
extension DownloadData.Status: Codable {
    private enum Key: String, CodingKey { case inProgress, paused, notStarted, completed, failed, cancelled }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Key.self)
        switch values.allKeys.first {
        case .inProgress: self = .inProgress(try values.decode(Double.self, forKey: .inProgress))
        case .notStarted: self = .notStarted
        case .completed: self = .completed
        case .failed: self = .failed
        case .cancelled: self = .cancelled
        case .paused, nil:
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "no status"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: Key.self)
        switch self {
        case .inProgress(let fraction): try values.encode(fraction, forKey: .inProgress)
        case .paused: try values.encode(true, forKey: .paused)
        case .notStarted: try values.encode(true, forKey: .notStarted)
        case .completed: try values.encode(true, forKey: .completed)
        case .failed: try values.encode(true, forKey: .failed)
        case .cancelled: try values.encode(true, forKey: .cancelled)
        }
    }
}

extension WindowModel {
    /// As Arc's `LittleBrowser` reducer takes its download manager's events. A failed or paused download stays as
    /// it last progressed, as Arc's, and the downloads the context already had are not listed.
    func receiveLittleDownload(_ event: DownloadEvent) {
        guard var downloads = little?.downloads.downloads else { return }
        switch event {
        case .create(let download):
            guard !downloads.contains(where: { $0.id == download.id }), let data = littleDownload(download) else {
                return
            }
            downloads.append(data)
        case .update(let download):
            guard let data = littleDownload(download) else { return }
            if let index = downloads.firstIndex(where: { $0.id == data.id }) {
                downloads[index] = data
            } else {
                downloads.append(data)
            }
        case .cancel(let download, let shouldRemove):
            guard let index = downloads.firstIndex(where: { $0.id == download.id }) else { return }
            downloads[index].status = .cancelled
            if shouldRemove { downloads.remove(at: index) }
        case .initialized, .failed, .paused:
            return
        }
        if downloads != little?.downloads.downloads { little?.downloads.downloads = downloads }
    }

    private func littleDownload(_ download: Download) -> DownloadData? {
        DownloadData(download, opensWhenFinished: self.downloads.openingWhenFinished.contains(download.id))
    }

    /// As Arc's tray: a finished card opens its file, and any other does nothing.
    func openLittleDownload(_ id: DownloadData.ID) {
        guard let data = little?.downloads.downloads.first(where: { $0.id == id }), data.status == .completed else {
            return
        }
        NSWorkspace.shared.open(data.localURL)
    }

    /// As Arc's ✕: the card goes first, then the download is cancelled unless it finished or was cancelled.
    func closeLittleDownload(_ id: DownloadData.ID) {
        guard let index = little?.downloads.downloads.firstIndex(where: { $0.id == id }),
            let data = little?.downloads.downloads.remove(at: index)
        else { return }
        if data.status != .completed, data.status != .cancelled { cancelLittleDownload(id) }
    }
}
