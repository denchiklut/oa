import DevKit
import QuickLookThumbnailing
import SwiftUI

/// Saved by Arc's `HomePageID` names.
enum LibrarySection: String, CaseIterable, Codable {
    case media = "MediaPage"
    case downloads = "DownloadsPage"
    case spaces = "SpacesPage"
    case archive = "ArchivePage"

    var title: String {
        switch self {
        case .media: "Media"
        case .downloads: "Downloads"
        case .spaces: "Spaces"
        case .archive: "Archived Tabs"
        }
    }

    var symbol: String {
        switch self {
        case .media: "photo.on.rectangle.angled"
        case .downloads: "arrow.down.circle"
        case .spaces: "square.on.square"
        case .archive: "archivebox"
        }
    }
}

/// Arc's Library in the sidebar's place, with the page still showing: its rail of sections, of which Oa has
/// Media, Downloads, Spaces and Archived Tabs in Arc's order, beside the section's page. The widths are Arc's.
struct LibraryView: View {
    private static let railWidth: CGFloat = 112

    /// Arc's rule: 417 pt, or as wide as the section's page asks, up to the window less the 56 pt of the page card
    /// left showing.
    static func width(for section: LibrarySection, spaces: Int, in window: CGFloat) -> CGFloat {
        let content = section == .spaces ? SpaceManagementSpacesPage.contentWidth(for: spaces) : 0
        return max(417, min(window - 56, content))
    }

    let model: WindowModel
    let layout: WindowLayoutController
    let section: LibrarySection
    let width: CGFloat
    let progress: CGFloat
    let pageInset: CGFloat
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            rail
            Group {
                switch section {
                case .media: MediaPage(model: model)
                case .downloads: DownloadsPage(model: model)
                case .spaces:
                    SpaceManagementSpacesPage(
                        model: model, layout: layout, progress: progress, pageInset: pageInset)
                case .archive: ArchivePage(model: model)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: width)
        // Arc's edge between the rail and the page, in fixed colours whatever the theme: a glow that rises across
        // the rail, a line, and a shade that runs into the page.
        .overlay(alignment: .topLeading) {
            HStack(spacing: 0) {
                LinearGradient(colors: [.white.opacity(0.05), .clear], startPoint: .trailing, endPoint: .leading)
                    .frame(width: Self.railWidth)
                Color.primary.opacity(0.1).frame(width: 1)
                LinearGradient(colors: [.black.opacity(0.05), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 32)
            }
            .allowsHitTesting(false)
        }
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            ForEach(model.librarySections, id: \.self) { item in
                let isPageSelected = item == section
                Button {
                    // Oa's own: how Arc moves the page between sections of different widths wasn't measured.
                    withAnimation(.spring(response: 0.205, dampingFraction: 1)) { model.viewLibrary(item) }
                } label: {
                    VStack(spacing: 6) {
                        // Arc's icons are its own animations, drawn in two of the theme's colours: the outline in
                        // the strongest, at 70% until its page is chosen, and then the inside in the cutout colour.
                        // Oa's symbols take the same colours.
                        ZStack {
                            if isPageSelected {
                                Image(systemName: item.symbol + ".fill").foregroundStyle(theme.cutout)
                            }
                            Image(systemName: item.symbol)
                                .foregroundStyle(theme.maxContrast.opacity(isPageSelected ? 1 : 0.7))
                        }
                        .font(.system(size: 20))
                        Text(item.title)
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .buttonStyle(PageSidebarItemButtonStyle(isPageSelected: isPageSelected))
                .frame(width: 97, height: 80)
            }
            Spacer()
            HStack {
                Button {
                    model.exitLibrary()
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(LibraryIconButtonStyle())
                .accessibilityLabel("Exit Library")
                .oaToolTip("Exit Library")
                Spacer()
            }
        }
        .padding([.leading, .vertical], 8)
        .frame(width: Self.railWidth, alignment: .leading)
        // As measured in Arc: the rail has its own window buttons, a little lower and further in than the header's.
        .overlay(alignment: .topLeading) {
            WindowStandardButtonsView()
                .padding(.leading, 16)
                .padding(.top, 21)
        }
    }
}

/// Arc's `PageSidebarItemButtonStyle`: the label in the label colour, at 70% until its page is chosen, over a fill of
/// the same colour at 10% when chosen and 5% under the pointer, which draws in by 2 pt while pressed.
private struct PageSidebarItemButtonStyle: ButtonStyle {
    let isPageSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        ButtonView(configuration: configuration, isPageSelected: isPageSelected)
    }

    private struct ButtonView: View {
        let configuration: Configuration
        let isPageSelected: Bool
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .foregroundStyle(Color.primary.opacity(isPageSelected ? 1 : 0.7))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(isPageSelected ? 0.1 : isHovered ? 0.05 : 0))
                        .padding(configuration.isPressed ? 2 : 0)
                        .animation(.spring(response: 0.18, dampingFraction: 0.8), value: configuration.isPressed)
                }
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
        }
    }
}

