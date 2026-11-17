import DevKit
import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    let model: WindowModel
    let layout: WindowLayoutController
    @State private var overLibraryButton = false
    @State private var overFlyout = false
    @State private var showingFlyout = false

    var body: some View {
        if let section = model.library {
            LibraryView(model: model, section: section, width: layout.libraryWidth(for: section))
        } else {
            tabs.frame(width: layout.sidebarWidth)
        }
    }

    private var tabs: some View {
        VStack(spacing: 0) {
            SidebarHeader(model: model, layout: layout)
            SidebarPagingContainerView(model: model, layout: layout)
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

    private var spaces: some View {
        HStack(spacing: 4) {
            LibraryButton(model: model)
                .onHover { overLibraryButton = $0 }
            SidebarDock(model: model, layout: layout)
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

/// Arc's Space items in the dock, between the Library button and the plus: an 8 pt dot for a Space without an icon,
/// which is every Space until Spaces have icons, 26 pt apart and closer once they don't fit. The current Space's is
/// darker and nothing else, and during a swipe the two Spaces' dots cross-fade with it. Past a pitch of 18 pt the
/// others shrink to 4 pt: Arc's do between its 8 Spaces and its 10, and where exactly is Oa's own.
private struct SidebarDock: View {
    let model: WindowModel
    let layout: WindowLayoutController
    @Environment(\.theme) private var theme

    var body: some View {
        let spaces = model.state.spaces
        let page = layout.sidebarScrollOffset / layout.sidebarWidth
        GeometryReader { geometry in
            let pitch = min(26, geometry.size.width / CGFloat(max(spaces.count, 1)))
            HStack(spacing: 0) {
                ForEach(Array(spaces.enumerated()), id: \.element.id) { index, space in
                    let emphasis = max(0, 1 - abs(page - CGFloat(index)))
                    let size: CGFloat = pitch < 18 ? 4 + 4 * emphasis : 8
                    Button {
                        model.selectSpace(space.id)
                    } label: {
                        Circle()
                            .fill(theme.dockItem(emphasis: emphasis))
                            .frame(width: size, height: size)
                            .frame(width: pitch, height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(space.name)
                    .accessibilityLabel(space.name)
                    .contextMenu { menu(for: space) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 34)
    }

    @ViewBuilder private func menu(for space: SidebarSpace) -> some View {
        Button("Rename…") {
            if let name = NamePrompt.run("Rename Space", name: space.name) { model.renameSpace(space.id, to: name) }
        }
        // As Arc, by name here, where Settings and Change Profile keep the engine's order.
        Menu("Set Profile") {
            ForEach(model.profiles.sorted { $0.name < $1.name }) { profile in
                Toggle(
                    profile.name,
                    isOn: Binding {
                        profile.id == space.profileID
                    } set: { _ in
                        ProfileDialogUtils.confirmSwitch([space.id], to: profile.id, in: model)
                    })
            }
            Divider()
            Button("New Profile…") { ProfileDialogUtils.createProfile(checking: [space.id], in: model) }
        }
        Button("Delete") { SpaceDeletion.confirm(space, in: model) }
            .disabled(model.state.spaces.count == 1)
    }
}

/// Arc's grid as measured: tiles 47 pt tall with 8 pt gaps filling the row, never narrower than 47 pt, so four to a
/// row at the default width and two at the narrowest; columns from the count as `rows = ⌈n / most⌉`,
/// `cols = ⌈n / rows⌉`, the last row left-aligned, a favicon and nothing else. A row dropped on a tile joins the grid
/// before it, one dropped beside the tiles is appended; tiles move the same way.
struct FavoritesGrid: View {
    let model: WindowModel
    let layout: WindowLayoutController
    let favorites: [SidebarTab]

    static func rows(for count: Int, in width: CGFloat) -> Int {
        let most = max(1, Int((width - 8) / 55))
        return max(1, (count + most - 1) / most)
    }

    /// What the grid takes of the sidebar's height, so a Space's page starts under its profile's grid.
    static func height(for count: Int, in width: CGFloat) -> CGFloat {
        let rows = CGFloat(rows(for: count, in: width))
        return rows * 47 + (rows - 1) * 8
    }

    var body: some View {
        let rows = Self.rows(for: favorites.count, in: layout.sidebarWidth)
        let columns = max(1, (favorites.count + rows - 1) / rows)
        let width = (layout.sidebarWidth - 16 - CGFloat(columns - 1) * 8) / CGFloat(columns)
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
                        FavoriteTile(model: model, layout: layout, tab: favorites[index], width: width)
                            .onDrop(of: [.plainText], delegate: TabDrop { model.favorite($0, at: index) })
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.height(for: favorites.count, in: layout.sidebarWidth), alignment: .top)
        .contentShape(Rectangle())
        .onDrop(of: [.plainText], delegate: TabDrop { model.favorite($0, at: nil) })
    }
}

private struct FavoriteTile: View {
    let model: WindowModel
    let layout: WindowLayoutController
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
            .onDrag {
                layout.setHold(.drag, true)
                return NSItemProvider(object: tab.id.uuidString as NSString)
            }
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
struct TabDrop: DropDelegate {
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

struct TabRow: View {
    let model: WindowModel
    let layout: WindowLayoutController
    let tab: SidebarTab
    let spaceID: UUID
    @State private var hovering = false

    var body: some View {
        let selected = model.selectedTabIDs[spaceID] == tab.id
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
        .onDrag {
            layout.setHold(.drag, true)
            return NSItemProvider(object: tab.id.uuidString as NSString)
        }
        .contextMenu {
            if !model.state.isPinned(tab.id) {
                Button("Archive Tab") { model.close(tab.id) }
                Button("Archive Tabs Below") { model.archiveTabs(below: tab.id) }
                    .disabled(model.unpinnedTabs.last?.id == tab.id)
            }
        }
    }
}
