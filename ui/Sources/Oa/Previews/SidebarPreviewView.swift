import AppKit
import SwiftUI

struct SidebarPreviewOverlay: View {
    let model: WindowModel
    let layout: WindowLayoutController
    let preview: WindowLayoutController.SidebarPreview

    var body: some View {
        switch preview.target {
        case .folder(let id):
            if let folder = model.state.tree.folder(id) {
                FolderPreviewView(model: model, layout: layout, folder: folder, anchor: preview.anchor)
                    .id(folder.id)
            }
        case .tab(let id):
            if let tab = model.state.tree.tab(id), let type = model.previewType(for: tab) {
                TabPreviewView(
                    model: model, layout: layout, tab: tab, type: type,
                    anchor: preview.anchor, placement: preview.placement
                )
                .id(tab.id)
            }
        }
    }
}

/// Arc's `StandardPreviewView` + `GroupedListView` + `CalendarPreviewContentView`.
struct TabPreviewView: View {
    let model: WindowModel
    let layout: WindowLayoutController
    let tab: SidebarTab
    let type: PreviewType
    let anchor: CGRect
    let placement: WindowLayoutController.SidebarPreview.Placement
    @State private var contentHeight: CGFloat = 140
    @Environment(\.theme) private var theme

    private var record: PreviewRecord? { model.previewRecord(for: tab) }

    var body: some View {
        let width = min(280, max(0, layout.size.width - 16))
        let maxBodyHeight = max(80, min(320, layout.size.height - 88))
        let bodyHeight = min(max(contentHeight, 76), maxBodyHeight)
        let totalHeight = bodyHeight + 45
        let frame = previewFrame(width: width, height: totalHeight)

        VStack(spacing: 0) {
            header
            Divider().frame(height: 1)
            ScrollView {
                bodyContent
                    .onGeometryChange(for: CGFloat.self) {
                        $0.size.height
                    } action: {
                        contentHeight = $0
                    }
            }
            .frame(height: bodyHeight)
        }
        .frame(width: width)
        .modifier(
            PopoverBackgroundView(cornerRadius: 12, shadowColor: .black.opacity(0.32), shadowRadius: 10, shadowY: 5)
        )
        .contentShape(Rectangle())
        .onHover { inside in
            if inside {
                layout.keepSidebarPreview(tab.id)
            } else {
                layout.leaveSidebarPreview(tab.id)
            }
        }
        .offset(x: frame.minX, y: frame.minY)
        .onChange(of: frame, initial: true) { layout.sidebarPreviewFrame = frame }
        .task(id: tab.id) { model.refreshPreview(for: tab) }
    }