private struct LibraryIconButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration, cornerRadius: cornerRadius)
    }

    private struct HoverBody: View {
        let configuration: Configuration
        let cornerRadius: CGFloat
        @State private var hovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            configuration.label
                .foregroundStyle(Color.primary.opacity(hovering || configuration.isPressed ? 1 : 0.7))
                .background(
                    shape.fill(Color.primary.opacity(configuration.isPressed ? 0.14 : hovering ? 0.09 : 0))
                )
                .contentShape(shape)
                .onHover { hovering = $0 }
        }
    }
}

/// Arc's 56 pt Library list header: a 36 pt rounded translucent search field beside a Filter toggle button, with no
/// divider beneath them.
struct LibrarySearchHeader: View {
    let prompt: String
    @Binding var search: String
    var hasFilters = false
    var openFilter: (() -> Void)? = nil
    @State private var hoveringFilter = false

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.45))
                TextField(prompt, text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                if !search.isEmpty {
                    Button {
                        search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.primary.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .frame(height: 36)
            .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            if let openFilter {
                Button(action: openFilter) {
                    HStack(spacing: 5) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 14, weight: .medium))
                        Text("Filter")
                            .font(.system(size: 13.5, weight: .medium))
                    }
                    .foregroundStyle(Color.primary.opacity(hasFilters || hoveringFilter ? 1 : 0.75))
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .background(
                        Color.primary.opacity(hasFilters ? 0.16 : hoveringFilter ? 0.1 : 0.05),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .fixedSize()
                .onHover { hoveringFilter = $0 }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }
}

/// Arc's in-place filter panel that replaces the Library list column while filtering.
private struct LibraryFilterView<Content: View>: View {
    let title: String
    let done: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var hoveringDone = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 8)
                Button(action: done) {
                    Text("Done")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(hoveringDone ? 1 : 0.85))
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(
                            Color.primary.opacity(hoveringDone ? 0.15 : 0.09),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .onHover { hoveringDone = $0 }
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .padding(.vertical, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
        }
    }
}

private struct LibraryFilterSection<Content: View>: View {
    let heading: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(heading)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.75))
            LibraryChipLayout(spacing: 8) {
                content()
            }
        }
    }
}

private struct LibraryFilterChip: View {
    let title: String
    var icon: String? = nil
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    SpaceIconGlyph(icon: icon)
                        .font(.system(size: 13))
                }
                Text(title)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.primary.opacity(selected || hovering ? 1 : 0.8))
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Color.primary.opacity(selected ? 0.2 : hovering ? 0.12 : 0.08), in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(selected ? 0.25 : 0), lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct LibraryChipLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(in: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, origin) in zip(subviews, arrange(in: bounds.width, subviews: subviews).origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(in width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxWidth = max(maxWidth, x - spacing)
        }
        return (CGSize(width: maxWidth, height: y + rowHeight), origins)
    }
}

private struct LibrarySectionHeader: View {
    let title: String
    let isFirst: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(0.75))
            .padding(.horizontal, 4)
            .padding(.top, isFirst ? 8 : 16)
            .padding(.bottom, 4)
    }
}

