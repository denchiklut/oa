import SwiftUI

/// Arc's `SplitViewCellView` as measured: a tab row's card with a 28 pt card for each of the split's tabs, 4 pt in
/// and 8.5 pt apart, a hairline between them while the split isn't selected. Under the pointer the cell has one ✕,
/// its tabs making room for it, or on the selected split a ✕ on each tab's card, none of them lit. A split with a title shows a 16 pt
/// badge with its count where a row's favicon is and the title where a row's is, in place of its tabs. A press selects
/// the split with the pane the window focused in it last, and on the selected split the tab pressed.
struct SplitViewCellView: View {
    let model: WindowModel
    let layout: WindowLayoutController
    let splitID: UUID
    let tabs: [SidebarTab]
    let spaceID: UUID
    @State private var hovering = false
    @State private var renaming = false
    @State private var draft = ""
    @State private var pressed = false
    @State private var capsules: [UUID: CGRect] = [:]
    @State private var pickingIcon = false
    @FocusState private var renameFocused: Bool
    @Environment(\.theme) private var theme
    @Environment(\.sidebarDrag) private var drag

    var body: some View {
        let selected = tabs.contains { $0.id == model.selectedTabIDs[spaceID] }
        let pinned = tabs.first.map { model.state.isPinned($0.id) } ?? false
        let data = model.state.splitView(splitID)
        let title = data?.title
        let icon = data?.icon
        let card = RoundedRectangle(cornerRadius: 12, style: .continuous)
        HStack(spacing: 0) {
            // As seen in Arc: a split with a title or an icon is drawn as a row, the icon or a count badge where a
            // row's favicon is and the title, "N Tabs" without one, where a row's is.
            if renaming || title != nil || icon != nil {
                Group {
                    if let icon {
                        SpaceIconGlyph(icon: icon)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(theme.secondaryGlyph)
                    } else {
                        SplitViewCountBadge(model: model, count: tabs.count)
                    }
                }
                .frame(width: 24, height: 24)
                Group {
                    if renaming {
                        TextField("Title", text: $draft)
                            .textFieldStyle(.plain)
                            .focused($renameFocused)
                            .onSubmit {
                                model.renameSplitView(splitID, to: draft)
                                renaming = false
                            }
                            .onExitCommand { renaming = false }
                            .endsOnClickAway { _ in renaming = false }
                            // After the menu has closed and given the window back its first responder.
                            .task {
                                try? await Task.sleep(for: .milliseconds(100))
                                renameFocused = true
                            }
                            .onChange(of: renameFocused) { _, focused in if !focused { renaming = false } }
                    } else {
                        Text(title ?? "\(tabs.count) Tabs").lineLimit(1).truncationMode(.tail)
                    }
                }
                .font(.system(size: 14))
                .foregroundStyle(theme.foreground)
                .padding(.leading, 6)
                Spacer(minLength: 0)
            } else {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                    if index > 0 {
                        // Arc's `ChildItem.separatorHeight`.
                        theme.separator.frame(width: 0.5, height: 16).frame(width: 8.5).opacity(selected ? 0 : 1)
                    }
                    ChildItem(
                        model: model, tab: tab, isSelected: selected, showsClose: selected && hovering && !pinned
                    )
                    .sidebarDragFrame { capsules[tab.id] = $0 }
                }
            }
        }
        .padding(.leading, renaming || title != nil || icon != nil ? 4.5 : 4)
        .padding(.trailing, hovering && (!selected || pinned) ? 34 : 4)
        .frame(height: 36)
        .background {
            // As seen in Arc: a tab held on the cell to join the split lights it.
            card.fill(
                selected
                    ? theme.selectedCard
                    : drag?.target?.combine == splitID ? theme.itemHoveredFill : hovering ? theme.itemFill : .clear
            )
            .shadow(color: selected ? theme.selectedShadow : .clear, radius: 1, y: 1)
        }
        .contentShape(card)
        // As measured on Arc: the split's card is 1.5 pt narrower at each side than a tab's.
        .padding(.horizontal, 1.5)
        // As seen in Arc: a press anywhere on the cell drags the split whole. It selects a split that isn't
        // selected, and on the selected one focuses the tab pressed. The split stays selected through the drag, so
        // it never drops on its own page.
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(SidebarDrag.space))
                .onChanged { value in
                    if !pressed {
                        pressed = true
                        if !selected {
                            model.selectSplitView(splitID)
                        } else if let tabID = capsules.first(where: { $0.value.contains(value.startLocation) })?.key {
                            model.select(tabID)
                        }
                    }
                    drag?.update(
                        .splitView(id: splitID, tabs: tabs), from: pinned ? .pinned : .today,
                        glyph: selected && pinned ? .minus : .close, at: value.location, start: value.startLocation,
                        model: model, layout: layout)
                }
                .onEnded { _ in
                    pressed = false
                    drag?.finish(model: model, layout: layout)
                },
            including: renaming ? .subviews : .all
        )
        .overlay(alignment: .trailing) {
            // As seen in Arc: the ✕ of a split that isn't selected closes all its tabs, and a selected pinned split
            // has one "—" that unloads its pages, as a pinned tab's.
            if hovering, !selected || pinned {
                SidebarCellButton(glyph: selected ? .minus : .close) {
                    if selected { model.closeSplitViewPages(splitID) } else { model.closeSplitView(splitID) }
                }
                // Arc's tooltip on the "—" also shows ⌘W as key badges.
                .help(selected ? "Close this item" : "Archive this item")
                .padding(.trailing, 7.5)
            }
        }
        .opacity(drag?.entry?.id == splitID && drag?.settling == true ? 0 : 1)
        .popover(
            isPresented: $pickingIcon, attachmentAnchor: .rect(.rect(CGRect(x: 16, y: 2, width: 20, height: 36))),
            arrowEdge: .bottom
        ) {
            // Oa's own: the Space icon picker. Arc's has its Ionicons and every emoji; a pick applies at once and the
            // picker stays, as Arc's does.
            SpaceIconPicker(selection: icon) { model.setSplitViewIcon(splitID, to: $0) }
        }
        .frame(height: 40)
        .onHover { hovering = $0 }
        .sidebarDragFrame { drag?.rows[splitID] = SidebarDrag.RowFrame(rect: $0, spaceID: spaceID) }
        .onDisappear { drag?.rows[splitID] = nil }
        .spaceMenuExclusion()
        .contextMenu {
            Button("Share Split View…") {}.disabled(true)
            Divider()
            Button("Separate All Tabs") { model.separateAllSplitViewChildren(splitID) }
            Button("Add Tab…") {
                model.selectSplitView(splitID)
                model.addSplitViewPane()
            }
            .disabled(tabs.count >= SidebarSplitViewData.maxNumberSplit)
            Button(
                model.state.splitView(splitID)?.layoutOrientation == .vertical
                    ? "Convert to Horizontal Split View" : "Convert to Vertical Split View"
            ) { model.flipSplitViewLayoutOrientation(splitID) }
            Section("Tab Options") {
                ForEach(tabs) { tab in
                    Menu(model.title(for: tab)) {
                        Button("Separate from Split View") { model.separateFromSplitView(tab.id) }
                        Divider()
                        Button("Archive Item") { model.close(tab.id) }
                    }
                }
            }
            Divider()
            if title != nil || icon != nil {
                Button("Reset Name and Icon") { model.resetSplitViewNameAndIcon(splitID) }
            }
            // As seen in Arc: the picker hangs below the cell, its arrow at the first tab's favicon.
            Button("Change Icon…") { Task { pickingIcon = true } }
            // As seen in Arc: the field starts with the split's count, all selected.
            Button("Rename…") {
                draft = model.state.splitView(splitID)?.title ?? "\(tabs.count) Tabs"
                renaming = true
            }
            Divider()
            Button("Duplicate") { model.duplicateSplitView(splitID) }
            SplitViewMoveMenu(model: model, splitID: splitID)
            Divider()
            Button("Archive Item") { model.closeSplitView(splitID) }
        }
    }

    /// Arc's `SplitViewItem.ChildItem`: 28 pt high, its title gone under Arc's 20 pt of room for it, and with the ✕
    /// of the selected split under the pointer, beside the title while there is room, as two panes' have and three
    /// panes' don't. Its tooltip is its tab's title.
    fileprivate struct ChildItem: View {
        let model: WindowModel
        let tab: SidebarTab
        let isSelected: Bool
        let showsClose: Bool
        @State private var width: CGFloat = 0
        @Environment(\.theme) private var theme

        var body: some View {
            let card = RoundedRectangle(cornerRadius: 8, style: .continuous)
            HStack(spacing: 0) {
                TabFavicon(model: model, tab: tab)
                    .frame(width: 18, height: 18)
                    .padding(.leading, 3.5)
                if width >= (showsClose ? 78 : 52) {
                    Text(model.title(for: tab))
                        .font(.system(size: 14))
                        .foregroundStyle(theme.foreground)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.leading, 10)
                }
                if showsClose {
                    Spacer(minLength: 0)
                    SidebarCellButton(glyph: .close) { model.close(tab.id) }
                        .help("Archive this item")
                        .padding(.trailing, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 28)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                width = $0
            }
            // As measured on Arc: white 7 % over the selected card in dark, black 8 % in light.
            .background { if isSelected { card.fill(theme.isDark ? .white.opacity(0.07) : .black.opacity(0.08)) } }
            .contentShape(card)
            .help(model.title(for: tab))
        }
    }
}

