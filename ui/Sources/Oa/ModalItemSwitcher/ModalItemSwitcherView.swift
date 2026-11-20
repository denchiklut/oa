import SwiftUI

/// Arc's switcher panel as measured live (arc-tab-switcher-live.md §4): a 190 pt strip of 181.75 pt cards inside
/// 16 pt, neutral whatever the Space, with nothing animated.
struct ModalItemSwitcherView: View {
    /// The room the window leaves around the panel for its shadow, as Arc's window has it.
    static let shadowInsets = EdgeInsets(top: 120, leading: 144, bottom: 168, trailing: 144)
    static let height: CGFloat = 190
    private static let padding: CGFloat = 16
    private static let itemWidth: CGFloat = 181.75

    static func width(itemCount: Int) -> CGFloat { 2 * padding + itemWidth * CGFloat(itemCount) }

    let model: WindowModel
    let switcher: ModalItemSwitcher
    let hover: (UUID) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        HStack(spacing: 0) {
            ForEach(switcher.visibleItemIDs, id: \.self) { id in
                if let tab = model.state.tree.tab(id) {
                    ModalItemSwitcherItemView(model: model, tab: tab, focused: id == switcher.focusedItemID)
                        .frame(width: Self.itemWidth)
                        .onContinuousHover { if case .active = $0 { hover(id) } }
                        .onTapGesture { model.dismissModalItemSwitcher(selecting: id) }
                }
            }
        }
        .padding(Self.padding)
        .frame(height: Self.height)
        .background(Color(white: scheme == .dark ? 0.106 : 0.976), in: shape)
        .overlay {
            if scheme == .dark { shape.inset(by: 0.5).strokeBorder(Color(white: 0.31), lineWidth: 1) }
        }
        .overlay { shape.strokeBorder(scheme == .dark ? .black : Color(white: 0.643), lineWidth: 0.5) }
        .compositingGroup()
        .shadow(color: .black.opacity(0.3), radius: 48, y: 24)
        .padding(Self.shadowInsets)
    }
}

/// Reads the model itself, so a card follows its page's title, icon and picture.
private struct ModalItemSwitcherItemView: View {
    let model: WindowModel
    let tab: SidebarTab
    let focused: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 12) {
            Color(white: scheme == .dark ? 0.11 : 0.973)
                .overlay {
                    if let snapshot = model.snapshot(for: tab) {
                        Image(nsImage: snapshot).resizable().interpolation(.high).scaledToFill()
                    }
                }
                .frame(height: 105)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(0.06), radius: 1, y: 2)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 2.5)
            HStack(spacing: 8) {
                TabFavicon(model: model, tab: tab)
                Text(model.title(for: tab))
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(scheme == .dark ? .white : focused ? .black : Color(white: 0.29))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 2)
        }
        .padding(12)
        .background {
            if focused { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selectionFill) }
        }
        .contentShape(Rectangle())
    }

    /// As Arc's focused card: the Space palette's `hover` in dark, and its `focus` at half in light.
    private var selectionFill: Color {
        let palette = (model.space?.theme ?? .default).semanticColorPalette[scheme]
        return scheme == .dark ? palette.hover.color : palette.focus.opacity(0.5).color
    }
}