/// Oa's own layout where Arc's exact empty-state spacing wasn't measured.
private struct LibraryEmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.primary.opacity(0.45))
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.85))
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.primary.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 64)
    }
}

private struct DownloadsPage: View {
    let model: WindowModel
    @State private var gone: Set<Download.ID> = []
    @State private var search = ""
    @State private var profileID: UUID?
    @State private var filtering = false

    var body: some View {
        Group {
            if filtering {
                LibraryFilterView(title: "Filter Downloads…") {
                    filtering = false
                } content: {
                    LibraryFilterSection(heading: "Profiles") {
                        ForEach(model.profiles) { profile in
                            let chosen = profileID == profile.id
                            LibraryFilterChip(title: profile.name, selected: chosen) {
                                profileID = chosen ? nil : profile.id
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 0) {
                    LibrarySearchHeader(
                        prompt: "Search Downloads…", search: $search, hasFilters: profileID != nil
                    ) {
                        filtering = true
                    }
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if groups.isEmpty {
                                LibraryEmptyState(
                                    symbol: "arrow.down.circle",
                                    title: "Nothing here yet!",
                                    message: "Come back after you've found some cool stuff to save."
                                )
                            }
                            ForEach(Array(groups.enumerated()), id: \.element.title) { index, group in
                                LibrarySectionHeader(title: group.title, isFirst: index == 0)
                                ForEach(group.entries) { DownloadRow(model: model, entry: $0) }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 12)
                    }
                }
            }
        }
        .onAppear { gone = model.downloads.gone }
    }

    /// As Arc: what was cancelled, failed or lost its file before the page opened isn't listed; one that ends so
    /// while it shows stays until the next time.
    private var groups: [(title: String, entries: [DownloadsStore.Entry])] {
        var groups: [(title: String, entries: [DownloadsStore.Entry])] = []
        for entry in model.downloads.entries
        where !gone.contains(entry.id) && (profileID == nil || entry.profileID == profileID)
            && (search.isEmpty || entry.name.localizedCaseInsensitiveContains(search))
        {
            let title = DownloadText.day(entry.download.startedAt)
            if groups.last?.title == title {
                groups[groups.count - 1].entries.append(entry)
            } else {
                groups.append((title, [entry]))
            }
        }
        return groups
    }
}

private struct ArchivePage: View {
    private enum SourceFilter: Hashable {
        case littleArc
        case space(UUID)
    }

    let model: WindowModel
    @State private var search = ""
    @State private var filtering = false
    @State private var reasons: Set<SidebarArchivedTab.Reason> = []
    @State private var sources: Set<SourceFilter> = []

    var body: some View {
        if filtering {
            LibraryFilterView(title: "Filter Archived Tabs") {
                filtering = false
            } content: {
                LibraryFilterSection(heading: "How was the tab closed?") {
                    reasonChip("Auto-Closed", reason: .auto)
                    reasonChip("Manually Closed", reason: .manual)
                }
                LibraryFilterSection(heading: "Where was the tab?") {
                    sourceChip("Little Arc", source: .littleArc)
                    ForEach(model.state.spaces) { space in
                        sourceChip(space.name, icon: space.icon, source: .space(space.id))
                    }
                }
            }
        } else {
            VStack(spacing: 0) {
                LibrarySearchHeader(
                    prompt: "Search Archive…", search: $search, hasFilters: !reasons.isEmpty || !sources.isEmpty
                ) {
                    filtering = true
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if groups.isEmpty {
                            LibraryEmptyState(
                                symbol: "archivebox",
                                title: "Nothing here yet!",
                                message: "Hover your mouse over a tab and press the × to archive it."
                            )
                        }
                        ForEach(Array(groups.enumerated()), id: \.element.title) { index, group in
                            LibrarySectionHeader(title: group.title, isFirst: index == 0)
                            ForEach(group.entries) { entry in
                                ArchiveRow(entry: entry, icon: model.savedFavicon(entry.id)) {
                                    model.peekArchived(entry.id)
                                } restore: {
                                    model.restoreArchived(entry.id)
                                } delete: {
                                    model.deleteArchived(entry.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private func reasonChip(_ title: String, reason: SidebarArchivedTab.Reason) -> some View {
        LibraryFilterChip(title: title, selected: reasons.contains(reason)) {
            if reasons.remove(reason) == nil { reasons.insert(reason) }
        }
    }

    private func sourceChip(_ title: String, icon: String? = nil, source: SourceFilter) -> some View {
        LibraryFilterChip(title: title, icon: icon, selected: sources.contains(source)) {
            if sources.remove(source) == nil { sources.insert(source) }
        }
    }

    private func matchesSource(_ source: SidebarArchivedTab.Source?) -> Bool {
        guard !sources.isEmpty else { return true }
        switch source {
        case .littleArc: return sources.contains(.littleArc)
        case .space(let id): return sources.contains(.space(id))
        case .standaloneSidebar, nil: return false
        }
    }

    private var groups: [(title: String, entries: [SidebarArchivedTab])] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var groups: [(title: String, entries: [SidebarArchivedTab])] = []
        for entry in model.state.archive.reversed()
        where (reasons.isEmpty || reasons.contains(entry.reason)) && matchesSource(entry.source)
            && (search.isEmpty || entry.displayTitle.localizedCaseInsensitiveContains(search)
                || entry.address.localizedCaseInsensitiveContains(search))
        {
            let days =
                calendar.dateComponents([.day], from: calendar.startOfDay(for: entry.archivedAt), to: today).day ?? 0
            let title = days <= 0 ? "Today" : days == 1 ? "Yesterday" : "\(days) days ago"
            if groups.last?.title == title {
                groups[groups.count - 1].entries.append(entry)
            } else {
                groups.append((title, [entry]))
            }
        }
        return groups
    }
}

private struct ArchiveRow: View {
    let entry: SidebarArchivedTab
    let icon: NSImage?
    let peek: () -> Void
    let restore: () -> Void
    let delete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.1))
                }
            }
            .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayTitle)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color.primary.opacity(hovering ? 1 : 0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !entry.address.isEmpty {
                    Text(entry.address)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.primary.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
            if hovering {
                HStack(spacing: 4) {
                    Button(action: delete) {
                        Image(systemName: "trash")
                            .font(.system(size: 13.5))
                            .frame(width: 28, height: 28)
                    }
                    .accessibilityLabel("Delete")
                    .oaToolTip("Delete", priority: 1)
                    Button(action: restore) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 13.5, weight: .medium))
                            .frame(width: 28, height: 28)
                    }
                    .accessibilityLabel("Restore")
                    .oaToolTip("Restore", priority: 1)
                }
                .buttonStyle(LibraryIconButtonStyle(cornerRadius: 6))
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(height: 56)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(hovering ? 0.1 : 0))
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture(perform: peek)
        .onHover { hovering = $0 }
        .oaToolTip(entry.displayTitle, delay: OaToolTipConfiguration.rowDelay)
        .contextMenu {
            Button("Restore", action: restore)
            Button("Delete", action: delete)
        }
    }
}

private struct DownloadRow: View {
    let model: WindowModel
    let entry: DownloadsStore.Entry
    @State private var hovering = false

    var body: some View {
        let ended = entry.download.status == .cancelled || entry.download.status == .failed
        HStack(spacing: 12) {
            Group {
                if entry.isRunning {
                    DownloadRing(progress: entry.fraction, size: 26)
                } else {
                    DownloadIcon(entry: entry)
                }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color.primary.opacity(hovering ? 1 : 0.9))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(
                    DownloadText.subtitle(entry, opening: model.downloads.openingWhenFinished.contains(entry.id))
                )
                .font(.system(size: 12))
                .foregroundStyle(Color.primary.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            if hovering {
                Menu {
                    DownloadMenu(model: model, entry: entry)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(LibraryIconButtonStyle(cornerRadius: 6))
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .opacity(ended ? 0.5 : 1)
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(height: 56)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(hovering ? 0.1 : 0))
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture { model.activate(entry) }
        .onHover { hovering = $0 }
        .oaToolTip(entry.name, delay: OaToolTipConfiguration.rowDelay)
        .contextMenu { DownloadMenu(model: model, entry: entry) }
    }
}

/// Arc's Library menu for a download, with Oa's name in Hide. Open on one still running makes it open when it
/// finishes; a cancelled or failed one keeps the first three, disabled.
struct DownloadMenu: View {
    let model: WindowModel
    let entry: DownloadsStore.Entry

    var body: some View {
        let downloads = model.downloads
        let finished = entry.download.status == .finished
        Button("Open \(entry.menuKind)") {
            if finished { downloads.open(entry) } else { downloads.toggleOpenWhenFinished(entry) }
        }
        .disabled(!finished && !entry.isRunning)
        Button("Copy \(entry.menuKind)") { downloads.copy(entry) }.disabled(!finished)
        Button("Show in Finder") { downloads.reveal(entry) }.disabled(!finished)
        Divider()
        if entry.isRunning {
            Button("Cancel Download") { downloads.cancel(entry) }
            Divider()
        }
        Button("Hide from \(appName)") { downloads.hide(entry) }
        if finished { Button("Move to Trash") { downloads.trash(entry) } }
    }

    private var appName: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Oa" }
}

/// A finished file's Quick Look thumbnail, else its type's icon; nothing for one that was cancelled or failed.
struct DownloadIcon: View {
    let entry: DownloadsStore.Entry
    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if entry.download.status == .cancelled || entry.download.status == .failed {
                RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.1))
            } else if let thumbnail {
                Image(nsImage: thumbnail).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 3))
            } else if let file = entry.download.file {
                Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: file.pathExtension) ?? .data))
                    .resizable()
            }
        }
        .task(id: entry.download.status) {
            guard entry.download.status == .finished, let file = entry.download.file else { return }
            let request = QLThumbnailGenerator.Request(
                fileAt: file, size: CGSize(width: 64, height: 64), scale: 2, representationTypes: .thumbnail)
            thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
        }
    }
}

