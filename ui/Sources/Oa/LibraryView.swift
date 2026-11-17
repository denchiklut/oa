import DevKit
import QuickLookThumbnailing
import SwiftUI

/// Saved by Arc's `HomePageID` names.
enum LibrarySection: String, CaseIterable, Codable {
    case downloads = "DownloadsPage"
    case spaces = "SpacesPage"
    case archive = "ArchivePage"

    var title: String {
        switch self {
        case .downloads: "Downloads"
        case .spaces: "Spaces"
        case .archive: "Archived Tabs"
        }
    }

    var symbol: String {
        switch self {
        case .downloads: "arrow.down.circle"
        case .spaces: "square.on.square"
        case .archive: "archivebox"
        }
    }
}

/// Arc's Library in the sidebar's place, with the page still showing: its rail of sections, of which Oa has
/// Downloads, Spaces and Archived Tabs in Arc's order, beside the section's page. The widths are Arc's.
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
            ForEach(LibrarySection.allCases, id: \.self) { item in
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
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Exit Library")
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

private struct DownloadsPage: View {
    let model: WindowModel
    @State private var gone: Set<Download.ID> = []
    @State private var search = ""
    @State private var profileID: UUID?
    @State private var filtering = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                TextField("Search Downloads…", text: $search)
                    .textFieldStyle(.roundedBorder)
                Button("Filter") { filtering = true }
                    .popover(isPresented: $filtering, arrowEdge: .bottom) { filter }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if groups.isEmpty, search.isEmpty, profileID == nil { empty }
                    ForEach(groups, id: \.title) { group in
                        Text(group.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.top, 8)
                            .padding(.bottom, 2)
                        ForEach(group.entries) { DownloadRow(model: model, entry: $0) }
                    }
                }
                .padding(8)
            }
        }
        .onAppear { gone = model.downloads.gone }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Nothing here yet!")
                .font(.system(size: 13, weight: .semibold))
            Text("Come back after you've found some cool stuff to save.")
                .foregroundStyle(.secondary)
        }
        .padding(10)
    }

    /// Arc's "Filter Downloads…": a chip for each profile, and the one chosen narrows the list to it.
    private var filter: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Filter Downloads…")
                .font(.system(size: 13, weight: .semibold))
            Text("Profiles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(model.profiles) { profile in
                    let chosen = profileID == profile.id
                    Button {
                        profileID = chosen ? nil : profile.id
                    } label: {
                        Text(profile.name)
                            .font(.system(size: 12, weight: chosen ? .semibold : .regular))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.primary.opacity(chosen ? 0.2 : 0.07)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Spacer()
                Button("Done") { filtering = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(minWidth: 220)
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
    let model: WindowModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if model.state.archive.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nothing here yet!")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Hover your mouse over a tab and press the × to archive it.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                }
                ForEach(groups, id: \.title) { group in
                    Text(group.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                        .padding(.bottom, 2)
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
            .padding(8)
        }
    }

    private var groups: [(title: String, entries: [SidebarArchivedTab])] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var groups: [(title: String, entries: [SidebarArchivedTab])] = []
        for entry in model.state.archive.reversed() {
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
        HStack(spacing: 6) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.1))
                }
            }
            .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.displayTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !entry.address.isEmpty {
                    Text(entry.address)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
            if hovering {
                Button(action: delete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .frame(width: 16, height: 16)
                }
                .help("Delete")
                Button(action: restore) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 16, height: 16)
                }
                .help("Restore")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hovering ? 0.06 : 0)))
        .contentShape(Rectangle())
        .onTapGesture(perform: peek)
        .onHover { hovering = $0 }
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
        HStack(spacing: 8) {
            Group {
                if entry.isRunning {
                    DownloadRing(progress: entry.fraction, size: 26)
                } else {
                    DownloadIcon(entry: entry)
                }
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(
                    DownloadText.subtitle(entry, opening: model.downloads.openingWhenFinished.contains(entry.id))
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            if hovering {
                Menu {
                    DownloadMenu(model: model, entry: entry)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .opacity(ended ? 0.5 : 1)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hovering ? 0.06 : 0)))
        .contentShape(Rectangle())
        .onTapGesture { model.activate(entry) }
        .onHover { hovering = $0 }
        .help(entry.name)
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
            Image(systemName: "square.stack")
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("View Library")
        .overlay(alignment: .topTrailing) {
            if let progress = model.downloads.progress {
                DownloadRing(progress: progress, size: 13)
                    .offset(x: 5, y: -4)
                    .allowsHitTesting(false)
            }
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