/// As seen in Arc: the row a tab is held on, drawn as the split the drop would make, with one ✕: the row's tab keeps
/// its card, and the held tabs' places are lit and empty, before it from the row's left half and after it from its
/// right half. The held copy stays over them. The lit cards' fill is LIKELY the selected card's: Arc's lay under the
/// copy in every capture.
struct SplitViewCombinePreview: View {
    let model: WindowModel
    let tab: SidebarTab
    let held: Int
    let last: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        let card = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let lit = RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.selectedCard).frame(height: 28)
        HStack(spacing: 8.5) {
            if !last { ForEach(0..<held, id: \.self) { _ in lit } }
            SplitViewCellView.ChildItem(model: model, tab: tab, isSelected: false, showsClose: false)
            if last { ForEach(0..<held, id: \.self) { _ in lit } }
        }
        .padding(.leading, 4)
        .padding(.trailing, 34)
        .frame(height: 36)
        .background(card.fill(theme.itemFill))
        .overlay(alignment: .trailing) {
            CellGlyph(glyph: .close).frame(width: 24, height: 24).padding(.trailing, 7.5)
        }
        .padding(.horizontal, 1.5)
        .allowsHitTesting(false)
    }
}

/// Arc's Move to ▸ on a split: every Space in the dock's order, then New Space….
struct SplitViewMoveMenu: View {
    let model: WindowModel
    let splitID: UUID

    var body: some View {
        Menu("Move to") {
            ForEach(model.state.spaces) { space in
                Button(space.name) { model.moveItem(splitID, toSpace: space.id) }
                    .disabled(!model.canMoveItem(splitID, toSpace: space.id))
            }
            Divider()
            Button("New Space…") { model.beginSpaceCreation(after: model.selectedSpaceID, moving: [splitID]) }
        }
    }
}

/// A titled split's count where a row's favicon is, LIKELY in the focus outline's colour: #2932E5 and #2229DD were
/// measured on the default theme.
struct SplitViewCountBadge: View {
    let model: WindowModel
    let count: Int
    @Environment(\.windowColorScheme) private var colorScheme

    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 16, height: 16)
            .background(model.splitViewFocusColor(dark: colorScheme == .dark), in: RoundedRectangle(cornerRadius: 4))
    }
}
