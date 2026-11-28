import SwiftUI

struct GmailPreviewView: View {
    let model: WindowModel
    let layout: WindowLayoutController
    let tabID: UUID
    let inbox: GmailInbox
    let anchor: CGRect
    @State private var highlighted: String?

    var body: some View {
        let rows = if case .loaded(let messages) = inbox.state { messages.count } else { 0 }
        let width = min(300, max(0, layout.size.width - 8))
        let height = min(38 + CGFloat(max(1, min(rows, 5))) * 62, max(0, layout.size.height - 8))
        let frame = layout.tabPreviewFrame(
            anchor: anchor, width: width, height: height,
            favorite: model.state.isFavorite(tabID), centered: true)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Unread").font(.headline)
                Spacer()
                Button {
                    open(inbox.account.compose)
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.plain).accessibilityLabel("New Email").help("New Email")
            }
            .padding(.horizontal, 12).frame(height: 37)
            Divider()
            switch inbox.state {
            case .loading: status("Loading…")
            case .unavailable: status("Couldn’t load this inbox.")
            case .loaded(let messages) where messages.isEmpty: status("No unread emails, you can exhale! 🍃")
            case .loaded(let messages):
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(messages) { message in
                            Button {
                                open(message.url)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(message.senders).fontWeight(.medium)
                                        Spacer()
                                        Text(message.date, style: .relative).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Text(message.subject)
                                    Text(message.summary).font(.caption).foregroundStyle(.secondary)
                                }
                                .lineLimit(1).padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, alignment: .leading).frame(height: 62)
                                .background(.primary.opacity(highlighted == message.id ? 0.08 : 0))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .onHover { highlighted = $0 ? message.id : nil }
                        }
                    }
                }.scrollBounceBehavior(.basedOnSize)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .modifier(
            PopoverBackgroundView(cornerRadius: 12, shadowColor: .black.opacity(0.32), shadowRadius: 10, shadowY: 5)
        )
        .contentShape(Rectangle())
        .onHover { if !$0 { layout.leaveSidebarPreview(tabID) } }
        .offset(x: frame.minX, y: frame.minY)
        .onChange(of: frame, initial: true) { layout.sidebarPreviewFrame = frame }
        .onDisappear { if layout.sidebarPreview?.id == tabID { layout.dismissSidebarPreview() } }
        .task(id: ObjectIdentifier(inbox)) { await model.refreshGmail(inbox, from: tabID) }
    }

    private func status(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary).padding(.horizontal, 12).frame(height: 62)
    }

    private func open(_ url: URL) {
        layout.dismissSidebarPreview()
        model.openGmail(url, from: tabID, inbox: inbox)
    }
}
