import DevKit
import SwiftUI

/// Arc's flyout over the Library button: the four most recent downloads, the newest at the bottom beside the
/// button, without a finished one whose file is gone. Arc mixes in its Library's other files, which Oa doesn't have.
struct DownloadsFlyout: View {
    let model: WindowModel

    var body: some View {
        let recent = model.downloads.entries.lazy.filter { $0.download.status != .finished || $0.fileExists }
            .prefix(4)
        if !recent.isEmpty {
            VStack(spacing: 2) {
                ForEach(recent.reversed()) { FlyoutRow(model: model, entry: $0) }
            }
            .padding(6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.1)))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        }
    }
}

private struct FlyoutRow: View {
    let model: WindowModel
    let entry: DownloadsStore.Entry
    @State private var hovering = false

    var body: some View {
        let finished = entry.download.status == .finished
        HStack(spacing: 8) {
            if entry.isRunning {
                DownloadRing(progress: entry.fraction, size: 24)
            } else if finished {
                DownloadIcon(entry: entry).frame(width: 24, height: 24)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
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
                .help("Cancel Download")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hovering ? 0.08 : 0)))
        .contentShape(Rectangle())
        .onTapGesture { model.activate(entry) }
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
            Button("Hide from \(appName)") { downloads.hide(entry) }
            Button("Move to Trash") { downloads.trash(entry) }
        case .inProgress, .paused, .notStarted:
            Button("Cancel Download") { downloads.cancel(entry) }
        case .cancelled, .failed:
            EmptyView()
        }
    }
}
