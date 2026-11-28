import SwiftUI

struct GmailPreviewView: View {
    let model: WindowModel
    let layout: WindowLayoutController
    let tabID: UUID
    let inbox: GmailInbox
    let anchor: CGRect
    @State private var highlighted: String?
    @State private var listHeight: CGFloat = 70

    var body: some View {
        let width = min(240, max(0, layout.size.width - 8))
        let hasRows = if case .loaded(let messages) = inbox.state { !messages.isEmpty } else { false }
        let height = min(hasRows ? listHeight : 62, 350, max(0, layout.size.height - 8))
        let frame = layout.tabPreviewFrame(
            anchor: anchor, width: width, height: height,
            favorite: model.state.isFavorite(tabID), centered: true)
        Group {
            switch inbox.state {
            case .loading: status("Loading…")
            case .unavailable: status("Couldn’t load this inbox.")
            case .loaded(let messages) where messages.isEmpty: status("No unread emails, you can exhale! 🍃")
            case .loaded(let messages):
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(messages) { message in
                            if message.id != messages.first?.id { Divider() }
                            row(message)
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) {
                        $0.size.height
                    } action: {
                        listHeight = $0
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .frame(width: width, height: height, alignment: .leading)
        .accessibilityLabel("Unread")
        .overlay(alignment: .bottomTrailing) {
            SidebarPreviewCreateButton(title: "New Email") { open(inbox.account.compose) }
        }
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

    private func row(_ message: GmailMessage) -> some View {
        Button {
            open(message.url)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(message.senders).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        let age = Duration.seconds(max(0, context.date.timeIntervalSince(message.date)))
                        Text(
                            age.formatted(
                                .units(
                                    allowed: [.days, .hours, .minutes], width: .narrow,
                                    maximumUnitCount: 1, fractionalPart: .hide(rounded: .toNearestOrAwayFromZero))))
                    }
                    .font(.system(size: 11, weight: .medium))
                    .fixedSize()
                }
                Text(message.subject).font(.system(size: 13, weight: .medium)).lineLimit(1)
                if !message.summary.isEmpty {
                    Text(message.summary).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(highlighted == message.id ? 0.08 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { highlighted = $0 ? message.id : nil }
    }

    private func status(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary).padding(.leading, 12).padding(.trailing, 52)
    }

    private func open(_ url: URL) {
        layout.dismissSidebarPreview()
        model.openGmail(url, from: tabID, inbox: inbox)
    }
}
