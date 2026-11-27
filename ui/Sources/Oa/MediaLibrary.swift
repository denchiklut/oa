import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

struct MediaItem: Identifiable, Hashable {
    let file: URL
    let date: Date
    let isMovie: Bool
    var captureTitle: String?
    var sourceURL: URL?
    var title: String { captureTitle ?? name }
    var id: URL { file }
    var name: String { file.lastPathComponent }

    static var screenshotDirectory: URL {
        let location =
            UserDefaults.standard.persistentDomain(forName: "com.apple.screencapture")?["location"] as? String
        if let location, !location.isEmpty {
            return URL(fileURLWithPath: (location as NSString).expandingTildeInPath, isDirectory: true)
        }
        return URL.desktopDirectory
    }

    static func changes(in directory: URL) -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let descriptor = open(directory.path, O_EVTONLY)
            guard descriptor >= 0 else { continuation.finish(); return }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .global(qos: .utility))
            source.setEventHandler {
                continuation.yield(())
                if !source.data.intersection([.delete, .rename]).isEmpty { continuation.finish() }
            }
            source.setCancelHandler { close(descriptor) }
            continuation.onTermination = { _ in source.cancel() }
            source.resume()
        }
    }

    static func canonicalFile(_ file: URL) -> URL {
        file.absoluteURL.resolvingSymlinksInPath().standardizedFileURL
    }

    static func newestFirst(_ lhs: Self, _ rhs: Self) -> Bool {
        lhs.date == rhs.date ? lhs.file.path < rhs.file.path : lhs.date > rhs.date
    }

    static func discover(files: [URL], screenshots: URL, saved: [MediaItem]) -> [Self] {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .creationDateKey, .contentModificationDateKey, .contentTypeKey,
        ]
        let local =
            (try? FileManager.default.contentsOfDirectory(
                at: screenshots, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])) ?? []
        // Arc names the system capture attribute and preference domain. Filename matching also picks up CleanShot recordings.
        let captures = local.filter { file in
            let name = file.lastPathComponent.lowercased()
            return ["cleanshot ", "screenshot ", "screen shot ", "screen recording "].contains(where: name.hasPrefix)
                || getxattr(file.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) >= 0
        }
        let library = Dictionary(uniqueKeysWithValues: saved.map { ($0.file, $0) })
        return Set((files + captures + library.keys).map(canonicalFile))
            .compactMap { file in
                guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true,
                    let type = values.contentType ?? UTType(filenameExtension: file.pathExtension),
                    type.conforms(to: .image) || type.conforms(to: .movie)
                else { return nil }
                return library[file]
                    ?? Self(
                        file: file, date: values.creationDate ?? values.contentModificationDate ?? .distantPast,
                        isMovie: type.conforms(to: .movie))
            }.sorted(by: newestFirst)
    }
}

struct MediaPage: View {
    let model: WindowModel
    @State private var items: [MediaItem] = []
    @State private var refresh = 0
    @State private var search = ""

    private var files: [URL] {
        model.downloads.entries.compactMap { $0.download.status == .finished ? $0.download.file : nil }
    }

    private struct MediaSources: Equatable {
        let files: [URL]
        let captures: [MediaItem]
        let refresh: Int
    }

    private var visible: [MediaItem] {
        items.filter {
            !model.captureLibrary.hidden.contains($0.file)
                && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
                    || $0.title.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            LibrarySearchHeader(prompt: "Search Media…", search: $search)
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                    ForEach(visible) { item in
                        MediaTile(item: item, revision: model.captureLibrary.revisions[item.file]) {
                            model.previewMedia(item, among: visible)
                        }
                        .contextMenu { MediaActions(model: model, item: item) }
                    }
                }.padding(.horizontal, 8)
                if visible.isEmpty {
                    Text(search.isEmpty ? "No media yet" : "No matching media").foregroundStyle(.secondary).padding(
                        .top, 40)
                }
            }
        }
        .task(id: MediaSources(files: files, captures: model.captureLibrary.items, refresh: refresh)) {
            await load(files)
        }
        .task(id: MediaItem.screenshotDirectory) {
            for await _ in MediaItem.changes(in: MediaItem.screenshotDirectory) { refresh += 1 }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh += 1
        }

    }

    private func load(_ files: [URL]) async {
        let directory = MediaItem.screenshotDirectory
        let captures = model.captureLibrary.items
        let found = await Task.detached(priority: .utility) {
            MediaItem.discover(files: files, screenshots: directory, saved: captures)
        }
        .value
        if !Task.isCancelled { items = found }
    }
}

private struct MediaTile: View {
    let item: MediaItem
    let revision: UUID?
    let open: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme
    @State private var hovered = false