/// Arc's Library button: while downloads run, a white disc with a blue arrow and one ring that fills, at its
/// top-right corner. The symbol is Oa's own.
struct LibraryButton: View {
    let model: WindowModel

    var body: some View {
        Button {
            model.viewLibrary()
        } label: {
            // As measured on Arc: a filled archive box about 14 by 16.5 pt in a 32 pt button, in the header's grey.
            Image(systemName: "archivebox.fill")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(ChromeButtonStyle())
        .contextMenu { FlyoutSourceMenu(home: model.home) }
        .accessibilityLabel("View Library")
        .oaToolTip("View Library", shortcut: model.keyBindings.state.shortcut(for: "viewLibrary"))
        .overlay(alignment: .topTrailing) {
            if let progress = model.downloads.progress {
                DownloadRing(progress: progress, size: 13)
                    .offset(x: 5, y: -4)
                    .allowsHitTesting(false)
            }
        }
    }
}

struct FlyoutSourceMenu: View {
    let home: StorableHome

    var body: some View {
        Text("Show Recent Media from:")
        ForEach(FlyoutSource.allCases, id: \.self) { source in
            Toggle(
                source.title,
                isOn: Binding {
                    home.flyoutSources.contains(source)
                } set: { enabled in
                    if enabled {
                        home.flyoutSources.insert(source)
                    } else {
                        home.flyoutSources.remove(source)
                    }
                })
        }
    }
}

struct DownloadRing: View {
    let progress: Double
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(.white)
            .overlay {
                Image(systemName: "arrow.down")
                    .font(.system(size: size * 0.5, weight: .heavy))
                    .foregroundStyle(.blue)
            }
            .overlay {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.blue, style: StrokeStyle(lineWidth: size * 0.14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: size, height: size)
            .animation(.linear(duration: 0.3), value: progress)
    }
}
