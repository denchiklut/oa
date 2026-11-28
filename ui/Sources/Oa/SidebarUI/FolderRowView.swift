import AppKit
import SwiftUI

@MainActor
enum FolderDeletion {
    static func confirm(_ folder: SidebarFolder, in model: WindowModel) {
        confirm([folder.id], in: model)
    }

    static func confirm(_ ids: ArraySlice<UUID>, in model: WindowModel) {
        for index in ids.indices {
            guard let folder = model.state.tree.folder(ids[index]) else { continue }
            if folder.gitHub != nil {
                guard let window = model.window else { return }
                DialogSheet.present(on: window, onDismiss: { confirm(ids[(index + 1)...], in: model) }) { dismiss in
                    DeleteLiveFolderDialog(title: folder.displayTitle, cancel: dismiss) {
                        model.deleteFolder(folder.id)
                        dismiss()
                    }
                }
                return
            }
            if !(model.state.tree[folder.id]?.childIDs.isEmpty ?? true) {
                let alert = NSAlert()
                alert.messageText = "Delete your “\(folder.displayTitle)” folder?"
                alert.informativeText = "This will archive all the tabs and folders inside it."
                alert.addButton(withTitle: "Delete")
                alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { continue }
            }
            model.deleteFolder(folder.id)
        }
    }
}

/// Arc's `ListHeaderCellView`: a 40 pt row with a 36 pt card indented 16 pt per nesting level, `FolderIcon` in the 24 pt
/// icon slot, 14 pt semibold title, and `maxContrast @ 0.5` drop-on feedback.
struct FolderRowView: View {
    let model: WindowModel
    let layout: WindowLayoutController
    let folder: SidebarFolder
    let spaceID: UUID
    let depth: Int
    let isExpanded: Bool
    let isPeeked: Bool
    var place = TabRow.Place.sidebar
    @State private var hovering = false
    @State private var leadingHovered = false
    @State private var pressed = false
    @State private var renaming = false
    @State private var pickingIcon = false
    @State private var picking = false
    @State private var heldMembers: [UUID] = []
    @Environment(\.theme) private var theme
    @Environment(\.sidebarDrag) private var drag

