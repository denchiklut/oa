import DevKit
import SwiftUI

struct DownloadsFlyout: View {
    let model: WindowModel
    let entries: [DownloadsStore.Entry]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(entries.reversed()) { FlyoutRow(model: model, entry: $0) }
        }
        .padding(.leading, 4)
        .padding(.trailing, 12)
        .contentShape(Rectangle())
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
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.name)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.foreground)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.foreground.opacity(0.65))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .frame(height: 48)
        .background(hovering ? theme.itemFill : .clear, in: RoundedRectangle(cornerRadius: 10))
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