    private func previewFrame(width: CGFloat, height: CGFloat) -> CGRect {
        let x: CGFloat
        let y: CGFloat
        switch placement {
        case .right:
            x = min(anchor.maxX + 12, layout.size.width - width - 8)
            y = max(8, min(anchor.midY - height / 2, layout.size.height - height - 8))
        case .diagonal:
            let preferredX = anchor.maxX - 4
            x = min(max(8, preferredX), layout.size.width - width - 8)
            y = max(8, min(anchor.maxY + 4, layout.size.height - height - 8))
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private var header: some View {
        HStack(spacing: 8) {
            TabFavicon(model: model, tab: tab).frame(width: 16, height: 16)
            Text(type.headerTitle)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            PreviewHeaderButton(symbol: "arrow.clockwise", tooltip: "Refresh") {
                model.refreshPreview(for: tab, force: true)
            }
            PreviewHeaderButton(symbol: "plus", tooltip: type.ctaTooltip) {
                open(type.ctaURL)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch record?.state ?? .loading {
        case .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .frame(height: 84)
        case .signedOut:
            signedOutView
        case .failed:
            VStack(spacing: 8) {
                Text("Failed to update")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                Button("Retry") { model.refreshPreview(for: tab, force: true) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 14)
        case .loaded(let content):
            switch content {
            case .recentPages(let domain, let items):
                recentPagesList(domain: domain, items: items)
            case .gmail(_, let emails):
                gmailList(emails)
            case .calendar(_, _, let events):
                calendarList(events)
            }
        }
    }

    private var signedOutView: some View {
        let message: String
        let buttonTitle: String
        switch type {
        case .gmail:
            message = "Sign in to your Email to see messages at a glance."
            buttonTitle = "Sign In"
        case .googleCalendar:
            message = "See upcoming meetings and join video calls instantly with the Calendar Preview."
            buttonTitle = "Connect Calendar"
        case .recentPages(let domain):
            message = domain.emptyState
            buttonTitle = "Open"
        }
        return VStack(spacing: 10) {
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let signInURL = type.signInURL {
                Button(buttonTitle) { open(signInURL) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func recentPagesList(domain: RecentPagesDomain, items: [RecentPageItem]) -> some View {
        if items.isEmpty {
            emptyState(domain.emptyState)
        } else {
            LazyVStack(spacing: 2) {
                ForEach(items) { item in
                    PreviewRowButton {
                        open(item.url)
                    } content: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                            if let visited = item.lastVisited {
                                Text(visited.formatted(.relative(presentation: .numeric)))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .padding(6)
        }
    }

    @ViewBuilder
    private func gmailList(_ emails: [UnreadEmailItem]) -> some View {
        if emails.isEmpty {
            emptyState("No unread emails, you can exhale! 🍃")
        } else {
            LazyVStack(spacing: 2) {
                ForEach(emails) { email in
                    PreviewRowButton {
                        open(email.url)
                    } content: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(email.sender)
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                if let date = email.date {
                                    Text(Self.compactTimestamp(date))
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(email.title)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                            if !email.summary.isEmpty {
                                Text(email.summary)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .padding(6)
        }
    }

    @ViewBuilder
    private func calendarList(_ events: [CalendarEventItem]) -> some View {
        if events.isEmpty {
            emptyState("No upcoming events")
        } else {
            let calendar = Calendar.current
            let today = events.filter { calendar.isDateInToday($0.start) || $0.start < .now }
            let tomorrow = events.filter { calendar.isDateInTomorrow($0.start) }
            LazyVStack(alignment: .leading, spacing: 4) {
                if !today.isEmpty {
                    sectionHeader("Today")
                    ForEach(today) { event in calendarRow(event) }
                }
                if !tomorrow.isEmpty {
                    sectionHeader("Tomorrow")
                    ForEach(tomorrow) { event in calendarRow(event) }
                }
            }
            .padding(6)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 4)
    }

    private func calendarRow(_ event: CalendarEventItem) -> some View {
        PreviewRowButton {
            if let destination = event.permalink ?? type.signInURL { open(destination) }
        } content: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(theme.maxContrast)
                    .frame(width: 3)
                    .padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(Self.eventTimeRange(event))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if let joinLink = event.joinLink {
                    Button("Join") { open(joinLink) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                }
            }
        }
        .contextMenu {
            if let joinLink = event.joinLink {
                Button("Copy Join Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(joinLink.absoluteString, forType: .string)
                }
            }
            if let permalink = event.permalink {
                Button("Open Event") { open(permalink) }
            }
        }
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .padding(.horizontal, 16)
    }

    private func open(_ url: URL) {
        layout.dismissSidebarPreview()
        model.openPreviewLink(url)
    }

    private static func compactTimestamp(_ date: Date) -> String {
        let elapsed = max(0, Date.now.timeIntervalSince(date))
        if elapsed < 60 { return "Now" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m" }
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private static func eventTimeRange(_ event: CalendarEventItem) -> String {
        if event.isAllDay { return "All day" }
        return
            "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))"
    }
}

private struct PreviewHeaderButton: View {
    let symbol: String
    let tooltip: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(hovering ? 0.09 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .oaToolTip(tooltip)
    }
}

private struct PreviewRowButton<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                content
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.085 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