    var body: some View {
        Button(action: open) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(.primary.opacity(hovered ? 0.12 : 0.035))
                MediaThumbnail(file: item.file, revision: revision) { image in
                    if let image {
                        let thumbnail = Image(nsImage: image).resizable().scaledToFit().padding(3)
                        if item.captureTitle != nil {
                            let expanded = hovered && !reduceMotion
                            thumbnail
                                .overlay {
                                    RoundedRectangle(cornerRadius: 2)
                                        .strokeBorder(
                                            theme.maxContrast.opacity(0.48),
                                            style: StrokeStyle(
                                                lineWidth: 2, lineCap: .round, dash: [5, 5],
                                                dashPhase: expanded ? 5 : 0))
                                }
                                .padding(expanded ? 7 : 10)
                                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
                        } else {
                            thumbnail.background(.white, in: RoundedRectangle(cornerRadius: 2))
                                .shadow(color: .black.opacity(0.24), radius: 4, y: 2)
                                .padding(10)
                        }
                    }
                }
                if item.isMovie {
                    Image(systemName: "play.fill").font(.system(size: 23)).foregroundStyle(.white).shadow(radius: 3)
                }
            }.aspectRatio(1, contentMode: .fit).contentShape(Rectangle())
        }
        .buttonStyle(.plain).oaToolTip(item.title).accessibilityLabel(item.title).onHover { hovered = $0 }
    }
}

struct MediaThumbnail<Content: View>: View {
    let file: URL
    let revision: UUID?
    @ViewBuilder let content: (NSImage?) -> Content
    @State private var image: NSImage?

    var body: some View {
        ZStack { content(image) }.task(id: revision) {
            let request = QLThumbnailGenerator.Request(
                fileAt: file, size: CGSize(width: 160, height: 160), scale: 2, representationTypes: .thumbnail)
            let thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
            if !Task.isCancelled { image = thumbnail }
        }
    }
}

struct MediaActions: View {
    let model: WindowModel
    let item: MediaItem
    var inFlyout = false

    var body: some View {
        Button(item.isMovie ? "Copy Video" : "Copy Image") {
            let object: NSPasteboardWriting?
            if item.isMovie { object = item.file as NSURL } else { object = NSImage(contentsOf: item.file) }
            if let object { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([object]) }
        }
        Divider()
        Button("Send via iMessage") { NSSharingService(named: .composeMessage)?.perform(withItems: [item.file]) }
        Button("AirDrop") { NSSharingService(named: .sendViaAirDrop)?.perform(withItems: [item.file]) }
        Divider()
        if inFlyout {
            if let source = item.sourceURL {
                Button("Open Source URL") { model.newTab(source) }
                Button("Copy Source URL") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([source as NSURL])
                    NSPasteboard.general.setString(source.absoluteString, forType: .string)
                }
                Divider()
            }
            Button("Delete") {
                do { try model.captureLibrary.remove(item.file) } catch { model.window?.presentError(error) }
            }
        } else {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.file]) }
            Divider()
            Button("Hide from Oa") {
                do {
                    try model.captureLibrary.hide(item.file)
                    if model.previewedMedia == item { model.closeFilePreview() }
                } catch { model.window?.presentError(error) }
            }
        }
    }
}

struct MediaPreview: View {
    let model: WindowModel
    let item: MediaItem

    var body: some View {
        FilePreviewCard(file: item.file, captureTitle: item.captureTitle, close: model.closeFilePreview) {
            HStack(spacing: 12) {
                Button(action: model.closeFilePreview) { Image(systemName: "xmark") }.accessibilityLabel("Close")
                FilePreviewNavigation(model: model)
                Text(item.title).lineLimit(1).truncationMode(.middle).fontWeight(.semibold)
                Text(DownloadText.age(item.date)).lineLimit(1).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Menu {
                    MediaActions(model: model, item: item)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.button).menuIndicator(.hidden).fixedSize().accessibilityLabel("More")
                Button {
                    let bundle = item.isMovie ? "com.apple.QuickTimePlayerX" : "com.apple.Preview"
                    if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
                        NSWorkspace.shared.open([item.file], withApplicationAt: app, configuration: .init()) {
                            _, error in
                            if let error { Task { @MainActor in model.window?.presentError(error) } }
                        }
                    } else {
                        NSWorkspace.shared.open(item.file)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(item.isMovie ? "Open in QuickTime Player" : "Open in Preview");
                        Image(systemName: "arrow.up.right")
                    }
                }.buttonStyle(.bordered)
            }.buttonStyle(.borderless).padding(.horizontal, 12)
        }
    }
}
