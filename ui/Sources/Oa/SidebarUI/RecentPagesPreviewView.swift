import SwiftUI

struct RecentPagesPreviewView: View {
    let model: WindowModel
    let layout: WindowLayoutController
    let tabID: UUID
    let site: RecentPagesSite
    let anchor: CGRect
    @State private var pages: [RecentPage]?
    @State private var highlighted: URL?

    private var isLinear: Bool { site == .linear }
    private var rowHeight: CGFloat { isLinear ? 52 : 36 }

    var body: some View {
        let width = min(isLinear ? 240 : 260, max(0, layout.size.width - 8))
        let chrome: CGFloat = isLinear ? 0 : 46
        let listHeight = min(CGFloat(max(pages?.count ?? 0, 1)) * rowHeight, max(0, layout.size.height - chrome - 8))
        let height = listHeight + chrome
        let frame = layout.tabPreviewFrame(
            anchor: anchor, width: width, height: height,
            favorite: model.state.isFavorite(tabID), centered: isLinear)
        VStack(alignment: .leading, spacing: 0) {
            if !isLinear {
                Text("Recent pages in \(site.name)")
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .frame(height: 37)
                Divider()
            }
            if let pages, !pages.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(pages, id: \.url) { page in
                            row(page)
                                .overlay(alignment: .top) {
                                    if isLinear, page.url != pages.first?.url { Divider() }
                                }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: listHeight)
                .padding(isLinear ? 0 : 4)
            } else {
                Text(pages == nil ? "Loading…" : site.emptyMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
                    .padding(.trailing, isLinear ? 48 : 12)
                    .frame(height: listHeight + (isLinear ? 0 : 8))
            }
        }
        .frame(width: width, alignment: .leading)
        .overlay(alignment: .bottomTrailing) {
            if isLinear {
                Button {
                    open(URL(string: "https://linear.app/new")!)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 32, height: 32)
                        .background(.background, in: Circle())
                        .overlay { Circle().strokeBorder(.primary.opacity(0.12)) }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New Issue")
                .help("New Issue")
                .padding(10)
            }
        }
        .modifier(
            PopoverBackgroundView(cornerRadius: 12, shadowColor: .black.opacity(0.32), shadowRadius: 10, shadowY: 5)
        )
        .contentShape(Rectangle())
        .onHover { if !$0 { layout.leaveSidebarPreview(tabID) } }
        .offset(x: frame.minX, y: frame.minY)
        .onChange(of: frame, initial: true) { layout.sidebarPreviewFrame = frame }
        .onDisappear { if layout.sidebarPreview?.id == tabID { layout.dismissSidebarPreview() } }
        .task(id: model.shownProfileID) {
            pages = nil
            let results = await model.recentPages(for: site, tabID: tabID)
            if !Task.isCancelled { pages = results }
        }
    }

    private func row(_ page: RecentPage) -> some View {
        Button {
            open(page.url)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(page.title)
                    .font(isLinear ? .system(size: 13, weight: .medium) : .body)
                if let subtitle = page.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .padding(.leading, isLinear ? 12 : 8)
            .padding(.trailing, isLinear ? 48 : 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: rowHeight)
            .background(.primary.opacity(highlighted == page.url ? 0.09 : 0), in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { highlighted = $0 ? page.url : nil }
    }

    private func open(_ url: URL) {
        layout.dismissSidebarPreview()
        model.openRecentPage(url, from: tabID)
    }
}
