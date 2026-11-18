import DevKit
import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    let model: WindowModel
    let layout: WindowLayoutController
    @State private var overLibraryButton = false
    @State private var overFlyout = false
    @State private var showingFlyout = false
    @State private var pointerInside = false
    @State private var creationSlot = CGPoint.zero

    var body: some View {
        VStack(spacing: 0) {
            SidebarHeader(model: model, layout: layout)
            SidebarPagingContainerView(model: model, layout: layout)
            spaces
        }
        .coordinateSpace(.named(Self.space))
        .overlay(alignment: .trailing) {
            EdgeFeedbackView(progress: layout.spaceCreationPull.progress, reveal: layout.spaceCreationPull.reveal)
        }
        .overlay {
            if let creation = model.spaceCreation, creation.phase == .animating {
                SpaceCreationSplashView(
                    icon: creation.icon ?? SpaceCreationState.defaultIcon, target: creationSlot,
                    complete: { model.completeSpaceCreation() })
            }
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
        // The sidebar stays mounted under the Library, where the pointer's leaving isn't reported.
        .onChange(of: model.library == nil) {
            overLibraryButton = false
            overFlyout = false
            showingFlyout = false
            pointerInside = false
        }
        .frame(width: layout.sidebarWidth, alignment: .leading)
        .onHover { pointerInside = $0 }
        // As Arc: the floating panel brings them in with it.
        .environment(\.sidebarRevealsControls, pointerInside || layout.sidebarPresentation == .floating)
        .animation(.easeInOut(duration: 0.19), value: pointerInside)
    }

    /// As Arc: on the Create a Space page the Library button and the plus go.
    private var spaces: some View {
        let creation = layout.spaceCreationProgress
        return HStack(spacing: 4) {
            LibraryButton(model: model)
                .onHover { overLibraryButton = $0 }
                .opacity(1 - creation)
                .allowsHitTesting(creation == 0)
            SidebarDock(model: model, layout: layout, creationSlot: $creationSlot)
            Button {
                model.beginSpaceCreation()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("New Space")
            .opacity(1 - creation)
            .allowsHitTesting(creation == 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

extension SidebarView {
    nonisolated static let space = "sidebar"
}

extension EnvironmentValues {
    /// Arc's one "pointer is in the sidebar" state, which shows the URL field's buttons and Clear together.
    @Entry var sidebarRevealsControls = false
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

/// Arc's Space items in the dock, between the Library button and the plus: an icon or an 8 pt dot, 26 pt apart and
/// closer once they don't fit. The current Space's is darker, and during a swipe the two Spaces cross-fade.
/// Past a pitch of 18 pt the icons give way to dots and the others shrink to 4 pt. Oa chose that threshold
/// between Arc's measured pitches at 8 and 10 Spaces.
private struct SidebarDock: View {
    let model: WindowModel
    let layout: WindowLayoutController
    @Binding var creationSlot: CGPoint
    @Environment(\.theme) private var theme

    var body: some View {
        let spaces = model.state.spaces
        let creation = layout.spaceCreationProgress
        let page = min(layout.sidebarScrollOffset / layout.sidebarWidth, CGFloat(spaces.count - 1))
        let count = spaces.count + (model.spaceCreation == nil ? 0 : 1)
        GeometryReader { geometry in
            let pitch = min(26, geometry.size.width / CGFloat(max(count, 1)))
            HStack(spacing: 0) {
                ForEach(Array(spaces.enumerated()), id: \.element.id) { index, space in
                    let emphasis = max(0, 1 - abs(page - CGFloat(index))) * (1 - creation)
                    let size: CGFloat = pitch < 18 ? 4 + 4 * emphasis : 8
                    Button {
                        model.selectSpace(space.id)
                    } label: {
                        Group {
                            if pitch >= 18, let icon = space.icon {
                                SpaceIconGlyph(icon: icon)
                                    .font(.system(size: 13, weight: .semibold))
                            } else {
                                Circle().frame(width: size, height: size)
                            }
                        }
                        .foregroundStyle(theme.dockItem(emphasis: emphasis))
                        .frame(width: pitch, height: 34)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(space.name)
                    .accessibilityLabel(space.name)
                    .spaceContextMenu(isEnabled: !model.coversWindow) {
                        SpaceMenu(model: model, layout: layout, space: space)
                    }
                }
                if model.spaceCreation != nil {
                    Circle()
                        .frame(width: 8, height: 8)
                        .foregroundStyle(theme.dockItem(emphasis: creation))
                        .frame(width: pitch, height: 34)
                        .onGeometryChange(for: CGPoint.self) {
                            let frame = $0.frame(in: .named(SidebarView.space))
                            return CGPoint(x: frame.midX, y: frame.midY)
                        } action: {
                            creationSlot = $0
                        }
                        .accessibilityLabel("New Space")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 34)
    }
}

/// Arc's grid (`AppTrayCollectionViewLayout`): tiles 47 pt tall with 8 pt gaps filling the row, at most four and
/// never narrower than 47 pt; columns from the count as `rows = ⌈n / most⌉`, `cols = ⌈n / rows⌉`, the last row
/// left-aligned. While a drag is over it, the grid makes the slot it would land in and the tiles slide to their new
/// places as Arc's do.
struct FavoritesGrid: View {
    struct Layout {
        let rows: Int
        let columns: Int
        let tileWidth: CGFloat

        init(count: Int, width: CGFloat) {
            let most = min(4, max(1, Int((width - 8) / 55)))
            rows = max(1, (count + most - 1) / most)
            columns = max(1, (count + rows - 1) / rows)
            tileWidth = (width - 16 - CGFloat(columns - 1) * 8) / CGFloat(columns)
        }

        var height: CGFloat { CGFloat(rows) * 47 + CGFloat(rows - 1) * 8 }

        func origin(of index: Int) -> CGPoint {
            CGPoint(x: CGFloat(index % columns) * (tileWidth + 8), y: CGFloat(index / columns) * 55)
        }
    }

    struct Slot: Identifiable {
        static let gapID = UUID()
        let id: UUID
        let tab: SidebarTab?
        /// The dragged tile: out of the layout but mounted, so its drag goes on.
        var isLifted = false
    }

    let model: WindowModel
    let layout: WindowLayoutController
    let slots: [Slot]

    /// The tiles as the drag leaves them: a dragged tile has left its place, and the slot opens where it would land.
    static func slots(_ favorites: [SidebarTab], drag: SidebarDrag?) -> [Slot] {
        guard let drag, let dragged = drag.tab else { return favorites.map { Slot(id: $0.id, tab: $0) } }
        var slots = favorites.filter { $0.id != dragged.id }.map { Slot(id: $0.id, tab: $0) }
        if let target = drag.target, target.section == .favorites {
            slots.insert(Slot(id: Slot.gapID, tab: nil), at: min(target.index, slots.count))
        }
        if favorites.contains(where: { $0.id == dragged.id }) {
            slots.append(Slot(id: dragged.id, tab: dragged, isLifted: true))
        }
        return slots
    }

    /// What the grid takes of the sidebar's height, so a Space's page starts under its profile's grid. It changes at
    /// once, so the list jumps as Arc's does.
    static func height(for count: Int, in width: CGFloat) -> CGFloat {
        Layout(count: count, width: width).height
    }

    @Environment(\.sidebarDrag) private var drag

    var body: some View {
        let shown = slots.filter { !$0.isLifted }
        let grid = Layout(count: shown.count, width: layout.sidebarWidth)
        ZStack(alignment: .topLeading) {
            if shown.isEmpty {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .foregroundStyle(.quaternary)
                    .frame(width: 47, height: 47)
            }
            ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                let origin = grid.origin(of: slot.isLifted ? 0 : index)
                Group {
                    if let tab = slot.tab {
                        FavoriteTile(model: model, layout: layout, tab: tab, width: grid.tileWidth)
                    } else {
                        Color.clear.sidebarDragFrame { drag?.gap = $0 }
                    }
                }
                .frame(width: grid.tileWidth, height: 47)
                .padding(.leading, origin.x)
                .padding(.top, origin.y)
                .opacity(slot.isLifted ? 0 : 1)
            }
        }
        .animation(.spring(response: 0.23, dampingFraction: 1), value: shown.map(\.id))
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: grid.height, alignment: .top)
    }
}

/// Arc's `AppTrayItemViewAppKit`, back to front: the selected white card and its shadow, the favicon's tint, the
/// body's fill (none when selected), the selection ring and the favicon. A tile has no button and no tooltip.
private struct FavoriteTile: View {
    let model: WindowModel
    let layout: WindowLayoutController
    let tab: SidebarTab
    let width: CGFloat
    @State private var hovering = false
    @State private var pressed = false
    @Environment(\.theme) private var theme
    @Environment(\.sidebarDrag) private var drag

    var body: some View {
        let selected = model.selectedTabID == tab.id
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let favicon = model.favicon(for: tab)
        ZStack {
            shape.fill(selected ? theme.selectedTile : .clear)
                .shadow(color: .black.opacity(selected ? 0.1 : 0), radius: 2, y: 1)
            if let favicon, selected {
                AppTrayVisualEffect(favicon: favicon, tileWidth: width)
                    .opacity(theme.isDark ? (hovering ? 0.3 : 0.2) : (hovering ? 0.1 : 0))
                    .animation(.easeOut(duration: 0.12), value: hovering)
                AppTrayRing(favicon: favicon, tileWidth: width)
            }
            shape.fill(selected ? .clear : hovering ? theme.itemHoveredFill : theme.itemFill)
                .animation(.easeOut(duration: hovering ? 0.14 : 0.1), value: hovering)
            if let favicon {
                Image(nsImage: favicon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .frame(width: width, height: 47)
        .overlay(alignment: .topTrailing) {
            if let peek = model.peeks[tab.id] { PeekBadge(favicon: peek.favicon).offset(x: 5, y: -5) }
        }
        // Arc's tiles carry the recording dot too (AppTray's `recordingIndicatorView`); the corner is Oa's own.
        .overlay(alignment: .topLeading) {
            if model.isRecording(tab) { RecordingDot().padding(6) }
        }
        .contentShape(shape)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(SidebarDrag.space))
                .onChanged { value in
                    if !pressed {
                        pressed = true
                        model.select(tab.id)
                    }
                    drag?.update(
                        tab, from: .favorites, glyph: .close, at: value.location, start: value.startLocation,
                        model: model, layout: layout)
                }
                .onEnded { _ in
                    pressed = false
                    drag?.finish(model: model, layout: layout)
                }
        )
        .onHover { hovering = $0 }
        .sidebarDragFrame { drag?.tiles[tab.id] = $0 }
        .contextMenu {
            if selected { Button("Close Tab") { model.close(tab.id) } }
            Button("Unfavorite") { model.unfavorite(tab.id) }
            Button("Remove Favorite") { model.removeFavorite(tab.id) }
        }
    }
}

/// Arc's `ModalV2SidebarBadgeView`; with no favicon, the grey square measured in Arc.
private struct PeekBadge: View {
    private static let emptyFavicon = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(displayP3Red: 119 / 255, green: 118 / 255, blue: 130 / 255, alpha: 1)
                : NSColor(displayP3Red: 195 / 255, green: 194 / 255, blue: 196 / 255, alpha: 1)
        })

    let favicon: NSImage?

    var body: some View {
        Group {
            if let favicon {
                Image(nsImage: favicon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Self.emptyFavicon)
                    .frame(width: 14, height: 14)
            }
        }
        .frame(width: 24, height: 24)
        .background(ARCUIColor.grayA4, in: RoundedRectangle(cornerRadius: 6))
    }
}

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

/// A row's favicon as Arc's: 16 pt with 4 pt corners, or its `EmptyFavicon`, a 14 pt square in the palette's
/// `maxContrastColor` at the image's 0.28.
struct TabFavicon: View {
    let model: WindowModel
    let tab: SidebarTab
    @Environment(\.theme) private var theme

    var body: some View {
        if let icon = model.favicon(for: tab) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            RoundedRectangle(cornerRadius: 3)
                .fill(theme.maxContrast.opacity(0.28))
                .frame(width: 14, height: 14)
        }
    }
}

/// Arc's tab cell: a 40 pt row with a 36 pt card, selected on mouse-down, its button only under the pointer.
/// Reads the model itself, so a change to its tab's page, Peek or selection re-renders the row alone.
struct TabRow: View {
    /// As Arc's Spaces cards: the same cell, with no selection drawn, always ✕, the saved title, and a click that
    /// leaves the Library for the tab on mouse-up.
    enum Place {
        case sidebar
        case card
    }

    let model: WindowModel
    let layout: WindowLayoutController
    let tab: SidebarTab
    let spaceID: UUID
    var place = Place.sidebar
    @State private var hovering = false
    @State private var size = CGSize.zero
    @State private var pressed = false
    @State private var bounces = 0
    @Environment(\.theme) private var theme
    @Environment(\.sidebarDrag) private var drag

    var body: some View {
        let inCard = place == .card
        let pinned = model.state.isPinned(tab.id)
        let current = !inCard && model.selectedTabIDs[spaceID] == tab.id
        // As Arc: the New Tab row takes the selected look while the bar makes a tab.
        let selected = current && (spaceID != model.selectedSpaceID || model.commandBar?.destination != .newTab)
        // As Arc's `closeButtonAction`: a pinned tab that is shown, or has left its address, keeps its pin.
        let glyph: SidebarCellButton.Glyph =
            pinned && !inCard && (current || model.leftAddress(tab) != nil) ? .minus : .close
        let peek = model.peeks[tab.id]
        let dragged = !inCard && drag?.tab?.id == tab.id
        let showsButton = hovering && !dragged
        let card = RoundedRectangle(cornerRadius: 12, style: .continuous)
        HStack(spacing: 0) {
            if model.isRecording(tab) { RecordingDot().padding(.trailing, 2) }
            TabFavicon(model: model, tab: tab)
                .frame(width: 24, height: 24)
            Text(inCard ? tab.displayTitle : model.title(for: tab))
                .font(.system(size: 14))
                .foregroundStyle(theme.foreground)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, 6)
            Spacer(minLength: 0)
        }
        .padding(.leading, 6)
        .padding(.trailing, showsButton || peek != nil ? 31 : 10)
        .frame(height: 36)
        .background {
            card.fill(selected ? theme.selectedCard : hovering ? theme.itemFill : .clear)
                .shadow(color: selected ? theme.selectedShadow : .clear, radius: 1, y: 1)
        }
        .contentShape(card)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: inCard ? .local : .named(SidebarDrag.space))
                .onChanged { value in
                    if !pressed {
                        pressed = true
                        if !inCard { model.select(tab.id) }
                    }
                    guard !inCard else { return }
                    drag?.update(
                        tab, from: pinned ? .pinned : .today, glyph: glyph, at: value.location,
                        start: value.startLocation, model: model, layout: layout)
                }
                .onEnded { value in
                    pressed = false
                    guard inCard else {
                        drag?.finish(model: model, layout: layout)
                        return
                    }
                    guard CGRect(origin: .zero, size: size).contains(value.location) else { return }
                    layout.dismissSidebar()
                    model.show(tab.id)
                }
        )
        .onGeometryChange(for: CGSize.self) {
            $0.size
        } action: {
            size = $0
        }
        .overlay(alignment: .trailing) {
            Group {
                if let peek {
                    PeekBadge(favicon: peek.favicon)
                } else if showsButton {
                    SidebarCellButton(glyph: glyph) {
                        if glyph == .minus {
                            bounces += 1
                            model.close(tab.id)
                        } else if pinned {
                            model.archivePinned(tab.id)
                        } else {
                            model.close(tab.id)
                        }
                    }
                    .help((glyph == .minus ? "Close and Keep Pinned" : "Archive this tab") + (current ? "  ⌘W" : ""))
                }
            }
            .padding(.trailing, 6)
        }
        .scaleEffect(pressed ? 0.99 : 1)
        .animation(.easeOut(duration: 0.1), value: pressed)
        // As Arc's drop: the row is in its new place at once, under the copy settling onto it.
        .opacity(dragged && drag?.settling == true ? 0 : 1)
        // As measured on Arc's −: the row drops to 0.89 and springs back.
        .keyframeAnimator(initialValue: 1.0, trigger: bounces) { content, scale in
            content.scaleEffect(scale)
        } keyframes: { _ in
            MoveKeyframe(0.89)
            SpringKeyframe(1, duration: 0.24, spring: Spring(response: 0.24, dampingRatio: 1))
        }
        .frame(height: 40)
        .onHover { hovering = $0 }
        .sidebarDragFrame { if !inCard { drag?.rows[tab.id] = SidebarDrag.RowFrame(rect: $0, spaceID: spaceID) } }
        .spaceMenuExclusion()
        .contextMenu {
            if !pinned {
                Button("Archive Tab") { model.close(tab.id) }
                Button("Archive Tabs Below") { model.archiveTabs(below: tab.id) }
                    .disabled(model.state.tabs(in: spaceID, pinned: false).last?.id == tab.id)
            }
        }
    }
}
