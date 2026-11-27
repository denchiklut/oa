import AppKit
import Quartz
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// Arc's preview is a borderless window of its own, the size of the browser window and above it, that takes the
/// keyboard and never becomes main: switching apps and back returns the keyboard to it, not to the page beneath.
@MainActor
final class WindowPreviewPanel {
    private var panel: PreviewPanel?
    private var resizing: NSObjectProtocol?

    func show(over parent: NSWindow, onClose: @escaping () -> Void, @ViewBuilder content makeContent: () -> some View) {
        guard panel == nil else { return }
        let panel = PreviewPanel(
            contentRect: parent.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.onCloseKey = onClose
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        let content = NSHostingView(rootView: makeContent())
        content.wantsLayer = true
        content.layer?.cornerRadius = Self.cornerRadius
        content.layer?.masksToBounds = true
        panel.contentView = content
        panel.setFrame(parent.frame, display: false)
        parent.addChildWindow(panel, ordered: .above)
        panel.makeKey()
        resizing = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: parent, queue: .main
        ) { [weak panel, weak parent] _ in
            MainActor.assumeIsolated {
                if let parent { panel?.setFrame(parent.frame, display: true) }
            }
        }
        self.panel = panel
    }

    func close() {
        guard let panel else { return }
        self.panel = nil
        if let resizing { NotificationCenter.default.removeObserver(resizing) }
        resizing = nil
        let parent = panel.parent
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        parent?.makeKey()
    }

    /// A titled window's corners on macOS 26, so the dim stays inside the browser window's.
    private static let cornerRadius: CGFloat = 16

    private final class PreviewPanel: NSWindow {
        var onCloseKey: () -> Void = {}

        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }

        /// As Arc's: Close Window closes the browser window beneath, preview and all.
        override func performClose(_ sender: Any?) {
            parent?.performClose(sender)
        }

        override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
            item.action == #selector(performClose(_:)) ? parent != nil : super.validateUserInterfaceItem(item)
        }

        /// As Arc's: ⌘W closes the preview, and the tab beneath stays.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                event.charactersIgnoringModifiers == "w"
            else { return super.performKeyEquivalent(with: event) }
            onCloseKey()
            return true
        }
    }
}

/// Reads the model in its own body, so the preview follows ‹ and › and closes with it.
struct PreviewContent: View {
    let model: WindowModel

    var body: some View {
        if let file = model.previewedMedia {
            MediaPreview(model: model, item: file)
        } else if let entry = model.previewedDownload {
            DownloadPreviewView(model: model, entry: entry)
        }
    }
}

/// Arc's preview of a finished download, as Quick Look draws a file: close, previous and next, the name and age, a menu
/// and "Open in ‹App›".
struct DownloadPreviewView: View {
    let model: WindowModel
    let entry: DownloadsStore.Entry

    var body: some View {
        FilePreviewCard(file: entry.download.file, close: model.closeFilePreview) { header }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: model.closeFilePreview) { Image(systemName: "xmark") }
                .help("Close")
            Button {
                model.previewAdjacentDownload(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            Button {
                model.previewAdjacentDownload(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(DownloadText.age(entry.download.startedAt))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Menu {
                Button("Send via iMessage") { model.downloads.share(entry, with: .composeMessage) }
                Button("AirDrop") { model.downloads.share(entry, with: .sendViaAirDrop) }
                Button("Show in Finder") { model.downloads.reveal(entry) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()
            if let app = entry.application {
                Button("Open in \(app)") {
                    model.downloads.open(entry)
                    model.closeFilePreview()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct FilePreviewCard<Header: View>: View {
    let file: URL?
    let close: () -> Void
    @ViewBuilder let header: Header
    var body: some View {
        GeometryReader { geometry in
            let outline = RoundedRectangle(cornerRadius: 16, style: .continuous)
            ZStack {
                Backdrop(onClick: close, color: NSColor.black.withAlphaComponent(0.7))
                KeyTrap(onReturn: {}, onEscape: close)
                // As measured in Arc, with no shadow. The strip's material is Oa's own: Arc's is unknown.
                VStack(spacing: 0) {
                    header.frame(height: 46).background(.regularMaterial)
                    if let file { FileView(file: file).padding(16) }
                }
                .background { if let file { BlurredCopy(file: file) } }
                .clipShape(outline)
                // The enlarged blur would otherwise intercept backdrop clicks beyond the visible card.
                .contentShape(outline)
                .frame(
                    width: max(geometry.size.width * 0.8 - 50, 100), height: max(geometry.size.height * 0.8 - 50, 100))
            }
        }
    }
}

/// As Arc's `MediaPreviewView`: an image as itself, anything else in Quick Look's compact view.
private struct FileView: View {
    let file: URL

    var body: some View {
        if let image = imageFile(file) {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
        } else {
            QuickLook(file: file)
        }
    }
}

private func imageFile(_ file: URL) -> NSImage? {
    UTType(filenameExtension: file.pathExtension)?.conforms(to: .image) == true ? NSImage(contentsOf: file) : nil
}

/// Arc's `BlurredItemContent`, over black as measured.
private struct BlurredCopy: View {
    let file: URL
    @State private var image: NSImage?

    var body: some View {
        GeometryReader { geometry in
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: geometry.size.width * 0.2, height: geometry.size.height * 0.2)
                    .blur(radius: 30)
                    .scaleEffect(7)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .background(.black)
        .task(id: file) {
            if let own = imageFile(file) { image = own } else { image = await Self.thumbnail(of: file) }
        }
    }

    private static func thumbnail(of file: URL) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: file, size: CGSize(width: 512, height: 512), scale: 1, representationTypes: .all)
        return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
    }
}

private struct QuickLook: NSViewRepresentable {
    let file: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .compact)!
        // SwiftUI owns the close in dismantleNSView, including when navigation replaces this view with an image.
        view.shouldCloseWithWindow = false
        view.autostarts = true
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? NSURL)?.isEqual(file) != true { view.previewItem = file as NSURL }
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) {
        view.close()
    }
}
