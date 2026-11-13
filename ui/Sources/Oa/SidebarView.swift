import DevKit
import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    static let width: CGFloat = 220

    let model: WindowModel
    @State private var overLibraryButton = false
    @State private var overFlyout = false
    @State private var showingFlyout = false
    @State private var overTabs = false

    var body: some View {
        if let section = model.library {
            LibraryView(model: model, section: section)
        } else {
            tabs
                .frame(width: Self.width)
                .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var tabs: some View {
        VStack(spacing: 0) {
            FavoritesGrid(model: model)
                .padding(8)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.pinnedTabs) { TabRow(model: model, tab: $0) }
                    if !model.unpinnedTabs.isEmpty { clearDivider }
                    ForEach(model.unpinnedTabs) { TabRow(model: model, tab: $0) }
                }
                .padding(8)
            }
            .onHover { overTabs = $0 }
            .onDrop(of: [.plainText], delegate: TabDrop { model.unfavorite($0) })
            Divider()
            Button {
                model.openCommandBar(.newTab)
            } label: {
                Label("New Tab", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    // As Arc: highlighted while the bar makes a new tab.
                    .background(model.commandBar?.destination == .newTab ? Color.primary.opacity(0.08) : .clear)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            Divider()
            spaces
        }
        .overlay(alignment: .bottomLeading) {
            if showingFlyout {
                DownloadsFlyout(model: model)
                    .onHover { overFlyout = $0 }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 40)
            }
        }
        // As Arc's hover regions: the button or the flyout keeps it up, and it outlasts the gap between them.
        .onChange(of: overLibraryButton || overFlyout) { _, over in
            guard !over else { return showingFlyout = true }
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                if !overLibraryButton, !overFlyout { showingFlyout = false }
            }
        }
        .onDisappear {
            overLibraryButton = false
            overFlyout = false
            showingFlyout = false
        }
    }

    /// Arc's divider above the unpinned tabs, with Clear while the pointer is over the sidebar.
    private var clearDivider: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(height: 1)
            if overTabs {
                Button("Clear") { model.clearTabs() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .help("Clear unselected Today tabs")
            }
        }
        .frame(height: 16)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private var spaces: some View {
        HStack(spacing: 4) {
            LibraryButton(model: model)
                .onHover { overLibraryButton = $0 }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(model.state.spaces) { space in
                        SpaceChip(name: space.name, selected: space.id == model.selectedSpaceID) {
                            model.selectSpace(space.id)
                        }
                        .contextMenu {
                            Button("Rename…") {
                                if let name = NamePrompt.run("Rename Space", name: space.name) {
                                    model.renameSpace(space.id, to: name)
                                }
                            }
                            Button("Delete") { SpaceDeletion.confirm(space, in: model) }
                                .disabled(model.state.spaces.count == 1)
                        }
                    }
                }
            }
            Button {
                if let name = NamePrompt.run("New Space") { model.addSpace(named: name) }
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("New Space")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

@MainActor
enum SpaceDeletion {
    static func confirm(_ space: SidebarSpace, in model: WindowModel) {
        if !model.state.tabs(in: space.id).isEmpty {
            let alert = NSAlert()
            alert.messageText = "Delete your “\(space.name)” Space?"
            alert.informativeText = "This will archive all the tabs inside it."
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        model.deleteSpace(space.id)
    }
}

private struct SpaceChip: View {
    let name: String
    let selected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            Text(name)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(selected ? 0.12 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Arc's grid as measured: 47 pt tiles with 8 pt gaps filling the row, columns from the count as
/// `rows = ⌈n / 4⌉`, `cols = ⌈n / rows⌉`, the last row left-aligned, a favicon and nothing else. A row dropped on a
/// tile joins the grid before it, one dropped beside the tiles is appended; tiles move the same way.
private struct FavoritesGrid: View {
    let model: WindowModel

    var body: some View {
        let favorites = model.favorites
        let rows = max(1, (favorites.count + 3) / 4)
        let columns = max(1, (favorites.count + rows - 1) / rows)
        let width = (SidebarView.width - 16 - CGFloat(columns - 1) * 8) / CGFloat(columns)
        VStack(alignment: .leading, spacing: 8) {
            if favorites.isEmpty {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .foregroundStyle(.quaternary)
                    .frame(width: 47, height: 47)
            }
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 8) {
                    let indices = (row * columns)..<min((row + 1) * columns, favorites.count)
                    ForEach(Array(indices), id: \.self) { index in
                        FavoriteTile(model: model, tab: favorites[index], width: width)
                            .onDrop(of: [.plainText], delegate: TabDrop { model.favorite($0, at: index) })
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onDrop(of: [.plainText], delegate: TabDrop { model.favorite($0, at: nil) })
    }
}

private struct FavoriteTile: View {
    let model: WindowModel
    let tab: SidebarTab
    let width: CGFloat
    @State private var hovering = false

    var body: some View {
        let selected = model.selectedTabID == tab.id
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.primary.opacity(selected ? 0.14 : hovering ? 0.08 : 0.05))
            .frame(width: width, height: 47)
            .overlay { icon.frame(width: 16, height: 16) }
            .overlay(alignment: .topTrailing) {
                if let peek = model.peeks[tab.id] { PeekBadge(favicon: peek.favicon).offset(x: 5, y: -5) }
            }
            // Arc's tiles carry the recording dot too (AppTray's `recordingIndicatorView`); the corner is Oa's own.
            .overlay(alignment: .topLeading) {
                if model.isRecording(tab) { RecordingDot().padding(6) }
            }
            .contentShape(Rectangle())
            .onTapGesture { model.select(tab.id) }
            .onHover { hovering = $0 }
            .onDrag { NSItemProvider(object: tab.id.uuidString as NSString) }
            .contextMenu {
                if selected { Button("Close Tab") { model.close(tab.id) } }
                Button("Unfavorite") { model.unfavorite(tab.id) }
                Button("Remove Favorite") { model.removeFavorite(tab.id) }
            }
    }

    /// The host's first letter stands in for a tab whose page never showed a favicon.
    @ViewBuilder private var icon: some View {
        if let icon = model.favicon(for: tab) {
            Image(nsImage: icon).resizable().interpolation(.high)
        } else {
            Text(String(tab.url?.host()?.replacingOccurrences(of: "www.", with: "").prefix(1) ?? "").uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

/// A dragged tab's ID arrives as text; the drop decides where it goes.
private struct TabDrop: DropDelegate {
    let drop: @MainActor @Sendable (UUID) -> Void

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { text, _ in
            guard let id = (text as? NSString).flatMap({ UUID(uuidString: String($0)) }) else { return }
            Task { @MainActor in drop(id) }
        }
        return true
    }
}

private struct PeekBadge: View {
    let favicon: NSImage?

    var body: some View {
        Group {
            if let favicon {
                Image(nsImage: favicon).resizable().interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.1))
            }
        }
        .frame(width: 12, height: 12)
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: .windowBackgroundColor)))
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
    }
}

/// Reads the model itself, so a change to its tab's page, Peek or selection re-renders the row alone.
/// Arc's recording dot, before the favicon while the tab's page uses the camera or microphone.
private struct RecordingDot: View {
    var body: some View {
        Circle()
            .fill(Color.red)
            .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5))
            .frame(width: 8, height: 8)
            .help("This tab is using your camera or microphone")
    }
}

private struct TabRow: View {
    let model: WindowModel
    let tab: SidebarTab
    @State private var hovering = false

    var body: some View {
        let selected = model.selectedTabID == tab.id
        HStack(spacing: 6) {
            if model.isRecording(tab) { RecordingDot() }
            Group {
                if let icon = model.favicon(for: tab) {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.1))
                }
            }
            .frame(width: 16, height: 16)
            Text(model.title(for: tab))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if let peek = model.peeks[tab.id] { PeekBadge(favicon: peek.favicon) }
            if hovering || selected {
                Button {
                    model.close(tab.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(selected ? 0.12 : hovering ? 0.06 : 0))
        )
        .contentShape(Rectangle())
        .onTapGesture { model.select(tab.id) }
        .onHover { hovering = $0 }
        .onDrag { NSItemProvider(object: tab.id.uuidString as NSString) }
    }
}
