import DevKit
import SwiftUI

enum LibraryFile: Identifiable {
    case download(DownloadsStore.Entry)
    case media(MediaItem)

    enum ID: Hashable {
        case download(String)
        case media(URL)
    }

    var id: ID {
        switch self {
        case .download(let entry): .download(entry.id)
        case .media(let item): .media(item.file)
        }
    }

    var date: Date {
        switch self {
        case .download(let entry): entry.download.startedAt
        case .media(let item): item.date
        }
    }

    @MainActor func canPreview(in library: CaptureLibrary) -> Bool {
        switch self {
        case .download(let entry): entry.download.status == .finished && entry.fileExists
        case .media(let item):
            !library.hidden.contains(item.file) && FileManager.default.fileExists(atPath: item.file.path)
        }
    }
}

struct FlyoutDirectory: Sendable {
    let url: URL
    var files: FlyoutSource?
    let screenshotFolder: Bool
    var includeScreenshots = false

    static func selected(
        _ sources: Set<FlyoutSource>, documents: URL = .documentsDirectory,
        desktop: URL = .desktopDirectory, screenshots: URL = MediaItem.screenshotDirectory
    ) -> [Self] {
        let screenshots = MediaItem.canonicalFile(screenshots)
        var directories: [URL: Self] = [:]
        for (source, folder) in [(FlyoutSource.documents, documents), (.desktop, desktop), (.screenshots, screenshots)]
        where sources.contains(source) {
            let url = MediaItem.canonicalFile(folder)
            var entry = directories[url] ?? Self(url: url, screenshotFolder: url == screenshots)
            if source == .screenshots { entry.includeScreenshots = true } else { entry.files = source }
            directories[url] = entry
        }
        return Array(directories.values)
    }

    @concurrent func read() async -> [FlyoutSource: [MediaItem]] {
        var found: [FlyoutSource: [MediaItem]] = [:]
        for file in MediaItem.contents(of: url) {
            if Task.isCancelled { break }
            guard let item = MediaItem.localFile(file) else { continue }
            if screenshotFolder && item.kind != .file && MediaItem.isScreenshot(file) {
                if includeScreenshots { found[.screenshots, default: []].append(item) }
            } else if let files {
                found[files, default: []].append(item)
            }
        }
        return found.mapValues { $0.sorted(by: MediaItem.newestFirst) }
    }
}

struct DownloadsFlyout: View {
    let model: WindowModel
    let entries: [LibraryFile]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(entries.reversed()) { file in
                switch file {
                case .download(let entry): FlyoutRow(model: model, entry: entry)
                case .media(let item): MediaFlyoutRow(model: model, item: item)
                }
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 12)
        .contentShape(Rectangle())
    }
}

private struct MediaFlyoutRow: View {
    let model: WindowModel
    let item: MediaItem
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Button {
            model.previewFromFlyout(.media(item))
        } label: {
            HStack(spacing: 12) {
                MediaThumbnail(file: item.file, revision: model.captureLibrary.revisions[item.file]) { image in
                    ZStack {
                        RoundedRectangle(cornerRadius: 6).fill(theme.itemFill)
                        if let image { Image(nsImage: image).resizable().scaledToFill() }
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                FlyoutLabel(title: item.title, subtitle: DownloadText.age(item.date))
            }
            .padding(.leading, 4).padding(.trailing, 10)
            .frame(height: 48)
            .background(hovering ? theme.itemFill : .clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
        .onDrag { NSItemProvider(contentsOf: item.file) ?? NSItemProvider() }
        .contextMenu { MediaActions(model: model, item: item, inFlyout: true) }
    }
}

private struct FlyoutLabel: View {
    let title: String
    let subtitle: String
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 14)).foregroundStyle(theme.foreground)
            Text(subtitle).font(.system(size: 12)).foregroundStyle(theme.foreground.opacity(0.65))
        }
        .lineLimit(1).truncationMode(.tail)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FlyoutRow: View {
    let model: WindowModel
    let entry: DownloadsStore.Entry
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        let finished = entry.download.status == .finished
        HStack(spacing: 12) {
            if entry.isRunning {
                DownloadRing(progress: entry.fraction, size: 32).frame(width: 40, height: 40)
            } else if finished {
                DownloadIcon(entry: entry).frame(width: 40, height: 40)
            }
            FlyoutLabel(title: entry.name, subtitle: subtitle)
            if entry.isRunning {
                Button {
                    model.downloads.cancel(entry)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Cancel Download")
                .oaToolTip("Cancel Download")
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .frame(height: 48)
        .background(hovering ? theme.itemFill : .clear, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { model.previewFromFlyout(.download(entry)) }
        .onHover { hovering = $0 }
        .onDrag {
            (finished ? entry.download.file.flatMap { NSItemProvider(contentsOf: $0) } : nil) ?? NSItemProvider()
        }
        .contextMenu { menu }
    }

    private var subtitle: String {
        switch entry.download.status {
        case .finished: DownloadText.age(entry.download.startedAt)
        default:
            DownloadText.subtitle(entry, opening: model.downloads.openingWhenFinished.contains(entry.id))
        }
    }

    /// Arc's flyout menus; a cancelled or failed row has none.
    @ViewBuilder private var menu: some View {
        let downloads = model.downloads
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Oa"
        switch entry.download.status {
        case .finished:
            Button("Copy \(entry.kind ?? "File")") { downloads.copy(entry) }
            Divider()
            Button("Send via iMessage") { downloads.share(entry, with: .composeMessage) }
            Button("AirDrop") { downloads.share(entry, with: .sendViaAirDrop) }
            Divider()
            if let app = entry.application { Button("Open in \(app)") { downloads.open(entry) } }
            Button("Show in Finder") { downloads.reveal(entry) }
            Divider()
            Button("Hide from \(appName)") { model.hideDownload(entry) }
            Button("Move to Trash") { downloads.trash(entry) }
        case .inProgress, .paused, .notStarted:
            Button("Cancel Download") { downloads.cancel(entry) }
        case .cancelled, .failed:
            EmptyView()
        }
    }
}
