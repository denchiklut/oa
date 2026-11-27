import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

struct MediaItem: Identifiable, Hashable {
    let file: URL
    let date: Date
    let isMovie: Bool
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

    static func discover(files: [URL], screenshots: URL) -> [Self] {
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
        return Set((files + captures).map { $0.resolvingSymlinksInPath().standardizedFileURL }).compactMap { file in
            guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true,
                let type = values.contentType ?? UTType(filenameExtension: file.pathExtension),
                type.conforms(to: .image) || type.conforms(to: .movie)
            else { return nil }
            return Self(
                file: file, date: values.creationDate ?? values.contentModificationDate ?? .distantPast,
                isMovie: type.conforms(to: .movie))
        }.sorted { $0.date == $1.date ? $0.file.path < $1.file.path : $0.date > $1.date }
    }
}

struct MediaPage: View {
    let model: WindowModel
    @State private var items: [MediaItem] = []
    @State private var refresh = 0
    @State private var search = ""

    private var files: [URL] {
        model.captureLibrary.files
            + model.downloads.entries.compactMap { $0.download.status == .finished ? $0.download.file : nil }
    }

    private struct MediaSources: Equatable {
        let files: [URL]
        let refresh: Int
    }

    private var visible: [MediaItem] {
        items.filter {
            !model.captureLibrary.hidden.contains($0.file)
                && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))
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
        .task(id: MediaSources(files: files, refresh: refresh)) { await load(files) }
        .task(id: MediaItem.screenshotDirectory) {
            for await _ in MediaItem.changes(in: MediaItem.screenshotDirectory) { refresh += 1 }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh += 1
        }

    }

    private func load(_ files: [URL]) async {
        let directory = MediaItem.screenshotDirectory
        let found = await Task.detached(priority: .utility) { MediaItem.discover(files: files, screenshots: directory) }
            .value
        if !Task.isCancelled { items = found }
    }
}

private struct MediaTile: View {
    let item: MediaItem
    let revision: UUID?
    let open: () -> Void
    @State private var image: NSImage?
    @State private var hovered = false

    var body: some View {
        Button(action: open) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(.primary.opacity(hovered ? 0.12 : 0.035))
                if let image {
                    Image(nsImage: image).resizable().scaledToFit()
                        .padding(3).background(.white, in: RoundedRectangle(cornerRadius: 2))
                        .shadow(color: .black.opacity(0.24), radius: 4, y: 2)
                        .padding(10)
                }
                if item.isMovie {
                    Image(systemName: "play.fill").font(.system(size: 23)).foregroundStyle(.white).shadow(radius: 3)
                }
            }.aspectRatio(1, contentMode: .fit).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(item.name).accessibilityLabel(item.name).onHover { hovered = $0 }
        .task(id: revision) {
            let request = QLThumbnailGenerator.Request(
                fileAt: item.file, size: CGSize(width: 160, height: 160), scale: 2, representationTypes: .thumbnail)
            let thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
            if !Task.isCancelled { image = thumbnail }
        }
    }
}

struct MediaActions: View {
    let model: WindowModel
    let item: MediaItem

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

struct MediaPreview: View {
    let model: WindowModel
    let item: MediaItem

    var body: some View {
        FilePreviewCard(file: item.file, close: model.closeFilePreview) {
            HStack(spacing: 12) {
                Button(action: model.closeFilePreview) { Image(systemName: "xmark") }.accessibilityLabel("Close")
                ForEach([-1, 1], id: \.self) { offset in
                    let next = model.adjacentMedia(offset)
                    Button {
                        model.previewedMedia = next
                    } label: {
                        Image(systemName: offset < 0 ? "chevron.left" : "chevron.right")
                    }.disabled(next == nil).accessibilityLabel(offset < 0 ? "Previous" : "Next")
                }
                Text(item.name).lineLimit(1).truncationMode(.middle).fontWeight(.semibold)
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
