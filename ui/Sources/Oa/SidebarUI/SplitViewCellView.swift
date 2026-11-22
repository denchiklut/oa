import SwiftUI

/// Arc's `SplitViewCellView` as measured: a tab row's card with a 28 pt card for each of the split's tabs, 4 pt in
/// and 8.5 pt apart, a hairline between them while the split isn't selected. A split with a title shows a 16 pt
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
    @FocusState private var renameFocused: Bool
    @Environment(\.theme) private var theme
    @Environment(\.windowColorScheme) private var colorScheme
    @Environment(\.sidebarDrag) private var drag

    var body: some View {
        let selected = tabs.contains { $0.id == model.selectedTabIDs[spaceID] }
        let pinned = tabs.first.map { model.state.isPinned($0.id) } ?? false
        let title = model.state.splitView(splitID)?.title
        let card = RoundedRectangle(cornerRadius: 12, style: .continuous)
        HStack(spacing: 0) {
            if renaming || title != nil {
                Text("\(tabs.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    // LIKELY the focus outline's colour: #2932E5 and #2229DD were measured on the default theme.
                    .background(
                        model.splitViewFocusColor(dark: colorScheme == .dark), in: RoundedRectangle(cornerRadius: 4)
                    )
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
                            // After the menu has closed and given the window back its first responder.
                            .task {
                                try? await Task.sleep(for: .milliseconds(100))
                                renameFocused = true
                            }
                            .onChange(of: renameFocused) { _, focused in if !focused { renaming = false } }
                    } else if let title {
                        Text(title).lineLimit(1).truncationMode(.tail)
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
        .padding(.leading, renaming || title != nil ? 4.5 : 4)
        .padding(.trailing, hovering && (!selected || pinned) ? 34 : 4)
        .frame(height: 36)
        .background {
            card.fill(selected ? theme.selectedCard : hovering ? theme.itemFill : .clear)
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
                .help(selected ? "Close and Keep Pinned" : "Archive this Split View")
                .padding(.trailing, 7.5)
            }
        }
        .opacity(drag?.entry?.id == splitID && drag?.settling == true ? 0 : 1)
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
            // As seen in Arc: the field starts with the split's count, all selected.
            Button("Rename…") {
                draft = model.state.splitView(splitID)?.title ?? "\(tabs.count) Tabs"
                renaming = true
            }
            Divider()
            Button("Archive Item") { model.closeSplitView(splitID) }
        }
    }

    /// Arc's `SplitViewItem.ChildItem`: 28 pt high, its title gone under Arc's 20 pt of room for it, and with the ✕
    /// of the selected split under the pointer.
    private struct ChildItem: View {
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
                if showsClose {
                    Spacer(minLength: 0)
                    SidebarCellButton(glyph: .close) { model.close(tab.id) }
                        .help("Archive this tab")
                        .padding(.trailing, 2)
                } else if width >= 52 {
                    Text(model.title(for: tab))
                        .font(.system(size: 14))
                        .foregroundStyle(theme.foreground)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.leading, 10)
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
        }
    }
}
