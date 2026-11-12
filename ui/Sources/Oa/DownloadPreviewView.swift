import AppKit
import Quartz
import SwiftUI

/// Arc's preview is a borderless window of its own, the size of the browser window and above it, that takes the
/// keyboard and never becomes main: switching apps and back returns the keyboard to it, not to the page beneath.
@MainActor
final class DownloadPreviewWindow {
    private var panel: PreviewPanel?
    private var resizing: NSObjectProtocol?

    func show(over parent: NSWindow, model: WindowModel) {
        guard panel == nil else { return }
        let panel = PreviewPanel(
            contentRect: parent.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        let content = NSHostingView(rootView: PreviewContent(model: model))
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
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }
}

/// Reads the model in its own body, so the preview follows ‹ and › and closes with it.
private struct PreviewContent: View {
    let model: WindowModel

    var body: some View {
        if let entry = model.previewedDownload { DownloadPreviewView(model: model, entry: entry) }
    }
}

/// Arc's preview of a finished download, as Quick Look draws a file: close, previous and next, the name and age, a menu
/// and "Open in ‹App›".
struct DownloadPreviewView: View {
    let model: WindowModel
    let entry: DownloadsStore.Entry

    var body: some View {
        ZStack {
            Backdrop(onClick: model.closeDownloadPreview, opacity: 0.45)
            KeyTrap(onReturn: {}, onEscape: model.closeDownloadPreview)
            VStack(spacing: 0) {
                header
                Divider()
                if let file = entry.download.file { QuickLook(file: file) }
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
            .padding(40)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: model.closeDownloadPreview) { Image(systemName: "xmark") }
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
                    model.closeDownloadPreview()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct QuickLook: NSViewRepresentable {
    let file: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
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