    var body: some View {
        let inCard = place == .card
        let indent = CGFloat(depth) * 16
        let dragged = !inCard && drag?.entry?.id == folder.id
        let isDropTarget = !inCard && drag?.target?.dropFolderID == folder.id
        let isDragActive = !inCard && (drag?.entry != nil || drag?.isLinkDrag == true)
        let previewed = !inCard && layout.sidebarPreview?.target == .folder(folder.id)
        let warning = folder.gitHub?.warning
        let canShowHoverContent =
            !inCard && !isDragActive && !pressed && !renaming && !pickingIcon
            && spaceID == model.selectedSpaceID && model.library == nil && model.spaceCreation == nil
            && model.peek == nil && !model.coversWindow
            && !layout.isPaging && layout.sidebarPresentation != .hidden
        let canPreview = canShowHoverContent && !isExpanded && warning == nil && PreviewSettings.shared.folderEnabled
        let multiSelected =
            !inCard && spaceID == model.selectedSpaceID && model.multiSelectedItemIDs.contains(folder.id)
        let iconState = Self.iconState(
            isExpanded: isExpanded, isPeeked: isPeeked, isDropTarget: isDropTarget, leadingHovered: leadingHovered,
            isDragActive: isDragActive)
        let card = RoundedRectangle(cornerRadius: 12, style: .continuous)

        HStack(spacing: 0) {
            FolderIcon(state: iconState, customIcon: folder.icon, theme: theme)
                .frame(width: FolderIcon.size.width, height: FolderIcon.size.height)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .onHover { leadingHovered = $0 }
            Group {
                if renaming {
                    renameField
                } else {
                    Text(folder.displayTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .modifier(LiveFolderReveal(start: revealStart))
                }
            }
            .foregroundStyle(theme.foreground)
            .padding(.leading, 6)
            Spacer(minLength: 0)
        }
        .padding(.leading, 6)
        .padding(.trailing, warning == nil ? 10 : 34)
        .frame(height: 36)
        .background {
            card.fill(
                isDropTarget
                    ? theme.maxContrast.opacity(0.5)
                    : multiSelected
                        ? theme.multiSelectedCard : (hovering || previewed) && !dragged ? theme.itemFill : .clear)
        }
        .contentShape(card)
        .padding(.leading, indent)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: inCard ? .local : .named(SidebarDrag.space))
                .onChanged { value in
                    if !pressed {
                        pressed = true
                        if !inCard { press() }
                    }
                    guard !inCard, !picking else { return }
                    drag?.update(
                        .folder(folder), from: .pinned, glyph: .close, at: value.location, start: value.startLocation,
                        members: heldMembers, model: model, layout: layout)
                }
                .onEnded { _ in
                    pressed = false
                    heldMembers = []
                    guard !picking else {
                        picking = false
                        return
                    }
                    guard inCard else {
                        let dragging = drag?.entry?.id == folder.id
                        drag?.finish(model: model, layout: layout)
                        if !dragging {
                            model.clearMultiSelection()
                            model.toggleFolderExpanded(folder.id)
                        }
                        return
                    }
                    model.toggleFolderExpanded(folder.id)
                },
            including: renaming ? .subviews : .all
        )
        .oaToolTip(
            canShowHoverContent && warning != nil && !previewed
                ? OaToolTipConfiguration(title: folder.displayTitle, delay: OaToolTipConfiguration.rowDelay) : nil
        )
        .overlay(alignment: .trailing) {
            if let warning {
                Button {
                    model.openRoutedLink(warning.destination, in: spaceID)
                } label: {
                    Image(systemName: warning.symbol).frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.foreground)
                .accessibilityLabel(warning.message)
                .oaToolTip(warning.message, delay: OaToolTipConfiguration.controlDelay, priority: 1)
                .padding(.trailing, 6)
            }
        }
        .scaleEffect(pressed ? 0.99 : 1)
        .animation(.easeOut(duration: 0.1), value: pressed)
        .opacity(!inCard && drag?.settling == true && drag?.entry?.id == folder.id ? 0 : 1)
        .popover(
            isPresented: $pickingIcon,
            attachmentAnchor: .rect(.rect(CGRect(x: 6 + indent, y: 2, width: 24, height: 36))), arrowEdge: .bottom
        ) {
            SpaceIconPicker(selection: folder.icon) { model.setFolderIcon(folder.id, to: $0) }
        }
        .onChange(of: pickingIcon) { _, open in layout.setHold(.popover, open) }
        .frame(height: 40)
        .onHover { inside in
            hovering = inside
            if !inside && !inCard { layout.leaveSidebarPreview(folder.id) }
        }
        .task(id: hovering && canPreview) {
            guard hovering && canPreview else { return }
            // As Arc's `PreviewsConstants.hoverTimeThreshold`: 200 ms.
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let rect = drag?.rows[folder.id]?.rect,
                !model.state.tree.tabs(under: folder.id).isEmpty
            else { return }
            layout.showSidebarPreview(.folder(folder.id), at: rect, placement: .right)
        }
        .onChange(of: canPreview) { if !canPreview && previewed { layout.dismissSidebarPreview() } }
        .sidebarDragFrame { rect in
            if !inCard { drag?.rows[folder.id] = SidebarDrag.RowFrame(rect: rect, spaceID: spaceID) }
            if previewed && layout.sidebarPreview?.anchor != rect { layout.dismissSidebarPreview() }
        }
        .onDisappear {
            if !inCard { drag?.rows[folder.id] = nil }
            if !inCard && layout.sidebarPreview?.target == .folder(folder.id) { layout.dismissSidebarPreview() }
        }
        .onAppear {
            if !inCard, model.editingFolderID == folder.id { renaming = true }
        }
        .onChange(of: model.editingFolderID) { _, id in
            if !inCard, id == folder.id { renaming = true }
        }
        .platformContextMenu(
            isEnabled: inCard
                ? model.library != nil
                : spaceID == model.selectedSpaceID && model.library == nil && !model.coversWindow
        ) {
            FolderContextMenu(
                model: model, folder: folder, changeIcon: { Task { pickingIcon = true } },
                rename: { renaming = true }
            ).make()
        }
    }

    /// Arc's `ListHeaderCellView` icon-state rule (`0x1003f3eb8`).
    private static func iconState(
        isExpanded: Bool, isPeeked: Bool, isDropTarget: Bool, leadingHovered: Bool, isDragActive: Bool
    ) -> FolderIconState {
        if isExpanded || isDropTarget { return .expanded }
        if isPeeked {
            if isDragActive { return .collapsed }
            return leadingHovered ? .peekedOpen : .peekedClosed
        }
        return .collapsed
    }

    private var revealStart: Date? {
        guard place == .sidebar, folder.gitHub != nil, let reveal = model.liveFolderReveal, reveal.id == folder.id
        else { return nil }
        return reveal.start
    }

    private func press() {
        let event = NSApp.currentEvent
        let flags = event?.type == .leftMouseDown ? event?.modifierFlags ?? [] : NSEvent.modifierFlags
        picking = !flags.contains(.option) && (flags.contains(.command) || flags.contains(.shift))
        guard picking else {
            let members = model.multiSelectedItemIDs
            if members.contains(folder.id) { heldMembers = members }
            return
        }
        if flags.contains(.command) {
            model.toggleMultiSelection(folder.id)
        } else {
            model.extendMultiSelection(to: folder.id)
        }
    }

    private var renameField: some View {
        InlineRenameField(
            layout: layout, text: folder.title, placeholder: "Folder Title", weight: .semibold,
            onCommit: commitRename
        ) { _ in
            cancelRename()
        }
        .frame(height: 19)
    }

    private func commitRename(_ title: String) {
        guard renaming else { return }
        renaming = false
        if model.editingFolderID == folder.id { model.editingFolderID = nil }
        model.renameFolder(folder.id, to: title)
    }

    private func cancelRename() {
        guard renaming else { return }
        renaming = false
        if model.editingFolderID == folder.id { model.editingFolderID = nil }
        // A newly created inline folder with no title yet falls back to "Untitled" on cancel, as Arc's `readableTitle`.
        if folder.title.isEmpty { model.renameFolder(folder.id, to: "") }
    }
}
