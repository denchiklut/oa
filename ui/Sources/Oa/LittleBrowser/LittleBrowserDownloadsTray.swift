import AppKit
import DevKit
import SwiftUI

/// Arc's `LittleBrowserDownloadsTrayViewController`: one row of cards along the bottom of the content, oldest first,
/// with no cap, nothing animated and no scroll to a new card.
struct LittleBrowserDownloadsTray: View {
    let model: WindowModel
    @Environment(\.colorScheme) private var colorScheme
    /// As seen in Arc: a click opens a finished card's file only when it selects the card, so a second click on the
    /// same card does nothing until the row changes or another card is clicked.
    @State private var selectedID: DownloadData.ID?

    var body: some View {
        let downloads = (model.little?.downloads.downloads ?? []).enumerated()
            .sorted {
                ($0.element.createdAt ?? .distantPast, $0.offset) < ($1.element.createdAt ?? .distantPast, $1.offset)
            }
            .map(\.element)
        if !downloads.isEmpty {
            LittleBrowserDownloadsRow(count: downloads.count) {
                HStack(spacing: LittleBrowserDownloadsRowMetrics.spacing) {
                    ForEach(downloads) { download in
                        LittleBrowserDownloadCard(model: model, download: download) {
                            guard selectedID != download.id else { return }
                            selectedID = download.id
                            model.openLittleDownload(download.id)
                        }
                    }
                }
                .padding(LittleBrowserDownloadsRowMetrics.inset)
                .environment(\.colorScheme, colorScheme)
            }
            .frame(height: LittleBrowserDownloadsRowMetrics.height)
            .onChange(of: downloads) { _, _ in selectedID = nil }
        }
    }
}

private enum LittleBrowserDownloadsRowMetrics {
    static let cardSize = NSSize(width: 250, height: 56)
    static let spacing: CGFloat = 10
    static let inset: CGFloat = 20
    static let height = cardSize.height + 2 * inset
}

/// The row scrolls sideways under a card, and only a card takes a click or a scroll: the strip around the cards
/// leaves them to the page, as Arc's `PassthroughView` does.
private struct LittleBrowserDownloadsRow<Content: View>: NSViewRepresentable {
    let count: Int
    @ViewBuilder let content: Content

    func makeNSView(context: Context) -> LittleBrowserDownloadsScrollView {
        let view = LittleBrowserDownloadsScrollView()
        view.drawsBackground = false
        view.hasHorizontalScroller = true
        view.scrollerStyle = .overlay
        view.autohidesScrollers = true
        view.verticalScrollElasticity = .none
        view.documentView = NSHostingView(rootView: content)
        return view
    }

    func updateNSView(_ view: LittleBrowserDownloadsScrollView, context: Context) {
        guard let document = view.documentView as? NSHostingView<Content> else { return }
        typealias Metrics = LittleBrowserDownloadsRowMetrics
        document.rootView = content
        let width = 2 * Metrics.inset + CGFloat(count) * (Metrics.cardSize.width + Metrics.spacing) - Metrics.spacing
        document.frame = NSRect(x: 0, y: 0, width: width, height: Metrics.height)
        view.cardCount = count
    }
}

private final class LittleBrowserDownloadsScrollView: NSScrollView {
    var cardCount = 0

    override func hitTest(_ point: NSPoint) -> NSView? {
        typealias Metrics = LittleBrowserDownloadsRowMetrics
        guard let documentView, let superview else { return nil }
        let inRow = documentView.convert(point, from: superview)
        let pitch = Metrics.cardSize.width + Metrics.spacing
        let offset = inRow.x - Metrics.inset
        let isOnCard =
            offset >= 0 && Int(offset / pitch) < cardCount
            && offset.truncatingRemainder(dividingBy: pitch) < Metrics.cardSize.width
            && (Metrics.inset...(Metrics.inset + Metrics.cardSize.height)).contains(inRow.y)
        return isOnCard ? super.hitTest(point) : nil
    }
}

/// Arc's `LittleBrowserDownloadsTrayItemView`.
private struct LittleBrowserDownloadCard: View {
    let model: WindowModel
    let download: DownloadData
    let select: () -> Void
    @State private var isHovered = false
    @State private var isCloseHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let entry = DownloadsStore.Entry(download: download.download, profileID: model.little?.profile ?? UUID())
        let subtitle = DownloadText.subtitle(entry, opening: false)
        let ink: Color = colorScheme == .dark ? .white : .black
        HStack(spacing: 10) {
            LittleBrowserDownloadIcon(download: download)
            VStack(alignment: .leading, spacing: 5) {
                Text(download.localURL.lastPathComponent)
                    .font(.system(size: 14))
                    .foregroundStyle(ink.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(ink.opacity(0.5))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if isHovered {
                Button {
                    model.closeLittleDownload(download.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(ink.opacity(0.8))
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(ink.opacity(isCloseHovered ? 0.08 : 0)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { isCloseHovered = $0 }
                .padding(.trailing, -1)
                .accessibilityLabel("Close")
            }
        }
        .padding(10)
        .frame(width: 250, height: 56)
        .background(RoundedRectangle(cornerRadius: 8).fill(fill).shadow(color: .black.opacity(0.25), radius: 3, y: 1))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onHover { isHovered = $0 }
        .onTapGesture(perform: select)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(download.localURL.lastPathComponent)
    }

    /// Arc's `DownloadItemBackground` and its hovered one.
    private var fill: Color {
        switch (colorScheme, isHovered) {
        case (.dark, false): Color(.displayP3, white: 0.05)
        case (.dark, true): Color(.displayP3, white: 0.12)
        case (_, false): .white
        case (_, true): Color(.displayP3, white: 0.96)
        }
    }
}

/// Arc's `IconWithProgressIndicatorView`: the file's icon cut to a circle, ringed clockwise from the top while the
/// download runs.
private struct LittleBrowserDownloadIcon: View {
    let download: DownloadData
    @Environment(\.colorScheme) private var colorScheme

    /// Arc's `DownloadProgressBarBackground` and `LoadingPageBorder`.
    private static let lightTrack = Color(red: 0xCE / 255, green: 0xD7 / 255, blue: 0xE7 / 255)
    private static let darkTrack = Color(red: 0x71 / 255, green: 0x77 / 255, blue: 0x82 / 255)
    private static let lightFill = Color(red: 0x0C / 255, green: 0x50 / 255, blue: 1)
    private static let darkFill = Color(red: 0x2A / 255, green: 0xB6 / 255, blue: 0xF6 / 255)

    var body: some View {
        // As seen in Arc: the icon of a file that isn't there yet, or no longer, is drawn large and off centre.
        let exists = FileManager.default.fileExists(atPath: download.localURL.path)
        Image(nsImage: NSWorkspace.shared.icon(forFile: download.localURL.path))
            .resizable()
            .frame(width: exists ? 32 : 56, height: exists ? 32 : 56)
            .offset(x: exists ? 0 : 9)
            .frame(width: 32, height: 32)
            .clipShape(Circle().inset(by: 2))
            .overlay {
                if case .inProgress(let fraction) = download.status {
                    Circle()
                        .inset(by: 1)
                        .stroke(colorScheme == .dark ? Self.darkTrack : Self.lightTrack, lineWidth: 2)
                    Circle()
                        .inset(by: 1)
                        .trim(from: 0, to: fraction)
                        .stroke(colorScheme == .dark ? Self.darkFill : Self.lightFill, lineWidth: 2)
                        .rotationEffect(.degrees(-90))
                }
            }
    }
}
