import DevKit
import SwiftUI

struct RecentPagesPreviewView: View {
    let model: WindowModel
    let layout: WindowLayoutController
    let tabID: UUID
    let site: RecentPagesSite
    let anchor: CGRect
    @State private var pages: [HistoryEntry]?
    @State private var highlighted: URL?

    var body: some View {
        let width = min(260, max(0, layout.size.width - 8))
        let listHeight = min(CGFloat(max(pages?.count ?? 0, 1)) * 36, max(0, layout.size.height - 54))
        let height = listHeight + 46
        let frame = CGRect(
            x: min(anchor.maxX + 8, layout.size.width - width - 4),
            y: max(4, min(anchor.minY, layout.size.height - height - 4)), width: width, height: height)
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent pages in \(site.name)")
                .font(.headline)
                .padding(.horizontal, 12)
                .frame(height: 37)
            Divider()
            if let pages, !pages.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(pages, id: \.url) { page in
                            Button {
                                layout.dismissSidebarPreview()
                                model.openRecentPage(page.url, from: tabID)
                            } label: {
                                Text(page.title)
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .frame(height: 36)
                                    .background(
                                        .primary.opacity(highlighted == page.url ? 0.09 : 0),
                                        in: RoundedRectangle(cornerRadius: 5)
                                    )
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .onHover { highlighted = $0 ? page.url : nil }
                        }
                    }
                }
                .frame(height: listHeight)
                .padding(4)
            } else {
                Text(pages == nil ? "Loading…" : site.emptyMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .frame(height: listHeight + 8)
            }
        }
        .frame(width: width, alignment: .leading)
        .modifier(
            PopoverBackgroundView(cornerRadius: 12, shadowColor: .black.opacity(0.32), shadowRadius: 10, shadowY: 5)
        )
        .contentShape(Rectangle())
        .onHover { if !$0 { layout.leaveSidebarPreview(tabID) } }
        .offset(x: frame.minX, y: frame.minY)
        .onChange(of: frame, initial: true) { layout.sidebarPreviewFrame = frame }
        .onDisappear { if layout.sidebarPreview?.id == tabID { layout.dismissSidebarPreview() } }
        .task(id: site) {
            pages = nil
            let results = await model.recentPages(for: site, tabID: tabID)
            if !Task.isCancelled { pages = results }
        }
    }
}
