import SwiftUI

/// Arc's `SplitViewCellView` as measured: a tab row's card with a 28 pt card for each of the split's tabs, 4 pt in
/// and 8.5 pt apart, a hairline between them while the split isn't selected. A click selects the split with the pane
/// the window focused in it last, and on the selected split the tab clicked.
struct SplitViewCellView: View {
    let model: WindowModel
    let splitID: UUID
    let tabs: [SidebarTab]
    let spaceID: UUID
    @State private var hovering = false
    @Environment(\.theme) private var theme
    @Environment(\.sidebarDrag) private var drag

    var body: some View {
        let selected = tabs.contains { $0.id == model.selectedTabIDs[spaceID] }
        let card = RoundedRectangle(cornerRadius: 12, style: .continuous)
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                if index > 0 {
                    // Arc's `ChildItem.separatorHeight`.
                    theme.separator.frame(width: 0.5, height: 16).frame(width: 8.5).opacity(selected ? 0 : 1)
                }
                ChildItem(model: model, tab: tab, isSelected: selected, showsClose: selected && hovering)
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, hovering && !selected ? 34 : 4)
        .frame(height: 36)
        .background {
            card.fill(selected ? theme.selectedCard : hovering ? theme.itemFill : .clear)
                .shadow(color: selected ? theme.selectedShadow : .clear, radius: 1, y: 1)
        }
        .contentShape(card)
        // As measured on Arc: the split's card is 1.5 pt narrower at each side than a tab's.
        .padding(.horizontal, 1.5)
        .onTapGesture { if !selected { model.selectSplitView(splitID) } }
        .overlay(alignment: .trailing) {
            // As seen in Arc: the ✕ of a split that isn't selected closes all its tabs.
            if hovering, !selected {
                SidebarCellButton(glyph: .close) { model.closeSplitView(splitID) }
                    .help("Archive this Split View")
                    .padding(.trailing, 7.5)
            }
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
            .onTapGesture { if isSelected { model.select(tab.id) } else { model.selectSplitView(parentID) } }
        }

        private var parentID: UUID { model.state.splitViewID(containing: tab.id) ?? tab.id }
    }
}
